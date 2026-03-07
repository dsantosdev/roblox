-- ============================================
-- CHEST FARM - OTIMIZADO
-- ============================================

local RS = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local RE = RS.RemoteEvents
local player = Players.LocalPlayer

-- ============================================
-- CONFIG PADRÃO + PERSISTÊNCIA
-- ============================================
local CONFIG_PATH = "chest_farm_config.json"

local configPadrao = {
    posX = 10,
    posY = -110,
    intervalo = 8
}

local function salvarConfig(cfg)
    if writefile then
        pcall(writefile, CONFIG_PATH, game:GetService("HttpService"):JSONEncode(cfg))
    end
end

local function carregarConfig()
    if isfile and readfile and isfile(CONFIG_PATH) then
        local ok, dados = pcall(function()
            return game:GetService("HttpService"):JSONDecode(readfile(CONFIG_PATH))
        end)
        if ok and dados then return dados end
    end
    return configPadrao
end

local cfg = carregarConfig()

-- CONFIG
local INTERVALO = cfg.intervalo or configPadrao.intervalo
local rodando = false
local totalAbertos = 0
local loopThread = nil
local userId = tostring(player.UserId)

-- ============================================
-- GUI
-- ============================================
local gui = Instance.new("ScreenGui")
gui.Name = "ChestFarm"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 180, 0, 100)
frame.Position = UDim2.new(0, cfg.posX or configPadrao.posX, 1, cfg.posY or configPadrao.posY)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

-- Sombra
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(60, 60, 60)
stroke.Thickness = 1

-- Título + drag handle
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 28)
titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -52, 1, 0)
titleLabel.Position = UDim2.new(0, 8, 0, 0)
titleLabel.Text = "⬡ CHEST FARM"
titleLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 11
titleLabel.BackgroundTransparency = 1
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- Botão minimizar
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

-- Botão fechar
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

-- Status label
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -16, 0, 22)
statusLabel.Position = UDim2.new(0, 8, 0, 32)
statusLabel.Text = "● INATIVO"
statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 11
statusLabel.BackgroundTransparency = 1
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = frame

-- Contador
local countLabel = Instance.new("TextLabel")
countLabel.Size = UDim2.new(1, -16, 0, 18)
countLabel.Position = UDim2.new(0, 8, 0, 52)
countLabel.Text = "Abertos: 0"
countLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
countLabel.Font = Enum.Font.Gotham
countLabel.TextSize = 10
countLabel.BackgroundTransparency = 1
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = frame

-- Botão toggle
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -16, 0, 22)
toggleBtn.Position = UDim2.new(0, 8, 0, 72)
toggleBtn.Text = "INICIAR  [PgDown]"
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 10
toggleBtn.Parent = frame
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)

-- ============================================
-- DRAG (interface móvel)
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
            -- Salva a posição atual no arquivo de config
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
local minimizado = false

local function atualizarUI()
    if rodando then
        statusLabel.Text = "● ATIVO"
        statusLabel.TextColor3 = Color3.fromRGB(80, 255, 120)
        toggleBtn.Text = "PARAR"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        titleLabel.TextColor3 = Color3.fromRGB(80, 255, 120)
    else
        statusLabel.Text = "● INATIVO"
        statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        toggleBtn.Text = "INICIAR"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
        titleLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
    end
end

local function toggleMinimizar()
    minimizado = not minimizado
    if minimizado then
        frame.Size = UDim2.new(0, 180, 0, 28)
        statusLabel.Visible = false
        countLabel.Visible = false
        toggleBtn.Visible = false
        minBtn.Text = "▲"
    else
        frame.Size = UDim2.new(0, 180, 0, 100)
        statusLabel.Visible = true
        countLabel.Visible = true
        toggleBtn.Visible = true
        minBtn.Text = "—"
    end
end

local function farmar()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if not rodando then break end
        if obj:IsA("ProximityPrompt") then
            local model = obj.Parent and obj.Parent.Parent and obj.Parent.Parent.Parent
            if model and model.Name then
                local nome = model.Name:lower()
                if nome:find("chest") or nome:find("bau") then
                    -- Verifica se já foi aberto por este jogador
                    local jaAberto = model:GetAttribute("LocalOpened")
                                  or model:GetAttribute(userId .. "Opened")
                    if not jaAberto then
                        pcall(function()
                            RE.RequestOpenItemChest:FireServer(model)
                            totalAbertos += 1
                            countLabel.Text = "Abertos: " .. totalAbertos
                        end)
                        task.wait(0.2)
                    end
                end
            end
        end
    end
end

local function toggleFarm()
    rodando = not rodando
    atualizarUI()
    if rodando then
        loopThread = task.spawn(function()
            while rodando do
                farmar()
                task.wait(INTERVALO)
            end
        end)
    elseif loopThread then
        task.cancel(loopThread)
        loopThread = nil
    end
end

-- ============================================
-- EVENTOS
-- ============================================
toggleBtn.MouseButton1Click:Connect(toggleFarm)
minBtn.MouseButton1Click:Connect(toggleMinimizar)

closeBtn.MouseButton1Click:Connect(function()
    rodando = false
    if loopThread then task.cancel(loopThread) end
    gui:Destroy()
end)
