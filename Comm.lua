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
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local ok, err = pcall(C_ChatInfo.SendAddonMessage, C.PREFIX, msg, channel, target)
        return ok
    end
    if SendAddonMessage then
        local ok, err = pcall(SendAddonMessage, C.PREFIX, msg, channel, target)
        return ok
    end
    return false
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

function C:FriendCount()
    return #C:OnlineFriends()
end

--[[-----------------------------------------------------------------------------
发送
-------------------------------------------------------------------------------]]
-- 好友分批发送：暴雪对 addon message 有节流（约 1 条/秒），
-- 一次性发几十条会被静默丢弃，所以每次只发 2 条、间隔 0.5 秒。
local function SendToFriends(msg)
    local friends = C:OnlineFriends()
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
        -- 有人要分数：回一条自己最近一期的
        local c = AS.char
        if c then
            local mine = c.settled and c.settled[1]
            local entry = {
                steps = mine and mine.steps or math.floor(c.steps or 0),
                trips = mine and mine.trips or c.trips or 0,
                kcal  = mine and mine.kcal or math.floor(c.kcal or 0),
                date  = mine and mine.date or AS:WindowKey(),
            }
            local msg = string.format("S|%d|%d|%d|%s",
                entry.steps, entry.trips, entry.kcal, entry.date)
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
