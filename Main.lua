--[[-----------------------------------------------------------------------------
StepWarden - Main
加载、斜杠命令
-------------------------------------------------------------------------------]]
local ADDON, AS = ...

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        AS:InitDB()

    elseif event == "PLAYER_LOGIN" then
        local ok, err = pcall(AS.RefreshWindow, AS)
        if not ok then AS:Print((AS.S.ERR_REFRESH) .. tostring(err)) end

        ok, err = pcall(AS.Panel.BuildMini, AS.Panel)
        if not ok then AS:Print((AS.S.MINI_ERR) .. tostring(err)) end
        -- 好友列表此时还没拉下来，稍等再同步
        if C_Timer and C_Timer.After then
            C_Timer.After(8, function()
                if AS.Comm and AS.Comm.RequestAll then AS.Comm:RequestAll() end
            end)
        end
        if AS.db and AS.db.settings and not AS.db.settings.welcomed then
            AS.db.settings.welcomed = true
            AS:Print(string.format(AS.S.LOADED_MSG, AS.VERSION))
        end

    elseif event == "PLAYER_LOGOUT" then
        -- 下线时如果窗口已经跨过，顺手结算一次
        AS:RefreshWindow()
    end
end)

--[[-----------------------------------------------------------------------------
斜杠命令
-------------------------------------------------------------------------------]]
local function Handle(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*([^%s]*)%s*(.*)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if cmd == "" or cmd == "show" then
        AS.Panel:Show()

    elseif cmd == "config" or cmd == "opt" or cmd == "options" then
        AS.Panel:OpenOptions()

    elseif cmd == "mini" then
        AS.Panel:ForceMini()

    elseif cmd == "alpha" then
        local v = tonumber(rest)
        if v then
            if v > 1 then v = 1 end
            if v < 0.3 then v = 0.3 end
            AS.Panel:ApplyAlpha(v)
            AS:Print(string.format(AS.S.ALPHA_SET, math.floor(v * 100 + 0.5)))
        else
            local cur = (AS.db and AS.db.settings and AS.db.settings.bgAlpha) or 0.85
            AS:Print(string.format(AS.S.ALPHA_CUR, math.floor(cur * 100 + 0.5)))
        end

    elseif cmd == "reset" then
        local c = AS.char
        if c then
            c.yards, c.steps, c.kcal = 0, 0, 0
            c.trips, c.tripFlight, c.tripBoat, c.tripTele = 0, 0, 0, 0
            c.walkSec, c.mountSec, c.rideSec = 0, 0, 0
        end
        AS:Print(AS.S.RESET_DONE)
        AS.Panel:Refresh()

    elseif cmd == "wipe" then
        local c = AS.char
        if c then c.settled = {} end
        if AS.db then AS.db.peers = {} end
        AS:Print(AS.S.WIPE_DONE)
        AS.Panel:Refresh()

    elseif cmd == "clear" then
        if AS.db then AS.db.peers = {} end
        AS:Print(AS.S.CLEAR_DONE)
        AS.Panel:Refresh()

    elseif cmd == "test" then
        local c = AS.char
        if c then
            AS.Stats:Settle(c.window or AS:WindowKey())
            AS:Print(AS.S.TEST_DONE)
            AS.Panel:Refresh()
        end

    elseif cmd == "lang" or cmd == "language" then
        local code = (rest or ""):lower()
        if code == "en" or code == "enus" or code == "english" then
            code = "enUS"
        elseif code == "zh" or code == "zhcn" or code == "cn" or code == "chinese" then
            code = "zhCN"
        else
            AS:Print(string.format(AS.S.LOADED_MSG, AS.VERSION))
            AS:Print("/step lang zh | /step lang en")
            do return end
        end
        AS.Panel:SetLanguage(code)

    
    elseif cmd == "help" then
        AS:Print(AS.S.HELP_TEXT)

    else
        AS:Print(string.format(AS.S.UNKNOWN_CMD, cmd))
    end
end

SLASH_STEPWARDEN1 = "/step"
SLASH_STEPWARDEN2 = "/azs"
SLASH_STEPWARDEN3 = "/azerothsteps"
SlashCmdList["STEPWARDEN"] = Handle
