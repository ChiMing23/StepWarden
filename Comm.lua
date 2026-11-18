--[[-----------------------------------------------------------------------------
StepWarden - Comm
好友间分数同步（公会频道 + 在线好友私聊），以及点赞私信
-------------------------------------------------------------------------------]]
local ADDON, AS = ...

AS.Comm = AS.Comm or {}
local C = AS.Comm

C.PREFIX = "AZSteps"
C.lastRequest = 0   -- RequestAll 节流时间戳

--[[-----------------------------------------------------------------------------
底层发送
-------------------------------------------------------------------------------]]
local function SendAM(msg, channel, target)
    local sent, err = false, nil

    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local ok, a, b = pcall(C_ChatInfo.SendAddonMessage, C.PREFIX, msg, channel, target)
        if ok then
            -- a 是接口自己的返回值：true 成功 / false 失败；nil 表示该版本不返回
            if a == nil then sent = true else sent = (a and true or false) end
            err = b
        else
            sent = false
            err = tostring(a)
        end
    elseif SendAddonMessage then
        local ok, a, b = pcall(SendAddonMessage, C.PREFIX, msg, channel, target)
        if ok then
            if a == nil then sent = true else sent = (a and true or false) end
            err = b
        else
            sent = false
            err = tostring(a)
        end
    else
        return false, "没有可用的发送接口"
    end

    -- 汇总一次广播的成败，供 /step comm 查看
    local st = C.lastSend
    if st then
        st.total = (st.total or 0) + 1
        if sent then
            st.ok = (st.ok or 0) + 1
        else
            st.fail = (st.fail or 0) + 1
            st.lastErr = tostring(err or "?") .. "  @ " .. tostring(channel)
                .. " -> " .. tostring(target or "-")
        end
    end

    return sent, err
end

local function RegisterPrefix()
    local ok, ret
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        ok, ret = pcall(C_ChatInfo.RegisterAddonMessagePrefix, C.PREFIX)
    elseif RegisterAddonMessagePrefix then
        ok, ret = pcall(RegisterAddonMessagePrefix, C.PREFIX)
    else
        ok, ret = false, nil
    end
    C.prefixOK = (ok and ret ~= false) and true or false
end

--[[-----------------------------------------------------------------------------
好友列表
-------------------------------------------------------------------------------]]
function C:OnlineFriends()
    local out = {}

    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local n = tonumber(select(1, C_FriendList.GetNumFriends())) or 0
        for i = 1, n do
            local f = C_FriendList.GetFriendInfoByIndex(i)
            if type(f) == "table" and f.connected then
                -- fullName 才带 "-服务器"，跨服好友拿它当密语目标才发得出去
                local nm = f.fullName or f.name
                if nm then table.insert(out, nm) end
            end
        end
        return out
    end

    if GetNumFriends and GetFriendInfo then
        local n = tonumber(select(1, GetNumFriends())) or 0
        for i = 1, n do
            local name, _, _, _, connected = GetFriendInfo(i)
            if name and connected then
                table.insert(out, name)
            end
        end
    end

    return out
end

-- 从一份好友账号信息里把"正在玩的角色名-服务器"取出来。
local function toonFromAccount(info)
    if type(info) ~= "table" then return nil end
    local ga = info.gameAccountInfo
    if type(ga) ~= "table" then return nil end

    local cp = ga.clientProgram
    if cp ~= nil and cp ~= "WoW" then return nil end

    local cn = ga.characterName
    if type(cn) ~= "string" or cn == "" then return nil end

    local cr = ga.characterRealmName
    if type(cr) == "string" and cr ~= "" then return cn .. "-" .. cr end
    return cn
end

-- 战网好友里正在玩 WoW 的那些，能拿到对方的角色名与服务器。
-- 跨阵营、跨公会的朋友只能靠这条线：好友列表里没有他们，公会频道也覆盖不到。
-- 注意：正式服的老接口 BNGetFriendInfo 在这个客户端不存在，
-- 真正的数据在 C_BattleNet.GetFriendAccountInfo 的 gameAccountInfo 里。
function C:BNToons()
    local out, seen = {}, {}
    if not BNGetNumFriends then return out end

    local okn, n = pcall(BNGetNumFriends)
    if not okn then return out end
    n = tonumber(n) or 0
    if n <= 0 then return out end

    local function take(full)
        if type(full) == "string" and full ~= "" and not seen[full] then
            seen[full] = true
            out[#out + 1] = full
        end
    end

    local getAcc = C_BattleNet and C_BattleNet.GetFriendAccountInfo
    if type(getAcc) == "function" then
        for i = 1, n do
            local ok, info = pcall(getAcc, i)
            if ok then
                if type(info) == "table" then
                    take(toonFromAccount(info))
                    -- 一个人可能有多个游戏账号，逐个看
                    local numGA = C_BattleNet.GetFriendNumGameAccounts
                    if type(numGA) == "function" then
                        local okc, cnt = pcall(numGA, i)
                        if okc and tonumber(cnt) and tonumber(cnt) > 1 then
                            local getGA = C_BattleNet.GetFriendGameAccountInfo
                            if type(getGA) == "function" then
                                for g = 2, tonumber(cnt) do
                                    local okg, ga = pcall(getGA, i, g)
                                    if okg and type(ga) == "table" then
                                        take(toonFromAccount({ gameAccountInfo = ga }))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 兜底：万一某个版本还留着老接口
    if #out == 0 and type(BNGetFriendInfo) == "function" then
        for i = 1, n do
            local ok, info = pcall(BNGetFriendInfo, i)
            if ok and type(info) == "table" then
                local toon, realm, client = info.toonName, info.toonRealm, info.client
                if type(toon) == "string" and toon ~= ""
                    and (client == nil or client == "WoW") then
                    take(toon .. ((type(realm) == "string" and realm ~= "") and ("-" .. realm) or ""))
                end
            end
        end
    end

    return out
end

function C:FriendCount()
    return #C:OnlineFriends() + #C:BNToons()
end

-- 探测本客户端到底暴露了哪些战网相关 API。
-- 正式服的 BNGetFriendInfo 在这里不存在，但好友数又有 184，说明命名不同。
-- 诊断结果额外存一份到存档，reload 后能从 SavedVariables 直接读，
-- 不用对着聊天框截图，也不依赖聊天记录。
function C:SaveDiag(kind, lines)
    local db = AS and AS.db
    if not db then return end
    if type(db.diag) ~= "table" then db.diag = {} end
    db.diag[kind] = lines
end

function C:BNApi()
    local out = {}

    local names = {}
    local okScan = pcall(function()
        for k, v in pairs(_G) do
            if type(k) == "string" and k:sub(1, 2) == "BN" then
                names[#names + 1] = k .. "  (" .. type(v) .. ")"
            end
        end
    end)
    if not okScan then
        out[#out + 1] = "扫描全局表失败，改用逐个探测"
    end
    table.sort(names)
    out[#out + 1] = "全局 BN* 函数：" .. #names .. " 个"
    for i = 1, math.min(#names, 40) do
        out[#out + 1] = "  " .. names[i]
    end

    if C_BattleNet then
        local members = {}
        pcall(function()
            for k, v in pairs(C_BattleNet) do
                members[#members + 1] = tostring(k) .. "  (" .. type(v) .. ")"
            end
        end)
        table.sort(members)
        out[#out + 1] = "C_BattleNet：" .. #members .. " 个"
        for i = 1, math.min(#members, 30) do
            out[#out + 1] = "  " .. members[i]
        end
    else
        out[#out + 1] = "C_BattleNet = (nil)"
    end

    -- BNGetNumFriends 的真实返回值（老版可能返回两个数）
    if BNGetNumFriends then
        local ok, a, b = pcall(BNGetNumFriends)
        out[#out + 1] = "BNGetNumFriends -> [" .. tostring(a) .. "] [" .. tostring(b) .. "]"
    end

    -- 看一个在线好友的真实字段，确认角色名到底藏在哪一层
    out[#out + 1] = "BNGetFriendInfo 存在 = " .. tostring(type(BNGetFriendInfo) == "function")
    local getAcc = C_BattleNet and C_BattleNet.GetFriendAccountInfo
    out[#out + 1] = "GetFriendAccountInfo 存在 = " .. tostring(type(getAcc) == "function")

    if type(getAcc) == "function" and BNGetNumFriends then
        local okn, n = pcall(BNGetNumFriends)
        n = tonumber(n) or 0
        local shown = 0
        for i = 1, math.min(n, 60) do
            local ok, info = pcall(getAcc, i)
            if ok and type(info) == "table" then
                local ga = info.gameAccountInfo
                if type(ga) == "table" and type(ga.characterName) == "string"
                    and ga.characterName ~= "" then
                    shown = shown + 1
                    out[#out + 1] = "--- 有角色的好友 #" .. i .. " ---"
                    local top = {}
                    for k in pairs(info) do top[#top + 1] = k end
                    table.sort(top)
                    out[#out + 1] = "  顶层: " .. table.concat(top, ", ")
                    local gk = {}
                    for k in pairs(ga) do gk[#gk + 1] = k end
                    table.sort(gk)
                    out[#out + 1] = "  gameAccountInfo: " .. table.concat(gk, ", ")
                    out[#out + 1] = "  -> 角色 [" .. tostring(ga.characterName) .. "]"
                        .. " 服 [" .. tostring(ga.characterRealmName) .. "]"
                        .. " 端 [" .. tostring(ga.clientProgram) .. "]"
                        .. " 在线 [" .. tostring(ga.isOnline) .. "]"
                        .. " 职业 [" .. tostring(ga.className) .. "]"
                    if shown >= 2 then break end
                end
            end
        end
        if shown == 0 then out[#out + 1] = "  前 60 个好友里没有带角色名的" end
    end

    local st = C.lastSend
    if st then
        out[#out + 1] = "上次广播    = 目标 " .. tostring(st.total or 0)
            .. " / 成功 " .. tostring(st.ok or 0)
            .. " / 失败 " .. tostring(st.fail or 0)
        if st.lastErr then out[#out + 1] = "  最后错误 = " .. st.lastErr end
    else
        out[#out + 1] = "上次广播    = 还没发过"
    end

    local got = C:BNToons()
    out[#out + 1] = "BNToons 实际取到 = " .. #got
    for i = 1, math.min(#got, 10) do out[#out + 1] = "  取到 " .. i .. " = [" .. got[i] .. "]" end

    C:SaveDiag("bn", out)
    return out
end

--[[-----------------------------------------------------------------------------
发送
-------------------------------------------------------------------------------]]
-- 好友分批发送：暴雪对 addon message 有节流（约 1 条/秒），
-- 一次性发几十条会被静默丢弃，所以每次只发 2 条、间隔 0.5 秒。
local function SendToFriends(msg)
    local friends = C:OnlineFriends()

    -- 叠加战网好友当前角色，去重后一起发；这条通道能覆盖跨阵营、跨公会的人
    local bn = C:BNToons()
    if #bn > 0 then
        local seen = {}
        for i = 1, #friends do seen[friends[i]] = true end
        for i = 1, #bn do
            local nm = bn[i]
            if nm and nm ~= "" and not seen[nm] then
                seen[nm] = true
                table.insert(friends, nm)
            end
        end
    end

    if #friends == 0 then return end

    if not (C_Timer and C_Timer.After) then
        for i = 1, #friends do SendAM(msg, "WHISPER", friends[i]) end
        return
    end

    local idx = 0
    local function step()
        local sent = 0
        while sent < 2 do
            idx = idx + 1
            local target = friends[idx]
            if not target then return end
            SendAM(msg, "WHISPER", target)
            sent = sent + 1
        end
        if friends[idx + 1] then C_Timer.After(0.5, step) end
    end
    step()
end

function C:BroadcastScore(entry)
    if not entry then return end

    C.lastSend = { total = 0, ok = 0, fail = 0 }
    local msg = string.format("S|%d|%d|%d|%s",
        math.floor(entry.steps or 0),
        math.floor(entry.trips or 0),
        math.floor(entry.kcal or 0),
        tostring(entry.date or AS:WindowKey())
    )

    if IsInGuild and IsInGuild() then
        SendAM(msg, "GUILD")
    end

    SendToFriends(msg)
end

function C:RequestAll()
    -- PLAYER_ENTERING_WORLD 每次过图/进本都会触发，加 30 秒冷却避免反复刷公会频道
    local now = time()
    if now - (C.lastRequest or 0) < 30 then return end
    C.lastRequest = now

    local msg = "Q"
    if IsInGuild and IsInGuild() then
        SendAM(msg, "GUILD")
    end

    SendToFriends(msg)
end

-- 通讯诊断
function C:Report()
    local out = {}
    out[#out + 1] = "在公会      = " .. tostring(IsInGuild and IsInGuild() and true or false)

    local fcount = 0
    if C_FriendList and C_FriendList.GetNumFriends then
        fcount = tonumber(select(1, C_FriendList.GetNumFriends())) or 0
    elseif GetNumFriends then
        fcount = tonumber(select(1, GetNumFriends())) or 0
    end
    out[#out + 1] = "好友总数    = " .. fcount

    local on = C:OnlineFriends()
    out[#out + 1] = "在线好友    = " .. #on
    for i = 1, math.min(#on, 12) do
        out[#out + 1] = "  好友 " .. i .. " = [" .. on[i] .. "]"
    end

    out[#out + 1] = "BN API      = " .. tostring(BNGetNumFriends ~= nil and BNGetFriendInfo ~= nil)
    if BNGetNumFriends then
        local okn, bnTotal = pcall(BNGetNumFriends)
        out[#out + 1] = "BN 好友总数 = " .. tostring(okn and tonumber(bnTotal) or "err")
    end
    local bn = C:BNToons()
    out[#out + 1] = "BN 在玩WoW   = " .. #bn
    for i = 1, math.min(#bn, 12) do
        out[#out + 1] = "  BN " .. i .. " = [" .. bn[i] .. "]"
    end

    local keys, pc = {}, 0
    if AS.db and AS.db.peers then
        for k in pairs(AS.db.peers) do keys[#keys + 1] = k; pc = pc + 1 end
    end
    out[#out + 1] = "peers 条数  = " .. pc
    table.sort(keys)
    for i = 1, math.min(#keys, 12) do
        out[#out + 1] = "  peers " .. i .. " = [" .. keys[i] .. "]"
    end

    out[#out + 1] = "距上次Q     = " .. (time() - (C.lastRequest or 0)) .. " 秒"
    out[#out + 1] = "前缀已注册  = " .. tostring(C.prefixOK == true)

    C:SaveDiag("comm", out)
    return out
end

--[[-----------------------------------------------------------------------------
接收
-------------------------------------------------------------------------------]]
-- CHAT_MSG_ADDON 的 sender：同服玩家只有角色名，跨服玩家才带 "-真实服务器"。
-- 注意：本客户端的 GetRealmName() 返回的是集群代号（形如 "CN1 Realm 8 PvE"），
-- 与玩家看到的服务器名（如"弥林女王"）并不一致，拿它拼后缀只会拼出错的名字。
-- 所以这里原样保存 sender，需要服务器信息的场合才拼。
local function StoreScore(sender, steps, trips, kcal, dateKey)
    if not sender or sender == "" then return end
    if not AS.db then return end

    steps = tonumber(steps) or 0
    trips = tonumber(trips) or 0
    kcal  = tonumber(kcal) or 0

    -- 自己广播的会被自己收到时忽略（半名与全名两种形态都要拦）
    if AS:IsSelfName(sender) then return end

    AS.db.peers[sender] = {
        steps = steps,
        trips = trips,
        kcal  = kcal,
        date  = dateKey,
        ts    = time(),
    }

    if AS.Panel and AS.Panel.Refresh then AS.Panel:Refresh() end
end

function C:OnMessage(text, sender)
    if type(text) ~= "string" then return end
    if type(sender) ~= "string" then return end

    -- GUILD / CHANNEL 会把消息投回发送者，不加这层会把自己写进 peers
    if AS:IsSelfName(sender) then return end

    local kind = text:sub(1, 1)

    if kind == "S" then
        local steps, trips, kcal, dateKey = text:match("^S|(%d+)|(%d+)|(%d+)|(%d%d%d%d%-%d%d%-%d%d)")
        if steps then StoreScore(sender, steps, trips, kcal, dateKey) end

    elseif kind == "Q" then
        -- 有人要分数：回自己当前这一期的实时成绩。
        -- 早先这里优先回 settled[1]（上一期已结算的成绩），连日期也是上一期的；
        -- 而榜单只认当期，收到的人会把它当成"上期成绩"直接丢掉，等于白问一圈。
        -- 实时排行要的是当期数字，所以这里一律用当期累计值与当期日期。
        local c = AS.char
        if c then
            local msg = string.format("S|%d|%d|%d|%s",
                math.floor(c.steps or 0),
                c.trips or 0,
                math.floor(c.kcal or 0),
                AS:WindowKey())
            -- 只回给请求者本人；再广播一遍会让 N 人互相回消息成 N×N 放大
            SendAM(msg, "WHISPER", sender)
        end
    end
end

--[[-----------------------------------------------------------------------------
点赞
-------------------------------------------------------------------------------]]
function C:CanLike(targetKey)
    if not targetKey or targetKey == "" then return false end
    if targetKey == AS:CharKey() then return false end
    local c = AS.char
    if not c then return false end
    local liked = c.likes[targetKey]
    -- 同一个窗口内只赞一次
    if liked and liked == (c.window or "") then return false end
    return true
end

function C:MarkLiked(targetKey)
    local c = AS.char
    if c then c.likes[targetKey] = c.window or "" end
end

function C:WasLiked(targetKey)
    local c = AS.char
    return c and c.likes[targetKey] == (c.window or "") and true or false
end

function C:SendLike(targetName, targetKey, steps)
    -- 优先用带服务器后缀的 key 当目标：跨服好友只有全名才发得出去
    local dest = targetKey
    if not dest or dest == "" then dest = targetName end
    if not dest or dest == "" then return false end

    C:MarkLiked(dest)

    if not AS:IsLikeWhisperEnabled() then
        return true
    end

    local msg = string.format(
        (AS.S and AS.S.WHISPER_LIKE) or "[StepWarden] gave you a like! You walked %s steps last cycle.",
        AS:Comma(steps or 0)
    )

    local ok, err = pcall(SendChatMessage, msg, "WHISPER", nil, dest)
    if not ok and AS.Print then
        -- 以前这里静默吞掉错误，玩家只会觉得"点赞了但没收到密语"
        AS:Print(string.format(
            (AS.S and AS.S.LIKE_WS_FAIL) or "Whisper to %s failed.", dest))
    end
    return ok
end

--[[-----------------------------------------------------------------------------
事件
-------------------------------------------------------------------------------]]
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
    if event ~= "CHAT_MSG_ADDON" then return end
    if prefix ~= C.PREFIX then return end
    C:OnMessage(text, sender)
end)
pcall(f.RegisterEvent, f, "CHAT_MSG_ADDON")

RegisterPrefix()

--[[-----------------------------------------------------------------------------
自动诊断
加载后自动把运行环境写进存档，省得手动敲命令再截图。
存档只在 reload/logout 时落盘，所以要跑两次 /reload 才能读到。
------------------------------------------------------------------------------]]
local function autoDiag()
    pcall(function()
        if type(C.Report) == "function" then C:SaveDiag("comm", C:Report()) end
        if type(C.BNApi) == "function" then C:SaveDiag("bn", C:BNApi()) end
    end)
end

local diagDone = false
local function scheduleDiag()
    if diagDone then return end
    diagDone = true
    autoDiag()
    -- 诊断结果照常写进存档，但不再往聊天框打提示，免得每次登录都刷一条
end

if C_Timer and C_Timer.After then
    C_Timer.After(5, scheduleDiag)
else
    -- 老客户端没有 C_Timer，退到 OnUpdate 计时
    local tick, elapsed = 0, 0
    local tf = CreateFrame("Frame")
    tf:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 5 then
            self:SetScript("OnUpdate", nil)
            scheduleDiag()
        end
    end)
end
