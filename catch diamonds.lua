-- ============================================
-- DIAMOND SNIPER (SÓ OS 5 ITENS REAIS)
-- ============================================

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local player = Players.LocalPlayer
local Remote = RS.RemoteEvents.RequestTakeDiamonds

local rodando = true

-- INTERFACE
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DiamondSniperHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 200, 0, 100)
mainFrame.Position = UDim2.new(0, 490, 1, -1075)
mainFrame.BackgroundColor3 = Color3.fromRGB(10, 40, 50)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 50)
statusLabel.Text = "Aguardando..."
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.BackgroundTransparency = 1
statusLabel.Parent = mainFrame

local btnSnipe = Instance.new("TextButton")
btnSnipe.Size = UDim2.new(0, 160, 0, 30)
btnSnipe.Position = UDim2.new(0.5, -80, 0, 55)
btnSnipe.Text = "PEGAR OS DIAMANTES"
btnSnipe.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
btnSnipe.TextColor3 = Color3.new(1, 1, 1)
btnSnipe.Parent = mainFrame
Instance.new("UICorner", btnSnipe)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -25, 0, 5)
closeBtn.Text = "X"
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Parent = mainFrame
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)

-- ============================================
-- LÓGICA DE PRECISÃO
-- ============================================
local function coletarDiamantesReais()
    local encontrados = 0
    
    -- Varre a pasta de Itens que apareceu no seu scan
    local pastaItems = workspace:FindFirstChild("Items")
    
    if pastaItems then
        for _, item in ipairs(pastaItems:GetChildren()) do
            -- Filtra APENAS pelo nome exato "Diamond"
            if item.Name == "Diamond" and item:IsA("Model") then
                encontrados = encontrados + 1
                statusLabel.Text = "Coletando " .. encontrados .. "/5..."
                
                -- Tenta coletar via Remote
                pcall(function()
                    Remote:FireServer(item)
                end)
                
                -- Pequena pausa para o servidor não bloquear por spam
                task.wait(0.1)
            end
        end
    end

    if encontrados == 0 then
        statusLabel.Text = "Nenhum 'Diamond' encontrado na pasta Items."
    else
        statusLabel.Text = "Tentativa finalizada!\nAchados: " .. encontrados
    end
end

btnSnipe.MouseButton1Click:Connect(coletarDiamantesReais)

closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
    rodando = false
end)
