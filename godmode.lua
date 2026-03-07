-- ============================================
-- GOD MODE - COM INTERFACE
-- ============================================

local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local HS = game:GetService('HttpService')
local player = Players.LocalPlayer or Players:GetPropertyChangedSignal('LocalPlayer'):Wait()

-- ============================================
-- CONFIG / PERSISTÊNCIA
-- ============================================
local CONFIG_PATH = "god_mode_config.json"

local configPadrao = { posX = 10, posY = 10 }

local function salvarConfig(cfg)
    if writefile then
        pcall(writefile, CONFIG_PATH, HS:JSONEncode(cfg))
    end
end

local function carregarConfig()
    if isfile and readfile and isfile(CONFIG_PATH) then
        local ok, dados = pcall(function()
            return HS:JSONDecode(readfile(CONFIG_PATH))
        end)
        if ok and dados then return dados end
    end
    return configPadrao
end

local cfg = carregarConfig()

-- ============================================
-- ESTADO
-- ============================================
local godAtivado = false
local auraAtivada = false
local minimizado = false
local godConexao = nil

-- ============================================
-- GUI
-- ============================================
local gui = Instance.new("ScreenGui")
gui.Name = "GodModeUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- Frame principal
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 200, 0, 160)
frame.Position = UDim2.new(0, cfg.posX or 10, 0, cfg.posY or 10)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(55, 55, 55)
stroke.Thickness = 1

-- Barra de título (drag handle)
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -60, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.Text = "⚔ GOD MODE"
titleLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 11
titleLabel.BackgroundTransparency = 1
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- Botão minimizar
local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 20)
minBtn.Position = UDim2.new(1, -46, 0.5, -10)
minBtn.Text = "—"
minBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
minBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 11
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(1, 0)

-- Botão fechar
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -22, 0.5, -10)
closeBtn.Text = "✕"
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 10
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)

-- Container do conteúdo (escondido ao minimizar)
local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 1, -30)
content.Position = UDim2.new(0, 0, 0, 30)
content.BackgroundTransparency = 1
content.Parent = frame

-- Helper: cria um botão de toggle
local function criarBotao(texto, posY)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 34)
    btn.Position = UDim2.new(0, 8, 0, posY)
    btn.Text = texto
    btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    btn.TextColor3 = Color3.fromRGB(180, 180, 180)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Parent = content
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local bstroke = Instance.new("UIStroke", btn)
    bstroke.Color = Color3.fromRGB(55, 55, 55)
    bstroke.Thickness = 1
    return btn, bstroke
end

local godBtn, godStroke = criarBotao("⚔  GOD MODE: OFF", 8)
local auraBtn, auraStroke = criarBotao("✦  AURA: OFF", 52)

-- ============================================
-- ATUALIZAR VISUAL DOS BOTÕES
-- ============================================
local function atualizarBotaoGod()
    if godAtivado then
        godBtn.Text = "⚔  GOD MODE: ON"
        godBtn.BackgroundColor3 = Color3.fromRGB(30, 100, 50)
        godBtn.TextColor3 = Color3.fromRGB(100, 255, 140)
        godStroke.Color = Color3.fromRGB(50, 160, 80)
    else
        godBtn.Text = "⚔  GOD MODE: OFF"
        godBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        godBtn.TextColor3 = Color3.fromRGB(180, 180, 180)
        godStroke.Color = Color3.fromRGB(55, 55, 55)
    end
end

local function atualizarBotaoAura()
    if auraAtivada then
        auraBtn.Text = "✦  AURA: ON"
        auraBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 120)
        auraBtn.TextColor3 = Color3.fromRGB(100, 180, 255)
        auraStroke.Color = Color3.fromRGB(60, 120, 220)
    else
        auraBtn.Text = "✦  AURA: OFF"
        auraBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        auraBtn.TextColor3 = Color3.fromRGB(180, 180, 180)
        auraStroke.Color = Color3.fromRGB(55, 55, 55)
    end
end

-- ============================================
-- LÓGICA GOD MODE
-- ============================================
local function limparEfeitos()
    local char = player.Character
    if not char then return end
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA('ForceField') then v:Destroy() end
    end
end

local function aplicarAura()
    limparEfeitos()
    if not auraAtivada then return end
    local char = player.Character
    if not char then return end
    local ff = Instance.new('ForceField')
    ff.Visible = true
    ff.Parent = char
end

local function aplicarGod()
    if godConexao then godConexao:Disconnect(); godConexao = nil end
    if not godAtivado then return end

    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild('Humanoid')
    if not hum then return end

    godConexao = hum.Changed:Connect(function(prop)
        if prop == 'Health' and hum.Health < hum.MaxHealth then
            hum.Health = hum.MaxHealth
            pcall(function()
                game.ReplicatedStorage.RemoteEvents.DamagePlayer:FireServer(-hum.MaxHealth)
            end)
        end
    end)
end

local function toggleGod()
    godAtivado = not godAtivado
    aplicarGod()
    atualizarBotaoGod()
end

local function toggleAura()
    auraAtivada = not auraAtivada
    aplicarAura()
    atualizarBotaoAura()
end

-- Reaplicar ao renascer
player.CharacterAdded:Connect(function()
    task.wait(0.3)
    if godAtivado then aplicarGod() end
    if auraAtivada then aplicarAura() end
end)

-- ============================================
-- MINIMIZAR
-- ============================================
local function toggleMinimizar()
    minimizado = not minimizado
    if minimizado then
        frame.Size = UDim2.new(0, 200, 0, 30)
        content.Visible = false
        minBtn.Text = "▲"
    else
        frame.Size = UDim2.new(0, 200, 0, 160)
        content.Visible = true
        minBtn.Text = "—"
    end
end

-- ============================================
-- DRAG
-- ============================================
local dragging, dragStart, startPos

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if dragging then
            cfg.posX = frame.Position.X.Offset
            cfg.posY = frame.Position.Y.Offset
            salvarConfig(cfg)
        end
        dragging = false
    end
end)

-- ============================================
-- EVENTOS
-- ============================================
godBtn.MouseButton1Click:Connect(toggleGod)
auraBtn.MouseButton1Click:Connect(toggleAura)
minBtn.MouseButton1Click:Connect(toggleMinimizar)

closeBtn.MouseButton1Click:Connect(function()
    godAtivado = false
    auraAtivada = false
    limparEfeitos()
    if godConexao then godConexao:Disconnect() end
    gui:Destroy()
end)

-- Início
task.spawn(function()
    local _ = player.Character or player.CharacterAdded:Wait()
    task.wait(0.3)
    atualizarBotaoGod()
    atualizarBotaoAura()
end)
