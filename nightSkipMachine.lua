-- ============================================
-- MÓDULO: NightSkipMachine
-- Verifica a cada 10s se a máquina está pronta
-- e dispara automaticamente quando Charged=true
-- ============================================

local VERSION   = "1.0"
local CATEGORIA = "Utility"

-- Não executa sem o hub
if not _G.Hub and not _G.HubFila then
    print('>>> night_skip: hub não encontrado, abortando')
    return
end

local Players = game:GetService("Players")
local RS      = game:GetService("RunService")
local TS      = game:GetService("TweenService")
local UIS     = game:GetService("UserInputService")
local RE      = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvents")
local player  = Players.LocalPlayer

-- ============================================
-- LÓGICA
-- ============================================
local INTERVALO   = 10    -- segundos entre verificações
local loopThread  = nil
local ultimoFire  = 0
local totalFires  = 0

local function getMaquina()
    local structs = workspace:FindFirstChild("Structures")
    return structs and structs:FindFirstChild("Temporal Accelerometer")
end

local function maquinaCarregada(maq)
    -- Dispara sempre que a máquina existir no workspace
    -- O servidor decide se aceita ou não
    return maq ~= nil
end

local function dispararMaquina(maq)
    -- Assinatura confirmada: workspace.Structures["Temporal Accelerometer"] como arg
    local ok = pcall(function()
        RE.RequestActivateNightSkipMachine:FireServer(maq)
    end)
    return ok
end

-- ============================================
-- CORES
-- ============================================
local C = {
    bg       = Color3.fromRGB(10, 11, 15),
    header   = Color3.fromRGB(12, 14, 20),
    border   = Color3.fromRGB(28, 32, 48),
    accent   = Color3.fromRGB(0, 220, 255),
    green    = Color3.fromRGB(50, 220, 100),
    greenDim = Color3.fromRGB(15, 55, 25),
    red      = Color3.fromRGB(220, 50, 70),
    redDim   = Color3.fromRGB(55, 12, 18),
    yellow   = Color3.fromRGB(255, 200, 50),
    blue     = Color3.fromRGB(80, 160, 255),
    blueDim  = Color3.fromRGB(12, 30, 60),
    text     = Color3.fromRGB(215, 222, 238),
    muted    = Color3.fromRGB(72, 82, 108),
    rowBg    = Color3.fromRGB(15, 17, 25),
}
local FB = Enum.Font.GothamBold
local FM = Enum.Font.GothamMedium
local F  = Enum.Font.Gotham

local W     = 220
local H_HDR = 34
local PAD   = 6

-- ============================================
-- GUI
-- ============================================
local pg  = player:WaitForChild("PlayerGui")
do local a = pg:FindFirstChild("NightSkip_hud"); if a then a:Destroy() end end

local gui = Instance.new("ScreenGui")
gui.Name = "NightSkip_hud"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true; gui.Parent = pg

local frame = Instance.new("Frame")
frame.Name = "NSFrame"; frame.Size = UDim2.new(0, W, 0, H_HDR)
frame.Position = UDim2.new(0, 20, 0, 400)
frame.BackgroundColor3 = C.bg; frame.BorderSizePixel = 0; frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", frame).Color = C.border

local topLine = Instance.new("Frame")
topLine.Size = UDim2.new(1,0,0,2); topLine.BackgroundColor3 = C.blue
topLine.BorderSizePixel = 0; topLine.ZIndex = 6; topLine.Parent = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0,4)

local header = Instance.new("Frame")
header.Size = UDim2.new(1,0,0,H_HDR); header.BackgroundColor3 = C.header
header.BorderSizePixel = 0; header.ZIndex = 4; header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0,6)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1,-80,1,0); titleLbl.Position = UDim2.new(0,10,0,0)
titleLbl.Text = "🌙 PULAR NOITE"; titleLbl.TextColor3 = C.red
titleLbl.Font = FB; titleLbl.TextSize = 12; titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.ZIndex = 5; titleLbl.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0,22,0,22); minBtn.Position = UDim2.new(1,-48,0.5,-11)
minBtn.Text = "—"; minBtn.BackgroundColor3 = Color3.fromRGB(22,25,35); minBtn.TextColor3 = C.muted
minBtn.Font = FB; minBtn.TextSize = 11; minBtn.BorderSizePixel = 0; minBtn.ZIndex = 5; minBtn.Parent = header
Instance.new("UIStroke", minBtn).Color = C.border; Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,4)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0,22,0,22); closeBtn.Position = UDim2.new(1,-22,0.5,-11)
closeBtn.Text = "✕"; closeBtn.BackgroundColor3 = C.redDim; closeBtn.TextColor3 = C.red
closeBtn.Font = FB; closeBtn.TextSize = 11; closeBtn.BorderSizePixel = 0; closeBtn.ZIndex = 5; closeBtn.Parent = header
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(100,20,35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,4)

-- ============================================
-- CONTEÚDO
-- ============================================
local CONTENT_H = 118

local content = Instance.new("Frame")
content.Size = UDim2.new(1,0,0,CONTENT_H); content.Position = UDim2.new(0,0,0,H_HDR)
content.BackgroundTransparency = 1; content.ZIndex = 3; content.Parent = frame

frame.Size = UDim2.new(0,W,0,H_HDR + CONTENT_H)

-- Status
local statusBg = Instance.new("Frame")
statusBg.Size = UDim2.new(1,-PAD*2,0,20); statusBg.Position = UDim2.new(0,PAD,0,PAD)
statusBg.BackgroundColor3 = Color3.fromRGB(8,10,18); statusBg.BorderSizePixel = 0
statusBg.ZIndex = 4; statusBg.Parent = content
Instance.new("UICorner", statusBg).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", statusBg).Color = C.border

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1,-10,1,0); statusLbl.Position = UDim2.new(0,6,0,0)
statusLbl.Text = "// DESATIVADO"; statusLbl.TextColor3 = C.muted
statusLbl.Font = FM; statusLbl.TextSize = 10; statusLbl.BackgroundTransparency = 1
statusLbl.TextXAlignment = Enum.TextXAlignment.Left; statusLbl.ZIndex = 5; statusLbl.Parent = statusBg

-- Máquina status
local maqBg = Instance.new("Frame")
maqBg.Size = UDim2.new(1,-PAD*2,0,28); maqBg.Position = UDim2.new(0,PAD,0,PAD+22)
maqBg.BackgroundColor3 = C.rowBg; maqBg.BorderSizePixel = 0; maqBg.ZIndex = 4; maqBg.Parent = content
Instance.new("UICorner", maqBg).CornerRadius = UDim.new(0,5)
Instance.new("UIStroke", maqBg).Color = C.border

local maqIconLbl = Instance.new("TextLabel")
maqIconLbl.Size = UDim2.new(0,20,1,0); maqIconLbl.Position = UDim2.new(0,6,0,0)
maqIconLbl.Text = "⚙"; maqIconLbl.TextColor3 = C.muted; maqIconLbl.Font = FB; maqIconLbl.TextSize = 14
maqIconLbl.BackgroundTransparency = 1; maqIconLbl.ZIndex = 5; maqIconLbl.Parent = maqBg

local maqLbl = Instance.new("TextLabel")
maqLbl.Size = UDim2.new(1,-28,1,0); maqLbl.Position = UDim2.new(0,26,0,0)
maqLbl.Text = "Temporal Accelerometer — procurando..."
maqLbl.TextColor3 = C.muted; maqLbl.Font = FM; maqLbl.TextSize = 10
maqLbl.BackgroundTransparency = 1; maqLbl.TextXAlignment = Enum.TextXAlignment.Left
maqLbl.TextTruncate = Enum.TextTruncate.AtEnd; maqLbl.ZIndex = 5; maqLbl.Parent = maqBg

-- Contador
local countBg = Instance.new("Frame")
countBg.Size = UDim2.new(1,-PAD*2,0,22); countBg.Position = UDim2.new(0,PAD,0,PAD+22+30)
countBg.BackgroundTransparency = 1; countBg.ZIndex = 4; countBg.Parent = content

local countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(0.5,0,1,0); countLbl.Position = UDim2.new(0,0,0,0)
countLbl.Text = "Disparos: 0"; countLbl.TextColor3 = C.muted; countLbl.Font = FM; countLbl.TextSize = 10
countLbl.BackgroundTransparency = 1; countLbl.TextXAlignment = Enum.TextXAlignment.Left
countLbl.ZIndex = 5; countLbl.Parent = countBg

local timerLbl = Instance.new("TextLabel")
timerLbl.Size = UDim2.new(0.5,0,1,0); timerLbl.Position = UDim2.new(0.5,0,0,0)
timerLbl.Text = "Próximo: --"; timerLbl.TextColor3 = C.muted; timerLbl.Font = FM; timerLbl.TextSize = 10
timerLbl.BackgroundTransparency = 1; timerLbl.TextXAlignment = Enum.TextXAlignment.Right
timerLbl.ZIndex = 5; timerLbl.Parent = countBg

-- Botão toggle
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1,-PAD*2,0,30); toggleBtn.Position = UDim2.new(0,PAD,0,PAD+22+30+24)
toggleBtn.Text = "🌙  ATIVAR AUTO SKIP"
toggleBtn.BackgroundColor3 = C.blueDim; toggleBtn.TextColor3 = C.blue
toggleBtn.Font = FB; toggleBtn.TextSize = 11; toggleBtn.BorderSizePixel = 0
toggleBtn.ZIndex = 4; toggleBtn.Parent = content
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,5)
Instance.new("UIStroke", toggleBtn).Color = Color3.fromRGB(30,70,160)

-- ============================================
-- TIMER VISUAL
-- ============================================
local tempoRestante  = INTERVALO
local timerConn      = nil
local ativo          = false

local function atualizarMaqStatus()
    local maq = getMaquina()
    if not maq then
        maqLbl.Text = "Temporal Accelerometer — não encontrada"
        maqLbl.TextColor3 = C.red
        maqIconLbl.TextColor3 = C.red
        return false
    end
    local charged  = maq:GetAttribute("Charged")
    local notClick = maq:GetAttribute("NotClickable")
    if charged == true or notClick == false then
        maqLbl.Text = "Temporal Accelerometer — ✓ CARREGADA"
        maqLbl.TextColor3 = C.green
        maqIconLbl.TextColor3 = C.green
    else
        -- Mostra estado mas dispara de qualquer forma
        maqLbl.Text = "Temporal Accelerometer — Charged="..tostring(charged)
        maqLbl.TextColor3 = C.yellow
        maqIconLbl.TextColor3 = C.yellow
    end
    return true  -- sempre retorna true se máquina existe
end

local function pararLoop()
    ativo = false
    titleLbl.TextColor3 = C.red
    if loopThread then task.cancel(loopThread); loopThread = nil end
    if timerConn  then timerConn:Disconnect(); timerConn = nil end
    statusLbl.Text = "// DESATIVADO"; statusLbl.TextColor3 = C.muted
    timerLbl.Text  = "Próximo: --"; timerLbl.TextColor3 = C.muted
    toggleBtn.Text = "🌙  ATIVAR AUTO SKIP"
    toggleBtn.BackgroundColor3 = C.blueDim; toggleBtn.TextColor3 = C.blue
end

local function iniciarLoop()
    ativo = true
    titleLbl.TextColor3 = C.green
    statusLbl.Text = "// ATIVO — verificando a cada "..INTERVALO.."s"
    statusLbl.TextColor3 = C.green
    toggleBtn.Text = "⬛  DESATIVAR"
    toggleBtn.BackgroundColor3 = Color3.fromRGB(14,35,14); toggleBtn.TextColor3 = C.green

    -- Contador regressivo visual
    tempoRestante = 0  -- dispara imediatamente na primeira vez
    timerConn = RS.Heartbeat:Connect(function(dt)
        if not ativo then return end
        tempoRestante = tempoRestante - dt
        if tempoRestante > 0 then
            timerLbl.Text = string.format("Próximo: %.0fs", tempoRestante)
            timerLbl.TextColor3 = C.muted
        else
            timerLbl.Text = "Verificando..."
            timerLbl.TextColor3 = C.yellow
        end
    end)

    loopThread = task.spawn(function()
        while ativo do
            task.wait(math.max(tempoRestante, 0))
            if not ativo then break end

            -- Atualiza status da máquina
            local pronta = atualizarMaqStatus()
            local maq = getMaquina()

            if pronta and maq then
                -- Dispara!
                dispararMaquina(maq)
                totalFires = totalFires + 1
                ultimoFire = os.time()
                countLbl.Text = "Disparos: " .. totalFires
                statusLbl.Text = "// DISPARADO às " .. os.date("%H:%M:%S")
                statusLbl.TextColor3 = C.green
                TS:Create(frame, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(10,30,10)}):Play()
                task.delay(0.5, function()
                    TS:Create(frame, TweenInfo.new(0.3), {BackgroundColor3 = C.bg}):Play()
                end)
            else
                statusLbl.Text = "// aguardando carga... próx em "..INTERVALO.."s"
                statusLbl.TextColor3 = C.muted
            end

            tempoRestante = INTERVALO
        end
    end)
end

-- ============================================
-- TOGGLE
-- ============================================
toggleBtn.MouseButton1Click:Connect(function()
    if ativo then pararLoop() else iniciarLoop() end
end)

-- Monitora mudança do atributo Charged em tempo real
task.spawn(function()
    while gui.Parent do
        task.wait(2)
        if not ativo then atualizarMaqStatus() end
    end
end)

-- ============================================
-- DRAG + PERSISTÊNCIA DE POSIÇÃO
-- ============================================
local HS = game:GetService("HttpService")
local POS_KEY_NS = "nightskip_pos.json"
local function salvarPosNS()
    if writefile then
        local __ok, __e = pcall(writefile, POS_KEY_NS, HS:JSONEncode({
            x = frame.Position.X.Offset, y = frame.Position.Y.Offset
        }))
        if not __ok then warn("salvarPosNS erro:", __e) end
    end
end
local function carregarPosNS()
    if isfile and readfile and isfile(POS_KEY_NS) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY_NS)) end)
        if ok and d then frame.Position = UDim2.new(0, d.x, 0, d.y) end
    end
end
carregarPosNS()

local dragInput, dragStartPos, dragStartMouse
header.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    dragInput = i; dragStartPos = frame.Position; dragStartMouse = i.Position
end)
UIS.InputChanged:Connect(function(i)
    if dragInput and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStartMouse
        frame.Position = UDim2.new(dragStartPos.X.Scale, dragStartPos.X.Offset + d.X,
                                   dragStartPos.Y.Scale, dragStartPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i == dragInput then dragInput = nil; salvarPosNS() end
end)

-- ============================================
-- MINIMIZAR
-- ============================================
local minimizado = false
local hCache = nil
minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    salvarPosNS()
    if minimizado then
        hCache = frame.Size.Y.Offset
        TS:Create(frame, TweenInfo.new(0.18), {Size = UDim2.new(0,W,0,H_HDR)}):Play()
        content.Visible = false; minBtn.Text = "▲"
    else
        content.Visible = true
        TS:Create(frame, TweenInfo.new(0.18), {Size = UDim2.new(0,W,0,hCache or H_HDR+CONTENT_H)}):Play()
        minBtn.Text = "—"
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    salvarPosNS()
    pararLoop()
    gui.Enabled = false
    if _G.Hub then pcall(function() _G.Hub.desligar("Night Skip") end) end
end)

-- ============================================
-- HUB
-- ============================================
local function onToggle(hubAtivo)
    if not hubAtivo then pararLoop() end
    if gui and gui.Parent then gui.Enabled = hubAtivo end
end

if _G.Hub then
    _G.Hub.registrar("Night Skip", onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {nome = "Night Skip", toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = true})
end

-- ============================================
-- INIT
-- ============================================
atualizarMaqStatus()minimizado = true
hCache = H_HDR + CONTENT_H
frame.Size = UDim2.new(0, W, 0, H_HDR)
content.Visible = false
minBtn.Text = "▲"
-- Inicia ativo
iniciarLoop()
print(">>> NIGHT SKIP ATIVO")
