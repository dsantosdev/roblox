-- ============================================
-- DIAMOND
-- ============================================

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local UIS = game:GetService('UserInputService')
local HS = game:GetService('HttpService')
local player = Players.LocalPlayer
local Remote = RS.RemoteEvents.RequestTakeDiamonds

-- ============================================
-- CONFIG / PERSISTÊNCIA
-- ============================================
local CONFIG_PATH = "diamond_config.json"
local configPadrao = { posX = 10, posY = -120 }

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
-- GUI
-- ============================================
local gui = Instance.new("ScreenGui")
gui.Name = "DiamondUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 180, 0, 90)
frame.Position = UDim2.new(0, cfg.posX or 10, 1, cfg.posY or -120)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(55, 55, 55)
stroke.Thickness = 1

-- Título / drag
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 28)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -30, 1, 0)
titleLabel.Position = UDim2.new(0, 8, 0, 0)
titleLabel.Text = "◆ DIAMOND"
titleLabel.TextColor3 = Color3.fromRGB(80, 200, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 11
titleLabel.BackgroundTransparency = 1
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 18, 0, 18)
closeBtn.Position = UDim2.new(1, -22, 0.5, -9)
closeBtn.Text = "✕"
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 10
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)

-- Status
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -16, 0, 22)
statusLabel.Position = UDim2.new(0, 8, 0, 32)
statusLabel.Text = "Aguardando..."
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 10
statusLabel.BackgroundTransparency = 1
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = frame

-- Botão coletar
local collectBtn = Instance.new("TextButton")
collectBtn.Size = UDim2.new(1, -16, 0, 24)
collectBtn.Position = UDim2.new(0, 8, 0, 58)
collectBtn.Text = "◆  COLETAR DIAMANTES"
collectBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 160)
collectBtn.TextColor3 = Color3.fromRGB(80, 200, 255)
collectBtn.Font = Enum.Font.GothamBold
collectBtn.TextSize = 10
collectBtn.Parent = frame
Instance.new("UICorner", collectBtn).CornerRadius = UDim.new(0, 6)
local btnStroke = Instance.new("UIStroke", collectBtn)
btnStroke.Color = Color3.fromRGB(0, 140, 200)
btnStroke.Thickness = 1

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
-- LÓGICA
-- ============================================
local function coletar()
    collectBtn.Active = false
    collectBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    collectBtn.TextColor3 = Color3.fromRGB(100, 100, 100)

    local encontrados = 0
    local pastaItems = workspace:FindFirstChild("Items")

    if pastaItems then
        for _, item in ipairs(pastaItems:GetChildren()) do
            if item.Name == "Diamond" and item:IsA("Model") then
                encontrados += 1
                statusLabel.Text = "Coletando " .. encontrados .. "..."
                pcall(function() Remote:FireServer(item) end)
                task.wait(0.1)
            end
        end
    end

    statusLabel.Text = encontrados == 0
        and "Nenhum diamante encontrado."
        or "Concluído! Achados: " .. encontrados

    task.wait(1.5)
    collectBtn.Active = true
    collectBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 160)
    collectBtn.TextColor3 = Color3.fromRGB(80, 200, 255)
    statusLabel.Text = "Aguardando..."
end

-- ============================================
-- EVENTOS
-- ============================================
collectBtn.MouseButton1Click:Connect(function()
    if collectBtn.Active ~= false then
        task.spawn(coletar)
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy()
end)
