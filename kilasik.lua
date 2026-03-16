print('[KAH][LOAD] kilasik.lua')
-- ============================================
-- MÓDULO: MULTI FLING (SkidFling)
-- Seleciona múltiplos alvos e flinga em loop
-- Filtro dinâmico por DisplayName
-- ============================================
local VERSION     = "1.0.0"
local CATEGORIA   = "Player"
local MODULE_NAME = "Multi Fling"
local MODULE_STATE_KEY = "__kah_multifling_state"

if not _G.Hub and not _G.HubFila then
    print('[KAH][WARN][MultiFling] hub nao encontrado, abortando')
    return
end

do
    local old = _G[MODULE_STATE_KEY]
    if old and old.cleanup then pcall(old.cleanup) end
end
_G[MODULE_STATE_KEY] = nil

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local TS      = game:GetService("TweenService")
local RS      = game:GetService("RunService")
local player  = Players.LocalPlayer

-- ============================================
-- ESTADO
-- ============================================
local flingAtivo    = false
local flingThread   = nil
local sessionToken  = 0    -- incrementado a cada stop/reexecução
local selectedMap   = {}   -- [Player] = true
local filterText    = ""
local filterToken   = 0
local oldPos        = nil
local origFPDH      = workspace.FallenPartsDestroyHeight

-- função de cleanup de personagem compartilhada
local function restoreCharacter()
    local c   = player.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local hrp = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
    if hum then
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    if hrp then
        hrp.AssemblyLinearVelocity  = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
    if c then
        for _, v in ipairs(c:GetDescendants()) do
            if v:IsA("BodyVelocity") or v:IsA("BodyAngularVelocity") then
                pcall(function() v:Destroy() end)
            end
        end
    end
    local cam = workspace.CurrentCamera
    if cam and hum then pcall(function() cam.CameraSubject = hum end) end
    workspace.FallenPartsDestroyHeight = origFPDH
end

-- ============================================
-- HELPERS
-- ============================================
local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function getOtherPlayersSorted(needle)
    needle = string.lower(trim(needle))
    local lista = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local display = string.lower(tostring(p.DisplayName or ""))
            local name    = string.lower(tostring(p.Name or ""))
            if needle == ""
            or string.find(display, needle, 1, true)
            or string.find(name,    needle, 1, true) then
                table.insert(lista, p)
            end
        end
    end
    table.sort(lista, function(a, b)
        local ad = string.lower(tostring(a.DisplayName or ""))
        local bd = string.lower(tostring(b.DisplayName or ""))
        if ad == bd then
            return string.lower(a.Name) < string.lower(b.Name)
        end
        return ad < bd
    end)
    return lista
end

local function countSelected()
    local n = 0
    for _ in pairs(selectedMap) do n = n + 1 end
    return n
end

-- ============================================
-- SKID FLING
-- FPos e SFBasePart ficam fora do skidFling
-- para não estourar o limite de 200 locais
-- ============================================
local _fCtx = {}  -- contexto compartilhado entre as funções de fling

local function _fAlive()
    return sessionToken == _fCtx.token
end

local function _fPos(BasePart, Pos, Ang)
    if not _fAlive() then return end
    local cf = CFrame.new(BasePart.Position) * Pos * Ang
    _fCtx.rootPart.CFrame = cf
    _fCtx.rootPart.AssemblyLinearVelocity  = Vector3.new(9e7, 9e7 * 10, 9e7)
    _fCtx.rootPart.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
end

local function _sfBasePart(BasePart)
    local Time  = tick()
    local Angle = 0
    local hum   = _fCtx.targetHum
    repeat
        if not _fAlive() then break end
        local rp   = _fCtx.rootPart
        if rp and hum then
            local tVel = BasePart.AssemblyLinearVelocity.Magnitude
            if tVel < 50 then
                Angle = Angle + 100
                _fPos(BasePart, CFrame.new(0,  1.5, 0) + hum.MoveDirection * tVel / 1.25, CFrame.Angles(math.rad(Angle), 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0, -1.5, 0) + hum.MoveDirection * tVel / 1.25, CFrame.Angles(math.rad(Angle), 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0,  1.5, 0) + hum.MoveDirection * tVel / 1.25, CFrame.Angles(math.rad(Angle), 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0, -1.5, 0) + hum.MoveDirection * tVel / 1.25, CFrame.Angles(math.rad(Angle), 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0,  1.5, 0) + hum.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0, -1.5, 0) + hum.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0)) task.wait()
                if not _fAlive() then break end
            else
                _fPos(BasePart, CFrame.new(0,  1.5,  hum.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0, -1.5, -hum.WalkSpeed), CFrame.Angles(0, 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0,  1.5,  hum.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0)) task.wait()
                if not _fAlive() then break end
                _fPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0)) task.wait()
                if not _fAlive() then break end
            end
        end
    until tick() - Time >= 2.0 or not _fAlive()
end

local function skidFling(target)
    local myToken   = sessionToken
    local Character = player.Character
    local Humanoid  = Character and Character:FindFirstChildOfClass("Humanoid")
    local RootPart  = Humanoid and Humanoid.RootPart
    local TChar     = target and target.Character
    if not Character or not Humanoid or not RootPart or not TChar then return end
    if sessionToken ~= myToken then return end

    local THum  = TChar:FindFirstChildOfClass("Humanoid")
    local TRoot = THum and THum.RootPart
    local THead = TChar:FindFirstChild("Head")
    local Acc   = TChar:FindFirstChildOfClass("Accessory")
    local Hand  = Acc and Acc:FindFirstChild("Handle")

    if not TChar:FindFirstChildWhichIsA("BasePart") then return end
    if THum and THum.Sit then return end

    if RootPart.AssemblyLinearVelocity.Magnitude < 50 then
        oldPos = RootPart.CFrame
    end

    if THead then workspace.CurrentCamera.CameraSubject = THead
    elseif Hand then workspace.CurrentCamera.CameraSubject = Hand
    elseif THum and TRoot then workspace.CurrentCamera.CameraSubject = THum end

    -- popula contexto para _fPos/_sfBasePart
    _fCtx.token     = myToken
    _fCtx.rootPart  = RootPart
    _fCtx.targetHum = THum

    local BV = nil
    pcall(function()
        workspace.FallenPartsDestroyHeight = 0/0
        BV = Instance.new("BodyVelocity")
        BV.Parent   = RootPart
        BV.Velocity = Vector3.new(0, 0, 0)
        BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

        local basePart = TRoot or THead or Hand
        if basePart then _sfBasePart(basePart) end
    end)

    if BV then pcall(function() BV:Destroy() end) end
    pcall(function() Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end)
    restoreCharacter()

    if sessionToken == myToken and oldPos then
        local attempts = 0
        repeat
            RootPart.CFrame = oldPos * CFrame.new(0, 0.5, 0)
            Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            for _, p in ipairs(Character:GetChildren()) do
                if p:IsA("BasePart") then
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                end
            end
            task.wait()
            attempts += 1
        until (RootPart.Position - oldPos.p).Magnitude < 25 or attempts > 60
    end
end

-- ============================================
-- CORES
-- ============================================
local C = {
    bg        = Color3.fromRGB(10, 11, 15),
    header    = Color3.fromRGB(12, 14, 20),
    border    = Color3.fromRGB(28, 32, 48),
    accent    = Color3.fromRGB(220, 60, 80),
    accentDim = Color3.fromRGB(55, 12, 18),
    green     = Color3.fromRGB(50, 220, 100),
    greenDim  = Color3.fromRGB(15, 55, 25),
    red       = Color3.fromRGB(220, 50, 70),
    redDim    = Color3.fromRGB(55, 12, 18),
    text      = Color3.fromRGB(180, 190, 210),
    muted     = Color3.fromRGB(80, 92, 118),
    rowBg     = Color3.fromRGB(15, 17, 24),
    rowSel    = Color3.fromRGB(45, 12, 16),
}

-- ============================================
-- GUI
-- ============================================
local W          = 240
local H_HDR      = 34
local H_STATUS   = 20
local H_FILTER   = 28
local H_BTN_ROW  = 30
local H_ACTION   = 34   -- linha START / STOP
local H_SCROLL   = 200
local PAD        = 6
local H_FULL     = H_HDR + H_STATUS + PAD + H_FILTER + PAD + H_BTN_ROW + PAD + H_ACTION + PAD + H_SCROLL + PAD

local pg  = player:WaitForChild("PlayerGui")
do
    local ant = pg:FindFirstChild("MultiFling_hud")
    if ant then ant:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name           = "MultiFling_hud"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Enabled        = false
gui.Parent         = pg

local frame = Instance.new("Frame")
frame.Name             = "MFFrame"
frame.Size             = UDim2.new(0, W, 0, H_FULL)
frame.Position         = UDim2.new(0, 20, 0, 400)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel  = 0
frame.Parent           = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color        = C.border

-- linha accent topo
do
    local tl = Instance.new("Frame")
    tl.Size             = UDim2.new(1, 0, 0, 2)
    tl.BackgroundColor3 = C.accent
    tl.BorderSizePixel  = 0
    tl.ZIndex           = 5
    tl.Parent           = frame
    Instance.new("UICorner", tl).CornerRadius = UDim.new(0, 4)
end

-- Header
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, H_HDR)
header.BackgroundColor3 = C.header
header.BorderSizePixel  = 0
header.Active           = true
header.ZIndex           = 3
header.Parent           = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size               = UDim2.new(1, -80, 1, 0)
titleLbl.Position           = UDim2.new(0, 10, 0, 0)
titleLbl.Text               = "MULTI FLING"
titleLbl.TextColor3         = C.accent
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 11
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 4
titleLbl.Parent             = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0, 20, 0, 20)
closeBtn.Position         = UDim2.new(1, -26, 0.5, -10)
closeBtn.Text             = "x"
closeBtn.BackgroundColor3 = C.redDim
closeBtn.TextColor3       = C.red
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 10
closeBtn.BorderSizePixel  = 0
closeBtn.ZIndex           = 4
closeBtn.Parent           = header
Instance.new("UIStroke", closeBtn).Color        = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 3)

-- Status bar
local statusY  = H_HDR
local statusBar = Instance.new("Frame")
statusBar.Size             = UDim2.new(1, 0, 0, H_STATUS)
statusBar.Position         = UDim2.new(0, 0, 0, statusY)
statusBar.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
statusBar.BorderSizePixel  = 0
statusBar.ZIndex           = 2
statusBar.Parent           = frame

local statusLbl = Instance.new("TextLabel")
statusLbl.Size               = UDim2.new(1, -16, 1, 0)
statusLbl.Position           = UDim2.new(0, 8, 0, 0)
statusLbl.Text               = "// 0 ALVOS SELECIONADOS"
statusLbl.TextColor3         = C.muted
statusLbl.Font               = Enum.Font.Code
statusLbl.TextSize           = 9
statusLbl.BackgroundTransparency = 1
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left
statusLbl.ZIndex             = 3
statusLbl.Parent             = statusBar

local function setStatus(txt, cor)
    statusLbl.Text       = "// " .. txt
    statusLbl.TextColor3 = cor or C.muted
end

-- Filter bar
local filterY = statusY + H_STATUS + PAD
local filterFrame = Instance.new("Frame")
filterFrame.Size             = UDim2.new(1, -PAD * 2, 0, H_FILTER)
filterFrame.Position         = UDim2.new(0, PAD, 0, filterY)
filterFrame.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
filterFrame.BorderSizePixel  = 0
filterFrame.ZIndex           = 3
filterFrame.Parent           = frame
Instance.new("UICorner", filterFrame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", filterFrame).Color        = C.border

local filterLabel = Instance.new("TextLabel")
filterLabel.Size               = UDim2.new(0, 34, 1, 0)
filterLabel.Position           = UDim2.new(0, 8, 0, 0)
filterLabel.BackgroundTransparency = 1
filterLabel.Text               = "FIND"
filterLabel.TextColor3         = C.muted
filterLabel.Font               = Enum.Font.GothamBold
filterLabel.TextSize           = 9
filterLabel.TextXAlignment     = Enum.TextXAlignment.Left
filterLabel.ZIndex             = 4
filterLabel.Parent             = filterFrame

local filterBox = Instance.new("TextBox")
filterBox.Size               = UDim2.new(1, -54, 0, 18)
filterBox.Position           = UDim2.new(0, 42, 0.5, -9)
filterBox.BackgroundColor3   = Color3.fromRGB(22, 26, 38)
filterBox.TextColor3         = C.text
filterBox.PlaceholderColor3  = C.muted
filterBox.PlaceholderText    = "Nome do personagem"
filterBox.Text               = ""
filterBox.Font               = Enum.Font.GothamBold
filterBox.TextSize           = 9
filterBox.BorderSizePixel    = 0
filterBox.ClearTextOnFocus   = false
filterBox.TextXAlignment     = Enum.TextXAlignment.Left
filterBox.ZIndex             = 4
filterBox.Parent             = filterFrame
Instance.new("UICorner", filterBox).CornerRadius = UDim.new(0, 3)
Instance.new("UIStroke", filterBox).Color        = C.border

-- Botões SELECT ALL / DESELECT ALL
local btnY = filterY + H_FILTER + PAD
local selAllBtn = Instance.new("TextButton")
selAllBtn.Size             = UDim2.new(0.5, -PAD - 2, 0, H_BTN_ROW)
selAllBtn.Position         = UDim2.new(0, PAD, 0, btnY)
selAllBtn.Text             = "SELECT ALL"
selAllBtn.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
selAllBtn.TextColor3       = C.text
selAllBtn.Font             = Enum.Font.GothamBold
selAllBtn.TextSize         = 9
selAllBtn.BorderSizePixel  = 0
selAllBtn.ZIndex           = 3
selAllBtn.Parent           = frame
Instance.new("UICorner", selAllBtn).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", selAllBtn).Color        = C.border

local deselAllBtn = Instance.new("TextButton")
deselAllBtn.Size             = UDim2.new(0.5, -PAD - 2, 0, H_BTN_ROW)
deselAllBtn.Position         = UDim2.new(0.5, 2, 0, btnY)
deselAllBtn.Text             = "DESELECT ALL"
deselAllBtn.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
deselAllBtn.TextColor3       = C.text
deselAllBtn.Font             = Enum.Font.GothamBold
deselAllBtn.TextSize         = 9
deselAllBtn.BorderSizePixel  = 0
deselAllBtn.ZIndex           = 3
deselAllBtn.Parent           = frame
Instance.new("UICorner", deselAllBtn).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", deselAllBtn).Color        = C.border

-- Botões START / STOP
local actionY  = btnY + H_BTN_ROW + PAD
local startBtn = Instance.new("TextButton")
startBtn.Size             = UDim2.new(0.5, -PAD - 2, 0, H_ACTION)
startBtn.Position         = UDim2.new(0, PAD, 0, actionY)
startBtn.Text             = "▶  START"
startBtn.BackgroundColor3 = C.greenDim
startBtn.TextColor3       = C.green
startBtn.Font             = Enum.Font.GothamBold
startBtn.TextSize         = 11
startBtn.BorderSizePixel  = 0
startBtn.ZIndex           = 3
startBtn.Parent           = frame
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0, 4)
local startStroke = Instance.new("UIStroke", startBtn)
startStroke.Color = Color3.fromRGB(30, 100, 50)

local stopBtn = Instance.new("TextButton")
stopBtn.Size             = UDim2.new(0.5, -PAD - 2, 0, H_ACTION)
stopBtn.Position         = UDim2.new(0.5, 2, 0, actionY)
stopBtn.Text             = "■  STOP"
stopBtn.BackgroundColor3 = C.redDim
stopBtn.TextColor3       = C.red
stopBtn.Font             = Enum.Font.GothamBold
stopBtn.TextSize         = 11
stopBtn.BorderSizePixel  = 0
stopBtn.ZIndex           = 3
stopBtn.Parent           = frame
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 4)
local stopStroke = Instance.new("UIStroke", stopBtn)
stopStroke.Color = Color3.fromRGB(100, 20, 35)

-- ScrollFrame de jogadores
local scrollY = actionY + H_ACTION + PAD
local scroll = Instance.new("ScrollingFrame")
scroll.Size                 = UDim2.new(1, -PAD * 2, 0, H_SCROLL)
scroll.Position             = UDim2.new(0, PAD, 0, scrollY)
scroll.BackgroundColor3     = Color3.fromRGB(8, 9, 13)
scroll.BorderSizePixel      = 0
scroll.ScrollBarThickness   = 3
scroll.ScrollBarImageColor3 = C.accent
scroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
scroll.ZIndex               = 3
scroll.Parent               = frame
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", scroll).Color        = C.border

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.Padding   = UDim.new(0, 3)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
local listPad = Instance.new("UIPadding", scroll)
listPad.PaddingLeft  = UDim.new(0, 4)
listPad.PaddingTop   = UDim.new(0, 4)
listPad.PaddingRight = UDim.new(0, 4)

-- ============================================
-- RENDER LISTA
-- ============================================
local rowRefs = {}  -- [Player] = { row, checkmark, bar }

local function setStartStopVisual(ativo)
    if ativo then
        TS:Create(startBtn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(20, 80, 35) }):Play()
        startStroke.Color = Color3.fromRGB(50, 180, 80)
        startBtn.TextColor3 = Color3.fromRGB(100, 255, 140)
        TS:Create(stopBtn,  TweenInfo.new(0.12), { BackgroundColor3 = C.redDim }):Play()
        stopStroke.Color  = Color3.fromRGB(100, 20, 35)
        stopBtn.TextColor3 = C.red
    else
        TS:Create(startBtn, TweenInfo.new(0.12), { BackgroundColor3 = C.greenDim }):Play()
        startStroke.Color = Color3.fromRGB(30, 100, 50)
        startBtn.TextColor3 = C.green
        TS:Create(stopBtn,  TweenInfo.new(0.12), { BackgroundColor3 = C.redDim }):Play()
        stopStroke.Color  = Color3.fromRGB(100, 20, 35)
        stopBtn.TextColor3 = C.red
    end
end

local function updateStatus()
    local n = countSelected()
    if flingAtivo then
        setStatus("FLINGANDO " .. n .. " ALVO(S)", C.accent)
    elseif n > 0 then
        setStatus(n .. " ALVO(S) SELECIONADO(S)", C.text)
    else
        setStatus("0 ALVOS SELECIONADOS", C.muted)
    end
end

local function renderPlayers()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    rowRefs = {}

    local lista = getOtherPlayersSorted(filterText)

    for i, p in ipairs(lista) do
        local row = Instance.new("Frame")
        row.Name             = "MF_" .. p.Name
        row.Size             = UDim2.new(1, 0, 0, 30)
        row.BackgroundColor3 = selectedMap[p] and C.rowSel or C.rowBg
        row.BorderSizePixel  = 0
        row.LayoutOrder      = i
        row.ZIndex           = 4
        row.Parent           = scroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
        local rowStroke = Instance.new("UIStroke", row)
        rowStroke.Color = selectedMap[p] and C.accent or C.border

        local bar = Instance.new("Frame")
        bar.Size             = UDim2.new(0, 2, 1, -6)
        bar.Position         = UDim2.new(0, 0, 0, 3)
        bar.BackgroundColor3 = selectedMap[p] and C.accent or C.border
        bar.BorderSizePixel  = 0
        bar.ZIndex           = 5
        bar.Parent           = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

        -- checkmark box
        local checkBox = Instance.new("Frame")
        checkBox.Size             = UDim2.new(0, 16, 0, 16)
        checkBox.Position         = UDim2.new(0, 10, 0.5, -8)
        checkBox.BackgroundColor3 = selectedMap[p] and C.accentDim or Color3.fromRGB(22, 26, 38)
        checkBox.BorderSizePixel  = 0
        checkBox.ZIndex           = 5
        checkBox.Parent           = row
        Instance.new("UICorner", checkBox).CornerRadius = UDim.new(0, 3)
        local checkStroke = Instance.new("UIStroke", checkBox)
        checkStroke.Color = selectedMap[p] and C.accent or C.border

        local checkmark = Instance.new("TextLabel")
        checkmark.Size               = UDim2.new(1, 0, 1, 0)
        checkmark.BackgroundTransparency = 1
        checkmark.Text               = selectedMap[p] and "✓" or ""
        checkmark.TextColor3         = C.accent
        checkmark.Font               = Enum.Font.GothamBold
        checkmark.TextSize           = 11
        checkmark.ZIndex             = 6
        checkmark.Parent             = checkBox

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size               = UDim2.new(1, -36, 0.6, 0)
        nameLbl.Position           = UDim2.new(0, 32, 0, 4)
        nameLbl.Text               = p.DisplayName
        nameLbl.TextColor3         = selectedMap[p] and C.accent or C.text
        nameLbl.Font               = Enum.Font.GothamBold
        nameLbl.TextSize           = 11
        nameLbl.BackgroundTransparency = 1
        nameLbl.TextXAlignment     = Enum.TextXAlignment.Left
        nameLbl.TextTruncate       = Enum.TextTruncate.AtEnd
        nameLbl.ZIndex             = 5
        nameLbl.Parent             = row

        local userLbl = Instance.new("TextLabel")
        userLbl.Size               = UDim2.new(1, -36, 0.38, 0)
        userLbl.Position           = UDim2.new(0, 32, 0.62, 0)
        userLbl.Text               = "@" .. p.Name
        userLbl.TextColor3         = C.muted
        userLbl.Font               = Enum.Font.Code
        userLbl.TextSize           = 8
        userLbl.BackgroundTransparency = 1
        userLbl.TextXAlignment     = Enum.TextXAlignment.Left
        userLbl.ZIndex             = 5
        userLbl.Parent             = row

        rowRefs[p] = { row = row, checkmark = checkmark, bar = bar, rowStroke = rowStroke, checkStroke = checkStroke, nameLbl = nameLbl, checkBox = checkBox }

        local clickArea = Instance.new("TextButton")
        clickArea.Size               = UDim2.new(1, 0, 1, 0)
        clickArea.BackgroundTransparency = 1
        clickArea.Text               = ""
        clickArea.ZIndex             = 7
        clickArea.Parent             = row

        clickArea.MouseButton1Click:Connect(function()
            local sel = not selectedMap[p]
            selectedMap[p] = sel or nil
            local refs = rowRefs[p]
            if refs then
                local on = selectedMap[p] ~= nil
                TS:Create(refs.row,       TweenInfo.new(0.1), { BackgroundColor3 = on and C.rowSel or C.rowBg }):Play()
                TS:Create(refs.bar,       TweenInfo.new(0.1), { BackgroundColor3 = on and C.accent or C.border }):Play()
                TS:Create(refs.nameLbl,   TweenInfo.new(0.1), { TextColor3 = on and C.accent or C.text }):Play()
                TS:Create(refs.checkBox,  TweenInfo.new(0.1), { BackgroundColor3 = on and C.accentDim or Color3.fromRGB(22,26,38) }):Play()
                refs.checkmark.Text  = on and "✓" or ""
                refs.rowStroke.Color   = on and C.accent or C.border
                refs.checkStroke.Color = on and C.accent or C.border
            end
            updateStatus()
        end)

        row.MouseEnter:Connect(function()
            if not selectedMap[p] then
                TS:Create(row, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(22, 26, 38) }):Play()
            end
        end)
        row.MouseLeave:Connect(function()
            if not selectedMap[p] then
                TS:Create(row, TweenInfo.new(0.08), { BackgroundColor3 = C.rowBg }):Play()
            end
        end)
    end

    updateStatus()
end

-- ============================================
-- FILTRO DINÂMICO
-- ============================================
local function scheduleFilter()
    filterToken += 1
    local tok = filterToken
    task.delay(0.35, function()
        if filterToken ~= tok then return end
        filterText = trim(filterBox.Text)
        renderPlayers()
    end)
end

filterBox:GetPropertyChangedSignal("Text"):Connect(scheduleFilter)
filterBox.FocusLost:Connect(function()
    filterToken += 1
    filterText = trim(filterBox.Text)
    renderPlayers()
end)

-- ============================================
-- FLING LOOP
-- ============================================
local function pararFling()
    sessionToken += 1    -- invalida qualquer skidFling em andamento
    flingAtivo = false
    if flingThread then task.cancel(flingThread); flingThread = nil end
    task.spawn(restoreCharacter)  -- garante cleanup mesmo se o pcall interno não terminou
    setStartStopVisual(false)
    updateStatus()
end

local function iniciarFling()
    if flingAtivo then return end
    if countSelected() == 0 then
        setStatus("NENHUM ALVO SELECIONADO", C.red)
        return
    end
    flingAtivo = true
    setStartStopVisual(true)
    updateStatus()

    flingThread = task.spawn(function()
        while flingAtivo do
            -- limpa jogadores que saíram
            for p in pairs(selectedMap) do
                if not p or not p.Parent then
                    selectedMap[p] = nil
                end
            end

            if countSelected() == 0 then
                pararFling()
                break
            end

            for p in pairs(selectedMap) do
                if not flingAtivo then break end
                if p and p.Parent then
                    skidFling(p)
                    task.wait(0.1)
                end
            end

            task.wait(0.5)
        end
    end)
end

-- ============================================
-- START / STOP
-- ============================================
startBtn.MouseButton1Click:Connect(iniciarFling)
stopBtn.MouseButton1Click:Connect(pararFling)

-- SELECT / DESELECT ALL
-- ============================================
selAllBtn.MouseButton1Click:Connect(function()
    for _, p in ipairs(getOtherPlayersSorted(filterText)) do
        selectedMap[p] = true
    end
    renderPlayers()
end)

deselAllBtn.MouseButton1Click:Connect(function()
    selectedMap = {}
    renderPlayers()
end)

-- ============================================
-- DRAG
-- ============================================
do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = frame.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement
        and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = i.Position - dragStart
        local vp = workspace.CurrentCamera.ViewportSize
        local nx = math.clamp(startPos.X.Offset + d.X, 4, vp.X - frame.Size.X.Offset - 4)
        local ny = math.clamp(startPos.Y.Offset + d.Y, 4, vp.Y - frame.Size.Y.Offset - 4)
        frame.Position = UDim2.new(0, nx, 0, ny)
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- ============================================
-- CLOSE
-- ============================================
closeBtn.MouseButton1Click:Connect(function()
    pararFling()
    gui.Enabled = false
    if _G.Hub then pcall(function() _G.Hub.desligar(MODULE_NAME) end) end
end)

-- ============================================
-- PLAYERS ENTRAM/SAEM
-- ============================================
Players.PlayerAdded:Connect(function()
    task.wait(0.5)
    renderPlayers()
end)
Players.PlayerRemoving:Connect(function(p)
    selectedMap[p] = nil
    task.wait(0.2)
    renderPlayers()
    updateStatus()
end)

-- ============================================
-- REGISTRA NO HUB
-- ============================================
local function onToggle(ativo)
    gui.Enabled = ativo
    if not ativo then
        pararFling()
    else
        renderPlayers()
    end
end

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, false)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = MODULE_NAME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = false })
end

-- ============================================
-- API GLOBAL (compatível com admin commands)
-- ============================================
_G.KAHMultiFling = {
    start  = iniciarFling,
    stop   = pararFling,
    isActive = function() return flingAtivo end,
}

-- ============================================
-- CLEANUP
-- ============================================
_G[MODULE_STATE_KEY] = {
    cleanup = function()
        pararFling()
        if gui and gui.Parent then gui:Destroy() end
        if _G.Hub then pcall(function() _G.Hub.remover(MODULE_NAME) end) end
    end
}

renderPlayers()
print('[KAH][READY] MULTI FLING v' .. VERSION)
