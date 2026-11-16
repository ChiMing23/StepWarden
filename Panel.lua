--[[-----------------------------------------------------------------------------
StepWarden - Panel
1) 挂起态：迷你实时计数条（可拖动、可调透明度、点击展开）
2) 展开态：设计稿面板（深色石纹底 + 金色描边 + 卡路里圆环）
-------------------------------------------------------------------------------]]
local ADDON, AS = ...

AS.Panel = AS.Panel or {}
local P = AS.Panel

local W, H    = 540, 720
local MEDIA   = "Interface\\AddOns\\StepWarden\\Media\\"
local MAX_ROWS = 5
local ROW_H    = 44

local DEF_ALPHA  = 0.72
local MIN_ALPHA  = 0.30

local C_GOLD  = { 0.831, 0.702, 0.380 }
local C_GOLDT = { 0.949, 0.855, 0.596 }
local C_WHITE = { 0.941, 0.941, 0.961 }
local C_MID   = { 0.745, 0.745, 0.800 }
local C_DIM   = { 0.588, 0.588, 0.659 }

local MK
local Mini
local el     = {}
local Opt
local rows   = {}
local boxes  = {}
local tick   = 0
local mtick  = 0

--[[-----------------------------------------------------------------------------
小工具
-------------------------------------------------------------------------------]]
local function txt(parent, size, color)
    local fs = AS.FontString(parent, size, "")
    if color then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    return fs
end

local function panelBox(parent, x, y, w, h, alpha, borderAlpha)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f.baseAlpha = alpha or 0.70
    AS.FlatBackdrop(f, 0.030, 0.042, 0.075, f.baseAlpha,
        C_GOLD[1], C_GOLD[2], C_GOLD[3], borderAlpha or 0.40)
    boxes[#boxes + 1] = f
    return f
end

local function getAlpha()
    local a = AS.db and AS.db.settings and AS.db.settings.bgAlpha
    if type(a) ~= "number" then a = DEF_ALPHA end
    if a < MIN_ALPHA then a = MIN_ALPHA end
    if a > 1 then a = 1 end
    return a
end

--[[-----------------------------------------------------------------------------
背景透明度
-------------------------------------------------------------------------------]]
local function refreshAlphaText(a)
    local pct = string.format("%d%%", math.floor((a or 0) * 100 + 0.5))
    if P.alphaText then P.alphaText:SetText(pct) end
    if P.optAlphaText then P.optAlphaText:SetText(pct) end
end
P.refreshAlphaText = refreshAlphaText

function P:ApplyAlpha(a)
    a = a or getAlpha()
    if a < MIN_ALPHA then a = MIN_ALPHA end
    if a > 1 then a = 1 end

    refreshAlphaText(a)

    if AS.db and AS.db.settings then
        AS.db.settings.bgAlpha = a
    end

    if P.bgtex then
        P.bgtex:SetAlpha(a)
    end

    local k = a / DEF_ALPHA
    for i = 1, #boxes do
        local b = boxes[i]
        local ba = b.baseAlpha * k
        if ba > 1 then ba = 1 end
        b:SetBackdropColor(0.030, 0.042, 0.075, ba)
    end

    if Mini and Mini.bg then
        Mini.bg:SetAlpha(a)
        if Mini.edges then
            for i = 1, #Mini.edges do
                Mini.edges[i]:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.25 + a * 0.35)
            end
        end
    end

    if Opt and Opt.bgtex then
        Opt.bgtex:SetAlpha(a)
    end
end

function P:StepAlpha(delta)
    local a = getAlpha() + delta
    if a < MIN_ALPHA then a = MIN_ALPHA end
    if a > 1 then a = 1 end
    P:ApplyAlpha(a)

    if P.optAlphaText then
        P.optAlphaText:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
    end
    if P.alphaText then
        P.alphaText:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.4, function()
            if P.optAlphaText then P.optAlphaText:SetTextColor(C_WHITE[1], C_WHITE[2], C_WHITE[3]) end
            if P.alphaText then P.alphaText:SetTextColor(C_MID[1], C_MID[2], C_MID[3]) end
        end)
    end
end

--[[-----------------------------------------------------------------------------
挂起态：迷你实时计数条
-------------------------------------------------------------------------------]]
function P:BuildMini()
    if Mini then return end

    local BW, BH = 132, 88

    Mini = CreateFrame("Button", "StepWardenMini", UIParent)
    Mini:SetSize(BW, BH)
    Mini:SetFrameStrata("MEDIUM")
    Mini:SetClampedToScreen(true)
    Mini:SetMovable(true)
    Mini:EnableMouse(true)
    Mini:RegisterForDrag("LeftButton")

    -- 圆形脚印徽章，也是“点我展开”的入口
    local glow = Mini:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(68, 68)
    glow:SetPoint("TOP", Mini, "TOP", 0, 4)
    AS.FlatTex(glow, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0)
    Mini.glow = glow

    local icon = Mini:CreateTexture(nil, "ARTWORK")
    icon:SetSize(58, 58)
    icon:SetPoint("TOP", Mini, "TOP", 0, 0)
    icon:SetTexture(MEDIA .. "Badge")
    Mini.icon = icon

    -- 数字条
    local bar = CreateFrame("Frame", nil, Mini)
    bar:SetSize(BW, 22)
    bar:SetPoint("BOTTOM", Mini, "BOTTOM", 0, 0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    AS.FlatTex(bg, 0.028, 0.038, 0.070, 1)
    bg:SetAlpha(getAlpha())
    Mini.bg = bg

    local edges = {}
    local function edge(w, h)
        local e = bar:CreateTexture(nil, "OVERLAY")
        AS.FlatTex(e, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.55)
        if w then e:SetWidth(w) end
        if h then e:SetHeight(h) end
        edges[#edges + 1] = e
        return e
    end

    local top    = edge(nil, 1)
    local bottom = edge(nil, 1)
    local left   = edge(1, nil)
    local right  = edge(1, nil)

    top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    left:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    Mini.edges = edges

    el.miniText = txt(bar, 12, C_GOLDT)
    el.miniText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    el.miniText:SetText(AS.S.MINI_EMPTY_TIP)

    local bp = AS.db and AS.db.settings and AS.db.settings.mini
    if bp and bp.point then
        Mini:SetPoint(bp.point, UIParent, bp.rel or bp.point, bp.x or 0, bp.y or 0)
    else
        Mini:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
    end

    local noClick = false

    Mini:SetScript("OnDragStart", function(self) self:StartMoving() end)
    Mini:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        noClick = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function() noClick = false end)
        else
            noClick = false
        end
        local point, _, relPoint, x, y = self:GetPoint()
        if AS.db and AS.db.settings then
            AS.db.settings.mini = { point = point, rel = relPoint, x = x, y = y }
        end
    end)
    Mini:SetScript("OnClick", function()
        if noClick then return end
        P:Expand()
    end)

    Mini:SetScript("OnEnter", function()
        AS.FlatTex(glow, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.25)
        icon:SetVertexColor(1.12, 1.10, 1.00)
        if GameTooltip then
            GameTooltip:SetOwner(Mini, "ANCHOR_LEFT")
            GameTooltip:AddLine(AS.S.MINI_NAME, 1, 0.85, 0.6)
            GameTooltip:AddLine(AS.S.MINI_HINT, 0.85, 0.85, 0.9)
            GameTooltip:AddLine(AS.S.MINI_DRAG, 0.7, 0.7, 0.75)
            GameTooltip:Show()
        end
    end)
    Mini:SetScript("OnLeave", function()
        AS.FlatTex(glow, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0)
        icon:SetVertexColor(1, 1, 1)
        if GameTooltip then GameTooltip:Hide() end
    end)

    Mini:SetScript("OnUpdate", function(_, elapsed)
        mtick = mtick + elapsed
        if mtick >= 0.5 then
            mtick = 0
            P:RefreshMini()
        end
    end)

    P:ApplyAlpha(getAlpha())
    P:RefreshMini()
    Mini:Show()

    -- 有些界面插件会在登录后重排 UIParent，延迟再确认一次可见性
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if Mini then
                local hidden = MK and MK:IsShown()
                if not hidden then
                    Mini:Show()
                    P:RefreshMini()
                end
            end
        end)
    end
end

function P:RefreshMini()
    if not Mini or not Mini:IsShown() then return end
    if not AS.char then return end
    if not el.miniText then return end

    local c = AS.char
    local m = math.floor
    el.miniText:SetText(string.format(AS.S.MINI_FMT,
        AS:Comma(m(c.steps or 0)), AS:Comma(m(c.kcal or 0)))
    )
end

--[[-----------------------------------------------------------------------------
排行榜行
-------------------------------------------------------------------------------]]
local function MakeRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * ROW_H)
    row.slot = index

    local bg = row:CreateTexture(nil, "ARTWORK")
    bg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
    AS.FlatTex(bg, 1, 1, 1, 0)
    row.bg = bg

    local rank = txt(row, 17, C_MID)
    rank:SetSize(24, 18)
    rank:SetPoint("LEFT", row, "LEFT", 14, 0)
    rank:SetJustifyH("LEFT")
    row.rank = rank

    local name = txt(row, 16, C_WHITE)
    name:SetPoint("LEFT", row, "LEFT", 46, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -220, 0)
    name:SetJustifyH("LEFT")
    row.name = name

    local steps = txt(row, 16, C_WHITE)
    steps:SetSize(74, 16)
    steps:SetPoint("RIGHT", row, "RIGHT", -142, 0)
    steps:SetJustifyH("RIGHT")
    row.steps = steps

    local kcal = txt(row, 14, C_DIM)
    kcal:SetSize(74, 16)
    kcal:SetPoint("RIGHT", row, "RIGHT", -62, 0)
    kcal:SetJustifyH("RIGHT")
    row.kcal = kcal

    local like = CreateFrame("Button", nil, row)
    like:SetSize(44, 20)
    like:SetPoint("RIGHT", row, "RIGHT", -14, 0)

    local lbg = like:CreateTexture(nil, "ARTWORK")
    lbg:SetAllPoints(like)
    AS.FlatTex(lbg, 0.09, 0.10, 0.14, 0.9)
    like.bg = lbg

    local ledge = like:CreateTexture(nil, "OVERLAY")
    ledge:SetPoint("TOPLEFT", like, "TOPLEFT", -1, 1)
    ledge:SetPoint("BOTTOMRIGHT", like, "BOTTOMRIGHT", 1, -1)
    AS.FlatTex(ledge, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.45)

    local lt = txt(like, 13, C_GOLDT)
    lt:SetPoint("CENTER", like, "CENTER", 0, 0)
    lt:SetText(AS.S.LIKE_LABEL)
    like.label = lt

    like:SetScript("OnClick", function()
        local d = row.data
        if not d or d.isMe then return end
        if not AS.Comm:CanLike(d.key) then
            AS:Print(string.format(AS.S.LIKE_ALREADY, d.name or ""))
            return
        end
        AS.Comm:SendLike(d.name, d.key, d.steps)
        if AS:IsLikeWhisperEnabled() then
            AS:Print(string.format(AS.S.LIKE_SENT, d.name or ""))
        else
            AS:Print(string.format(AS.S.LIKE_LOCAL, d.name or ""))
        end
        P:Refresh()
    end)
    like:SetScript("OnEnter", function() AS.FlatTex(lbg, 0.16, 0.15, 0.10, 0.95) end)
    like:SetScript("OnLeave", function() AS.FlatTex(lbg, 0.09, 0.10, 0.14, 0.9) end)

    row.like = like

    row:SetScript("OnEnter", function(r)
        if r.data and not r.data.isMe then
            AS.FlatTex(r.bg, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.10)
        end
    end)
    row:SetScript("OnLeave", function(r)
        if r.data and not r.data.isMe then
            AS.FlatTex(r.bg, 1, 1, 1, (r.slot % 2 == 0) and 0.028 or 0.0)
        end
    end)

    return row
end

--[[-----------------------------------------------------------------------------
主面板
-------------------------------------------------------------------------------]]
--[[-----------------------------------------------------------------------------
设置窗口
-------------------------------------------------------------------------------]]

local function optRow(parent, y, key)
    local l = txt(parent, 14, C_MID)
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    l.key = key
    l:SetText(AS.S[key] or key)
    parent.rowList = parent.rowList or { }
    parent.rowList[#parent.rowList + 1] = l
    return l
end

local function mkToggle(parent, x, y, onChange)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(16, 16)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(cb)
    AS.FlatTex(bg, 0.06, 0.07, 0.10, 1)

    local edge = cb:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT", cb, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 1, -1)
    AS.FlatTex(edge, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.55)

    local check = cb:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT", cb, "TOPLEFT", 2, -2)
    check:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -2, 2)
    AS.FlatTex(check, C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
    cb.check = check

    cb:SetScript("OnClick", function(self)
        local v = not self.on
        self.on = v
        if v then check:Show() else check:Hide() end
        if onChange then onChange(v) end
    end)
    return cb
end

local function mkButton(parent, x, y, w, h, key, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    AS.FlatBackdrop(b, 0.07, 0.08, 0.11, 0.92, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.50)

    local t = txt(b, 12, C_GOLDT)
    t:SetPoint("CENTER", b, "CENTER", 0, 0)
    t:SetText(AS.S[key] or key)
    b.label = t
    b.key = key
    parent.btnList = parent.btnList or { }
    parent.btnList[#parent.btnList + 1] = b

    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.17, 0.09, 0.96)
        self:SetBackdropBorderColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.90)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.07, 0.08, 0.11, 0.92)
        self:SetBackdropBorderColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.50)
    end)
    b:SetScript("OnClick", onClick)
    return b
end

function P:SyncOptions()
    if not Opt then return end

    refreshAlphaText(getAlpha())

    local db = AS.db and AS.db.settings
    if Opt.tShow then
        Opt.tShow.on = (db == nil) or (db.showMini ~= false)
        if Opt.tShow.on then Opt.tShow.check:Show() else Opt.tShow.check:Hide() end
    end
    if Opt.tLike then
        Opt.tLike.on = AS:IsLikeWhisperEnabled()
        if Opt.tLike.on then Opt.tLike.check:Show() else Opt.tLike.check:Hide() end
    end

    P:PaintLangButtons()
end

function P:PaintLangButtons()
    if not Opt then return end
    local list = { Opt.zhBtn, Opt.enBtn }
    for i = 1, 2 do
        local b = list[i]
        if b then
            if b.code == AS.locale then
                b:SetBackdropColor(0.27, 0.22, 0.11, 0.98)
                b:SetBackdropBorderColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1.0)
                if b.label then b.label:SetTextColor(1, 0.97, 0.86) end
                if b.mark then b.mark:Show() end
            else
                b:SetBackdropColor(0.05, 0.06, 0.09, 0.80)
                b:SetBackdropBorderColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.32)
                if b.label then b.label:SetTextColor(0.68, 0.66, 0.60) end
                if b.mark then b.mark:Hide() end
            end
        end
    end
end

-- 按当前语言重设全部静态文案（不重载界面）
function P:Relocalize()
    if MK then
        if el.title        then el.title:SetText(AS.S.PANEL_TITLE) end
        if el.sub          then el.sub:SetText(AS.S.PANEL_SUB) end
        if el.unit         then el.unit:SetText(AS.S.UNIT_STEP) end
        if el.steplabel    then el.steplabel:SetText(AS.S.LABEL_TODAY) end
        if el.walk         then el.walk:SetText(string.format(AS.S.LINE_WALK, 0)) end
        if el.mount        then el.mount:SetText(string.format(AS.S.LINE_MOUNT, 0)) end
        if el.ride         then el.ride:SetText(string.format(AS.S.LINE_RIDE, 0)) end
        if el.distance     then el.distance:SetText(string.format(AS.S.LINE_DISTANCE, 0)) end
        if el.kcalunit     then el.kcalunit:SetText(AS.S.KCAL_UNIT) end
        if el.settletitle  then el.settletitle:SetText(AS.S.SETTLE_TITLE) end
        if el.period       then el.period:SetText(AS.S.SETTLE_PERIOD) end
        if el.countdown    then el.countdown:SetText(AS.S.COUNTDOWN_IDLE) end
        if el.rankTitle    then el.rankTitle:SetText(AS.S.RANK_TITLE) end
        if el.empty        then el.empty:SetText(AS.S.RANK_EMPTY) end
        if P.topLikeText   then P.topLikeText:SetText(AS.S.TOPLIKE_DEFAULT) end
        if el.ml1          then el.ml1:SetText(AS.S.MY_RANK_LBL) end
        if el.sl1          then el.sl1:SetText(AS.S.STEPS_LBL) end
        if el.kl1          then el.kl1:SetText(AS.S.KCAL_LBL) end
        if el.selfLikeText then el.selfLikeText:SetText(AS.S.SELF_LIKE) end
        if el.foot         then el.foot:SetText(AS.S.FOOT_NOTE) end
        if el.cbLabel      then el.cbLabel:SetText(AS.S.CB_LIKE) end
        if el.alabel       then el.alabel:SetText(AS.S.BG_LBL) end
    end

    if el.miniText then el.miniText:SetText(AS.S.MINI_EMPTY_TIP) end

    if Opt then
        if Opt.titleText then Opt.titleText:SetText(AS.S.OPT_TITLE) end
        if Opt.rowList then
            for i = 1, #Opt.rowList do
                local r = Opt.rowList[i]
                if r and r.key then r:SetText(AS.S[r.key] or r.key) end
            end
        end
        if Opt.btnList then
            for i = 1, #Opt.btnList do
                local b = Opt.btnList[i]
                if b and b.label and b.key then b.label:SetText(AS.S[b.key] or b.key) end
            end
        end
        if Opt.zhBtn and Opt.zhBtn.label then Opt.zhBtn.label:SetText(AS.S.OPT_LANG_ZH) end
        if Opt.enBtn and Opt.enBtn.label then Opt.enBtn.label:SetText(AS.S.OPT_LANG_EN) end
    end
end

function P:SetLanguage(code)
    if code ~= "zhCN" and code ~= "enUS" then return end
    if code == AS.locale then return end

    if AS.db and AS.db.settings then AS.db.settings.locale = code end
    AS:SetLocale(code)

    P:Relocalize()
    if MK then pcall(P.Refresh, P) end
    if MK then pcall(P.UpdateCountdown, P) end
    if Mini then pcall(P.RefreshMini, P) end
    P:PaintLangButtons()

    local name = (code == "enUS") and AS.S.OPT_LANG_EN or AS.S.OPT_LANG_ZH
    AS:Print(string.format(AS.S.LANG_SWITCHED, name))
end

function P:BuildOptions()
    if Opt then return end

    Opt = CreateFrame("Frame", "StepWardenOptions", UIParent)
    Opt:SetSize(320, 384)
    Opt:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    Opt:SetFrameStrata("DIALOG")
    Opt:SetClampedToScreen(true)
    Opt:SetMovable(true)
    Opt:EnableMouse(true)
    Opt:RegisterForDrag("LeftButton")
    Opt:SetScript("OnDragStart", Opt.StartMoving)
    Opt:SetScript("OnDragStop", Opt.StopMovingOrSizing)

    -- 背景板：直接取自主面板石纹，风格完全一致
    Opt.bgtex = Opt:CreateTexture(nil, "BACKGROUND")
    Opt.bgtex:SetAllPoints(Opt)
    Opt.bgtex:SetTexture(MEDIA .. "OptBG")
    Opt.bgtex:SetAlpha(getAlpha())

    -- 背景板之上压一层深色，保证文字对比度
    local veil = Opt:CreateTexture(nil, "BORDER")
    veil:SetAllPoints(Opt)
    AS.FlatTex(veil, 0.010, 0.014, 0.026, 0.55)

    -- 亮金外框（底色压到很低，让石纹透出来）
    AS.FlatBackdrop(Opt, 0.010, 0.014, 0.026, 0.16, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.90)

    -- 顶部标题条
    local tb = Opt:CreateTexture(nil, "ARTWORK")
    tb:SetPoint("TOPLEFT", Opt, "TOPLEFT", 1, -1)
    tb:SetPoint("TOPRIGHT", Opt, "TOPRIGHT", -1, -1)
    tb:SetHeight(34)
    AS.FlatTex(tb, 0.075, 0.062, 0.036, 0.88)

    local tbl = Opt:CreateTexture(nil, "OVERLAY")
    tbl:SetPoint("BOTTOMLEFT", tb, "BOTTOMLEFT", 0, 0)
    tbl:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", 0, 0)
    tbl:SetHeight(1)
    AS.FlatTex(tbl, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.90)

    local title = txt(Opt, 20, { 1.00, 0.90, 0.66 })
    title:SetPoint("LEFT", Opt, "TOPLEFT", 18, -18)
    title:SetText(AS.S.OPT_TITLE)
    Opt.titleText = title

    local cls = CreateFrame("Button", nil, Opt)
    cls:SetSize(22, 22)
    cls:SetPoint("TOPRIGHT", Opt, "TOPRIGHT", -9, -6)
    local ct = txt(cls, 16, C_GOLDT)
    ct:SetPoint("CENTER", cls, "CENTER", 0, -1)
    ct:SetText("×")
    cls:SetScript("OnClick", function() Opt:Hide() end)
    cls:SetScript("OnEnter", function() ct:SetTextColor(1, 0.92, 0.72) end)
    cls:SetScript("OnLeave", function() ct:SetTextColor(unpack(C_GOLDT)) end)

    -- 背景透明度
    optRow(Opt, -64, "OPT_ALPHA")
    mkButton(Opt, 148, -60, 20, 20, "−", function()
        P:StepAlpha(-0.06)
        P:SyncOptions()
    end)
    el.optAlpha = txt(Opt, 14, C_WHITE)
    el.optAlpha:SetPoint("TOPLEFT", Opt, "TOPLEFT", 178, -64)
    el.optAlpha:SetWidth(34)
    el.optAlpha:SetJustifyH("LEFT")
    P.optAlphaText = el.optAlpha
    el.optAlpha:SetText(string.format("%d%%", math.floor(getAlpha() * 100 + 0.5)))
    mkButton(Opt, 214, -60, 20, 20, "+", function()
        P:StepAlpha(0.06)
        P:SyncOptions()
    end)

    -- 显示挂件
    optRow(Opt, -108, "OPT_SHOWMINI")
    Opt.tShow = mkToggle(Opt, 148, -108, function(v)
        if AS.db and AS.db.settings then AS.db.settings.showMini = v end
        if Mini then
            if v then Mini:Show() P:RefreshMini() else Mini:Hide() end
        end
    end)

    -- 挂件位置
    optRow(Opt, -152, "OPT_POS")
    mkButton(Opt, 148, -148, 100, 22, "OPT_RESET", function()
        if AS.db and AS.db.settings then AS.db.settings.mini = nil end
        if Mini then
            Mini:ClearAllPoints()
            Mini:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
            Mini:Show()
            P:RefreshMini()
        end
        AS:Print(AS.S.OPT_RESET_DONE)
    end)

    -- 语言
    optRow(Opt, -240, "OPT_LANG")

    local function langBtn(x, w, key, code)
        local b = CreateFrame("Button", nil, Opt)
        b:SetSize(w, 24)
        b:SetPoint("TOPLEFT", Opt, "TOPLEFT", x, -236)
        b.code = code
        AS.FlatBackdrop(b, 0.05, 0.06, 0.09, 0.80, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.32)

        -- 选中标记：左侧竖金条（纯纹理，任何客户端都能显示）
        b.mark = b:CreateTexture(nil, "OVERLAY")
        b.mark:SetSize(3, 16)
        b.mark:SetPoint("LEFT", b, "LEFT", 0, 0)
        AS.FlatTex(b.mark, C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
        b.mark:Hide()

        local t = txt(b, 12, C_GOLDT)
        t:SetPoint("CENTER", b, "CENTER", 2, 0)
        t:SetText(AS.S[key] or key)
        b.label = t
        b.key = key

        b:SetScript("OnClick", function() P:SetLanguage(code) end)
        b:SetScript("OnEnter", function(self)
            if self.code ~= AS.locale then
                self:SetBackdropColor(0.17, 0.14, 0.08, 0.92)
                self:SetBackdropBorderColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.70)
            end
        end)
        b:SetScript("OnLeave", function() P:PaintLangButtons() end)
        return b
    end

    Opt.zhBtn = langBtn(148, 56, "OPT_LANG_ZH", "zhCN")
    Opt.enBtn = langBtn(208, 66, "OPT_LANG_EN", "enUS")

    -- 点赞私信
    optRow(Opt, -196, "OPT_LIKEWHISPER")
    Opt.tLike = mkToggle(Opt, 148, -196, function(v)
        AS:SetLikeWhisper(v)
        P:Refresh()
    end)

    local hl2 = Opt:CreateTexture(nil, "ARTWORK")
    hl2:SetPoint("TOPLEFT", Opt, "TOPLEFT", 14, -276)
    hl2:SetPoint("TOPRIGHT", Opt, "TOPRIGHT", -14, -276)
    hl2:SetHeight(1)
    AS.FlatTex(hl2, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.55)

    -- 只保留「清空今日」；「清空好友」「清空全部」已隐藏，改为整行居中
    mkButton(Opt, 110, -292, 100, 28, "OPT_CLEAR_DAY", function()
        local c = AS.char
        if c then
            c.yards, c.steps, c.kcal = 0, 0, 0
            c.trips, c.tripFlight, c.tripBoat, c.tripTele = 0, 0, 0, 0
            c.walkSec, c.mountSec, c.rideSec = 0, 0, 0
        end
        P:Refresh()
        P:RefreshMini()
        AS:Print(AS.S.TODAY_CLEARED)
    end)

    
    table.insert(UISpecialFrames, "StepWardenOptions")

    Opt:Hide()
    P:SyncOptions()
end

function P:OpenOptions()
    P:BuildOptions()
    Opt:Show()
    P:SyncOptions()
end

function P:Build()
    if MK then return end

    MK = CreateFrame("Frame", "StepWardenFrame", UIParent)
    MK:SetSize(W, H)
    MK:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    MK:SetClampedToScreen(true)
    MK:SetMovable(true)
    MK:EnableMouse(true)
    MK:RegisterForDrag("LeftButton")
    MK:SetScript("OnDragStart", MK.StartMoving)
    MK:SetScript("OnDragStop", MK.StopMovingOrSizing)
    MK:SetFrameStrata("DIALOG")

    local bgtex = MK:CreateTexture(nil, "BACKGROUND")
    bgtex:SetAllPoints(MK)
    bgtex:SetTexture(MEDIA .. "PanelBG")
    P.bgtex = bgtex

    el.title = txt(MK, 27, C_GOLDT)
    el.title:SetPoint("TOPLEFT", MK, "TOPLEFT", 20, -12)
    el.title:SetText(AS.S.PANEL_TITLE)

    el.sub = txt(MK, 13, C_DIM)
    el.sub:SetPoint("TOPLEFT", MK, "TOPLEFT", 22, -44)
    el.sub:SetText(AS.S.PANEL_SUB)

    -- 右上角两个按钮：同尺寸、同风格，默认无底直接浮在石纹上，悬停才透出淡金
    local close = CreateFrame("Button", nil, MK)
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", MK, "TOPRIGHT", -14, -10)
    local cbg = close:CreateTexture(nil, "ARTWORK")
    cbg:SetAllPoints(close)
    AS.FlatTex(cbg, 0.34, 0.27, 0.12, 0)
    local ct = txt(close, 15, C_GOLDT)
    ct:SetPoint("CENTER", close, "CENTER", 0, 0)
    ct:SetText("×")
    close:SetScript("OnClick", function() P:Collapse() end)
    close:SetScript("OnEnter", function()
        AS.FlatTex(cbg, 0.34, 0.27, 0.12, 0.22)
        ct:SetTextColor(1, 0.96, 0.84)
    end)
    close:SetScript("OnLeave", function()
        AS.FlatTex(cbg, 0.34, 0.27, 0.12, 0)
        ct:SetTextColor(C_GOLDT[1], C_GOLDT[2], C_GOLDT[3])
    end)

    local gear = CreateFrame("Button", nil, MK)
    gear:SetSize(22, 22)
    gear:SetPoint("TOPRIGHT", MK, "TOPRIGHT", -40, -10)
    local gbg = gear:CreateTexture(nil, "ARTWORK")
    gbg:SetAllPoints(gear)
    AS.FlatTex(gbg, 0.34, 0.27, 0.12, 0)
    local gicon = gear:CreateTexture(nil, "OVERLAY")
    gicon:SetSize(13, 13)
    gicon:SetPoint("CENTER", gear, "CENTER", 0, 0)
    gicon:SetTexture(MEDIA .. "Gear")

    gear:SetScript("OnClick", function() P:OpenOptions() end)
    gear:SetScript("OnEnter", function()
        AS.FlatTex(gbg, 0.34, 0.27, 0.12, 0.22)
        gicon:SetVertexColor(1.18, 1.12, 0.95)
        if GameTooltip then
            GameTooltip:SetOwner(gear, "ANCHOR_LEFT")
            GameTooltip:AddLine(AS.S.TIP_SETTINGS, 1, 0.85, 0.6)
            GameTooltip:AddLine(AS.S.TIP_SETTINGS2, 0.85, 0.85, 0.9)
            GameTooltip:Show()
        end
    end)
    gear:SetScript("OnLeave", function()
        AS.FlatTex(gbg, 0.34, 0.27, 0.12, 0)
        gicon:SetVertexColor(1, 1, 1)
        if GameTooltip then GameTooltip:Hide() end
    end)

    local hline = MK:CreateTexture(nil, "ARTWORK")
    hline:SetPoint("TOPLEFT", MK, "TOPLEFT", 16, -60)
    hline:SetPoint("TOPRIGHT", MK, "TOPRIGHT", -16, -60)
    hline:SetHeight(1)
    AS.FlatTex(hline, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.55)

    -- 今日大卡
    local big = panelBox(MK, 16, -72, 508, 160, 0.68, 0.45)

    el.steps = txt(big, 36, C_WHITE)
    el.steps:SetPoint("TOPLEFT", big, "TOPLEFT", 22, -14)
    el.steps:SetText("0")
    el.steps:SetJustifyH("LEFT")

    el.unit = txt(big, 16, C_DIM)
    el.unit:SetPoint("LEFT", el.steps, "RIGHT", 6, -3)
    el.unit:SetText(AS.S.UNIT_STEP)

    el.steplabel = txt(big, 13, C_DIM)
    el.steplabel:SetPoint("TOPLEFT", big, "TOPLEFT", 24, -66)
    el.steplabel:SetText(AS.S.LABEL_TODAY)

    el.walk = txt(big, 14, C_MID)
    el.walk:SetPoint("TOPLEFT", big, "TOPLEFT", 196, -24)
    el.walk:SetText(string.format(AS.S.LINE_WALK, 0))

    el.mount = txt(big, 14, C_MID)
    el.mount:SetPoint("TOPLEFT", big, "TOPLEFT", 196, -48)
    el.mount:SetText(string.format(AS.S.LINE_MOUNT, 0))

    el.ride = txt(big, 14, C_MID)
    el.ride:SetPoint("TOPLEFT", big, "TOPLEFT", 196, -72)
    el.ride:SetText(string.format(AS.S.LINE_RIDE, 0))

    el.distance = txt(big, 13, C_DIM)
    el.distance:SetPoint("TOPLEFT", big, "TOPLEFT", 24, -98)
    el.distance:SetText(string.format(AS.S.LINE_DISTANCE, 0))

    local ring = big:CreateTexture(nil, "ARTWORK")
    ring:SetSize(82, 82)
    ring:SetPoint("TOPRIGHT", big, "TOPRIGHT", -18, -20)
    ring:SetTexture(MEDIA .. "Ring")

    el.kcal = txt(big, 26, C_WHITE)
    el.kcal:SetPoint("CENTER", ring, "CENTER", 0, 3)
    el.kcal:SetText("0")

    el.kcalunit = txt(big, 12, C_DIM)
    el.kcalunit:SetPoint("TOP", ring, "BOTTOM", 0, 0)
    el.kcalunit:SetText(AS.S.KCAL_UNIT)

    -- 结算条
    local strip = panelBox(MK, 16, -244, 508, 64, 0.62, 0.38)

    el.settletitle = txt(strip, 17, C_GOLDT)
    el.settletitle:SetPoint("TOPLEFT", strip, "TOPLEFT", 18, -12)
    el.settletitle:SetText(AS.S.SETTLE_TITLE)

    el.period = txt(strip, 13, C_DIM)
    el.period:SetPoint("TOPLEFT", strip, "TOPLEFT", 18, -38)
    el.period:SetText(AS.S.SETTLE_PERIOD)

    local pill = CreateFrame("Frame", nil, strip)
    pill:SetSize(156, 24)
    pill:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -16, -10)
    AS.FlatBackdrop(pill, 0.10, 0.085, 0.055, 0.90, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.60)

    el.countdown = txt(pill, 13, C_GOLDT)
    el.countdown:SetPoint("CENTER", pill, "CENTER", 0, 0)
    el.countdown:SetText(AS.S.COUNTDOWN_IDLE)

    -- 排行榜
    el.rankTitle = txt(MK, 20, C_GOLDT)
    el.rankTitle:SetPoint("TOPLEFT", MK, "TOPLEFT", 18, -314)
    el.rankTitle:SetText(AS.S.RANK_TITLE)

    el.rankCount = txt(MK, 13, C_DIM)
    el.rankCount:SetPoint("LEFT", el.rankTitle, "RIGHT", 10, -1)
    el.rankCount:SetText("")

    local box = CreateFrame("Frame", nil, MK)
    box:SetPoint("TOPLEFT", MK, "TOPLEFT", 16, -338)
    box:SetPoint("TOPRIGHT", MK, "TOPRIGHT", -16, -338)
    box:SetHeight(MAX_ROWS * ROW_H)

    for i = 1, MAX_ROWS do
        rows[i] = MakeRow(box, i)
    end

    el.empty = txt(box, 12, C_DIM)
    el.empty:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -(MAX_ROWS * ROW_H) / 2)
    el.empty:SetWidth(460)
    el.empty:SetJustifyH("LEFT")
    el.empty:SetText(AS.S.RANK_EMPTY)

    -- 排行之后的点赞入口：默认给榜首点赞
    local rankLike = CreateFrame("Button", nil, MK)
    rankLike:SetSize(508, 26)
    rankLike:SetPoint("TOPLEFT", MK, "TOPLEFT", 16, -562)
    AS.FlatBackdrop(rankLike, 0.085, 0.075, 0.045, 0.85,
        C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.55)

    local rlText = txt(rankLike, 14, C_GOLDT)
    rlText:SetPoint("CENTER", rankLike, "CENTER", 0, 0)
    rlText:SetText(AS.S.TOPLIKE_DEFAULT)
    P.topLikeText = rlText
    P.topLike = rankLike

    rankLike:SetScript("OnClick", function()
        local d = P.topLikeData
        if not d then
            AS:Print(AS.S.TOPLIKE_NONE)
            return
        end
        if not AS.Comm:CanLike(d.key) then
            AS:Print(string.format(AS.S.LIKE_ALREADY, d.name or ""))
            return
        end
        AS.Comm:SendLike(d.name, d.key, d.steps)
        if AS:IsLikeWhisperEnabled() then
            AS:Print(string.format(AS.S.LIKE_SENT, d.name or ""))
        else
            AS:Print(string.format(AS.S.LIKE_LOCAL, d.name or ""))
        end
        P:Refresh()
    end)
    rankLike:SetScript("OnEnter", function() rankLike:SetBackdropColor(0.18, 0.15, 0.08, 0.95) end)
    rankLike:SetScript("OnLeave", function() rankLike:SetBackdropColor(0.085, 0.075, 0.045, 0.85) end)

    -- 我的排名条
    local mine = panelBox(MK, 16, -594, 508, 60, 0.62, 0.45)

    el.ml1 = txt(mine, 12, C_DIM)
    el.ml1:SetPoint("TOPLEFT", mine, "TOPLEFT", 18, -9)
    el.ml1:SetText(AS.S.MY_RANK_LBL)

    el.myRank = txt(mine, 18, C_WHITE)
    el.myRank:SetPoint("TOPLEFT", mine, "TOPLEFT", 18, -26)
    el.myRank:SetText(AS.S.RANK_DASH)

    el.sl1 = txt(mine, 12, C_DIM)
    el.sl1:SetPoint("TOPLEFT", mine, "TOPLEFT", 138, -9)
    el.sl1:SetText(AS.S.STEPS_LBL)

    el.mySteps = txt(mine, 18, C_WHITE)
    el.mySteps:SetPoint("TOPLEFT", mine, "TOPLEFT", 138, -26)
    el.mySteps:SetText(string.format(AS.S.STEPS_VAL, "0"))

    el.kl1 = txt(mine, 12, C_DIM)
    el.kl1:SetPoint("TOPLEFT", mine, "TOPLEFT", 266, -9)
    el.kl1:SetText(AS.S.KCAL_LBL)

    el.myKcal = txt(mine, 18, C_WHITE)
    el.myKcal:SetPoint("TOPLEFT", mine, "TOPLEFT", 266, -26)
    el.myKcal:SetText(string.format(AS.S.KCAL_VAL, "0"))

    local selfLike = CreateFrame("Button", nil, mine)
    selfLike:SetSize(112, 26)
    selfLike:SetPoint("RIGHT", mine, "RIGHT", -16, 0)
    local sbg = selfLike:CreateTexture(nil, "ARTWORK")
    sbg:SetAllPoints(selfLike)
    AS.FlatTex(sbg, 0.72, 0.56, 0.26, 0.95)
    el.selfLikeText = txt(selfLike, 13, { 0.16, 0.12, 0.05 })
    el.selfLikeText:SetPoint("CENTER", selfLike, "CENTER", 0, 0)
    el.selfLikeText:SetText(AS.S.SELF_LIKE)
    selfLike:SetScript("OnClick", function()
        AS:Print(string.format(AS.S.SELF_LIKE_MSG, AS:Comma(math.floor(AS.char.steps or 0))))
    end)
    selfLike:SetScript("OnEnter", function() AS.FlatTex(sbg, 0.85, 0.68, 0.33, 1) end)
    selfLike:SetScript("OnLeave", function() AS.FlatTex(sbg, 0.72, 0.56, 0.26, 0.95) end)

    -- 页脚
    el.foot = txt(MK, 13, C_DIM)
    el.foot:SetPoint("TOP", MK, "TOP", 0, -658)
    el.foot:SetText(AS.S.FOOT_NOTE)

    -- 底部行：私信开关 + 背景透明度
    local cb = CreateFrame("Button", nil, MK)
    cb:SetSize(14, 14)
    cb:SetPoint("TOPLEFT", MK, "TOPLEFT", 20, -682)
    el.cb = cb

    local cbbg = cb:CreateTexture(nil, "BACKGROUND")
    cbbg:SetAllPoints(cb)
    AS.FlatTex(cbbg, 0.09, 0.09, 0.11, 1)

    local cbed = cb:CreateTexture(nil, "ARTWORK")
    cbed:SetPoint("TOPLEFT", cb, "TOPLEFT", -1, 1)
    cbed:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 1, -1)
    AS.FlatTex(cbed, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.35)

    local cbck = cb:CreateTexture(nil, "OVERLAY")
    cbck:SetPoint("TOPLEFT", cb, "TOPLEFT", 2, -2)
    cbck:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -2, 2)
    AS.FlatTex(cbck, C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
    el.cbCheck = cbck

    el.cbLabel = txt(MK, 13, C_MID)
    el.cbLabel:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    el.cbLabel:SetText(AS.S.CB_LIKE)

    cb:SetScript("OnClick", function()
        local v = not AS:IsLikeWhisperEnabled()
        AS:SetLikeWhisper(v)
        P:Refresh()
        AS:Print(v and AS.S.CB_ON_TIP or AS.S.CB_OFF_TIP)
    end)

    -- 透明度控件
    el.alabel = txt(MK, 12, C_DIM)
    el.alabel:SetPoint("TOPLEFT", MK, "TOPLEFT", 300, -685)
    el.alabel:SetText(AS.S.BG_LBL)

    local minus = CreateFrame("Button", nil, MK)
    minus:SetSize(18, 18)
    minus:SetPoint("TOPLEFT", el.alabel, "TOPRIGHT", 8, 2)
    AS.FlatBackdrop(minus, 0.09, 0.09, 0.12, 0.9, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.35)
    local mt = txt(minus, 14, C_GOLDT)
    mt:SetPoint("CENTER", minus, "CENTER", 0, 0)
    mt:SetText("−")
    minus:SetScript("OnClick", function() P:StepAlpha(-0.06) end)

    el.alphaVal = txt(MK, 13, C_MID)
    el.alphaVal:SetPoint("CENTER", minus, "CENTER", 30, 0)
    el.alphaVal:SetWidth(34)
    el.alphaVal:SetJustifyH("CENTER")
    P.alphaText = el.alphaVal
    el.alphaVal:SetText(string.format("%d%%", math.floor(getAlpha() * 100 + 0.5)))

    local plus = CreateFrame("Button", nil, MK)
    plus:SetSize(18, 18)
    plus:SetPoint("LEFT", el.alphaVal, "RIGHT", 12, 0)
    AS.FlatBackdrop(plus, 0.09, 0.09, 0.12, 0.9, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.35)
    local pt = txt(plus, 14, C_GOLDT)
    pt:SetPoint("CENTER", plus, "CENTER", 0, 0)
    pt:SetText("+")
    plus:SetScript("OnClick", function() P:StepAlpha(0.06) end)

    table.insert(UISpecialFrames, "StepWardenFrame")

    MK:SetScript("OnHide", function()
        if Mini and (AS.db == nil or AS.db.settings == nil or AS.db.settings.showMini ~= false) then
            Mini:Show()
            P:RefreshMini()
        end
    end)

    MK:SetScript("OnUpdate", function(_, elapsed)
        tick = tick + elapsed
        if tick >= 1 then
            tick = 0
            P:Refresh()
        end
    end)

    P:ApplyAlpha(getAlpha())
end

--[[-----------------------------------------------------------------------------
刷新
-------------------------------------------------------------------------------]]
function P:UpdateCountdown()
    if not el.countdown then return end
    local left = AS:SecondsToSettle()
    el.countdown:SetText(string.format(AS.S.COUNTDOWN,
        math.floor(left / 3600),
        math.floor((left % 3600) / 60),
        math.floor(left % 60)))
end

function P:Refresh()
    if not MK then return end
    if not MK:IsShown() then return end
    if not AS.char then return end

    local c = AS.char
    local m = math.floor

    if el.steps then el.steps:SetText(AS:Comma(m(c.steps or 0))) end
    if el.walk then el.walk:SetText(string.format(AS.S.LINE_WALK, m((c.walkSec or 0) / 60))) end
    if el.mount then el.mount:SetText(string.format(AS.S.LINE_MOUNT, m((c.mountSec or 0) / 60))) end
    if el.ride then el.ride:SetText(string.format(AS.S.LINE_RIDE, m((c.rideSec or 0) / 60))) end
    if el.distance then
        el.distance:SetText(string.format(AS.S.LINE_DISTANCE, (c.yards or 0) * 0.9144 / 1000))
    end
    if el.kcal then el.kcal:SetText(AS:Comma(m(c.kcal or 0))) end

    if el.cbCheck then
        if AS:IsLikeWhisperEnabled() then el.cbCheck:Show() else el.cbCheck:Hide() end
    end

    local list = AS.Stats:BuildRanking()
    local myRank, total = AS.Stats:MyRank()

    if el.myRank then
        if myRank > 0 then
            el.myRank:SetText(string.format(AS.S.RANK_N, myRank))
        else
            el.myRank:SetText(AS.S.RANK_DASH)
        end
    end
    if el.mySteps then el.mySteps:SetText(string.format(AS.S.STEPS_VAL, AS:Comma(m(c.steps or 0)))) end
    if el.myKcal then el.myKcal:SetText(string.format(AS.S.KCAL_VAL, AS:Comma(m(c.kcal or 0)))) end

    if el.rankCount then
        local mineEntry = c.settled and c.settled[1]
        if total > 0 and mineEntry then
            el.rankCount:SetText(string.format(AS.S.RANK_COUNT_DATE, total, mineEntry.date or "—"))
        elseif total > 0 then
            el.rankCount:SetText(string.format(AS.S.RANK_COUNT, total))
        else
            el.rankCount:SetText("")
        end
    end

    local shown = 0
    for i = 1, MAX_ROWS do
        local row = rows[i]
        local d = list[i]
        if row then
            if d then
                shown = shown + 1
                row.data = d
                row:Show()
                row.rank:SetText(tostring(i))
                -- 列表只渲染角色名：服务器名（如 "CN1 Realm 8 PvE"）有 20 个字符，
        -- 拼上去会撑满 242px 的名字列并被右侧数字列挤掉，完整名放到悬停提示里看
        row.name:SetText(d.name or "?")
                row.steps:SetText(string.format(AS.S.STEPS_VAL, AS:Comma(m(d.steps or 0))))
                row.kcal:SetText(string.format(AS.S.KCAL_VAL, AS:Comma(m(d.kcal or 0))))

                if d.isMe then
                    AS.FlatTex(row.bg, 0.98, 0.92, 0.66, 0.16)
                    row.rank:SetTextColor(C_GOLDT[1], C_GOLDT[2], C_GOLDT[3])
                    row.name:SetTextColor(C_GOLDT[1], C_GOLDT[2], C_GOLDT[3])
                    row.steps:SetTextColor(C_GOLDT[1], C_GOLDT[2], C_GOLDT[3])
                    row.like:Hide()
                elseif i == 1 then
                    AS.FlatTex(row.bg, C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.14)
                    row.rank:SetTextColor(C_GOLDT[1], C_GOLDT[2], C_GOLDT[3])
                    row.name:SetTextColor(C_GOLDT[1], C_GOLDT[2], C_GOLDT[3])
                    row.steps:SetTextColor(C_WHITE[1], C_WHITE[2], C_WHITE[3])
                    row.like:Show()
                else
                    AS.FlatTex(row.bg, 1, 1, 1, (i % 2 == 0) and 0.028 or 0.0)
                    row.rank:SetTextColor(C_MID[1], C_MID[2], C_MID[3])
                    row.name:SetTextColor(C_WHITE[1], C_WHITE[2], C_WHITE[3])
                    row.steps:SetTextColor(C_WHITE[1], C_WHITE[2], C_WHITE[3])
                    row.like:Show()
                end

                if not d.isMe then
                    if AS.Comm:WasLiked(d.key) then
                        row.like.label:SetText(AS.S.LIKED_LABEL)
                        row.like.label:SetTextColor(0.55, 0.85, 0.55, 1)
                    else
                        row.like.label:SetText(AS.S.LIKE_LABEL)
                        row.like.label:SetTextColor(C_GOLDT[1], C_GOLDT[2], C_GOLDT[3], 1)
                    end
                end
            else
                row.data = nil
                row:Hide()
            end
        end
    end

    if el.empty then
        if shown <= 1 then el.empty:Show() else el.empty:Hide() end
    end

    if P.topLike then
        local topD = list and list[1]
        if topD and not topD.isMe then
            P.topLikeData = topD
            if AS.Comm:WasLiked(topD.key) then
                P.topLikeText:SetText(string.format(AS.S.TOPLIKE_LIKED, topD.name or ""))
            else
                P.topLikeText:SetText(string.format(AS.S.TOPLIKE_ACTION, topD.name or ""))
            end
            P.topLike:Show()
        else
            P.topLikeData = nil
            P.topLike:Hide()
        end
    end

    P:UpdateCountdown()
end

--[[-----------------------------------------------------------------------------
收纳 / 展开
-------------------------------------------------------------------------------]]
function P:Expand()
    P:Build()
    if Mini then Mini:Hide() end
    MK:Show()
    P:ApplyAlpha(getAlpha())
    P:Refresh()
end

function P:Collapse()
    if MK then MK:Hide() end
    if Mini and (AS.db == nil or AS.db.settings == nil or AS.db.settings.showMini ~= false) then
        Mini:Show()
        P:RefreshMini()
    end
end

function P:Show()
    P:Expand()
end

function P:Hide()
    P:Collapse()
end

function P:Toggle()
    if MK and MK:IsShown() then
        P:Collapse()
    else
        P:Expand()
    end
end

-- 强制唤出挂件：重建（若不存在）+ 回到屏幕右侧中央 + 显示
function P:ForceMini()
    if not Mini then
        local ok, err = pcall(P.BuildMini, P)
        if not ok then
            AS:Print(AS.S.MINI_ERR .. tostring(err) .. "|r")
            return
        end
    end

    if not Mini then
        AS:Print(AS.S.MINI_VOID)
        return
    end

    if AS.db and AS.db.settings then
        AS.db.settings.showMini = true
        AS.db.settings.mini = nil
    end

    Mini:ClearAllPoints()
    Mini:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
    Mini:Show()
    P:RefreshMini()

    AS:Print(string.format(AS.S.MINI_OK, tostring(Mini:IsShown())))
end
