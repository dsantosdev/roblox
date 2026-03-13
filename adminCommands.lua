print('[KAH][LOAD] adminCommands.lua')
-- ============================================
-- MÓDULO: CHAT MONITOR
-- Monitora o chat e ativa funções via comandos
-- Integrado ao sistema Hub/HubFila
-- ============================================
local VERSION      = "1.0.0"
local CATEGORIA    = "Utility"
local MODULE_NAME  = "Chat Monitor"

-- Não executa sem o hub
if not _G.Hub and not _G.HubFila then
    print(">>> ChatMonitor: hub não encontrado, abortando")
    return
end

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TS           = game:GetService("TweenService")
local HS           = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local player       = Players.LocalPlayer

-- ============================================
-- CONFIGURAÇÃO DE COMANDOS
-- Adicione seus comandos aqui.
-- trigger: texto que ativa o comando (case-insensitive)
-- action:  função chamada quando o trigger é detectado
-- quem:    "qualquer" | "eu" | "outros" — quem pode ativar
-- ============================================
local COMANDOS = {
    {
        trigger = "!hello",
        quem    = "qualquer",
        action  = function(remetente, mensagem)
            print(">>> ChatMonitor: HELLO detectado de " .. remetente)
            -- Exemplo: exibir notificação na tela
            -- Substitua pelo que quiser fazer aqui
        end,
    },
    {
        trigger = "!tp",
        quem    = "eu",         -- só ativa quando EU escrever
        action  = function(remetente, mensagem)
            -- Exemplo: extrair argumento após o trigger
            local alvo = mensagem:match("!tp%s+(%S+)")
            if alvo then
                print(">>> ChatMonitor: Teleporte para " .. alvo)
                -- Coloque sua lógica de teleporte aqui
            end
        end,
    },
    {
        trigger = "!speed",
        quem    = "eu",
        action  = function(remetente, mensagem)
            local val = mensagem:match("!speed%s+(%d+)")
            local speed = tonumber(val) or 16
            local char  = player.Character
            local hum   = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = math.clamp(speed, 0, 500)
                print(">>> ChatMonitor: Speed definida para " .. hum.WalkSpeed)
            end
        end,
    },
    {
        trigger = "!jump",
        quem    = "eu",
        action  = function(remetente, mensagem)
            local val = mensagem:match("!jump%s+(%d+)")
            local power = tonumber(val) or 50
            local char  = player.Character
            local hum   = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.JumpPower = math.clamp(power, 0, 1000)
                print(">>> ChatMonitor: JumpPower definida para " .. hum.JumpPower)
            end
        end,
    },
    {
        trigger = "!reset",
        quem    = "eu",
        action  = function(remetente, mensagem)
            local char = player.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if hum then hum.Health = 0 end
        end,
    },
    -- ----------------------------------------
    -- ADICIONE SEUS PRÓPRIOS COMANDOS ABAIXO:
    -- {
    --     trigger = "!meucomando",
    --     quem    = "eu",             -- "eu" | "outros" | "qualquer"
    --     action  = function(remetente, mensagem)
    --         -- sua lógica aqui
    --     end,
    -- },
    -- ----------------------------------------
}

-- ============================================
-- ESTADO INTERNO
-- ============================================
local monitorAtivo   = false
local chatConn       = nil
local logMsgs        = {}   -- histórico exibido na janela
local MAX_LOG        = 30   -- máximo de linhas no log
local logRows        = {}   -- labels da UI

-- ============================================
-- CORES
-- ============================================
local C = {
    bg        = Color3.fromRGB(10, 11, 15),
    header    = Color3.fromRGB(12, 14, 20),
    border    = Color3.fromRGB(28, 32, 48),
    accent    = Color3.fromRGB(0, 220, 255),
    green     = Color3.fromRGB(50, 220, 100),
    greenDim  = Color3.fromRGB(15, 55, 25),
    red       = Color3.fromRGB(220, 50, 70),
    redDim    = Color3.fromRGB(55, 12, 18),
    yellow    = Color3.fromRGB(255, 210, 50),
    yellowDim = Color3.fromRGB(50, 40, 5),
    text      = Color3.fromRGB(180, 190, 210),
    muted     = Color3.fromRGB(100, 110, 135),
    rowBg     = Color3.fromRGB(18, 20, 28),
    panel     = Color3.fromRGB(15, 17, 23),
}

-- ============================================
-- LAYOUT
-- ============================================
local W        = 260
local H_HDR    = 34
local H_STATUS = 22
local H_LOG    = 180
local H_TOGGLE = 34
local PAD      = 6
local H_FULL   = H_HDR + H_STATUS + H_TOGGLE + H_LOG + PAD * 3

local function getMinimizedWidth()
    if _G.KAHUiDefaults and _G.KAHUiDefaults.getMinWidth then
        local ok, v = pcall(_G.KAHUiDefaults.getMinWidth)
        if ok and tonumber(v) then return math.clamp(math.floor(tonumber(v)), 220, 420) end
    end
    return 240
end

-- ============================================
-- GUI
-- ============================================
local pg  = player:WaitForChild("PlayerGui")
local ant = pg:FindFirstChild("ChatMonitor_hud")
if ant then ant:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name           = "ChatMonitor_hud"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = pg

local frame = Instance.new("Frame")
frame.Name             = "ChatMonFrame"
frame.Size             = UDim2.new(0, W, 0, H_HDR)
frame.Position         = UDim2.new(0, 280, 0, 20)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel  = 0
frame.ClipsDescendants = false
frame.Parent           = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color        = C.border

-- linha accent topo
local topLine = Instance.new("Frame")
topLine.Size             = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.yellow
topLine.BorderSizePixel  = 0
topLine.ZIndex           = 5
topLine.Parent           = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

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
titleLbl.Text               = "💬 CHAT MONITOR"
titleLbl.TextColor3         = C.yellow
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 11
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 4
titleLbl.Parent             = header

local minBtn = Instance.new("TextButton")
minBtn.Size             = UDim2.new(0, 20, 0, 20)
minBtn.Position         = UDim2.new(1, -44, 0.5, -10)
minBtn.Text             = "—"
minBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
minBtn.TextColor3       = C.muted
minBtn.Font             = Enum.Font.GothamBold
minBtn.TextSize         = 10
minBtn.BorderSizePixel  = 0
minBtn.ZIndex           = 4
minBtn.Parent           = header
Instance.new("UIStroke", minBtn).Color        = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 3)

local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0, 20, 0, 20)
closeBtn.Position         = UDim2.new(1, -20, 0.5, -10)
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
local statusBar = Instance.new("Frame")
statusBar.Size             = UDim2.new(1, 0, 0, H_STATUS)
statusBar.Position         = UDim2.new(0, 0, 0, H_HDR)
statusBar.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
statusBar.BorderSizePixel  = 0
statusBar.ZIndex           = 2
statusBar.Parent           = frame

local statusLbl = Instance.new("TextLabel")
statusLbl.Size               = UDim2.new(1, -16, 1, 0)
statusLbl.Position           = UDim2.new(0, 8, 0, 0)
statusLbl.Text               = "// MONITOR INATIVO"
statusLbl.TextColor3         = C.muted
statusLbl.Font               = Enum.Font.Code
statusLbl.TextSize           = 9
statusLbl.BackgroundTransparency = 1
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left
statusLbl.ZIndex             = 3
statusLbl.Parent             = statusBar

-- Toggle monitor (botão ON/OFF)
local Y_TOGGLE = H_HDR + H_STATUS + PAD

local toggleFrame = Instance.new("Frame")
toggleFrame.Size             = UDim2.new(1, -PAD * 2, 0, H_TOGGLE)
toggleFrame.Position         = UDim2.new(0, PAD, 0, Y_TOGGLE)
toggleFrame.BackgroundColor3 = C.rowBg
toggleFrame.BorderSizePixel  = 0
toggleFrame.ZIndex           = 3
toggleFrame.Parent           = frame
Instance.new("UICorner", toggleFrame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", toggleFrame).Color        = C.border

local toggleBar = Instance.new("Frame")
toggleBar.Size             = UDim2.new(0, 2, 1, -6)
toggleBar.Position         = UDim2.new(0, 0, 0, 3)
toggleBar.BackgroundColor3 = C.border
toggleBar.BorderSizePixel  = 0
toggleBar.ZIndex           = 4
toggleBar.Parent           = toggleFrame
Instance.new("UICorner", toggleBar).CornerRadius = UDim.new(0, 2)

local toggleLbl = Instance.new("TextLabel")
toggleLbl.Size               = UDim2.new(1, -60, 1, 0)
toggleLbl.Position           = UDim2.new(0, 12, 0, 0)
toggleLbl.Text               = "Monitor de Chat"
toggleLbl.TextColor3         = C.text
toggleLbl.Font               = Enum.Font.GothamBold
toggleLbl.TextSize           = 11
toggleLbl.BackgroundTransparency = 1
toggleLbl.TextXAlignment     = Enum.TextXAlignment.Left
toggleLbl.ZIndex             = 4
toggleLbl.Parent             = toggleFrame

local track = Instance.new("Frame")
track.Size             = UDim2.new(0, 34, 0, 16)
track.Position         = UDim2.new(1, -44, 0.5, -8)
track.BackgroundColor3 = Color3.fromRGB(25, 28, 40)
track.BorderSizePixel  = 0
track.ZIndex           = 5
track.Parent           = toggleFrame
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
local trackStroke = Instance.new("UIStroke", track)
trackStroke.Color = C.border

local knob = Instance.new("Frame")
knob.Size             = UDim2.new(0, 12, 0, 12)
knob.Position         = UDim2.new(0, 2, 0.5, -6)
knob.BackgroundColor3 = C.muted
knob.BorderSizePixel  = 0
knob.ZIndex           = 6
knob.Parent           = track
Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

-- Log de mensagens
local Y_LOG = Y_TOGGLE + H_TOGGLE + PAD

local logFrame = Instance.new("ScrollingFrame")
logFrame.Size                 = UDim2.new(1, -PAD * 2, 0, H_LOG)
logFrame.Position             = UDim2.new(0, PAD, 0, Y_LOG)
logFrame.BackgroundColor3     = Color3.fromRGB(8, 9, 13)
logFrame.BorderSizePixel      = 0
logFrame.ScrollBarThickness   = 3
logFrame.ScrollBarImageColor3 = C.yellow
logFrame.CanvasSize           = UDim2.new(0, 0, 0, 0)
logFrame.AutomaticCanvasSize  = Enum.AutomaticSize.Y
logFrame.ZIndex               = 3
logFrame.Parent               = frame
Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", logFrame).Color        = C.border

local listLayout = Instance.new("UIListLayout", logFrame)
listLayout.Padding   = UDim.new(0, 1)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- ============================================
-- FUNÇÕES DE LOG NA UI
-- ============================================
local function addLog(texto, cor)
    table.insert(logMsgs, { texto = texto, cor = cor or C.text })
    if #logMsgs > MAX_LOG then table.remove(logMsgs, 1) end

    -- cria ou reutiliza row
    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(1, -8, 0, 14)
    lbl.BackgroundTransparency = 1
    lbl.Text               = texto
    lbl.TextColor3         = cor or C.text
    lbl.Font               = Enum.Font.Code
    lbl.TextSize           = 9
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.TextWrapped        = true
    lbl.TextScaled         = false
    lbl.ZIndex             = 4
    lbl.LayoutOrder        = #logMsgs
    lbl.Parent             = logFrame

    -- scroll para o fim
    task.defer(function()
        logFrame.CanvasPosition = Vector2.new(0, math.huge)
    end)
end

local function clearLog()
    for _, c in ipairs(logFrame:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    logMsgs = {}
end

-- ============================================
-- LÓGICA DO MONITOR
-- ============================================
local function processarMensagem(remetente, mensagem)
    if not monitorAtivo then return end

    local msgLower = mensagem:lower()

    for _, cmd in ipairs(COMANDOS) do
        local triggerLower = cmd.trigger:lower()

        -- Verifica se começa com o trigger
        if msgLower:sub(1, #triggerLower) == triggerLower then

            -- Verifica quem pode ativar
            local autorizado = false
            if cmd.quem == "qualquer" then
                autorizado = true
            elseif cmd.quem == "eu" then
                autorizado = (remetente == player.Name or remetente == player.DisplayName)
            elseif cmd.quem == "outros" then
                autorizado = (remetente ~= player.Name and remetente ~= player.DisplayName)
            end

            if autorizado then
                -- Log visual
                local cor = (remetente == player.Name or remetente == player.DisplayName)
                    and C.yellow or C.green
                addLog("[CMD] " .. remetente .. ": " .. mensagem, cor)

                -- Executa a ação com proteção de erro
                local ok, err = pcall(cmd.action, remetente, mensagem)
                if not ok then
                    addLog("[ERRO] " .. tostring(err), C.red)
                    warn(">>> ChatMonitor: erro em '" .. cmd.trigger .. "': " .. tostring(err))
                end
            end
        end
    end
end

-- ============================================
-- CONECTAR AO CHAT
-- Tenta TextChatService primeiro (novo sistema),
-- depois fallback para Chat legado
-- ============================================
local function conectarChat()
    if chatConn then chatConn:Disconnect(); chatConn = nil end

    local ok = false

    -- TENTATIVA 1: TextChatService (Roblox novo)
    local succ = pcall(function()
        local channels = TextChatService:GetDescendants()
        for _, ch in ipairs(channels) do
            if ch:IsA("TextChannel") then
                chatConn = ch.MessageReceived:Connect(function(msg)
                    local origem = msg.TextSource
                    local nome   = origem and Players:GetPlayerByUserId(origem.UserId)
                    local nomeStr = nome and nome.Name or "?"
                    processarMensagem(nomeStr, msg.Text or "")
                end)
                ok = true
                break
            end
        end
        -- Aguarda canal aparecer se ainda não existir
        if not ok then
            TextChatService.DescendantAdded:Connect(function(d)
                if d:IsA("TextChannel") and not chatConn then
                    chatConn = d.MessageReceived:Connect(function(msg)
                        local origem = msg.TextSource
                        local nome   = origem and Players:GetPlayerByUserId(origem.UserId)
                        local nomeStr = nome and nome.Name or "?"
                        processarMensagem(nomeStr, msg.Text or "")
                    end)
                end
            end)
            ok = true
        end
    end)

    -- TENTATIVA 2: Chat legado (LocalScript via Chatted)
    if not succ or not ok then
        chatConn = player.Chatted:Connect(function(msg)
            processarMensagem(player.Name, msg)
        end)
        -- Também monitora outros jogadores (apenas se o servidor permitir)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player then
                p.Chatted:Connect(function(msg)
                    processarMensagem(p.Name, msg)
                end)
            end
        end
        Players.PlayerAdded:Connect(function(p)
            p.Chatted:Connect(function(msg)
                processarMensagem(p.Name, msg)
            end)
        end)
    end

    addLog("[INFO] Chat conectado! Aguardando comandos...", C.accent)
end

local function desconectarChat()
    if chatConn then
        chatConn:Disconnect()
        chatConn = nil
    end
    addLog("[INFO] Monitor desativado.", C.muted)
end

-- ============================================
-- TOGGLE VISUAL
-- ============================================
local function setVisualAtivo(ativo)
    if ativo then
        TS:Create(knob,        TweenInfo.new(0.15), { Position = UDim2.new(1, -14, 0.5, -6), BackgroundColor3 = C.yellow }):Play()
        TS:Create(track,       TweenInfo.new(0.15), { BackgroundColor3 = C.yellowDim }):Play()
        TS:Create(toggleBar,   TweenInfo.new(0.15), { BackgroundColor3 = C.yellow }):Play()
        TS:Create(toggleFrame, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(30, 25, 5) }):Play()
        TS:Create(toggleLbl,   TweenInfo.new(0.15), { TextColor3 = C.yellow }):Play()
        trackStroke.Color = Color3.fromRGB(120, 90, 10)
        statusLbl.Text      = "// MONITORANDO CHAT — " .. #COMANDOS .. " COMANDOS"
        statusLbl.TextColor3 = C.yellow
    else
        TS:Create(knob,        TweenInfo.new(0.15), { Position = UDim2.new(0, 2, 0.5, -6), BackgroundColor3 = C.muted }):Play()
        TS:Create(track,       TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(25, 28, 40) }):Play()
        TS:Create(toggleBar,   TweenInfo.new(0.15), { BackgroundColor3 = C.border }):Play()
        TS:Create(toggleFrame, TweenInfo.new(0.15), { BackgroundColor3 = C.rowBg }):Play()
        TS:Create(toggleLbl,   TweenInfo.new(0.15), { TextColor3 = C.text }):Play()
        trackStroke.Color    = C.border
        statusLbl.Text       = "// MONITOR INATIVO"
        statusLbl.TextColor3 = C.muted
    end
end

local function toggleMonitor()
    monitorAtivo = not monitorAtivo
    setVisualAtivo(monitorAtivo)
    if monitorAtivo then
        conectarChat()
    else
        desconectarChat()
    end
end

-- Botão transparente sobre o toggle row
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size               = UDim2.new(1, 0, 1, 0)
toggleBtn.BackgroundTransparency = 1
toggleBtn.Text               = ""
toggleBtn.ZIndex             = 7
toggleBtn.Parent             = toggleFrame
toggleBtn.MouseButton1Click:Connect(toggleMonitor)

-- ============================================
-- MINIMIZAR
-- ============================================
local minimizado = false
local hFullCache = H_FULL

local function setMinimizado(v)
    minimizado = v
    if minimizado then
        hFullCache = frame.Size.Y.Offset
        frame.Size         = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
        statusBar.Visible  = false
        toggleFrame.Visible = false
        logFrame.Visible   = false
        minBtn.Text        = "A"
    else
        statusBar.Visible   = true
        toggleFrame.Visible = true
        logFrame.Visible    = true
        TS:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, hFullCache)
        }):Play()
        minBtn.Text = "—"
    end
end

minBtn.MouseButton1Click:Connect(function()
    setMinimizado(not minimizado)
end)

closeBtn.MouseButton1Click:Connect(function()
    if monitorAtivo then desconectarChat() end
    gui.Enabled = false
    if _G.Hub then pcall(function() _G.Hub.desligar(MODULE_NAME) end) end
end)

-- ============================================
-- DRAG
-- ============================================
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
    local d  = i.Position - dragStart
    local vp = workspace.CurrentCamera.ViewportSize
    local nx = math.clamp(startPos.X.Offset + d.X, 4, vp.X - frame.Size.X.Offset - 4)
    local ny = math.clamp(startPos.Y.Offset + d.Y, 4, vp.Y - frame.Size.Y.Offset - 4)
    if _G.Snap then _G.Snap.mover(frame, nx, ny)
    else frame.Position = UDim2.new(0, nx, 0, ny) end
end)
UIS.InputEnded:Connect(function(i)
    if not dragging then return end
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        if _G.Snap then _G.Snap.soltar(frame) end
        dragging = false
    end
end)

-- ============================================
-- INTEGRAÇÃO COM SNAP
-- ============================================
if _G.Snap then
    _G.Snap.registrar(frame, function() end, function(targetW, mode)
        if mode == "minimize" then
            setMinimizado(true)
        else
            setMinimizado(false)
        end
    end)
end

-- ============================================
-- EXPANDIR JANELA PARA O TAMANHO COMPLETO
-- ============================================
frame.Size = UDim2.new(0, W, 0, H_FULL)

-- ============================================
-- REGISTRA NO HUB
-- ============================================
local booting = true

local function onToggle(ativo)
    if not ativo then
        if monitorAtivo then desconectarChat(); monitorAtivo = false end
        setVisualAtivo(false)
    end
    if gui and gui.Parent then gui.Enabled = ativo end
end

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome      = MODULE_NAME,
        toggleFn  = onToggle,
        categoria = CATEGORIA,
        jaAtivo   = true,
    })
end

booting = false
addLog("[INIT] Chat Monitor v" .. VERSION .. " pronto!", C.accent)
addLog("[INFO] " .. #COMANDOS .. " comandos registrados.", C.muted)
for i, cmd in ipairs(COMANDOS) do
    addLog("  [" .. i .. "] " .. cmd.trigger .. " (" .. cmd.quem .. ")", C.muted)
end

print(">>> CHAT MONITOR v" .. VERSION .. " ATIVO")