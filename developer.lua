-- ============================================
-- MODULE: DEVELOPER
-- Private toolkit for diagnostics and data capture.
-- ============================================

local VERSION = "1.0.0"
local CATEGORIA = "Developer"
local MODULE_NAME = "Developer"
local MODULE_STATE_KEY = "__kah_developer_module_state"

if not _G.Hub and not _G.HubFila then
    return
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local HS = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local PLACE_ID = tostring(game.PlaceId)

local function isAllowedUser()
    local n = string.lower(tostring(player.Name))
    local d = string.lower(tostring(player.DisplayName))
    local allowedNames = {
        kahrrasco = true,
        dieisson = true,
    }
    if allowedNames[n] or allowedNames[d] then
        return true
    end
    local allowedIds = {
        [10384315642] = true,
    }
    return allowedIds[player.UserId] == true
end

if not isAllowedUser() then
    return
end

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

local function loadJson(path)
    if not (isfile and readfile and isfile(path)) then return nil end
    local ok, data = pcall(function()
        return HS:JSONDecode(readfile(path))
    end)
    if ok and type(data) == "table" then return data end
    return nil
end

local function saveJson(path, data)
    if not writefile then return end
    pcall(writefile, path, HS:JSONEncode(data))
end

local POS_KEY = "developer_pos_" .. PLACE_ID .. ".json"
local SIZE_KEY = "developer_size_" .. PLACE_ID .. ".json"
local UI_KEY = "developer_ui_" .. PLACE_ID .. ".json"

local posData = loadJson(POS_KEY) or {}
local sizeData = loadJson(SIZE_KEY) or {}
local uiData = loadJson(UI_KEY) or {}

local C = {
    bg = Color3.fromRGB(10, 11, 15),
    panel = Color3.fromRGB(15, 17, 23),
    header = Color3.fromRGB(12, 14, 20),
    border = Color3.fromRGB(28, 32, 48),
    accent = Color3.fromRGB(0, 220, 255),
    text = Color3.fromRGB(180, 190, 210),
    muted = Color3.fromRGB(95, 108, 132),
    green = Color3.fromRGB(50, 220, 100),
    greenDim = Color3.fromRGB(15, 55, 25),
    yellow = Color3.fromRGB(255, 200, 50),
    red = Color3.fromRGB(220, 50, 70),
    redDim = Color3.fromRGB(55, 12, 18),
    tabBg = Color3.fromRGB(12, 15, 24),
    tabOn = Color3.fromRGB(16, 28, 40),
    row = Color3.fromRGB(18, 20, 28),
}

local ICONS = {
    min = "rbxassetid://6031090990",
    close = "rbxassetid://6031091004",
    copy = "rbxassetid://6031260782",
}

local BASE_W = 260
local MIN_W = 220
local MAX_W = 460
local MIN_EXTRA_H = 0
local MAX_EXTRA_H = 360
local H_HDR = 34
local H_TAB = 26
local BODY_BASE = 176
local PAD = 6

local W = math.clamp(tonumber(sizeData.w) or BASE_W, MIN_W, MAX_W)
local H_EXTRA = math.clamp(tonumber(sizeData.hExtra) or 0, MIN_EXTRA_H, MAX_EXTRA_H)
local minimizado = uiData.minimizado == true
local hCache = tonumber(uiData.hCache) or (H_HDR + H_TAB + BODY_BASE + H_EXTRA)
local activeTab = tostring(uiData.activeTab or "tools")

local function savePos(frame)
    saveJson(POS_KEY, {
        x = frame.Position.X.Offset,
        y = frame.Position.Y.Offset,
    })
end

local function saveSize()
    saveJson(SIZE_KEY, { w = W, hExtra = H_EXTRA })
end

local function saveUi()
    saveJson(UI_KEY, {
        minimizado = minimizado,
        hCache = hCache,
        activeTab = activeTab,
    })
end

local function getHRP()
    local ch = player.Character
    if not ch then return nil end
    return ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso")
end

local function setEstadoJanela(v)
    if _G.KAHWindowState and _G.KAHWindowState.set then
        _G.KAHWindowState.set(MODULE_NAME, v)
    end
end

local pg = player:WaitForChild("PlayerGui")
local oldGui = pg:FindFirstChild("Developer_hud")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "Developer_hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Name = "DeveloperFrame"
frame.Size = UDim2.new(0, W, 0, H_HDR + H_TAB + BODY_BASE + H_EXTRA)
frame.Position = UDim2.new(0, tonumber(posData.x) or 20, 0, tonumber(posData.y) or 150)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color = C.border

local frameScale = Instance.new("UIScale")
frameScale.Name = "__DeveloperScale"
frameScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.88, 1.32)
frameScale.Parent = frame

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
titleLbl.Size = UDim2.new(1, -90, 1, 0)
titleLbl.Position = UDim2.new(0, 10, 0, 0)
titleLbl.Text = "DEVELOPER"
titleLbl.TextColor3 = C.accent
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 11
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.ZIndex = 4
titleLbl.Parent = header

local subtitleLbl = Instance.new("TextLabel")
subtitleLbl.Size = UDim2.new(1, -120, 0, 12)
subtitleLbl.Position = UDim2.new(0, 10, 1, -13)
subtitleLbl.Text = "private toolkit"
subtitleLbl.TextColor3 = C.muted
subtitleLbl.Font = Enum.Font.Gotham
subtitleLbl.TextSize = 9
subtitleLbl.BackgroundTransparency = 1
subtitleLbl.TextXAlignment = Enum.TextXAlignment.Left
subtitleLbl.ZIndex = 4
subtitleLbl.Parent = header

local function addIcon(btn, id, color)
    local icon = Instance.new("ImageLabel")
    icon.AnchorPoint = Vector2.new(0.5, 0.5)
    icon.Position = UDim2.new(0.5, 0, 0.5, 0)
    icon.Size = UDim2.new(0, 12, 0, 12)
    icon.BackgroundTransparency = 1
    icon.Image = id
    icon.ImageColor3 = color
    icon.ZIndex = btn.ZIndex + 1
    icon.Parent = btn
end

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 20)
minBtn.Position = UDim2.new(1, -44, 0.5, -10)
minBtn.Text = ""
minBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
minBtn.BorderSizePixel = 0
minBtn.ZIndex = 4
minBtn.Parent = header
Instance.new("UIStroke", minBtn).Color = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 3)
addIcon(minBtn, ICONS.min, C.muted)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -20, 0.5, -10)
closeBtn.Text = ""
closeBtn.BackgroundColor3 = C.redDim
closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 4
closeBtn.Parent = header
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 3)
addIcon(closeBtn, ICONS.close, C.red)

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, H_TAB)
tabBar.Position = UDim2.new(0, 0, 0, H_HDR)
tabBar.BackgroundColor3 = C.tabBg
tabBar.BorderSizePixel = 0
tabBar.Parent = frame

local tabToolsBtn = Instance.new("TextButton")
tabToolsBtn.Size = UDim2.new(0.5, 0, 1, 0)
tabToolsBtn.Position = UDim2.new(0, 0, 0, 0)
tabToolsBtn.Text = "TOOLS"
tabToolsBtn.BackgroundColor3 = C.tabBg
tabToolsBtn.TextColor3 = C.muted
tabToolsBtn.Font = Enum.Font.GothamBold
tabToolsBtn.TextSize = 10
tabToolsBtn.BorderSizePixel = 0
tabToolsBtn.Parent = tabBar

local tabInfoBtn = Instance.new("TextButton")
tabInfoBtn.Size = UDim2.new(0.5, 0, 1, 0)
tabInfoBtn.Position = UDim2.new(0.5, 0, 0, 0)
tabInfoBtn.Text = "INFO"
tabInfoBtn.BackgroundColor3 = C.tabBg
tabInfoBtn.TextColor3 = C.muted
tabInfoBtn.Font = Enum.Font.GothamBold
tabInfoBtn.TextSize = 10
tabInfoBtn.BorderSizePixel = 0
tabInfoBtn.Parent = tabBar

local body = Instance.new("Frame")
body.Size = UDim2.new(1, -12, 1, -(H_HDR + H_TAB + 8))
body.Position = UDim2.new(0, 6, 0, H_HDR + H_TAB + 4)
body.BackgroundTransparency = 1
body.Parent = frame

local toolsPage = Instance.new("Frame")
toolsPage.Size = UDim2.new(1, 0, 1, 0)
toolsPage.BackgroundTransparency = 1
toolsPage.Parent = body

local infoPage = Instance.new("Frame")
infoPage.Size = UDim2.new(1, 0, 1, 0)
infoPage.BackgroundTransparency = 1
infoPage.Visible = false
infoPage.Parent = body

local statusBar = Instance.new("Frame")
statusBar.Size = UDim2.new(1, 0, 0, 24)
statusBar.Position = UDim2.new(0, 0, 1, -24)
statusBar.BackgroundColor3 = C.panel
statusBar.BorderSizePixel = 0
statusBar.Parent = body
Instance.new("UICorner", statusBar).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", statusBar).Color = C.border

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -8, 1, 0)
statusLbl.Position = UDim2.new(0, 8, 0, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Pronto."
statusLbl.TextColor3 = C.text
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 10
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = statusBar

local function setStatus(msg, color)
    statusLbl.Text = tostring(msg)
    statusLbl.TextColor3 = color or C.text
end

local capCard = Instance.new("Frame")
capCard.Size = UDim2.new(1, 0, 0, 146)
capCard.Position = UDim2.new(0, 0, 0, 0)
capCard.BackgroundColor3 = C.panel
capCard.BorderSizePixel = 0
capCard.Parent = toolsPage
Instance.new("UICorner", capCard).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", capCard).Color = C.border

local capTitle = Instance.new("TextLabel")
capTitle.Size = UDim2.new(1, -12, 0, 20)
capTitle.Position = UDim2.new(0, 8, 0, 6)
capTitle.Text = "CAPTURE"
capTitle.BackgroundTransparency = 1
capTitle.TextColor3 = C.accent
capTitle.Font = Enum.Font.GothamBold
capTitle.TextSize = 10
capTitle.TextXAlignment = Enum.TextXAlignment.Left
capTitle.Parent = capCard

local capDesc = Instance.new("TextLabel")
capDesc.Size = UDim2.new(1, -12, 0, 38)
capDesc.Position = UDim2.new(0, 8, 0, 28)
capDesc.Text = "Pose e pontos do Stronghold para clipboard."
capDesc.BackgroundTransparency = 1
capDesc.TextWrapped = true
capDesc.TextColor3 = C.text
capDesc.Font = Enum.Font.Gotham
capDesc.TextSize = 10
capDesc.TextXAlignment = Enum.TextXAlignment.Left
capDesc.TextYAlignment = Enum.TextYAlignment.Top
capDesc.Parent = capCard

local captureBtn = Instance.new("TextButton")
captureBtn.Size = UDim2.new(1, -16, 0, 28)
captureBtn.Position = UDim2.new(0, 8, 0, 72)
captureBtn.Text = "COPIAR POSE"
captureBtn.BackgroundColor3 = C.greenDim
captureBtn.TextColor3 = C.green
captureBtn.Font = Enum.Font.GothamBold
captureBtn.TextSize = 10
captureBtn.BorderSizePixel = 0
captureBtn.Parent = capCard
Instance.new("UICorner", captureBtn).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", captureBtn).Color = C.border

local copyIcon = Instance.new("ImageLabel")
copyIcon.AnchorPoint = Vector2.new(0, 0.5)
copyIcon.Position = UDim2.new(0, 10, 0.5, 0)
copyIcon.Size = UDim2.new(0, 11, 0, 11)
copyIcon.BackgroundTransparency = 1
copyIcon.Image = ICONS.copy
copyIcon.ImageColor3 = C.green
copyIcon.Parent = captureBtn

local captureStrongBtn = Instance.new("TextButton")
captureStrongBtn.Size = UDim2.new(1, -16, 0, 28)
captureStrongBtn.Position = UDim2.new(0, 8, 0, 104)
captureStrongBtn.Text = "COPIAR PONTOS STRONG"
captureStrongBtn.BackgroundColor3 = Color3.fromRGB(12, 36, 50)
captureStrongBtn.TextColor3 = C.accent
captureStrongBtn.Font = Enum.Font.GothamBold
captureStrongBtn.TextSize = 10
captureStrongBtn.BorderSizePixel = 0
captureStrongBtn.Parent = capCard
Instance.new("UICorner", captureStrongBtn).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", captureStrongBtn).Color = C.border

local strongIcon = Instance.new("ImageLabel")
strongIcon.AnchorPoint = Vector2.new(0, 0.5)
strongIcon.Position = UDim2.new(0, 10, 0.5, 0)
strongIcon.Size = UDim2.new(0, 11, 0, 11)
strongIcon.BackgroundTransparency = 1
strongIcon.Image = ICONS.copy
strongIcon.ImageColor3 = C.accent
strongIcon.Parent = captureStrongBtn

local placeholderCard = Instance.new("Frame")
placeholderCard.Size = UDim2.new(1, 0, 0, 52)
placeholderCard.Position = UDim2.new(0, 0, 0, 152)
placeholderCard.BackgroundColor3 = C.panel
placeholderCard.BorderSizePixel = 0
placeholderCard.Parent = toolsPage
Instance.new("UICorner", placeholderCard).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", placeholderCard).Color = C.border

local placeholderText = Instance.new("TextLabel")
placeholderText.Size = UDim2.new(1, -12, 1, 0)
placeholderText.Position = UDim2.new(0, 8, 0, 0)
placeholderText.BackgroundTransparency = 1
placeholderText.Text = "Espaco reservado para proximas ferramentas."
placeholderText.TextColor3 = C.muted
placeholderText.Font = Enum.Font.Gotham
placeholderText.TextSize = 10
placeholderText.TextWrapped = true
placeholderText.TextXAlignment = Enum.TextXAlignment.Left
placeholderText.Parent = placeholderCard

local infoCard = Instance.new("Frame")
infoCard.Size = UDim2.new(1, 0, 1, 0)
infoCard.BackgroundColor3 = C.panel
infoCard.BorderSizePixel = 0
infoCard.Parent = infoPage
Instance.new("UICorner", infoCard).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", infoCard).Color = C.border

local infoText = Instance.new("TextLabel")
infoText.Size = UDim2.new(1, -12, 1, -12)
infoText.Position = UDim2.new(0, 8, 0, 6)
infoText.BackgroundTransparency = 1
infoText.TextWrapped = true
infoText.TextYAlignment = Enum.TextYAlignment.Top
infoText.TextXAlignment = Enum.TextXAlignment.Left
infoText.TextColor3 = C.text
infoText.Font = Enum.Font.Gotham
infoText.TextSize = 10
infoText.Text = "Modulo privado habilitado para seu usuario.\n\nTab TOOLS: captura dados do personagem para clipboard.\n\nTab INFO: area para notas e diagnosticos futuros."
infoText.Parent = infoCard

local resizeHandle = Instance.new("TextButton")
resizeHandle.Size = UDim2.new(0, 14, 0, 14)
resizeHandle.Position = UDim2.new(1, -16, 1, -16)
resizeHandle.Text = ""
resizeHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHandle.BorderSizePixel = 0
resizeHandle.ZIndex = 8
resizeHandle.Parent = frame
Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 2)
Instance.new("UIStroke", resizeHandle).Color = C.border

local resizeDot = Instance.new("Frame")
resizeDot.Size = UDim2.new(0, 3, 0, 3)
resizeDot.Position = UDim2.new(1, -5, 1, -5)
resizeDot.BackgroundColor3 = C.muted
resizeDot.BorderSizePixel = 0
resizeDot.Parent = resizeHandle
Instance.new("UICorner", resizeDot).CornerRadius = UDim.new(1, 0)

local resizeHHandle = Instance.new("TextButton")
resizeHHandle.Size = UDim2.new(0, 24, 0, 8)
resizeHHandle.Position = UDim2.new(0.5, -12, 1, -10)
resizeHHandle.Text = ""
resizeHHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHHandle.BorderSizePixel = 0
resizeHHandle.ZIndex = 8
resizeHHandle.Parent = frame
Instance.new("UICorner", resizeHHandle).CornerRadius = UDim.new(1, 0)
Instance.new("UIStroke", resizeHHandle).Color = C.border

local resizeLHandle = Instance.new("TextButton")
resizeLHandle.Size = UDim2.new(0, 8, 0, 36)
resizeLHandle.Position = UDim2.new(0, -4, 0.5, -18)
resizeLHandle.Text = ""
resizeLHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeLHandle.BorderSizePixel = 0
resizeLHandle.ZIndex = 8
resizeLHandle.Parent = frame
Instance.new("UICorner", resizeLHandle).CornerRadius = UDim.new(1, 0)
Instance.new("UIStroke", resizeLHandle).Color = C.border

local resizeRHandle = Instance.new("TextButton")
resizeRHandle.Size = UDim2.new(0, 8, 0, 36)
resizeRHandle.Position = UDim2.new(1, -4, 0.5, -18)
resizeRHandle.Text = ""
resizeRHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeRHandle.BorderSizePixel = 0
resizeRHandle.ZIndex = 8
resizeRHandle.Parent = frame
Instance.new("UICorner", resizeRHandle).CornerRadius = UDim.new(1, 0)
Instance.new("UIStroke", resizeRHandle).Color = C.border

local function frameHeight()
    return H_HDR + H_TAB + BODY_BASE + H_EXTRA
end

local function clampToScreen()
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    local nx = math.clamp(frame.Position.X.Offset, 4, vp.X - frame.Size.X.Offset - 4)
    local ny = math.clamp(frame.Position.Y.Offset, 4, vp.Y - frame.Size.Y.Offset - 4)
    frame.Position = UDim2.new(0, nx, 0, ny)
end

local function applySize(newW, newHExtra, persist)
    W = math.clamp(math.floor((tonumber(newW) or W) + 0.5), MIN_W, MAX_W)
    if tonumber(newHExtra) ~= nil then
        H_EXTRA = math.floor((tonumber(newHExtra) or H_EXTRA) + 0.5)
    end
    H_EXTRA = math.clamp(H_EXTRA, MIN_EXTRA_H, MAX_EXTRA_H)
    frameScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.88, 1.32)
    if minimizado then
        frame.Size = UDim2.new(0, W, 0, H_HDR)
    else
        frame.Size = UDim2.new(0, W, 0, frameHeight())
    end
    clampToScreen()
    if persist then
        saveSize()
        savePos(frame)
    end
    if _G.Snap and _G.Snap.atualizarTamanho then
        pcall(function() _G.Snap.atualizarTamanho(frame) end)
    end
end

local function switchTab(tabName)
    activeTab = tabName
    local toolsOn = tabName == "tools"
    toolsPage.Visible = toolsOn
    infoPage.Visible = not toolsOn
    tabToolsBtn.BackgroundColor3 = toolsOn and C.tabOn or C.tabBg
    tabToolsBtn.TextColor3 = toolsOn and C.accent or C.muted
    tabInfoBtn.BackgroundColor3 = toolsOn and C.tabBg or C.tabOn
    tabInfoBtn.TextColor3 = toolsOn and C.muted or C.accent
    saveUi()
end

local dragging = false
local dragStart
local startPos
local resizing = false
local resizeMode = nil
local resizeStartMouse
local resizeStartW
local resizeStartExtra
local resizeStartRightX
local conns = {}
local uiDestroyed = false
local booting = true

table.insert(conns, header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        if resizing then return end
        dragging = true
        dragStart = i.Position
        startPos = frame.Position
    end
end))

table.insert(conns, resizeHandle.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        if minimizado then return end
        resizing = true
        resizeMode = "both"
        dragging = false
        resizeStartMouse = i.Position
        resizeStartW = W
        resizeStartExtra = H_EXTRA
    end
end))

table.insert(conns, resizeHHandle.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        if minimizado then return end
        resizing = true
        resizeMode = "height"
        dragging = false
        resizeStartMouse = i.Position
        resizeStartW = W
        resizeStartExtra = H_EXTRA
    end
end))

table.insert(conns, resizeLHandle.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        if minimizado then return end
        resizing = true
        resizeMode = "left"
        dragging = false
        resizeStartMouse = i.Position
        resizeStartW = W
        resizeStartExtra = H_EXTRA
        resizeStartRightX = frame.Position.X.Offset + frame.Size.X.Offset
    end
end))

table.insert(conns, resizeRHandle.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        if minimizado then return end
        resizing = true
        resizeMode = "right"
        dragging = false
        resizeStartMouse = i.Position
        resizeStartW = W
        resizeStartExtra = H_EXTRA
    end
end))

table.insert(conns, UIS.InputChanged:Connect(function(i)
    if resizing and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local dx = i.Position.X - resizeStartMouse.X
        local dy = i.Position.Y - resizeStartMouse.Y
        if resizeMode == "height" then
            applySize(W, resizeStartExtra + dy, false)
        elseif resizeMode == "left" then
            applySize(resizeStartW - dx, resizeStartExtra, false)
            local sw = workspace.CurrentCamera.ViewportSize.X
            local nx = math.clamp(resizeStartRightX - frame.Size.X.Offset, 4, sw - frame.Size.X.Offset - 4)
            frame.Position = UDim2.new(0, nx, 0, frame.Position.Y.Offset)
        elseif resizeMode == "right" then
            applySize(resizeStartW + dx, resizeStartExtra, false)
        else
            applySize(resizeStartW + dx, resizeStartExtra + dy, false)
        end
        return
    end
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        clampToScreen()
    end
end))

table.insert(conns, UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        if resizing then
            resizing = false
            resizeMode = nil
            applySize(W, H_EXTRA, true)
            return
        end
        if dragging then
            savePos(frame)
        end
        dragging = false
    end
end))

table.insert(conns, tabToolsBtn.MouseButton1Click:Connect(function()
    switchTab("tools")
end))

table.insert(conns, tabInfoBtn.MouseButton1Click:Connect(function()
    switchTab("info")
end))

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Developer",
            Text = tostring(msg),
            Duration = 2.5,
        })
    end)
end

local function pathGet(root, path)
    local cur = root
    for i = 1, #path do
        if not cur then return nil end
        cur = cur:FindFirstChild(path[i])
    end
    return cur
end

local function asPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        if obj.PrimaryPart then return obj.PrimaryPart end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function pairCenter(pathRight, pathLeft)
    local right = asPart(pathGet(workspace, pathRight))
    local left = asPart(pathGet(workspace, pathLeft))
    if right and left then
        return (right.Position + left.Position) * 0.5
    end
    if right then return right.Position end
    if left then return left.Position end
    return nil
end

local function vecToLua(v)
    if not v then return "nil" end
    return string.format("Vector3.new(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
end

local function vecToText(tag, v)
    if not v then
        return tag .. "=nil"
    end
    return string.format("%s=(%.3f, %.3f, %.3f)", tag, v.X, v.Y, v.Z)
end

local function capturePose()
    local ch = player.Character
    local hrp = getHRP()
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hrp then
        setStatus("Falha: personagem sem HRP.", C.red)
        return
    end

    local cf = hrp.CFrame
    local p = cf.Position
    local lv = cf.LookVector
    local rv = cf.RightVector
    local uv = cf.UpVector
    local rx, ry, rz = cf:ToEulerAnglesYXZ()
    local yaw = math.deg(ry)
    local pitch = math.deg(rx)
    local roll = math.deg(rz)
    local comps = { cf:GetComponents() }

    local function vec(v)
        return string.format("(%.4f, %.4f, %.4f)", v.X, v.Y, v.Z)
    end
    local function num(v)
        return string.format("%.6f", tonumber(v) or 0)
    end

    local cRows = {}
    for i = 1, #comps do
        cRows[#cRows + 1] = num(comps[i])
    end

    local floorMat = hum and tostring(hum.FloorMaterial) or "Unknown"
    local payload = table.concat({
        string.format("dev_pose | place=%s | job=%s | user=%s(%d)", tostring(game.PlaceId), tostring(game.JobId), tostring(player.Name), tonumber(player.UserId)),
        string.format("pos=%s", vec(p)),
        string.format("look=%s", vec(lv)),
        string.format("right=%s", vec(rv)),
        string.format("up=%s", vec(uv)),
        string.format("ypr_deg=(%.3f, %.3f, %.3f)", yaw, pitch, roll),
        string.format("height_y=%.4f", p.Y),
        string.format("hip_height=%.4f", hum and hum.HipHeight or 0),
        string.format("walkspeed=%.2f", hum and hum.WalkSpeed or 0),
        string.format("jumppower=%.2f", hum and hum.JumpPower or 0),
        string.format("floor_material=%s", floorMat),
        "cf_components=" .. table.concat(cRows, ","),
    }, "\n")

    if setclipboard then
        local ok = pcall(setclipboard, payload)
        if ok then
            setStatus("Pose copiada para clipboard.", C.green)
            notify("Pose copiada.")
        else
            setStatus("Falha ao copiar para clipboard.", C.red)
        end
    else
        setStatus("Executor sem setclipboard.", C.red)
    end
end

table.insert(conns, captureBtn.MouseButton1Click:Connect(function()
    TS:Create(captureBtn, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(22, 88, 44) }):Play()
    task.delay(0.18, function()
        if captureBtn and captureBtn.Parent then
            TS:Create(captureBtn, TweenInfo.new(0.12), { BackgroundColor3 = C.greenDim }):Play()
        end
    end)
    capturePose()
end))

local function captureStrongPoints()
    local hrp = getHRP()
    if not hrp then
        setStatus("Falha: personagem sem HRP.", C.red)
        return
    end

    local entryCenter = pairCenter(
        {"Map", "Landmarks", "Stronghold", "Functional", "EntryDoors", "DoorRight", "Main"},
        {"Map", "Landmarks", "Stronghold", "Functional", "EntryDoors", "DoorLeft", "Main"}
    )
    local door1Center = pairCenter(
        {"Map", "Landmarks", "Stronghold", "Functional", "Doors", "LockedDoorsFloor1", "DoorRight", "Main"},
        {"Map", "Landmarks", "Stronghold", "Functional", "Doors", "LockedDoorsFloor1", "DoorLeft", "Main"}
    )
    local myPos = hrp.Position

    local data = {
        placeId = game.PlaceId,
        jobId = game.JobId,
        user = { name = player.Name, userId = player.UserId },
        myPos = { x = myPos.X, y = myPos.Y, z = myPos.Z },
        strongEntry = entryCenter and { x = entryCenter.X, y = entryCenter.Y, z = entryCenter.Z } or nil,
        strongDoor1 = door1Center and { x = door1Center.X, y = door1Center.Y, z = door1Center.Z } or nil,
    }

    _G.KAH_STRONG_ROUTE_SAMPLE = {
        placeId = game.PlaceId,
        jobId = game.JobId,
        userId = player.UserId,
        capturedAt = os.time(),
        entry = entryCenter,
        door1 = door1Center,
        between = myPos,
    }

    local payload = table.concat({
        "DEV_STRONG_POINTS",
        string.format("place=%s | job=%s | user=%s(%d)", tostring(game.PlaceId), tostring(game.JobId), tostring(player.Name), tonumber(player.UserId)),
        vecToText("entry_between", entryCenter),
        vecToText("door1_between", door1Center),
        vecToText("my_pos", myPos),
        "lua_entry_between=" .. vecToLua(entryCenter),
        "lua_door1_between=" .. vecToLua(door1Center),
        "lua_my_pos=" .. vecToLua(myPos),
        "json=" .. HS:JSONEncode(data),
    }, "\n")

    if setclipboard then
        local ok = pcall(setclipboard, payload)
        if ok then
            if entryCenter and door1Center then
                setStatus("Pontos do Strong copiados.", C.green)
                notify("Strong points copiados.")
            else
                setStatus("Copiado com campos faltando (strong parcial).", C.yellow)
                notify("Strong points parcial.")
            end
        else
            setStatus("Falha ao copiar para clipboard.", C.red)
        end
    else
        setStatus("Executor sem setclipboard.", C.red)
    end
end

table.insert(conns, captureStrongBtn.MouseButton1Click:Connect(function()
    TS:Create(captureStrongBtn, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(18, 54, 72) }):Play()
    task.delay(0.18, function()
        if captureStrongBtn and captureStrongBtn.Parent then
            TS:Create(captureStrongBtn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(12, 36, 50) }):Play()
        end
    end)
    captureStrongPoints()
end))

local function refreshMinState()
    if minimizado then
        hCache = frameHeight()
        frame.Size = UDim2.new(0, W, 0, H_HDR)
        tabBar.Visible = false
        body.Visible = false
    else
        frame.Size = UDim2.new(0, W, 0, frameHeight())
        tabBar.Visible = true
        body.Visible = true
    end
end

table.insert(conns, minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    refreshMinState()
    setEstadoJanela(minimizado and "minimizado" or "maximizado")
    saveUi()
    savePos(frame)
end))

local function closeUi(fromHub)
    if uiDestroyed then return end
    gui.Enabled = false
    if not fromHub and _G.Hub and _G.Hub.desligar then
        pcall(function() _G.Hub.desligar(MODULE_NAME) end)
    end
    setEstadoJanela("fechado")
    saveUi()
    savePos(frame)
end

table.insert(conns, closeBtn.MouseButton1Click:Connect(function()
    closeUi(false)
end))

if _G.Snap then
    _G.Snap.registrar(frame, function()
        savePos(frame)
    end)
end

local savedWinState = (_G.KAHWindowState and _G.KAHWindowState.get) and _G.KAHWindowState.get(MODULE_NAME, nil) or nil
local estadoJanela = savedWinState or (uiData.minimizado and "minimizado" or "maximizado")

local function onToggle(ativo)
    if uiDestroyed then return end
    gui.Enabled = ativo
    if not booting then
        if ativo then
            setEstadoJanela(minimizado and "minimizado" or "maximizado")
        else
            setEstadoJanela("fechado")
        end
        saveUi()
        savePos(frame)
    end
end

local iniciarAtivo = estadoJanela ~= "fechado"
gui.Enabled = iniciarAtivo

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, iniciarAtivo)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = MODULE_NAME,
        toggleFn = onToggle,
        categoria = CATEGORIA,
        jaAtivo = iniciarAtivo
    })
end

if activeTab ~= "info" then activeTab = "tools" end
switchTab(activeTab)
applySize(W, H_EXTRA, false)
refreshMinState()

if estadoJanela == "minimizado" then
    minimizado = true
    refreshMinState()
elseif estadoJanela == "maximizado" then
    minimizado = false
    refreshMinState()
end

local function cleanup()
    if uiDestroyed then return end
    uiDestroyed = true
    for _, c in ipairs(conns) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(conns)
    if gui and gui.Parent then
        pcall(function() gui:Destroy() end)
    end
    _G[MODULE_STATE_KEY] = nil
end

_G[MODULE_STATE_KEY] = {
    gui = gui,
    cleanup = cleanup,
}

booting = false
setStatus("Pronto.", C.text)
