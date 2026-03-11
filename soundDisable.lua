-- ============================================
-- MODULE: SOUND MIXER / DISABLE
-- Category-based volume controller with robust muting.
-- Resizable window (same interaction model as teleporter).
-- ============================================

local VERSION = "1.0.0"
local CATEGORIA = "World"
local MODULE_NAME = "Sound Mixer"
local MODULE_STATE_KEY = "__kah_sound_mixer_state"

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local HS = game:GetService("HttpService")

local player = Players.LocalPlayer

-- Cleanup previous instance if re-executed.
do
    local old = _G[MODULE_STATE_KEY]
    if old then
        if old.cleanup then pcall(old.cleanup) end
        if old.gui and old.gui.Parent then
            pcall(function() old.gui:Destroy() end)
        end
    end
    _G[MODULE_STATE_KEY] = nil
end

-- ============================================
-- PERSISTENCE
-- ============================================
local CFG_KEY = "sound_mixer_cfg.json"
local SIZE_KEY = "sound_mixer_size.json"
local POS_KEY = "sound_mixer_pos.json"

local defaults = {
    enabled = true,
    master = 0,
    music = 0,
    ambient = 0,
    sfx = 0,
    ui = 0,
    fx_enabled = false,
    fx_cervo = true,
    fx_gato = true,
}

local function clampPct(v)
    return math.clamp(math.floor((tonumber(v) or 0) + 0.5), 0, 100)
end

local function loadJson(path)
    if not (isfile and readfile and isfile(path)) then return nil end
    local ok, data = pcall(function()
        return HS:JSONDecode(readfile(path))
    end)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local function saveJson(path, data)
    if not writefile then return end
    pcall(writefile, path, HS:JSONEncode(data))
end

local cfg = loadJson(CFG_KEY) or {}
for k, v in pairs(defaults) do
    if cfg[k] == nil then cfg[k] = v end
end
cfg.enabled = cfg.enabled == true
cfg.master = clampPct(cfg.master)
cfg.music = clampPct(cfg.music)
cfg.ambient = clampPct(cfg.ambient)
cfg.sfx = clampPct(cfg.sfx)
cfg.ui = clampPct(cfg.ui)
cfg.fx_enabled = cfg.fx_enabled == true
cfg.fx_cervo = cfg.fx_cervo ~= false
cfg.fx_gato = cfg.fx_gato ~= false

local function saveCfg()
    saveJson(CFG_KEY, cfg)
end

local sizeData = loadJson(SIZE_KEY) or {}
local BASE_W = 240
local MIN_W = 200
local MAX_W = 420
local MIN_EXTRA_H = 0
local MAX_EXTRA_H = 420
local W = math.clamp(tonumber(sizeData.w) or BASE_W, MIN_W, MAX_W)
local H_EXTRA = math.clamp(tonumber(sizeData.hExtra) or 0, MIN_EXTRA_H, MAX_EXTRA_H)

local function saveSize()
    saveJson(SIZE_KEY, { w = W, hExtra = H_EXTRA })
end

-- ============================================
-- SOUND ENGINE
-- ============================================
local tracked = setmetatable({}, { __mode = "k" })
local fxTracked = setmetatable({}, { __mode = "k" })
local moduleRunning = false
local applying = false
local descAddedConn = nil
local uiDestroyed = false

local CERVO_NAMES = { "deer", "stag", "cervo", "elk" }
local GATO_NAMES = { "cat", "gato", "wildcat", "lynx" }
local FX_CLASSES = {
    ParticleEmitter = true,
    Trail = true,
    Highlight = true,
    SelectionBox = true,
    Beam = true,
    Fire = true,
    Smoke = true,
    Sparkles = true,
}

local function isFxObject(obj)
    if not obj then return false end
    return FX_CLASSES[obj.ClassName] == true
end

local function untrackFx(obj)
    local info = fxTracked[obj]
    if not info then return end
    if info.ancConn then info.ancConn:Disconnect() end
    fxTracked[obj] = nil
end

local function modelKind(name)
    local n = string.lower(tostring(name or ""))
    for _, s in ipairs(CERVO_NAMES) do
        if string.find(n, s, 1, true) then
            return "cervo"
        end
    end
    for _, s in ipairs(GATO_NAMES) do
        if string.find(n, s, 1, true) then
            return "gato"
        end
    end
    return nil
end

local function kindFromObject(obj)
    local cur = obj
    while cur and cur ~= workspace do
        if cur:IsA("Model") then
            return modelKind(cur.Name)
        end
        cur = cur.Parent
    end
    return nil
end

local function fxShouldSuppress(kind)
    if not moduleRunning then return false end
    if not cfg.fx_enabled then return false end
    if kind == "cervo" then return cfg.fx_cervo end
    if kind == "gato" then return cfg.fx_gato end
    return false
end

local function safeSetEnabled(obj, enabled)
    pcall(function()
        obj.Enabled = enabled
    end)
end

local function applyOneFx(obj)
    if not obj or not obj.Parent or not isFxObject(obj) then return end

    local info = fxTracked[obj]
    if not info then
        local ok, baseEnabled = pcall(function() return obj.Enabled end)
        if not ok then return end
        info = { baseEnabled = baseEnabled }
        fxTracked[obj] = info
        info.ancConn = obj.AncestryChanged:Connect(function(_, parent)
            if parent == nil then
                untrackFx(obj)
            end
        end)
    end

    local kind = kindFromObject(obj)
    local suppress = fxShouldSuppress(kind)
    local target = suppress and false or info.baseEnabled
    local ok, cur = pcall(function() return obj.Enabled end)
    if ok and cur ~= target then
        safeSetEnabled(obj, target)
    end
end

local function applyAllFx()
    for _, d in ipairs(workspace:GetDescendants()) do
        if isFxObject(d) then
            applyOneFx(d)
        end
    end
end

local function applyTrackedFx()
    local list = {}
    for obj in pairs(fxTracked) do
        table.insert(list, obj)
    end
    for _, obj in ipairs(list) do
        if obj and obj.Parent then
            applyOneFx(obj)
        else
            untrackFx(obj)
        end
    end
end

local function hasVoiceAncestor(obj)
    local cur = obj
    while cur and cur ~= game do
        if cur:IsA("AudioDeviceInput") or cur:IsA("AudioDeviceOutput") then
            return true
        end
        cur = cur.Parent
    end
    return false
end

local musicWords = { "music", "bgm", "song", "radio", "theme", "track" }
local ambientWords = { "ambient", "env", "environment", "wind", "rain", "weather", "forest", "nature", "ocean" }
local uiWords = { "ui", "interface", "menu", "click", "button", "hover" }

local function matchWords(text, words)
    for _, w in ipairs(words) do
        if string.find(text, w, 1, true) then
            return true
        end
    end
    return false
end

local function soundCategory(sound)
    if hasVoiceAncestor(sound) then
        return nil
    end

    local n = string.lower(sound.Name or "")
    local full = ""
    pcall(function() full = string.lower(sound:GetFullName()) end)
    local sg = sound.SoundGroup
    local sgName = sg and string.lower(sg.Name) or ""

    if matchWords(n, uiWords) or matchWords(full, uiWords) or matchWords(sgName, uiWords) then
        return "ui"
    end
    if matchWords(n, musicWords) or matchWords(full, musicWords) or matchWords(sgName, musicWords) then
        return "music"
    end
    if matchWords(n, ambientWords) or matchWords(full, ambientWords) or matchWords(sgName, ambientWords) then
        return "ambient"
    end

    local tl = tonumber(sound.TimeLength) or 0
    if sound.Looped and tl >= 20 then
        return "music"
    end

    return "sfx"
end

local function categoryFactor(cat)
    if not moduleRunning then return 1 end
    if not cfg.enabled then return 1 end
    local master = clampPct(cfg.master) / 100
    local catPct = clampPct(cfg[cat] or 100) / 100
    return master * catPct
end

local function safeSetVolume(sound, volume)
    applying = true
    pcall(function()
        sound.Volume = math.clamp(tonumber(volume) or 0, 0, 10)
    end)
    applying = false
end

local function untrackSound(sound)
    local info = tracked[sound]
    if not info then return end
    if info.volConn then info.volConn:Disconnect() end
    if info.ancConn then info.ancConn:Disconnect() end
    tracked[sound] = nil
end

local function applyOneSound(sound)
    if not sound or not sound:IsA("Sound") then return end
    local cat = soundCategory(sound)
    if not cat then return end

    local info = tracked[sound]
    if not info then
        info = {
            base = tonumber(sound.Volume) or 0,
            category = cat,
        }
        tracked[sound] = info

        info.volConn = sound:GetPropertyChangedSignal("Volume"):Connect(function()
            if applying then return end
            local i = tracked[sound]
            if not i then return end
            local c = soundCategory(sound)
            if not c then return end
            i.category = c
            local f = categoryFactor(c)
            local nowVol = tonumber(sound.Volume) or 0
            if moduleRunning and cfg.enabled and f > 0 then
                i.base = nowVol / f
            else
                i.base = nowVol
            end
            task.defer(function()
                if sound.Parent then
                    applyOneSound(sound)
                end
            end)
        end)

        info.ancConn = sound.AncestryChanged:Connect(function(_, parent)
            if parent == nil then
                untrackSound(sound)
            end
        end)
    else
        info.category = cat
        if info.base == nil then
            info.base = tonumber(sound.Volume) or 0
        end
    end

    local target = (tonumber(info.base) or 0) * categoryFactor(info.category)
    if math.abs((tonumber(sound.Volume) or 0) - target) > 0.001 then
        safeSetVolume(sound, target)
    end
end

local function applyAllSounds()
    for _, d in ipairs(game:GetDescendants()) do
        if d:IsA("Sound") then
            applyOneSound(d)
        end
    end
end

local function applyTrackedSounds()
    local list = {}
    for sound in pairs(tracked) do
        table.insert(list, sound)
    end
    for _, sound in ipairs(list) do
        if sound and sound.Parent then
            applyOneSound(sound)
        else
            untrackSound(sound)
        end
    end
end

local function applyTrackedCategory(categoryKey)
    local list = {}
    for sound in pairs(tracked) do
        table.insert(list, sound)
    end
    for _, sound in ipairs(list) do
        local info = tracked[sound]
        if not info then
            -- removed while iterating
        elseif not sound or not sound.Parent then
            untrackSound(sound)
        elseif categoryKey == "master" or info.category == categoryKey then
            applyOneSound(sound)
        end
    end
end

local function stopEngine()
    moduleRunning = false
    if descAddedConn then
        descAddedConn:Disconnect()
        descAddedConn = nil
    end
    local toClear = {}
    for sound in pairs(tracked) do
        table.insert(toClear, sound)
    end
    for _, sound in ipairs(toClear) do
        local info = tracked[sound]
        if sound and sound.Parent and info and info.base ~= nil then
            safeSetVolume(sound, info.base)
        end
        untrackSound(sound)
    end

    local fxToClear = {}
    for obj in pairs(fxTracked) do
        table.insert(fxToClear, obj)
    end
    for _, obj in ipairs(fxToClear) do
        local info = fxTracked[obj]
        if obj and obj.Parent and info and info.baseEnabled ~= nil then
            safeSetEnabled(obj, info.baseEnabled)
        end
        untrackFx(obj)
    end
end

local function startEngine()
    if moduleRunning then return end
    moduleRunning = true
    applyAllSounds()
    applyAllFx()
    descAddedConn = game.DescendantAdded:Connect(function(obj)
        if obj:IsA("Sound") then
            task.defer(function()
                if moduleRunning and obj.Parent then
                    applyOneSound(obj)
                end
            end)
        elseif isFxObject(obj) then
            task.defer(function()
                if moduleRunning and obj.Parent then
                    applyOneFx(obj)
                end
            end)
        end
    end)
end

local function refreshEngine(changedKey)
    if moduleRunning then
        if changedKey then
            applyTrackedCategory(changedKey)
        else
            applyTrackedSounds()
        end
    end
end

local function refreshVisualFx()
    if moduleRunning then
        applyTrackedFx()
    end
end

-- ============================================
-- UI
-- ============================================
local C = {
    bg = Color3.fromRGB(10, 11, 15),
    header = Color3.fromRGB(12, 14, 20),
    border = Color3.fromRGB(28, 32, 48),
    accent = Color3.fromRGB(0, 220, 255),
    green = Color3.fromRGB(50, 220, 100),
    greenDim = Color3.fromRGB(15, 55, 25),
    red = Color3.fromRGB(220, 50, 70),
    redDim = Color3.fromRGB(55, 12, 18),
    yellow = Color3.fromRGB(255, 200, 50),
    text = Color3.fromRGB(180, 190, 210),
    muted = Color3.fromRGB(65, 75, 100),
    rowBg = Color3.fromRGB(18, 20, 28),
    rowHov = Color3.fromRGB(22, 26, 38),
    slider = Color3.fromRGB(28, 34, 50),
}

local H_HDR = 34
local BASE_CONTENT_H = 366
local PAD = 6

local pg = player:WaitForChild("PlayerGui")
local oldGui = pg:FindFirstChild("SoundDisable_hud")
if oldGui then oldGui:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name = "SoundDisable_hud"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.Parent = pg

local frame = Instance.new("Frame")
frame.Name = "SoundFrame"
frame.Size = UDim2.new(0, W, 0, H_HDR)
frame.Position = UDim2.new(0, 390, 0, 70)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel = 0
frame.Parent = sg
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color = C.border

local uiScale = Instance.new("UIScale")
uiScale.Name = "__SoundResizeScale"
uiScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.9, 1.35)
uiScale.Parent = frame

local topLine = Instance.new("Frame")
topLine.Size = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.accent
topLine.BorderSizePixel = 0
topLine.ZIndex = 5
topLine.Parent = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, H_HDR)
header.BackgroundColor3 = C.header
header.BorderSizePixel = 0
header.Active = true
header.ZIndex = 3
header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -96, 1, 0)
titleLbl.Position = UDim2.new(0, 26, 0, 0)
titleLbl.Text = "SOUND MIXER"
titleLbl.TextColor3 = C.accent
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 11
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.ZIndex = 4
titleLbl.Parent = header

local titleIcon = Instance.new("ImageLabel")
titleIcon.Size = UDim2.new(0, 13, 0, 13)
titleIcon.Position = UDim2.new(0, 9, 0.5, -6)
titleIcon.BackgroundTransparency = 1
titleIcon.Image = "rbxassetid://6031094678"
titleIcon.ImageColor3 = C.accent
titleIcon.ZIndex = 4
titleIcon.Parent = header

local function addBtnIcon(btn, imageId, color)
    local icon = Instance.new("ImageLabel")
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.new(0.5, 0, 0.5, 0)
    icon.Size = UDim2.new(0, 11, 0, 11)
    icon.BackgroundTransparency = 1
    icon.Image = imageId
    icon.ImageColor3 = color or Color3.new(1, 1, 1)
    icon.ZIndex = (btn.ZIndex or 1) + 1
    icon.Parent = btn
    btn.Text = ""
end

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 20)
minBtn.Position = UDim2.new(1, -44, 0.5, -10)
minBtn.Text = ""
minBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
minBtn.TextColor3 = C.muted
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 11
minBtn.BorderSizePixel = 0
minBtn.ZIndex = 4
minBtn.Parent = header
Instance.new("UIStroke", minBtn).Color = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 3)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -20, 0.5, -10)
closeBtn.Text = ""
closeBtn.BackgroundColor3 = C.redDim
closeBtn.TextColor3 = C.red
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 10
closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 4
closeBtn.Parent = header
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 3)
addBtnIcon(minBtn, "rbxassetid://6031090990", C.muted)
addBtnIcon(closeBtn, "rbxassetid://6031091004", C.red)

local resizeHandle = Instance.new("TextButton")
resizeHandle.Name = "ResizeHandle"
resizeHandle.Size = UDim2.new(0, 14, 0, 14)
resizeHandle.Position = UDim2.new(1, -16, 1, -16)
resizeHandle.Text = ""
resizeHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHandle.BorderSizePixel = 0
resizeHandle.AutoButtonColor = true
resizeHandle.ZIndex = 8
resizeHandle.Parent = frame
Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 2)
local rsStroke = Instance.new("UIStroke", resizeHandle)
rsStroke.Color = C.border
rsStroke.Thickness = 1

local resizeDot = Instance.new("Frame")
resizeDot.Size = UDim2.new(0, 3, 0, 3)
resizeDot.Position = UDim2.new(1, -5, 1, -5)
resizeDot.BackgroundColor3 = C.muted
resizeDot.BorderSizePixel = 0
resizeDot.Parent = resizeHandle
Instance.new("UICorner", resizeDot).CornerRadius = UDim.new(1, 0)

local resizeHHandle = Instance.new("TextButton")
resizeHHandle.Name = "ResizeHeightHandle"
resizeHHandle.Size = UDim2.new(0, 24, 0, 8)
resizeHHandle.Position = UDim2.new(0.5, -12, 1, -10)
resizeHHandle.Text = ""
resizeHHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHHandle.BorderSizePixel = 0
resizeHHandle.AutoButtonColor = true
resizeHHandle.ZIndex = 8
resizeHHandle.Parent = frame
Instance.new("UICorner", resizeHHandle).CornerRadius = UDim.new(1, 0)
local rsHStroke = Instance.new("UIStroke", resizeHHandle)
rsHStroke.Color = C.border
rsHStroke.Thickness = 1

local content = Instance.new("ScrollingFrame")
content.Name = "Content"
content.Position = UDim2.new(0, PAD, 0, H_HDR + PAD)
content.Size = UDim2.new(1, -PAD * 2, 0, BASE_CONTENT_H - PAD * 2)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 3
content.ScrollBarImageColor3 = C.accent
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.ZIndex = 3
content.Parent = frame

local list = Instance.new("UIListLayout", content)
list.Padding = UDim.new(0, 6)
list.FillDirection = Enum.FillDirection.Vertical
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.SortOrder = Enum.SortOrder.LayoutOrder

local function makeRow(height)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, height)
    row.BackgroundColor3 = C.rowBg
    row.BorderSizePixel = 0
    row.ZIndex = 4
    row.Parent = content
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", row).Color = C.border
    return row
end

local statusRow = makeRow(24)
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -12, 1, 0)
statusLbl.Position = UDim2.new(0, 8, 0, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 10
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.ZIndex = 5
statusLbl.Parent = statusRow

local toggleRow = makeRow(30)
local toggleName = Instance.new("TextLabel")
toggleName.Size = UDim2.new(1, -68, 1, 0)
toggleName.Position = UDim2.new(0, 8, 0, 0)
toggleName.BackgroundTransparency = 1
toggleName.Text = "MIXER ENABLED"
toggleName.TextColor3 = C.text
toggleName.Font = Enum.Font.GothamBold
toggleName.TextSize = 10
toggleName.TextXAlignment = Enum.TextXAlignment.Left
toggleName.ZIndex = 5
toggleName.Parent = toggleRow

local togglePill = Instance.new("Frame")
togglePill.Size = UDim2.new(0, 42, 0, 18)
togglePill.Position = UDim2.new(1, -48, 0.5, -9)
togglePill.BorderSizePixel = 0
togglePill.ZIndex = 5
togglePill.Parent = toggleRow
Instance.new("UICorner", togglePill).CornerRadius = UDim.new(0, 9)
local toggleStroke = Instance.new("UIStroke", togglePill)
toggleStroke.Color = C.border

local toggleKnob = Instance.new("Frame")
toggleKnob.Size = UDim2.new(0, 12, 0, 12)
toggleKnob.Position = UDim2.new(0, 3, 0.5, -6)
toggleKnob.BackgroundColor3 = C.red
toggleKnob.BorderSizePixel = 0
toggleKnob.ZIndex = 6
toggleKnob.Parent = togglePill
Instance.new("UICorner", toggleKnob).CornerRadius = UDim.new(1, 0)

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, 0, 1, 0)
toggleBtn.BackgroundTransparency = 1
toggleBtn.Text = ""
toggleBtn.ZIndex = 7
toggleBtn.Parent = toggleRow

local sliderRows = {}
local sliderOrder = { "master", "music", "ambient", "sfx", "ui" }
local sliderTitles = {
    master = "MASTER",
    music = "MUSIC",
    ambient = "AMBIENT",
    sfx = "SFX",
    ui = "UI",
}
local sliderInputs = {}
local updateStatus
local activeSlider = nil
local sliderCfgDirty = false

local function flushCfgIfDirty()
    if sliderCfgDirty then
        saveCfg()
        sliderCfgDirty = false
    end
end

local function createSliderRow(key)
    local row = makeRow(38)

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(0.55, 0, 0, 14)
    nameLbl.Position = UDim2.new(0, 8, 0, 4)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = sliderTitles[key]
    nameLbl.TextColor3 = C.text
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextSize = 10
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.ZIndex = 5
    nameLbl.Parent = row

    local valueLbl = Instance.new("TextLabel")
    valueLbl.Size = UDim2.new(0.45, -10, 0, 14)
    valueLbl.Position = UDim2.new(0.55, 0, 0, 4)
    valueLbl.BackgroundTransparency = 1
    valueLbl.Text = "0%"
    valueLbl.TextColor3 = C.accent
    valueLbl.Font = Enum.Font.Code
    valueLbl.TextSize = 10
    valueLbl.TextXAlignment = Enum.TextXAlignment.Right
    valueLbl.ZIndex = 5
    valueLbl.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -16, 0, 10)
    track.Position = UDim2.new(0, 8, 1, -14)
    track.BackgroundColor3 = C.slider
    track.BorderSizePixel = 0
    track.ZIndex = 5
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 5)
    Instance.new("UIStroke", track).Color = C.border

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = C.accent
    fill.BorderSizePixel = 0
    fill.ZIndex = 6
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 12, 0, 12)
    knob.Position = UDim2.new(0, -6, 0.5, -6)
    knob.BackgroundColor3 = C.accent
    knob.BorderSizePixel = 0
    knob.ZIndex = 7
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.new(1, 0, 1, 0)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.ZIndex = 8
    hit.Parent = track

    local rowData = {
        key = key,
        valueLbl = valueLbl,
        fill = fill,
        knob = knob,
        track = track,
    }
    sliderRows[key] = rowData

    local dragging = false
    sliderInputs[key] = dragging

    local function setValueFromX(px)
        local x = rowData.track.AbsolutePosition.X
        local w = math.max(rowData.track.AbsoluteSize.X, 1)
        local t = math.clamp((px - x) / w, 0, 1)
        cfg[key] = clampPct(t * 100)
        sliderCfgDirty = true
        refreshEngine(key)
        rowData.update()
        updateStatus()
    end

    rowData.update = function()
        local pct = clampPct(cfg[key])
        rowData.valueLbl.Text = string.format("%d%%", pct)
        rowData.fill.Size = UDim2.new(pct / 100, 0, 1, 0)
        rowData.knob.Position = UDim2.new(pct / 100, -6, 0.5, -6)
    end

    hit.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
        and i.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if uiDestroyed then return end
        dragging = true
        sliderInputs[key] = true
        activeSlider = rowData
        setValueFromX(i.Position.X)
    end)
    hit.InputEnded:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
        and i.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if uiDestroyed then return end
        dragging = false
        sliderInputs[key] = false
        if activeSlider == rowData then
            activeSlider = nil
        end
        flushCfgIfDirty()
    end)
    rowData.dragFlag = function(v)
        dragging = v
        sliderInputs[key] = v
    end
    rowData.setFromX = setValueFromX

    rowData.update()
end

for _, key in ipairs(sliderOrder) do
    createSliderRow(key)
end

local fxHeaderRow = makeRow(22)
local fxHeaderLbl = Instance.new("TextLabel")
fxHeaderLbl.Size = UDim2.new(1, -12, 1, 0)
fxHeaderLbl.Position = UDim2.new(0, 8, 0, 0)
fxHeaderLbl.BackgroundTransparency = 1
fxHeaderLbl.Text = "VISUAL FX"
fxHeaderLbl.TextColor3 = C.yellow
fxHeaderLbl.Font = Enum.Font.GothamBold
fxHeaderLbl.TextSize = 10
fxHeaderLbl.TextXAlignment = Enum.TextXAlignment.Left
fxHeaderLbl.ZIndex = 5
fxHeaderLbl.Parent = fxHeaderRow

local fxToggleRows = {}
local function createFxToggleRow(title, cfgKey)
    local row = makeRow(30)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -68, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = title
    lbl.TextColor3 = C.text
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 5
    lbl.Parent = row

    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 42, 0, 18)
    pill.Position = UDim2.new(1, -48, 0.5, -9)
    pill.BorderSizePixel = 0
    pill.ZIndex = 5
    pill.Parent = row
    Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 9)
    local stroke = Instance.new("UIStroke", pill)
    stroke.Color = C.border

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 12, 0, 12)
    knob.Position = UDim2.new(0, 3, 0.5, -6)
    knob.BackgroundColor3 = C.red
    knob.BorderSizePixel = 0
    knob.ZIndex = 6
    knob.Parent = pill
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.ZIndex = 7
    btn.Parent = row

    local function update()
        local on = cfg[cfgKey] == true
        if on then
            pill.BackgroundColor3 = C.greenDim
            knob.Position = UDim2.new(1, -15, 0.5, -6)
            knob.BackgroundColor3 = C.green
            stroke.Color = Color3.fromRGB(30, 100, 50)
        else
            pill.BackgroundColor3 = C.redDim
            knob.Position = UDim2.new(0, 3, 0.5, -6)
            knob.BackgroundColor3 = C.red
            stroke.Color = Color3.fromRGB(100, 20, 35)
        end
    end

    btn.MouseButton1Click:Connect(function()
        cfg[cfgKey] = not cfg[cfgKey]
        saveCfg()
        update()
        refreshVisualFx()
        updateStatus()
    end)

    fxToggleRows[cfgKey] = update
    update()
end

createFxToggleRow("FX ENABLED", "fx_enabled")
createFxToggleRow("CERVO FX", "fx_cervo")
createFxToggleRow("GATO FX", "fx_gato")

local minimizado = false
local hFullCache = nil
local _posData = loadJson(POS_KEY) or {}
local estadoJanela = "maximizado"
local hubWindowState = (_G.KAHWindowState and _G.KAHWindowState.get) and _G.KAHWindowState.get(MODULE_NAME, nil) or nil
if hubWindowState then
    estadoJanela = hubWindowState
elseif _posData.windowState == "maximizado" or _posData.windowState == "minimizado" or _posData.windowState == "fechado" then
    estadoJanela = _posData.windowState
elseif _posData.minimizado then
    estadoJanela = "minimizado"
end

if tonumber(_posData.x) and tonumber(_posData.y) then
    frame.Position = UDim2.new(0, _posData.x, 0, _posData.y)
end

local function setEstadoJanela(v)
    estadoJanela = v
    if _G.KAHWindowState and _G.KAHWindowState.set then
        _G.KAHWindowState.set(MODULE_NAME, v)
    end
end

local function savePos()
    saveJson(POS_KEY, {
        x = frame.Position.X.Offset,
        y = frame.Position.Y.Offset,
        minimizado = minimizado,
        hCache = hFullCache,
        windowState = estadoJanela,
    })
end

updateStatus = function()
    if not moduleRunning then
        statusLbl.Text = "// ENGINE OFF (HUB)"
        statusLbl.TextColor3 = C.red
        return
    end
    local audioState = cfg.enabled and "AUDIO ON" or "AUDIO OFF"
    local fxState = cfg.fx_enabled and "FX ON" or "FX OFF"
    statusLbl.Text = "// " .. audioState .. " | " .. fxState
    if cfg.enabled or cfg.fx_enabled then
        statusLbl.TextColor3 = C.green
    else
        statusLbl.TextColor3 = C.yellow
    end
end

local function updateToggleVisual()
    if cfg.enabled then
        togglePill.BackgroundColor3 = C.greenDim
        toggleKnob.Position = UDim2.new(1, -15, 0.5, -6)
        toggleKnob.BackgroundColor3 = C.green
        toggleStroke.Color = Color3.fromRGB(30, 100, 50)
        titleLbl.TextColor3 = C.green
    else
        togglePill.BackgroundColor3 = C.redDim
        toggleKnob.Position = UDim2.new(0, 3, 0.5, -6)
        toggleKnob.BackgroundColor3 = C.red
        toggleStroke.Color = Color3.fromRGB(100, 20, 35)
        titleLbl.TextColor3 = C.accent
    end
    for _, fn in pairs(fxToggleRows) do
        fn()
    end
    updateStatus()
end

local function applyFrameSize()
    uiScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.9, 1.35)
    local contentH = BASE_CONTENT_H + H_EXTRA
    if minimizado then
        frame.Size = UDim2.new(0, W, 0, H_HDR)
        content.Visible = false
        minBtn.Text = ""
    else
        frame.Size = UDim2.new(0, W, 0, H_HDR + contentH)
        content.Visible = true
        content.Size = UDim2.new(1, -PAD * 2, 0, contentH - PAD * 2)
        minBtn.Text = ""
    end

    local sw = workspace.CurrentCamera.ViewportSize.X
    local sh = workspace.CurrentCamera.ViewportSize.Y
    local nx = math.clamp(frame.Position.X.Offset, 4, sw - frame.Size.X.Offset - 4)
    local ny = math.clamp(frame.Position.Y.Offset, 4, sh - frame.Size.Y.Offset - 4)
    frame.Position = UDim2.new(0, nx, 0, ny)

    if _G.Snap and _G.Snap.atualizarTamanho then
        pcall(function() _G.Snap.atualizarTamanho(frame) end)
    end
end

local function applyResize(newW, newHExtra, save)
    W = math.clamp(math.floor((tonumber(newW) or W) + 0.5), MIN_W, MAX_W)
    if tonumber(newHExtra) ~= nil then
        H_EXTRA = math.floor(tonumber(newHExtra) + 0.5)
    end
    H_EXTRA = math.clamp(H_EXTRA, MIN_EXTRA_H, MAX_EXTRA_H)

    local sh = workspace.CurrentCamera.ViewportSize.Y
    local maxExtra = math.max(0, sh - (H_HDR + BASE_CONTENT_H) - 8)
    H_EXTRA = math.clamp(H_EXTRA, MIN_EXTRA_H, math.min(MAX_EXTRA_H, maxExtra))

    applyFrameSize()

    if save then
        saveSize()
        savePos()
    end
end

toggleBtn.MouseButton1Click:Connect(function()
    cfg.enabled = not cfg.enabled
    saveCfg()
    refreshEngine()
    updateToggleVisual()
end)

local dragging = false
local dragInput = nil
local dragStartPos = nil
local dragStartMouse = nil
local resizing = false
local resizeMode = nil
local resizeStartMouse = nil
local resizeStartW = nil
local resizeStartH = nil
local uiConnInputChanged = nil
local uiConnInputEnded = nil
local sliderConnChanged = nil
local sliderConnEnded = nil

local function disconnectUiConnections()
    uiDestroyed = true
    if uiConnInputChanged then uiConnInputChanged:Disconnect(); uiConnInputChanged = nil end
    if uiConnInputEnded then uiConnInputEnded:Disconnect(); uiConnInputEnded = nil end
    if sliderConnChanged then sliderConnChanged:Disconnect(); sliderConnChanged = nil end
    if sliderConnEnded then sliderConnEnded:Disconnect(); sliderConnEnded = nil end
end

header.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if resizing then return end
    dragging = true
    dragInput = i
    dragStartPos = frame.Position
    dragStartMouse = i.Position
end)

resizeHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    resizing = true
    resizeMode = "both"
    dragging = false
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartH = H_EXTRA
end)

resizeHHandle.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if minimizado then return end
    resizing = true
    resizeMode = "height"
    dragging = false
    resizeStartMouse = i.Position
    resizeStartW = W
    resizeStartH = H_EXTRA
end)

uiConnInputChanged = UIS.InputChanged:Connect(function(i)
    if uiDestroyed then return end
    if resizing and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local dx = i.Position.X - resizeStartMouse.X
        local dy = i.Position.Y - resizeStartMouse.Y
        if resizeMode == "height" then
            applyResize(W, resizeStartH + dy, false)
        else
            applyResize(resizeStartW + dx, resizeStartH + dy, false)
        end
        return
    end

    if not dragging then return end
    if i.UserInputType ~= Enum.UserInputType.MouseMovement
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if dragInput and dragInput.UserInputType == Enum.UserInputType.Touch
    and i.UserInputType == Enum.UserInputType.Touch
    and i ~= dragInput then
        return
    end

    local d = i.Position - dragStartMouse
    local nx = dragStartPos.X.Offset + d.X
    local ny = dragStartPos.Y.Offset + d.Y
    if _G.Snap then
        _G.Snap.mover(frame, nx, ny)
    else
        frame.Position = UDim2.new(0, nx, 0, ny)
    end
end)

uiConnInputEnded = UIS.InputEnded:Connect(function(i)
    if uiDestroyed then return end
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    if resizing then
        resizing = false
        resizeMode = nil
        applyResize(W, H_EXTRA, true)
        return
    end

    if dragging then
        if _G.Snap then
            _G.Snap.soltar(frame)
        else
            savePos()
        end
    end
    dragging = false
    dragInput = nil
end)

sliderConnChanged = UIS.InputChanged:Connect(function(i)
    if uiDestroyed then return end
    if not activeSlider then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch then
        activeSlider.setFromX(i.Position.X)
    end
end)

sliderConnEnded = UIS.InputEnded:Connect(function(i)
    if uiDestroyed then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        if activeSlider and activeSlider.dragFlag then
            activeSlider.dragFlag(false)
        end
        activeSlider = nil
        flushCfgIfDirty()
    end
end)

minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        hFullCache = frame.Size.Y.Offset
    end
    setEstadoJanela(minimizado and "minimizado" or "maximizado")
    applyFrameSize()
    savePos()
end)

local function closeStandalone()
    disconnectUiConnections()
    flushCfgIfDirty()
    stopEngine()
    sg:Destroy()
    _G[MODULE_STATE_KEY] = nil
end

closeBtn.MouseButton1Click:Connect(function()
    sg.Enabled = false
    setEstadoJanela("fechado")
    savePos()
    if _G.Hub and _G.Hub.desligar then
        local ok = pcall(function() _G.Hub.desligar(MODULE_NAME) end)
        if not ok then
            closeStandalone()
        end
    else
        closeStandalone()
    end
end)

if _G.Snap then _G.Snap.registrar(frame, savePos) end

local booting = true
local function onToggle(ativo)
    if sg and sg.Parent then
        sg.Enabled = ativo
    end

    if ativo then
        startEngine()
        applyFrameSize()
        updateToggleVisual()
    else
        stopEngine()
    end

    if not booting then
        if ativo then
            setEstadoJanela(minimizado and "minimizado" or "maximizado")
        else
            setEstadoJanela("fechado")
        end
        savePos()
    end
end

local iniciarAtivo
if _G.Hub or _G.HubFila then
    iniciarAtivo = estadoJanela ~= "fechado"
else
    iniciarAtivo = true
end

sg.Enabled = iniciarAtivo

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, iniciarAtivo)
elseif _G.HubFila then
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = MODULE_NAME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = iniciarAtivo })
end

if estadoJanela == "minimizado" then
    minimizado = true
    hFullCache = _posData.hCache or (H_HDR + BASE_CONTENT_H + H_EXTRA)
elseif _posData and _posData.minimizado and estadoJanela ~= "maximizado" then
    minimizado = true
    hFullCache = _posData.hCache or (H_HDR + BASE_CONTENT_H + H_EXTRA)
else
    minimizado = false
    hFullCache = _posData.hCache or (H_HDR + BASE_CONTENT_H + H_EXTRA)
end

applyResize(W, H_EXTRA, false)
updateToggleVisual()

if iniciarAtivo then
    startEngine()
    refreshEngine()
else
    stopEngine()
end

booting = false
savePos()

local function cleanup()
    disconnectUiConnections()
    stopEngine()
end

_G[MODULE_STATE_KEY] = {
    gui = sg,
    cleanup = cleanup,
}
