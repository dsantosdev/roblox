-- ============================================
-- CHEST FARM FINAL (INFERIOR ESQUERDA + FECHAR)
-- ============================================

local RS = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local RE = RS.RemoteEvents
local player = Players.LocalPlayer

-- CONFIG
local INTERVALO = 8
local rodando = false
local totalAbertosGeral = 0
local conexaoTecla = nil

-- ============================================
-- CRIAÇÃO DA INTERFACE (GUI)
-- ============================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FarmMonitorFinal"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 180, 0, 90)
mainFrame.Position = UDim2.new(0, 10, 1, -100) -- Canto inferior esquerdo
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 6)

-- Botão de Fechar (X)
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -25, 0, 5)
closeBtn.Text = "X"
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = mainFrame
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)

-- Status e Contador
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -10, 0, 30)
statusLabel.Position = UDim2.new(0, 10, 0, 20)
statusLabel.Text = "STATUS: OFF"
statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.BackgroundTransparency = 1
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = mainFrame

local countLabel = Instance.new("TextLabel")
countLabel.Size = UDim2.new(1, -10, 0, 30)
countLabel.Position = UDim2.new(0, 10, 0, 45)
countLabel.Text = "ABERTOS: 0"
countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
countLabel.Font = Enum.Font.Gotham
countLabel.BackgroundTransparency = 1
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = mainFrame

-- ============================================
-- FUNÇÃO DE DESCARREGAR (UNLOAD)
-- ============================================
local function descarregar()
    rodando = false
    if conexaoTecla then conexaoTecla:Disconnect() end
    screenGui:Destroy()
    warn(">>> SCRIPT DESCARREGADO")
end

closeBtn.MouseButton1Click:Connect(descarregar)

-- ============================================
-- LÓGICA DO FARM
-- ============================================
local function farmar()
    local baus = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA('ProximityPrompt') then
            local bisavo = obj.Parent and obj.Parent.Parent and obj.Parent.Parent.Parent
            if bisavo and bisavo.Name and bisavo.Name:lower():find("chest") or bisavo and bisavo.Name:lower():find("bau") then
                table.insert(baus, bisavo)
            end
        end
    end

    for _, model in ipairs(baus) do
        if not rodando then break end
        pcall(function()
            RE.RequestOpenItemChest:FireServer(model)
            totalAbertosGeral = totalAbertosGeral + 1
            countLabel.Text = "ABERTOS: " .. totalAbertosGeral
        end)
        task.wait(0.2)
    end
end

-- ============================================
-- CONTROLE
-- ============================================
conexaoTecla = UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.PageDown then
        rodando = not rodando
        if rodando then
            statusLabel.Text = "STATUS: ON"
            statusLabel.TextColor3 = Color3.fromRGB(80, 255, 80)
            task.spawn(function()
                while rodando do
                    farmar()
                    task.wait(INTERVALO)
                end
            end)
        else
            statusLabel.Text = "STATUS: OFF"
            statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        end
    end
end)
