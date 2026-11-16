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
        date   = key,
        steps  = math.floor(c.steps or 0),
        trips  = c.trips or 0,
        kcal   = math.floor(c.kcal or 0),
        yards  = math.floor(c.yards or 0),
        race   = AS:GetRaceToken(),
        owner  = AS:CharKey(),
    }

    table.insert(c.settled, 1, entry)
    while #c.settled > AS.KEEP_DAYS do
        table.remove(c.settled)
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

    if AS.Panel and AS.Panel.Refresh then AS.Panel:Refresh() end
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
        local myName = (AS:ShortName() or ""):lower()
        for key, p in pairs(AS.db.peers) do
            local nm = AS:NamePart(key)
            if key ~= AS:CharKey() and nm:lower() ~= myName and type(p) == "table" then
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

    table.sort(rows, function(a, b)
        if (a.steps or 0) == (b.steps or 0) then
            return (a.name or "") < (b.name or "")
        end
        return (a.steps or 0) > (b.steps or 0)
    end)

    return rows
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
