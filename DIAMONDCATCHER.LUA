-- ============================================
-- MÓDULO: DIAMOND FARM
-- Loop com intervalo configurável
-- ============================================

local CATEGORIA = "Farm"

-- Não executa sem o hub
if not _G.Hub and not _G.HubFila then
    print('>>> diamond: hub não encontrado, abortando')
    return
end

local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local TS       = game:GetService("TweenService")
local RunS     = game:GetService("RunService")
local UIS      = game:GetService("UserInputService")
local HS       = game:GetService("HttpService")
local Remote   = RS.RemoteEvents.RequestTakeDiamonds
local player   = Players.LocalPlayer
local pg       = player.PlayerGui

-- ============================================
-- CONFIGURAÇÃO PERSISTENTE
-- ============================================
local CFG_KEY   = "diamond_cfg.json"
local INTERVALO = 30
local MIN_INT   = 5
local MAX_INT   = 120

local function salvarCfg()
    if writefile then
        pcall(writefile, CFG_KEY, HS:JSONEncode({ intervalo = INTERVALO }))
    end
end
local function carregarCfg()
    if isfile and readfile and isfile(CFG_KEY) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(CFG_KEY)) end)
        if ok and d and d.intervalo then
            INTERVALO = math.clamp(d.intervalo, MIN_INT, MAX_INT)
        end
    end
end
carregarCfg()

-- ============================================
-- GUI
-- ============================================
do local a = pg:FindFirstChild("Diamond_hud"); if a then a:Destroy() end end

local C = {
    bg       = Color3.fromRGB(10, 11, 18),
    header   = Color3.fromRGB(12, 14, 22),
    border   = Color3.fromRGB(28, 32, 48),
    yellow   = Color3.fromRGB(255, 210, 50),
    yellowDim= Color3.fromRGB(55, 42, 5),
    green    = Color3.fromRGB(50, 220, 100),
    red      = Color3.fromRGB(220, 50, 70),
    redDim   = Color3.fromRGB(55, 12, 18),
    text     = Color3.fromRGB(180, 190, 210),
    muted    = Color3.fromRGB(65, 75, 100),
}
local FB = Enum.Font.GothamBold
local FM = Enum.Font.GothamMedium
local W  = 240; local H_HDR = 34; local PAD = 8

local gui = Instance.new("ScreenGui")
gui.Name = "Diamond_hud"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true; gui.Parent = pg
gui.DescendantAdded:Connect(function(d)
    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
        d.TextStrokeTransparency = 1
    end
end)

local frame = Instance.new("Frame")
frame.Name = "DiamondFrame"; frame.Size = UDim2.new(0,W,0,H_HDR)
frame.Position = UDim2.new(0,20,0,540)
frame.BackgroundColor3 = C.bg; frame.BorderSizePixel = 0; frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,6)
Instance.new("UIStroke", frame).Color = C.border

local topLine = Instance.new("Frame")
topLine.Size = UDim2.new(1,0,0,2); topLine.BackgroundColor3 = C.yellow
topLine.BorderSizePixel = 0; topLine.ZIndex = 6; topLine.Parent = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0,4)

local header = Instance.new("Frame")
header.Size = UDim2.new(1,0,0,H_HDR); header.BackgroundColor3 = C.header
header.BorderSizePixel = 0; header.ZIndex = 4; header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0,6)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1,-70,1,0); titleLbl.Position = UDim2.new(0,10,0,0)
titleLbl.Text = "💎 DIAMOND FARM"; titleLbl.TextColor3 = C.yellow
titleLbl.Font = FB; titleLbl.TextSize = 11; titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.ZIndex = 5; titleLbl.Parent = header

local function mkBtn(parent, xOff, txt, bgC, txC)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0,22,0,22); b.Position = UDim2.new(1,xOff,0.5,-11)
    b.Text = txt; b.BackgroundColor3 = bgC; b.TextColor3 = txC
    b.Font = FB; b.TextSize = 10; b.BorderSizePixel = 0; b.ZIndex = 6; b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,3)
    return b
end
local minBtn   = mkBtn(header, -48, "—", C.border, C.muted)
local closeBtn = mkBtn(header, -24, "✕", C.redDim, C.red)
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(100,20,35)

-- Conteúdo
local content = Instance.new("Frame")
content.Name = "Content"; content.BackgroundTransparency = 1; content.ZIndex = 3
content.Position = UDim2.new(0,0,0,H_HDR); content.Size = UDim2.new(1,0,0,0)
content.Parent = frame

local layout = Instance.new("UIListLayout", content)
layout.Padding = UDim.new(0,6); layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new("UIPadding", content)
pad.PaddingLeft = UDim.new(0,PAD); pad.PaddingRight = UDim.new(0,PAD)
pad.PaddingTop = UDim.new(0,PAD)

local function makeRow(order, h)
    local r = Instance.new("Frame")
    r.Size = UDim2.new(1,0,0,h); r.BackgroundTransparency = 1
    r.LayoutOrder = order; r.ZIndex = 4; r.Parent = content
    return r
end

-- Status
local rowStatus = makeRow(1, 26)
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1,0,1,0); statusLbl.BackgroundTransparency = 1
statusLbl.Text = "⏸ Aguardando..."; statusLbl.TextColor3 = C.muted
statusLbl.Font = FM; statusLbl.TextSize = 12
statusLbl.TextXAlignment = Enum.TextXAlignment.Left; statusLbl.ZIndex = 5
statusLbl.Parent = rowStatus

-- Contador
local rowCount = makeRow(2, 20)
local countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(1,0,1,0); countLbl.BackgroundTransparency = 1
countLbl.Text = "💎 0 coletados  |  próximo: —"
countLbl.TextColor3 = C.muted; countLbl.Font = FM; countLbl.TextSize = 10
countLbl.TextXAlignment = Enum.TextXAlignment.Left; countLbl.ZIndex = 5
countLbl.Parent = rowCount

-- Label intervalo
local rowIntLbl = makeRow(3, 18)
local intLabel = Instance.new("TextLabel")
intLabel.Size = UDim2.new(1,0,1,0); intLabel.BackgroundTransparency = 1
intLabel.Text = "Intervalo: " .. INTERVALO .. "s"
intLabel.TextColor3 = C.text; intLabel.Font = FM; intLabel.TextSize = 11
intLabel.TextXAlignment = Enum.TextXAlignment.Left; intLabel.ZIndex = 5
intLabel.Parent = rowIntLbl

-- Slider
local rowSlider = makeRow(4, 20)
local sliderTrack = Instance.new("Frame")
sliderTrack.Size = UDim2.new(1,0,0,6); sliderTrack.Position = UDim2.new(0,0,0.5,-3)
sliderTrack.BackgroundColor3 = C.border; sliderTrack.BorderSizePixel = 0
sliderTrack.ZIndex = 5; sliderTrack.Parent = rowSlider
Instance.new("UICorner", sliderTrack).CornerRadius = UDim.new(1,0)

local sliderFill = Instance.new("Frame")
sliderFill.Size = UDim2.new(0,0,1,0); sliderFill.BackgroundColor3 = C.yellow
sliderFill.BorderSizePixel = 0; sliderFill.ZIndex = 6; sliderFill.Parent = sliderTrack
Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1,0)

local sliderKnob = Instance.new("Frame")
sliderKnob.Size = UDim2.new(0,14,0,14); sliderKnob.AnchorPoint = Vector2.new(0.5,0.5)
sliderKnob.Position = UDim2.new(0,0,0.5,0)
sliderKnob.BackgroundColor3 = C.yellow; sliderKnob.BorderSizePixel = 0; sliderKnob.ZIndex = 7
sliderKnob.Parent = sliderTrack
Instance.new("UICorner", sliderKnob).CornerRadius = UDim.new(1,0)
Instance.new("UIStroke", sliderKnob).Color = Color3.fromRGB(120,90,0)

-- Input + botão
local rowInput = makeRow(5, 28)
local inputBox = Instance.new("TextBox")
inputBox.Size = UDim2.new(0.54,0,1,0)
inputBox.Text = tostring(INTERVALO); inputBox.PlaceholderText = "5–120"
inputBox.BackgroundColor3 = Color3.fromRGB(20,18,30)
inputBox.TextColor3 = Color3.fromRGB(240,230,255)
inputBox.Font = FB; inputBox.TextSize = 12; inputBox.BorderSizePixel = 0
inputBox.ClearTextOnFocus = false; inputBox.ZIndex = 5; inputBox.Parent = rowInput
Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", inputBox).Color = C.yellow

local confirmBtn = Instance.new("TextButton")
confirmBtn.Size = UDim2.new(0.43,0,1,0); confirmBtn.Position = UDim2.new(0.57,0,0,0)
confirmBtn.Text = "✓ Aplicar"; confirmBtn.BackgroundColor3 = C.yellowDim
confirmBtn.TextColor3 = C.yellow; confirmBtn.Font = FB; confirmBtn.TextSize = 11
confirmBtn.BorderSizePixel = 0; confirmBtn.ZIndex = 5; confirmBtn.Parent = rowInput
Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", confirmBtn).Color = Color3.fromRGB(100,75,0)

local function atualizarAltura()
    task.wait()
    local h = layout.AbsoluteContentSize.Y + PAD
    content.Size = UDim2.new(1,0,0,h)
    frame.Size = UDim2.new(0,W,0,H_HDR + h)
end

-- ============================================
-- SLIDER LOGIC
-- ============================================
local function setIntervalo(v)
    INTERVALO = math.clamp(math.round(v), MIN_INT, MAX_INT)
    local pct = (INTERVALO - MIN_INT) / (MAX_INT - MIN_INT)
    sliderFill.Size = UDim2.new(pct, 0, 1, 0)
    sliderKnob.Position = UDim2.new(pct, 0, 0.5, 0)
    intLabel.Text = "Intervalo: " .. INTERVALO .. "s"
    inputBox.Text = tostring(INTERVALO)
    salvarCfg()
end
setIntervalo(INTERVALO)

local sliding = false
sliderTrack.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = true end
end)
UIS.InputChanged:Connect(function(i)
    if not sliding or i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local rel = (i.Position.X - sliderTrack.AbsolutePosition.X) / sliderTrack.AbsoluteSize.X
    setIntervalo(MIN_INT + (MAX_INT - MIN_INT) * math.clamp(rel, 0, 1))
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end
end)

local function aplicarInput()
    local v = tonumber(inputBox.Text)
    if v then setIntervalo(v) end
end
confirmBtn.MouseButton1Click:Connect(aplicarInput)
inputBox.FocusLost:Connect(function(enter) if enter then aplicarInput() end end)

-- ============================================
-- LÓGICA DE COLETA
-- ============================================
local loopConn     = nil
local proxTick     = 0
local totalColetados = 0

local function coletar()
    local pastaItems = workspace:FindFirstChild("Items")
    if not pastaItems then return 0 end
    local n = 0
    for _, item in ipairs(pastaItems:GetChildren()) do
        if item.Name == "Diamond" and item:IsA("Model") then
            if pcall(function() Remote:FireServer(item) end) then n += 1 end
            task.wait(0.1)
        end
    end
    return n
end

local function iniciarLoop()
    if loopConn then return end
    proxTick = tick() + INTERVALO
    statusLbl.Text = "🟢 Rodando"; statusLbl.TextColor3 = C.green

    loopConn = RunS.Heartbeat:Connect(function()
        local restante = math.max(0, math.ceil(proxTick - tick()))
        countLbl.Text = "💎 " .. totalColetados .. " coletados  |  próximo: " .. restante .. "s"

        if tick() >= proxTick then
            proxTick = tick() + INTERVALO
            task.spawn(function()
                statusLbl.Text = "⚡ Coletando..."; statusLbl.TextColor3 = C.yellow
                local n = coletar()
                totalColetados += n
                statusLbl.Text = "🟢 Rodando"; statusLbl.TextColor3 = C.green
            end)
        end
    end)
end

local function pararLoop()
    if loopConn then loopConn:Disconnect(); loopConn = nil end
    statusLbl.Text = "⏸ Desativado"; statusLbl.TextColor3 = C.muted
    countLbl.Text = "💎 " .. totalColetados .. " coletados  |  próximo: —"
end

-- ============================================
-- MINIMIZAR / FECHAR
-- ============================================
local minimizado, hCache = false, nil
minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        hCache = frame.Size.Y.Offset
        TS:Create(frame, TweenInfo.new(0.18), {Size=UDim2.new(0,W,0,H_HDR)}):Play()
        content.Visible = false; minBtn.Text = "▲"
    else
        content.Visible = true
        TS:Create(frame, TweenInfo.new(0.18), {Size=UDim2.new(0,W,0,hCache or H_HDR+120)}):Play()
        minBtn.Text = "—"
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    pararLoop(); gui.Enabled = false
    if _G.Hub then pcall(function() _G.Hub.desligar("Diamond") end) end
end)

-- ============================================
-- DRAG + POSIÇÃO PERSISTENTE
-- ============================================
local POS_KEY = "diamond_pos.json"
local function salvarPos()
    if writefile then
        pcall(writefile, POS_KEY, HS:JSONEncode({
            x = frame.Position.X.Offset, y = frame.Position.Y.Offset
        }))
    end
end
local function carregarPos()
    if isfile and readfile and isfile(POS_KEY) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY)) end)
        if ok and d then frame.Position = UDim2.new(0, d.x, 0, d.y) end
    end
end
carregarPos()

local dragInput, dragStartPos, dragStartMouse
header.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    dragInput = i; dragStartPos = frame.Position; dragStartMouse = i.Position
end)
header.InputEnded:Connect(function(i)
    if i == dragInput then dragInput = nil; salvarPos() end
end)
UIS.InputChanged:Connect(function(i)
    if dragInput and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStartMouse
        frame.Position = UDim2.new(dragStartPos.X.Scale, dragStartPos.X.Offset + d.X,
                                   dragStartPos.Y.Scale, dragStartPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i == dragInput then dragInput = nil; salvarPos() end
end)

-- ============================================
-- HUB
-- ============================================
local function onToggle(ativo)
    if ativo then gui.Enabled = true; iniciarLoop()
    else pararLoop(); gui.Enabled = false end
end

if _G.Hub then
    _G.Hub.registrar("Diamond", onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome="Diamond", toggleFn=onToggle, categoria=CATEGORIA, jaAtivo=true })
end

-- ============================================
-- INIT
-- ============================================
atualizarAltura()
-- iniciarLoop é chamado pelo hub via toggleFn(true) ao registrar
-- Se hub não existir ainda (HubFila), inicia manualmente
if not _G.Hub then iniciarLoop() end
print(">>> DIAMOND FARM ATIVO | Intervalo: " .. INTERVALO .. "s")
