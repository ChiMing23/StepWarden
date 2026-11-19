--[[-----------------------------------------------------------------------------
StepWarden - Stats
步数与交通工具统计、每日 22:00 结算
-------------------------------------------------------------------------------]]
local ADDON, AS = ...

AS.Stats = AS.Stats or {}
local S = AS.Stats

-- 判定为«传送»的法术 ID（炉石、法师传送、德鲁伊传送）
S.TELEPORT_SPELLS = {
    [8690]  = true,  -- 炉石
    [3561]  = true,  -- 传送：暴风城
    [3562]  = true,  -- 传送：铁炉堡
    [3563]  = true,  -- 传送：幽暗城
    [3565]  = true,  -- 传送：达纳苏斯
    [3567]  = true,  -- 传送：雷霆崖
    [32271] = true,  -- 传送：埃索达
    [32272] = true,  -- 传送：银月城
    [49359] = true,  -- 传送：塞拉摩
    [49360] = true,  -- 传送：斯通纳德
    [18960] = true,  -- 传送：月光林地
    [23453] = true,  -- 工程：空间传送器（备用）
}

local acc = 0
local windowCheck = 0
local wasOnTaxi = false
local lostSince = 0
local lost = false
local boatCounted = false

local function SafeRegister(f, ev)
    if not f or not ev then return end
    pcall(f.RegisterEvent, f, ev)
end

-- 速度积分
function S:Tick(dt)
    local c = AS.char
    if not c then return end

    -- 记下最后一次在线的时刻。结算时一并归档，
    -- 这样"离线期间按当日最后记录上榜"这件事有据可查。
    c.lastSeen = time()

    local onTaxi = false
    if UnitOnTaxi then
        local ok, v = pcall(UnitOnTaxi, "player")
        if ok then onTaxi = v and true or false end
    end

    -- 上了飞行点的鸟：一次出行记一次
    if onTaxi and not wasOnTaxi then
        S:AddTrip("flight")
    end
    wasOnTaxi = onTaxi

    local mounted = false
    if IsMounted then
        local ok, v = pcall(IsMounted)
        if ok then mounted = v and true or false end
    end

    local flying = false
    if IsFlying then
        local okf, vf = pcall(IsFlying)
        if okf then flying = vf and true or false end
    end

    local speed = 0
    if GetUnitSpeed then
        local ok, v = pcall(GetUnitSpeed, "player")
        if ok and type(v) == "number" then speed = v end
    end
    if issecretvalue and speed ~= nil and issecretvalue(speed) then speed = 0 end

    if speed > 0 then
        local yards = speed * dt

        if onTaxi then
            -- 飞行点出行：只累计距离，不计步数与卡路里
            c.yards = (c.yards or 0) + yards
            c.rideSec = (c.rideSec or 0) + dt

        elseif lost then
            -- 脱离控制（船、飞艇、剧情传送）
            c.yards = (c.yards or 0) + yards
            c.rideSec = (c.rideSec or 0) + dt

        elseif mounted then
            -- 地面坐骑：按种族坐骑步距计步，步频与徒步接近；飞行坐骑只计距离
            c.yards = (c.yards or 0) + yards
            c.mountSec = (c.mountSec or 0) + dt
            if not flying then
                local rate = speed * AS:GetMountStride()
                if rate > AS.MAX_STEP_RATE then rate = AS.MAX_STEP_RATE end
                local steps = rate * dt
                c.steps = (c.steps or 0) + steps
                c.kcal  = (c.kcal or 0) + steps * (c.raceMul or AS.RACE_DEFAULT)
            end

        else
            -- 两条腿走路
            c.yards = (c.yards or 0) + yards
            local rate = speed * AS.STEPS_PER_YARD
            if rate > AS.MAX_STEP_RATE then rate = AS.MAX_STEP_RATE end
            local steps = rate * dt
            c.steps = (c.steps or 0) + steps
            c.kcal  = (c.kcal or 0) + steps * (c.raceMul or AS.RACE_DEFAULT)
            c.walkSec = (c.walkSec or 0) + dt
        end

    elseif onTaxi then
        c.rideSec = (c.rideSec or 0) + dt
    end
end

function S:AddTrip(kind, n)
    local c = AS.char
    if not c then return end
    n = n or 1
    c.trips = (c.trips or 0) + n
    if kind == "flight" then
        c.tripFlight = (c.tripFlight or 0) + n
    elseif kind == "boat" then
        c.tripBoat = (c.tripBoat or 0) + n
    else
        c.tripTele = (c.tripTele or 0) + n
    end
end

-- 结算：把当前窗口冻结进历史，并广播给好友
function S:Settle(key)
    local c = AS.char
    if not c then return end

    key = key or c.window or AS:WindowKey()
    local entry = {
        date     = key,
        steps    = math.floor(c.steps or 0),
        trips    = c.trips or 0,
        tripFlight = c.tripFlight or 0,
        tripBoat   = c.tripBoat or 0,
        tripTele   = c.tripTele or 0,
        kcal     = math.floor(c.kcal or 0),
        yards    = math.floor(c.yards or 0),
        walkSec  = math.floor(c.walkSec or 0),
        mountSec = math.floor(c.mountSec or 0),
        rideSec  = math.floor(c.rideSec or 0),
        race     = AS:GetRaceToken(),
        owner    = AS:CharKey(),
        lastSeen = c.lastSeen or 0,
    }

    -- 同一天可能被重复结算（/step test、系统时间回拨、反复跨窗口），
    -- 旧版本也留过同日期两条的记录。新条目插到最前面之后，
    -- 整张表按日期扫一遍，每个日期只留排在最前（也就是最新）的那条。
    table.insert(c.settled, 1, entry)
    do
        local seen, i = { }, 1
        while i <= #c.settled do
            local e = c.settled[i]
            local d = (type(e) == "table" and type(e.date) == "string") and e.date or nil
            if not d then
                table.remove(c.settled, i)      -- 结构残缺的条目直接丢掉
            elseif seen[d] then
                table.remove(c.settled, i)      -- 同日期重复，留前面那条
            else
                seen[d] = true
                i = i + 1
            end
        end
    end
    while #c.settled > AS.KEEP_DAYS do
        table.remove(c.settled)
    end

    -- 冻结当天的排行榜，供历史记录页回看。
    -- 必须在这里取，因为 peers 只缓存最新一期的数据，过了这天就被覆盖了。
    if AS.db then
        if type(AS.db.snapshots) ~= "table" then AS.db.snapshots = {} end
        local snap = {}
        local ok, rows = pcall(S.BuildRanking, S)
        if not ok then
            -- 以前这里静默吞掉，出问题时快照会是空表，看起来就像"没归档"
            AS:Print("[StepWarden] 快照构建失败：" .. tostring(rows))
            rows = nil
        end
        if ok and type(rows) == "table" then
            for _, r in ipairs(rows) do
                snap[#snap + 1] = {
                    key   = r.key,
                    name  = r.name,
                    steps = math.floor(r.steps or 0),
                    trips = r.trips or 0,
                    kcal  = math.floor(r.kcal or 0),
                    isMe  = r.isMe and true or nil,
                }
            end
        end
        AS.db.snapshots[key] = snap

        -- 只留最近 HIST_DAYS 期
        local dates = {}
        for d in pairs(AS.db.snapshots) do dates[#dates + 1] = d end
        table.sort(dates)
        while #dates > (AS.HIST_DAYS or 3) do
            AS.db.snapshots[dates[1]] = nil
            table.remove(dates, 1)
        end
    end

    -- 自己的分数也进 peers，方便统一排序
    if AS.db then
        AS.db.peers[AS:CharKey()] = {
            steps = entry.steps,
            trips = entry.trips,
            kcal  = entry.kcal,
            date  = entry.date,
            ts    = time(),
            isMe  = true,
        }
    end

    if AS.Comm and AS.Comm.BroadcastScore then
        AS.Comm:BroadcastScore(entry)
    end

    -- 归档写完就开始新的一天：当日数字归零、好友排行清空。
    -- 顺序必须在写快照之后，否则刚冻结的那份会被清掉。
    S:ResetDay()

    if AS.Panel and AS.Panel.Refresh then AS.Panel:Refresh() end
end

-- 归档之后把当天从头开始。
-- 归档过的东西已经落在 settled（个人成绩）和 snapshots（当期排行）里，
-- 这里清的是"今天这一份"，所以历史不受影响。
function S:ResetDay()
    local c = AS.char
    if not c then return end

    c.yards     = 0
    c.steps     = 0
    c.kcal      = 0
    c.trips     = 0
    c.tripFlight = 0
    c.tripBoat   = 0
    c.tripTele   = 0
    c.walkSec   = 0
    c.mountSec  = 0
    c.rideSec   = 0
    c.window    = AS:WindowKey()

    -- 好友排行不跨期保留：新一天各自重新计步，靠广播重新汇聚
    local peers = AS.db and AS.db.peers
    if type(peers) == "table" then
        for k in pairs(peers) do peers[k] = nil end
    end
end

-- 排行榜：自己 + 好友缓存，按步数降序
function S:BuildRanking()
    local rows = {}
    local c = AS.char
    if not c then return rows end

    table.insert(rows, {
        key   = AS:CharKey(),      -- 全名，供密语等需要服务器的场合使用
        name  = AS:ShortName(),    -- 角色名
        steps = c.steps or 0,
        trips = c.trips or 0,
        kcal  = c.kcal or 0,
        date  = AS:WindowKey(),
        isMe  = true,
    })

    if AS.db and AS.db.peers then
        local myFull = (AS:ShortName() or ""):lower()
        -- UnitName 只给名字第一段，所以半名和全名两种形态都要排除，否则自己占两行
        local myBase = (AS:NamePart(UnitName("player") or "") or ""):lower()
        -- 只认当期广播：好友下线后 peers 里那份成绩会一直留着，
        -- 不按日期筛的话，几天没上线的人会一直在今日榜上挂着。
        --
        -- 但对方给的 date 不能全信。结算与 Q 应答在旧版里都可能带上"上一期"的
        -- 日期，只按 date 比对会把在线的人误判成上期成绩剔掉。所以 date 对不上
        -- 时改用 ts 兜底：一天以内有过广播的照收，超过一天才算真的过期。
        local curWin = AS:WindowKey()
        local now = time()
        for key, p in pairs(AS.db.peers) do
            if type(p) == "table" then
                local nm = AS:NamePart(key)
                local low = nm:lower()
                local stale
                if p.date == curWin then
                    stale = false
                else
                    stale = (now - (p.ts or 0)) > 86400
                end
                if not stale and key ~= AS:CharKey() and low ~= myFull and low ~= myBase then
                    table.insert(rows, {
                        key   = key,               -- 全名
                        name  = nm,                -- 角色名
                        steps = p.steps or 0,
                        trips = p.trips or 0,
                        kcal  = p.kcal or 0,
                        date  = p.date or "",
                        ts    = p.ts,
                        isPeer = true,
                    })
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if (a.steps or 0) == (b.steps or 0) then
            return (a.name or "") < (b.name or "")
        end
        return (a.steps or 0) > (b.steps or 0)
    end)

    return rows
end

--[[-----------------------------------------------------------------------------
历史查询（给「过去 3 天」用）
-------------------------------------------------------------------------------]]

-- 历史页要显示的三期：从"刚走完的那一天"往前数，永远是最新三个已归档的日期。
-- 结算归档用的就是这个窗口键，所以第 i 期 = 当前窗口往前 i-1 天。
-- 结算之后窗口前移一天，这三个日期自动整体后移，不用等人来手动刷新。
-- 某一期没有快照（早期版本还没写快照功能）时日期照样占一格，
-- 点进去由 RankingFromSnapshot 降级成"只有自己"，不至于整页空白。
-- 不再用"存档里恰好有哪几期"来决定标签，否则缺一期标签就少一格。
function S:HistDates()
    local out = { }
    local days = AS.HIST_DAYS or 3
    for i = 1, days do
        out[#out + 1] = AS:DayKeysBefore(i - 1)
    end
    return out
end

-- 某一天的个人成绩：先找 settled，找不到就从快照里认自己那条
function S:HistEntry(date)
    local c = AS.char
    if c and type(c.settled) == "table" then
        for _, e in ipairs(c.settled) do
            if type(e) == "table" and e.date == date then return e end
        end
    end

    local snap = AS.db and AS.db.snapshots and AS.db.snapshots[date]
    if type(snap) == "table" then
        local meBase = (AS:NamePart(UnitName("player") or "") or ""):lower()
        local myFull = (AS:ShortName() or ""):lower()
        for _, r in ipairs(snap) do
            local nm = (r.name or ""):lower()
            if r.isMe or nm == meBase or nm == myFull then
                return {
                    date    = date,
                    steps   = r.steps or 0,
                    trips   = r.trips or 0,
                    kcal    = r.kcal or 0,
                    yards   = 0,
                    walkSec = 0,
                    mountSec = 0,
                    rideSec = 0,
                }
            end
        end
    end
    return nil
end

-- 把某天的快照转成和「今日排行榜」同构的列表，便于面板复用同一套行渲染
function S:RankingFromSnapshot(date)
    local rows = { }

    local snap = AS.db and AS.db.snapshots and AS.db.snapshots[date]
    if type(snap) ~= "table" or #snap == 0 then
        -- 这一期是在「快照功能上线前」结算的，只留下了个人成绩。
        -- 至少把自己那一行补上，历史页不至于整页空白。
        local e = S:HistEntry(date)
        if e then
            rows[1] = {
                key = AS:CharKey(), name = AS:ShortName(),
                steps = e.steps or 0, trips = e.trips or 0, kcal = e.kcal or 0,
                date = date, isMe = true, isHist = true,
            }
        end
        return rows
    end

    local meBase = (AS:NamePart(UnitName("player") or "") or ""):lower()
    local myFull = (AS:ShortName() or ""):lower()

    for i = 1, #snap do
        local r = snap[i]
        if type(r) == "table" then
            local nm = (r.name or ""):lower()
            rows[#rows + 1] = {
                key    = r.key,
                name   = r.name,
                steps  = r.steps or 0,
                trips  = r.trips or 0,
                kcal   = r.kcal or 0,
                date   = date,
                isMe   = (r.isMe or (nm ~= "" and (nm == meBase or nm == myFull))) and true or nil,
                isHist = true,
            }
        end
    end

    table.sort(rows, function(a, b)
        if (a.steps or 0) == (b.steps or 0) then
            return (a.name or "") < (b.name or "")
        end
        return (a.steps or 0) > (b.steps or 0)
    end)

    return rows
end

-- 供面板滚轮判断榜单是否还有下一页
function S:GetRankingCount()
    return #S:BuildRanking()
end

function S:MyRank()
    local rows = S:BuildRanking()
    for i = 1, #rows do
        if rows[i].isMe then return i, #rows end
    end
    return 0, #rows
end

--[[-----------------------------------------------------------------------------
驱动
-------------------------------------------------------------------------------]]
local driver = CreateFrame("Frame", nil, UIParent)
driver:SetSize(1, 1)
driver:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200)
driver:SetAlpha(0)
driver:SetScript("OnUpdate", function(_, elapsed)
    if not AS.char then return end
    if elapsed > AS.MAX_STEP_DT then return end

    acc = acc + elapsed
    if acc < AS.SAMPLE_DT then return end
    S:Tick(acc)
    acc = 0

    windowCheck = windowCheck + elapsed
    if windowCheck >= 10 then
        windowCheck = 0
        AS:RefreshWindow()
    end
end)

--[[-----------------------------------------------------------------------------
事件
-------------------------------------------------------------------------------]]
local function OnEvent(self, event, ...)
    if not AS.char then return end

    if event == "PLAYER_CONTROL_LOST" then
        lost = true
        lostSince = time()
        boatCounted = false

    elseif event == "PLAYER_CONTROL_GAINED" then
        lost = false

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- 脱离控制后很快换了区域：判定为坐船/飞艇
        local onTaxi = false
        if UnitOnTaxi then
            local ok, v = pcall(UnitOnTaxi, "player")
            if ok then onTaxi = v and true or false end
        end
        if lost and not onTaxi and not boatCounted and (time() - lostSince) <= 8 then
            boatCounted = true
            S:AddTrip("boat")
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and spellID and S.TELEPORT_SPELLS[spellID] then
            S:AddTrip("tele")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        AS:RefreshWindow()
        if AS.Comm and AS.Comm.RequestAll then AS.Comm:RequestAll() end
    end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", OnEvent)
SafeRegister(ev, "PLAYER_CONTROL_LOST")
SafeRegister(ev, "PLAYER_CONTROL_GAINED")
SafeRegister(ev, "ZONE_CHANGED_NEW_AREA")
SafeRegister(ev, "UNIT_SPELLCAST_SUCCEEDED")
SafeRegister(ev, "PLAYER_ENTERING_WORLD")
SafeRegister(ev, "PLAYER_LOGIN")
