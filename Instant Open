-- ============================================
-- INSTANT PROMPT
-- ============================================

local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local HS = game:GetService('HttpService')
local player = Players.LocalPlayer

-- CONFIG / PERSISTÊNCIA
local CONFIG_PATH = "instant_prompt_config.json"
local configPadrao = { posX = 10, posY = -140 }

local function salvarConfig(cfg)
    if writefile then pcall(writefile, CONFIG_PATH, HS:JSONEncode(cfg)) end
end

local function carregarConfig()
    if isfile and readfile and isfile(CONFIG_PATH) then
        local ok, dados = pcall(function() return HS:JSONDecode(readfile(CONFIG_PATH)) end)
        if ok and dados then return dados end
    end
    return configPadrao
end

local cfg = carregarConfig()
local ativo = false
local minimizado = false

-- GUI
local gui = Instance.new("ScreenGui")
gui.Name = "InstantPromptUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 190, 0, 70)
frame.Position = UDim2.new(0, cfg.posX or 10, 1, cfg.posY or -140)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", frame).Color = Color3.fromRGB(55, 55, 55)

-- Título
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 28)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -52, 1, 0)
titleLabel.Position = UDim2.new(0, 8, 0, 0)
titleLabel.Text = "⚡ INSTANT PROMPT"
titleLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 11
titleLabel.BackgroundTransparency = 1
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 18, 0, 18)
minBtn.Position = UDim2.new(1, -42, 0.5, -9)
minBtn.Text = "—"
minBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
minBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 10
minBtn.BorderSizePixel = 0
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(1, 0)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 18, 0, 18)
closeBtn.Position = UDim2.new(1, -20, 0.5, -9)
closeBtn.Text = "✕"
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 10
closeBtn.BorderSizePixel = 0
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)

-- Botão toggle
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -16, 0, 28)
toggleBtn.Position = UDim2.new(0, 8, 0, 33)
toggleBtn.Text = "ATIVAR"
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 11
toggleBtn.BorderSizePixel = 0
toggleBtn.Parent = frame
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)

-- LÓGICA
local function zerarPrompts()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.HoldDuration > 0 then
            obj.HoldDuration = 0
        end
    end
end

local function toggle()
    ativo = not ativo
    if ativo then
        zerarPrompts()
        toggleBtn.Text = "DESATIVAR"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        titleLabel.TextColor3 = Color3.fromRGB(80, 255, 120)
    else
        toggleBtn.Text = "ATIVAR"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
        titleLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
    end
end

local function toggleMinimizar()
    minimizado = not minimizado
    if minimizado then
        frame.Size = UDim2.new(0, 190, 0, 28)
        toggleBtn.Visible = false
        minBtn.Text = "▲"
    else
        frame.Size = UDim2.new(0, 190, 0, 70)
        toggleBtn.Visible = true
        minBtn.Text = "—"
    end
end

-- DRAG
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
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
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

-- EVENTOS
toggleBtn.MouseButton1Click:Connect(toggle)
minBtn.MouseButton1Click:Connect(toggleMinimizar)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)
