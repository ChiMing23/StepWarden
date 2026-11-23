--[[-----------------------------------------------------------------------------
StepWarden - Core
初始化、存档、公共函数与扁平化皮肤工具
-------------------------------------------------------------------------------]]
local ADDON, AS = ...

AS.ADDON   = ADDON
AS.VERSION = "V1.0.75"

-- 每晚结算的小时（服务器/本地时间），到点后开启新的一天
AS.SETTLE_HOUR = 22

-- 统计口径
AS.YARDS_PER_METER = 1.0936      -- 1 码 = 0.9144 米
AS.STEPS_PER_YARD  = 0.42        -- 每码折算步数（游戏跑速远高于现实，按步频校准）
AS.MAX_STEP_RATE   = 3.2         -- 每秒步数上限，防止速度插值把数字冲飞
AS.MAX_STEP_DT     = 0.5         -- 单帧最大积分时长，防卡顿跳变
AS.SAMPLE_DT       = 0.2         -- 速度采样节流
AS.KEEP_DAYS       = 7           -- 保留最近几期结算
AS.HIST_DAYS       = 3           -- 历史记录页展示最近几期（个人数据与好友排行快照）

-- 皮肤
AS.WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
AS.ACCENT   = { 128, 128, 255 }  -- 与 MinimapStats 保持同一强调色

--[[-----------------------------------------------------------------------------
种族虚拟代谢系数：每走一步折算的卡路里（纯趣味值，按体型给档）
体型越大越费劲，亡灵没肉、侏儒地精最小
-------------------------------------------------------------------------------]]
AS.RACE_MUL = {
    Tauren   = 0.085,
    Pandaren = 0.070,
    Draenei  = 0.065,
    Orc      = 0.060,
    Dwarf    = 0.055,
    Worgen   = 0.055,
    Human    = 0.045,
    Troll    = 0.042,
    NightElf = 0.040,
    BloodElf = 0.038,
    Undead   = 0.030,
    Gnome    = 0.022,
    Goblin   = 0.020,
}
AS.RACE_DEFAULT = 0.045

AS.RACE_BY_ID = {
    [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf",
    [5] = "Undead", [6] = "Tauren", [7] = "Gnome", [8] = "Troll",
    [9] = "Goblin", [10] = "BloodElf", [11] = "Draenei",
    [22] = "Worgen", [24] = "Pandaren", [25] = "Pandaren", [26] = "Pandaren",
}

AS.RACE_CN = {
    ["人类"] = "Human", ["兽人"] = "Orc", ["矮人"] = "Dwarf",
    ["暗夜精灵"] = "NightElf", ["亡灵"] = "Undead", ["牛头人"] = "Tauren",
    ["侏儒"] = "Gnome", ["巨魔"] = "Troll", ["地精"] = "Goblin",
    ["血精灵"] = "BloodElf", ["德莱尼"] = "Draenei", ["狼人"] = "Worgen",
    ["熊猫人"] = "Pandaren",
}

AS.locale = "zhCN"
AS.S = AS.S or {}

function AS:SetLocale(code)
    if not AS.L then return end
    if code ~= "zhCN" and code ~= "enUS" then code = "zhCN" end
    AS.locale = code
    AS.S = AS.L[code] or AS.L.zhCN
end

--[[-----------------------------------------------------------------------------
事件分发（不依赖 Ace3，保持零依赖）
-------------------------------------------------------------------------------]]
local listeners = {}

function AS:On(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return end
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function AS:Fire(event, ...)
    local t = listeners[event]
    if not t then return end
    for i = 1, #t do
        local ok, err = pcall(t[i], event, ...)
        if not ok and not AS._errShown then
            AS._errShown = true
            AS:Print((AS.S and AS.S.ERR_INTERNAL or "|cffff5555Internal error: ") .. tostring(err) .. "|r")
        end
    end
end

--[[-----------------------------------------------------------------------------
基础工具
-------------------------------------------------------------------------------]]
function AS:Print(msg)
    local frame = DEFAULT_CHAT_FRAME or _G.ChatFrame1
    local prefix = (AS.S and AS.S.PREFIX) or "|cff8080ff[StepWarden]|r "
    if frame then frame:AddMessage(prefix .. tostring(msg)) end
end

function AS:CharKey()
    local n = UnitName("player") or "?"
    -- UnitName 在部分客户端已带 "-服务器" 后缀，再拼一次会变成 名字-服务器-服务器
    if n:find("-", 1, true) then return n end
    local r = GetRealmName() or "?"
    return n .. "-" .. r
end

-- 从 "Name-Realm" / "Name Realm" / "Name" 里取出纯角色名
function AS:NamePart(s)
    if type(s) ~= "string" or s == "" then return "" end
    -- 只剥掉 "-服务器" 后缀，名字内部的空格必须保留。
    -- 无限服支持 6+6 的十二字命名（如 "全境守护者 弥林女王"），空格是名字的一部分，
    -- 早期写法用 "^([^%s%-]+)" 会在空格处截断，导致只显示前六个字。
    local i = s:find("-", 1, true)
    if i then
        local head = s:sub(1, i - 1)
        if head ~= "" then return head end
    end
    return s
end

-- 从 "名字-服务器" 里取出服务器段；没有后缀返回 nil
function AS:RealmPart(s)
    if type(s) ~= "string" then return nil end
    local r = s:match("%-(.*)$")
    if not r or r == "" or r == s then return nil end
    return r
end


-- UnitName 在无限服只返回名字的第一段（如 "全境守护者"），第二段拿不到。
-- 但消息里的 sender 是完整 6+6 全名，所以从 peers 里把自己认回来：
-- 找唯一一个「以本段开头、后接空格」的键，那就是自己的完整角色名。
function AS:SelfFullName()
    local base = AS:NamePart(UnitName("player") or "")
    if base == "" then return "?" end
    if not (AS.db and AS.db.peers) then return base end

    local cand, cnt = nil, 0
    for k in pairs(AS.db.peers) do
        local nm = AS:NamePart(k)
        if nm ~= base and nm:sub(1, #base + 1) == base .. " " then
            cnt = cnt + 1
            cand = nm
        end
    end
    if cnt == 1 then return cand end
    return base
end

function AS:ShortName()
    return AS:SelfFullName()
end

-- 判断某个 sender / 名字是不是自己：半名和全名两种形态都算
function AS:IsSelfName(s)
    if type(s) ~= "string" or s == "" then return false end
    local sn = (AS:NamePart(s) or ""):lower()
    if sn == "" then return false end
    local full = (AS:SelfFullName() or ""):lower()
    local base = (AS:NamePart(UnitName("player") or "") or ""):lower()
    return sn == full or sn == base
end

-- 诊断：把名字相关的实际取值一次性打出来
function AS:NameReport()
    local base = AS:NamePart(UnitName("player") or "")
    local list = {}
    list[#list + 1] = "UnitName      = [" .. tostring(UnitName("player")) .. "]"
    if GetUnitName then
        local ok, v = pcall(GetUnitName, "player")
        list[#list + 1] = "GetUnitName   = [" .. tostring(ok and v or "err") .. "]"
    else
        list[#list + 1] = "GetUnitName   = (nil)"
    end
    if UnitFullName then
        local ok, a, b = pcall(UnitFullName, "player")
        list[#list + 1] = "UnitFullName  = [" .. tostring(ok and a or "err") .. "] / [" .. tostring(ok and b or "") .. "]"
    else
        list[#list + 1] = "UnitFullName  = (nil)"
    end
    list[#list + 1] = "GetRealmName  = [" .. tostring(GetRealmName()) .. "]"
    list[#list + 1] = "NamePart      = [" .. base .. "]"
    list[#list + 1] = "CharKey       = [" .. AS:CharKey() .. "]"
    list[#list + 1] = "SelfFullName  = [" .. AS:SelfFullName() .. "]"

    if AS.db and AS.db.peers then
        local hits = {}
        for k in pairs(AS.db.peers) do
            local nm = AS:NamePart(k)
            if nm:sub(1, #base) == base then hits[#hits + 1] = k end
        end
        table.sort(hits)
        for i = 1, #hits do
            list[#list + 1] = "peers 命中 " .. i .. " = [" .. hits[i] .. "]"
        end
    end
    return list
end

-- 当前统计窗口的起点时刻：22:00 前属于前一天
function AS:WindowBase(t)
    t = t or time()
    local h = tonumber(date("%H", t)) or 0
    return h < AS.SETTLE_HOUR and (t - 86400) or t
end

-- 当前统计窗口的标识：22:00 前属于前一天
function AS:WindowKey(t)
    return date("%Y-%m-%d", AS:WindowBase(t))
end

-- 当前窗口往前 n 天的日期键。给历史页算「过去三天」用。
-- 结算归档用的就是窗口键，所以第 i 期正是"当前窗口往前 i 天"，
-- 不依赖存档里恰好存在几期快照，缺数据的那期自然显示为空。
function AS:DayKeysBefore(n)
    local base = AS:WindowBase()
    return date("%Y-%m-%d", base - (n or 1) * 86400)
end

-- 日期键往后挪一天。"2026-11-30" -> "2026-12-01"，跨月跨年闰月都算。
-- WoW 的 os.time 不收表参数，所以只能自己排日历。
function AS:NextDayKey(key)
    local y, m, d = tostring(key or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return key end
    local yy, mm, dd = tonumber(y), tonumber(m), tonumber(d)
    local mdays = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    local leap = ((yy % 4 == 0) and (yy % 100 ~= 0)) or (yy % 400 == 0)
    if leap then mdays[2] = 29 end
    dd = dd + 1
    if dd > mdays[mm] then
        dd = 1
        mm = mm + 1
        if mm > 12 then mm = 1; yy = yy + 1 end
    end
    return string.format("%04d-%02d-%02d", yy, mm, dd)
end

-- 把 "V1.0.6.5" 这类版本号压成可比较的整数。
-- 段数不一样（1.0.7 是三段、1.0.6.5 是四段）时必须按四段补齐再比，
-- 否则位数不同会得出"1.0.6.5 比 1.0.7 新"这种反向结论。
function AS:VersionRank(v)
    local parts = { 0, 0, 0, 0 }
    local i = 1
    for p in tostring(v or ""):gmatch("%d+") do
        if i > 4 then break end
        parts[i] = tonumber(p) or 0
        i = i + 1
    end
    return ((parts[1] * 1000 + parts[2]) * 1000 + parts[3]) * 1000 + parts[4]
end

-- 距下次结算还有多少秒
function AS:SecondsToSettle()
    local t = time()
    local h = tonumber(date("%H", t)) or 0
    local m = tonumber(date("%M", t)) or 0
    local s = tonumber(date("%S", t)) or 0
    local now = h * 3600 + m * 60 + s
    local target = AS.SETTLE_HOUR * 3600
    local left = target - now
    if left < 0 then left = left + 86400 end
    return left
end

function AS:GetRaceToken()
    local raceName, raceToken, raceID = UnitRace("player")
    if type(raceToken) == "string" and AS.RACE_MUL[raceToken] then
        return raceToken
    end
    if type(raceID) == "number" and AS.RACE_BY_ID[raceID] then
        return AS.RACE_BY_ID[raceID]
    end
    if type(raceName) == "string" then
        if AS.RACE_CN[raceName] then return AS.RACE_CN[raceName] end
        if AS.RACE_MUL[raceName] then return raceName end
    end
    return nil
end

function AS:GetRaceLabel()
    local token = AS:GetRaceToken()
    if token then
        local key = "RACE_" .. string.upper(token)
        if AS.S and AS.S[key] then return AS.S[key] end
        return token
    end
    return (AS.S and AS.S.UNKNOWN) or "Unknown"
end

function AS:GetRaceMul()
    local token = AS:GetRaceToken()
    if token and AS.RACE_MUL[token] then return AS.RACE_MUL[token] end
    return AS.RACE_DEFAULT
end

-- 地面坐骑步距（步/码）。坐骑满速约为徒步的 2 倍，所以取值约为 0.42 的一半，
-- 保证骑乘步频与徒步接近；步距越大（如科多兽），同样距离步数越少。
AS.RACE_MOUNT_STRIDE = {
    Tauren   = 0.17,   -- 科多兽，步伐最大
    Pandaren = 0.18,   -- 龙
    Draenei  = 0.18,   -- 雷象
    Orc      = 0.19,   -- 狼
    NightElf = 0.19,   -- 夜刃豹
    Human    = 0.20,   -- 马
    Worgen   = 0.20,   -- 马
    Undead   = 0.20,   -- 骷髅马
    Dwarf    = 0.21,   -- 山羊
    Troll    = 0.21,   -- 迅猛龙
    BloodElf = 0.22,   -- 陆行鸟
    Gnome    = 0.22,   -- 机械陆行鸟，步伐最小
    Goblin   = 0.22,   -- 三轮车
}
AS.MOUNT_STRIDE_DEFAULT = 0.20

function AS:GetMountStride()
    local token = AS:GetRaceToken()
    if token and AS.RACE_MOUNT_STRIDE[token] then return AS.RACE_MOUNT_STRIDE[token] end
    return AS.MOUNT_STRIDE_DEFAULT
end

-- 数字千分位
function AS:Comma(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out
end

--[[-----------------------------------------------------------------------------
扁平化皮肤工具（与 MinimapStats 面板同一套做法）
-------------------------------------------------------------------------------]]
function AS:AccentRGB()
    local a = AS.ACCENT
    return a[1] / 255, a[2] / 255, a[3] / 255
end

function AS.FlatTex(tex, r, g, b, a)
    if not tex then return end
    tex:SetTexture(AS.WHITE8X8)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
end

function AS.Solid(obj)
    if not obj then return nil end
    if obj.AS_BG then return obj.AS_BG end
    local bg = obj:CreateTexture(nil, "ARTWORK")
    bg:SetAllPoints(obj)
    AS.FlatTex(bg, 1, 1, 1, 1)
    obj.AS_BG = bg
    return bg
end

function AS.BlankTextures(obj)
    if not obj or not obj.GetRegions then return end
    for _, r in ipairs({ obj:GetRegions() }) do
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            r:SetAlpha(0)
        end
    end
end

function AS.FlatBackdrop(frame, br, bg_, bb, ba, er, eg, eb, ea, edgeSize)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile  = AS.WHITE8X8,
        edgeFile = AS.WHITE8X8,
        tile = false,
        edgeSize = edgeSize or 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(br, bg_, bb, ba)
    if er then
        frame:SetBackdropBorderColor(er, eg, eb, ea)
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function AS.FontString(parent, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "")
    fs:SetShadowColor(0, 0, 0, 0)
    return fs
end

--[[-----------------------------------------------------------------------------
存档
-------------------------------------------------------------------------------]]
function AS:InitDB()
    if type(AzerothStepsDB) ~= "table" then AzerothStepsDB = {} end
    local db = AzerothStepsDB

    if type(db.chars) ~= "table" then db.chars = {} end
    if type(db.peers) ~= "table" then db.peers = {} end
    if type(db.settings) ~= "table" then db.settings = {} end
    if db.settings.likeWhisper == nil then db.settings.likeWhisper = true end
    if db.settings.bgAlpha == nil then db.settings.bgAlpha = 0.85 end
    if db.settings.pinned == nil then db.settings.pinned = false end
    if db.settings.locale ~= "zhCN" and db.settings.locale ~= "enUS" then
        db.settings.locale = "zhCN"
    end
    AS:SetLocale(db.settings.locale)
    if db.settings.showMini == nil then db.settings.showMini = true end
    db.settings.stepRate = nil   -- 步频固定，不再允许玩家调整
    if db.version == nil then db.version = 1 end

    local key = AS:CharKey()

    -- 旧版本会把自己写进 peers，这里自清洁。
    -- 只能用 UnitName 的半名当基准：ShortName() 会反过来读 peers 找全名，
    -- 在这里调用会形成循环依赖，把别人也判错删掉。
    if db.peers then
        local myBase = (AS:NamePart(UnitName("player") or "") or ""):lower()
        for pk in pairs(db.peers) do
            local pn = (AS:NamePart(pk)):lower()
            if pk == key or (myBase ~= "" and pn == myBase) then
                db.peers[pk] = nil
            end
        end
    end
    if type(db.chars[key]) ~= "table" then db.chars[key] = {} end
    local c = db.chars[key]

    -- 每日结算时冻结的排行快照，供历史记录页回看
    if type(db.snapshots) ~= "table" then db.snapshots = {} end

    c.window      = c.window or ""
    c.yards       = c.yards or 0
    c.steps       = c.steps or 0
    c.kcal        = c.kcal or 0
    c.trips       = c.trips or 0
    c.tripFlight  = c.tripFlight or 0
    c.tripBoat    = c.tripBoat or 0
    c.tripTele    = c.tripTele or 0
    c.lastSeen    = c.lastSeen or 0
    c.walkSec     = c.walkSec or 0
    c.mountSec    = c.mountSec or 0
    c.rideSec     = c.rideSec or 0
    c.raceMul     = c.raceMul or AS:GetRaceMul()
    if type(c.settled) ~= "table" then c.settled = {} end
    if type(c.likes) ~= "table" then c.likes = {} end

    -- 一次性迁移（schema 1 -> 2）。
    -- 旧版本归档时用的是"这一期的起点日"（22:00 之前算前一天的那个窗口键），
    -- 所以 11-18 结算出来的成绩被记在了 11-17 名下，历史页看起来永远差一天。
    -- 现在结算改按"刚走完的那一天"归档，已有数据整体后移一天即可对齐。
    -- 只做一次，之后靠 db.schema 挡住，避免反复挪动。
    if (tonumber(db.schema) or 0) < 2 then
        local shifted = { }
        if type(db.snapshots) == "table" then
            for k, v in pairs(db.snapshots) do
                shifted[AS:NextDayKey(k)] = v
            end
        end
        db.snapshots = shifted

        for _, cc in pairs(type(db.chars) == "table" and db.chars or { }) do
            if type(cc.settled) == "table" then
                for _, e in ipairs(cc.settled) do
                    if type(e) == "table" and type(e.date) == "string" then
                        e.date = AS:NextDayKey(e.date)
                    end
                end
                -- 挪完之后可能有两条挤到同一天，只留最前面（最新）的那条
                local seen, i = { }, 1
                while i <= #cc.settled do
                    local e = cc.settled[i]
                    local d = (type(e) == "table" and type(e.date) == "string") and e.date or nil
                    if not d then
                        table.remove(cc.settled, i)
                    elseif seen[d] then
                        table.remove(cc.settled, i)
                    else
                        seen[d] = true
                        i = i + 1
                    end
                end
                while #cc.settled > AS.KEEP_DAYS do
                    table.remove(cc.settled)
                end
            end
        end

        db.schema = 2
    end

    AS.db = db
    AS.char = c
    AS:RefreshWindow()
end

-- 窗口切换（用于登录时补算）
function AS:RefreshWindow()
    local key = AS:WindowKey()
    if AS.char.window ~= key then
        -- 窗口已经变了但还没结算：先补结算刚才走完的那一期。
        -- 归档日期取"结算这一刻的窗口键"，也就是刚结束的那一天，
        -- 而不是 char.window —— 后者是上一期开始时记下的旧值，比它晚一天，
        -- 照它归档会让玩家看到的历史日期永远比日历差一天。
        if AS.char.window ~= "" then
            if AS.Stats and AS.Stats.Settle then AS.Stats:Settle(key) end
        end
        AS.char.window = key
        AS.char.yards = 0
        AS.char.steps = 0
        AS.char.kcal = 0
        AS.char.trips = 0
        AS.char.tripFlight = 0
        AS.char.tripBoat = 0
        AS.char.tripTele = 0
        AS.char.walkSec = 0
        AS.char.mountSec = 0
        AS.char.rideSec = 0
    end
end

function AS:IsLikeWhisperEnabled()
    return AS.db and AS.db.settings and AS.db.settings.likeWhisper and true or false
end

function AS:SetLikeWhisper(v)
    if AS.db and AS.db.settings then AS.db.settings.likeWhisper = v and true or false end
end

--[[-----------------------------------------------------------------------------
多语言包（内联在 Core 末尾，避免新增文件扫不到）
-------------------------------------------------------------------------------]]
local L = { }
AS.L = L

L.zhCN = {
    -- 通用 / Common
    ADDON_NAME      = "艾泽拉斯足迹",
    PREFIX          = "|cff8080ff[足迹]|r ",
    UNKNOWN         = "未知",
    ERR_INTERNAL    = "|cffff5555内部错误：",
    LANG_SWITCHED   = "语言已切换为 %s，界面已即时更新。",

    -- 种族 / Races
    RACE_HUMAN      = "人类",
    RACE_ORC        = "兽人",
    RACE_DWARF      = "矮人",
    RACE_NIGHTELF   = "暗夜精灵",
    RACE_UNDEAD     = "亡灵",
    RACE_TAUREN     = "牛头人",
    RACE_GNOME      = "侏儒",
    RACE_TROLL      = "巨魔",
    RACE_GOBLIN     = "地精",
    RACE_BLOODELF   = "血精灵",
    RACE_DRAENEI    = "德莱尼",
    RACE_WORGEN     = "狼人",
    RACE_PANDAREN   = "熊猫人",

    -- 挂件 / Widget
    MINI_EMPTY_TIP  = "0 步 · 0 千卡",
    MINI_NAME       = "艾泽拉斯足迹",
    MINI_HINT       = "今日实时计数 · 点击展开面板",
    MINI_DRAG       = "左键拖动可移动",
    MINI_FMT        = "%s 步 · %s 千卡",
    MINI_ERR        = "|cffff5555挂件创建出错：",
    MINI_VOID       = "|cffff5555挂件依然为空，说明创建过程没走完，请把之前的红字发我。|r",
    MINI_OK         = "挂件已唤出，当前可见：%s。",

    -- 面板 / Panel
    PANEL_TITLE     = "艾泽拉斯运动健康",
    PANEL_SUB       = "每日结算 · 好友排行 · 点赞互动",
    TIP_SETTINGS    = "设置",
    TIP_SETTINGS2   = "也可以用 /step config 打开",

    UNIT_STEP       = "步",
    LABEL_TODAY     = "今日步数",
    LINE_WALK       = "步行 %d 分钟",
    LINE_MOUNT      = "骑行 %d 分钟",
    LINE_RIDE       = "交通 %d 分钟",
    LINE_DISTANCE   = "累计 %.2f 公里",
    KCAL_UNIT       = "千卡",

    SETTLE_TITLE    = "每晚 10 点自动结算",
    SETTLE_PERIOD   = "统计周期 22:00 - 次日 22:00，结算后计入次日排名",
    COUNTDOWN       = "距离结算 %02d:%02d:%02d",
    COUNTDOWN_IDLE  = "距离结算 --:--:--",

    RANK_TITLE      = "好友运动排名",
    RANK_EMPTY      = "还没有好友数据。换上装了 StepWarden 的朋友一起跑，22:00 后面板会自动结算排名。",
    RANK_COUNT      = "共 %d 人",

    TOPLIKE_DEFAULT = "给榜首点赞",
    TOPLIKE_ACTION  = "给榜首 %s 点赞",
    TOPLIKE_LIKED   = "已给 %s 点赞",
    TOPLIKE_NONE    = "目前没有可点赞的好友，等别人上榜再来。",

    MY_RANK_LBL     = "我的排名",
    RANK_N          = "第 %d 名",
    RANK_DASH       = "第 -- 名",
    STEPS_LBL       = "步数",
    STEPS_VAL       = "%s 步",
    KCAL_LBL        = "卡路里",
    KCAL_VAL        = "%s 千卡",

    SELF_LIKE       = "为自己点赞",
    SELF_LIKE_MSG   = "今天已经走了 %s 步，给自己记一笔。",

    FOOT_NOTE       = "排名按实时数据排序，每晚 22:00 定格存档",
    NEWER_VER       = "同伴有更新的版本 %s，建议更新后再一起跑",
    NEWER_VER_LOG   = "发现新版本 %s（当前 %s）。WoW 插件无法自行下载，请到发布页更新。",
    CB_LIKE         = "点赞时发送私信",
    CB_ON_TIP       = "点赞会同时发送一条私信。",
    CB_OFF_TIP      = "点赞只在本地记录，不发送私信。",
    BG_LBL          = "背景",

    LIKE_LABEL      = "赞",
    LIKED_LABEL     = "已赞",
    LIKE_ALREADY    = "今天已经赞过 %s 了，明天再来。",
    LIKE_SENT       = "已给 %s 点赞并发送私信。",
    LIKE_LOCAL      = "已给 %s 点赞（私信开关已关闭）。",

    -- 设置窗 / Options
    OPT_TITLE       = "StepWarden 设置",
    OPT_LANG        = "语言",
    OPT_LANG_ZH     = "中文",
    OPT_LANG_EN     = "English",
    OPT_ALPHA       = "背景透明度",
    OPT_SHOWMINI    = "显示屏幕挂件",
    OPT_POS         = "挂件位置",
    OPT_RESET       = "重置到右侧",
    OPT_RESET_DONE  = "挂件已移回屏幕右侧中央。",
    OPT_LIKEWHISPER = "点赞时发送私信",
    OPT_CLEAR_DAY   = "清空今日",
    OPT_HISTORY     = "历史记录",

    -- 历史记录页
    HIST_TITLE      = "历史记录",
    HIST_SUB        = "近 3 天 · 每晚 22:00 结算后归档",
    HIST_EMPTY      = "还没有历史记录。每晚 22:00 结算后，这里会留下当天 的个人数据与好友排行。",
    HIST_MINE       = "我的",
    HIST_TOP        = "当日前三",
    HIST_RANK       = "第 %d 名 / 共 %d 人",
    HIST_NORANK     = "未上榜",
    HIST_LINE_FMT   = "%s 步 · %s 公里 · %s 千卡",
    HIST_DATE_FMT   = "%s  ·  %s",
    HIST_OPEN       = "过去 3 天",
    HIST_BACK       = "返回今日",
    HIST_TOP_ALL    = "当日排行",
    HIST_EMPTY_TITLE = "暂无记录",
    HIST_SETTLED    = "当日已归档",
    OPT_CLEAR_FRI   = "清空好友",
    OPT_CLEAR_ALL   = "清空全部",
    TODAY_CLEARED   = "今日数据已清零。",
    FRIENDS_CLEARED = "好友缓存已清空。",
    ALL_CLEARED     = "历史与好友数据已清空。",

    -- 命令 / Slash
    ERR_REFRESH     = "|cffff5555刷新窗口出错：",
    LOADED_MSG      = "%s 已加载，输入 |cffffffff/step|r 打开面板，|cffffffff/step config|r 打开设置。",
    ALPHA_SET       = "背景透明度已设为 %d%%。",
    ALPHA_CUR       = "当前背景透明度 %d%%，用法 /step alpha 0.8",
    RESET_DONE      = "今日数据已清零。",
    WIPE_DONE       = "历史与好友数据已清空。",
    CLEAR_DONE      = "好友缓存已清空。",
    TEST_DONE       = "已按当前数据模拟结算一次（历史与广播都走了真实流程）。",
    UNKNOWN_CMD     = "未知命令：%s，试试 /step help",
    HELP_TEXT       = "/step 打开面板 · /step config 打开设置 · /step mini 唤出挂件 · /step alpha 0.8 透明度 · /step reset 清零今日 · /step clear 清好友缓存 · /step wipe 清空历史 · /step hist 历史记录 · /step test 模拟结算",

    -- 私信 / Whisper
    WHISPER_LIKE_1  = "【艾泽拉斯足迹】给你点了个赞！今天的榜首是你，%s 步——金冠戴稳了，别晃掉。",
    WHISPER_LIKE_2  = "【艾泽拉斯足迹】给你点了个赞！今天第二名，%s 步。银冠也挺亮，就是没金的那股嚣张。",
    WHISPER_LIKE_3  = "【艾泽拉斯足迹】给你点了个赞！今天第三名，%s 步。铜冠也是冠，别嫌它土。",
    WHISPER_LIKE    = "【艾泽拉斯足迹】给你点了个赞！你走了 %s 步，腿没白长。明天要不要往前挤两名？",
    LIKE_WS_FAIL    = "密语没发出去：找不到 %s，对方可能不在本服好友列表里。",
}

L.enUS = {
    ADDON_NAME      = "StepWarden",
    PREFIX          = "|cff8080ff[StepWarden]|r ",
    UNKNOWN         = "Unknown",
    ERR_INTERNAL    = "|cffff5555Internal error: ",
    LANG_SWITCHED   = "Language set to %s. UI updated instantly.",

    RACE_HUMAN      = "Human",
    RACE_ORC        = "Orc",
    RACE_DWARF      = "Dwarf",
    RACE_NIGHTELF   = "Night Elf",
    RACE_UNDEAD     = "Undead",
    RACE_TAUREN     = "Tauren",
    RACE_GNOME      = "Gnome",
    RACE_TROLL      = "Troll",
    RACE_GOBLIN     = "Goblin",
    RACE_BLOODELF   = "Blood Elf",
    RACE_DRAENEI    = "Draenei",
    RACE_WORGEN     = "Worgen",
    RACE_PANDAREN   = "Pandaren",

    MINI_EMPTY_TIP  = "0 st · 0 kcal",
    MINI_NAME       = "StepWarden",
    MINI_HINT       = "Live count today · click to open the panel",
    MINI_DRAG       = "Left-drag to move",
    MINI_FMT        = "%s st · %s kcal",
    MINI_ERR        = "|cffff5555Widget error: ",
    MINI_VOID       = "|cffff5555Widget is still nil; creation did not finish. Please send me the earlier red text.|r",
    MINI_OK         = "Widget shown, visible: %s.",

    PANEL_TITLE     = "Azeroth Fitness",
    PANEL_SUB       = "Daily settle · Friend ranking · Likes",
    TIP_SETTINGS    = "Settings",
    TIP_SETTINGS2   = "Or open with /step config",

    UNIT_STEP       = "steps",
    LABEL_TODAY     = "Steps today",
    LINE_WALK       = "Walk %d min",
    LINE_MOUNT      = "Ride %d min",
    LINE_RIDE       = "Transit %d min",
    LINE_DISTANCE   = "Total %.2f km",
    KCAL_UNIT       = "kcal",

    SETTLE_TITLE    = "Auto-settle at 10 PM",
    SETTLE_PERIOD   = "Cycle 22:00 to 22:00 next day; settles into the next day's ranking",
    COUNTDOWN       = "Settles in %02d:%02d:%02d",
    COUNTDOWN_IDLE  = "Settles in --:--:--",

    RANK_TITLE      = "Friend Ranking",
    RANK_EMPTY      = "No friend data yet. Run alongside friends who also use StepWarden; the panel settles the ranking at 22:00.",
    RANK_COUNT      = "%d player(s)",

    TOPLIKE_DEFAULT = "Like the leader",
    TOPLIKE_ACTION  = "Like leader %s",
    TOPLIKE_LIKED   = "Already liked %s",
    TOPLIKE_NONE    = "No friend to like yet; wait for someone to hit the board.",

    MY_RANK_LBL     = "My Rank",
    RANK_N          = "Rank %d",
    RANK_DASH       = "Rank --",
    STEPS_LBL       = "Steps",
    STEPS_VAL       = "%s st",
    KCAL_LBL        = "Calories",
    KCAL_VAL        = "%s kcal",

    SELF_LIKE       = "Like Yourself",
    SELF_LIKE_MSG   = "You walked %s steps today. Give yourself credit.",

    FOOT_NOTE       = "Ranked by live data, frozen and archived at 22:00",
    NEWER_VER       = "A friend runs newer version %s - worth updating",
    NEWER_VER_LOG   = "New version %s found (you are on %s). Addons cannot self-update; grab it from the release page.",
    CB_LIKE         = "Whisper on like",
    CB_ON_TIP       = "Liking also sends a whisper.",
    CB_OFF_TIP      = "Likes are recorded locally only; no whisper is sent.",
    BG_LBL          = "BG",

    LIKE_LABEL      = "Like",
    LIKED_LABEL     = "Liked",
    LIKE_ALREADY    = "You already liked %s today. Come back tomorrow.",
    LIKE_SENT       = "Liked %s and sent a whisper.",
    LIKE_LOCAL      = "Liked %s (whisper toggle is off).",

    OPT_TITLE       = "StepWarden Settings",
    OPT_LANG        = "Language",
    OPT_LANG_ZH     = "Chinese",
    OPT_LANG_EN     = "English",
    OPT_ALPHA       = "Opacity",
    OPT_SHOWMINI    = "Show widget",
    OPT_POS         = "Position",
    OPT_RESET       = "Reset to right",
    OPT_RESET_DONE  = "Widget moved back to the right center of the screen.",
    OPT_LIKEWHISPER = "Whisper on like",
    OPT_CLEAR_DAY   = "Clear today",
    OPT_HISTORY     = "History",

    -- History page
    HIST_TITLE      = "History",
    HIST_SUB        = "Last 3 days · archived after the 22:00 settlement",
    HIST_EMPTY      = "No history yet. After the 22:00 settlement, this page keeps that day's personal stats and friend ranking.",
    HIST_MINE       = "Me",
    HIST_TOP        = "Top 3",
    HIST_RANK       = "Rank %d of %d",
    HIST_NORANK     = "Unranked",
    HIST_LINE_FMT   = "%s steps · %s km · %s kcal",
    HIST_DATE_FMT   = "%s  ·  %s",
    HIST_OPEN       = "Last 3 days",
    HIST_BACK       = "Back to today",
    HIST_TOP_ALL    = "That day's ranking",
    HIST_EMPTY_TITLE = "No records",
    HIST_SETTLED    = "Archived",
    OPT_CLEAR_FRI   = "Clear friends",
    OPT_CLEAR_ALL   = "Clear all",
    TODAY_CLEARED   = "Today's data has been cleared.",
    FRIENDS_CLEARED = "Friend cache cleared.",
    ALL_CLEARED     = "History and friend data cleared.",

    ERR_REFRESH     = "|cffff5555Panel refresh error: ",
    LOADED_MSG      = "%s loaded. Type |cffffffff/step|r to open the panel, |cffffffff/step config|r for settings.",
    ALPHA_SET       = "Background opacity set to %d%%.",
    ALPHA_CUR       = "Current background opacity %d%%. Usage: /step alpha 0.8",
    RESET_DONE      = "Today's data has been cleared.",
    WIPE_DONE       = "History and friend data cleared.",
    CLEAR_DONE      = "Friend cache cleared.",
    TEST_DONE       = "Simulated one settlement with current data (history and broadcast ran for real).",
    UNKNOWN_CMD     = "Unknown command: %s. Try /step help",
    HELP_TEXT       = "/step panel · /step config settings · /step mini show widget · /step alpha 0.8 opacity · /step reset clear today · /step clear friend cache · /step wipe clear history · /step hist history · /step test simulate settle",

    WHISPER_LIKE_1  = "[StepWarden] gave you a like! Top of the board today - %s steps. Gold crown, and the bragging rights that come with it. Wear it well.",
    WHISPER_LIKE_2  = "[StepWarden] gave you a like! Second today - %s steps. Silver medal energy: so close it stings a little.",
    WHISPER_LIKE_3  = "[StepWarden] gave you a like! Third today - %s steps. Bronze. Still a crown. Technically.",
    WHISPER_LIKE    = "[StepWarden] gave you a like! %s steps today - legs clearly doing their job. Feel like climbing two spots tomorrow?",
    LIKE_WS_FAIL    = "Whisper not delivered - %s could not be reached. They may not be on this realm.",
}

-- 加载即初始化中文，InitDB 会按存档覆盖；保证 AS.S 永不为空
AS:SetLocale("zhCN")
