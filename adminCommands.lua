print('[KAH][LOAD] adminCommands.lua')
-- ============================================
-- MODULE: ADMIN COMMANDS
-- Spells via chat - executam no cliente local
-- de quem estiver rodando o script.
-- So aceita comandos de admins da lista ADMINS.
-- ============================================
local VERSION     = "1.0.0"
local CATEGORIA   = "Admin"
local MODULE_NAME = "Admin Commands"
local MODULE_STATE_KEY = "__kah_admin_commands_state"
local PANEL_TOGGLE_NAME = "Admin Panel"
local SELF_TOGGLE_NAME = "Execute on Self"
local PLAYER_FLING_ACCESS_STATE_KEY = "__player_actions_fling_access"

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
local panelAtivo = false
local apparateTarget = ""

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
local flyMobileGui = nil
local flyDownBtn   = nil
local flyDownHeld  = false
local jumpRequestConn = nil
local mobileJumpUntil = 0
local useTouchFlightControls = nil
local setMobileFlyControlsVisible = nil

local godAtivo     = false
local godConn      = nil

local noclipAtivo  = false
local noclipConn   = nil

local impedAtivo   = false
local bombardaAtivo = false
local bombardaThread = nil
local HIDE_TELEPORTERS_STATE_KEY = "__kah_hide_teleporters_state"
local teleportersHidden = false
local teleportersSaved = false
local teleporterData = {}
local BOMBARDA_INTERVAL = 0.22

do
    local persisted = rawget(_G, HIDE_TELEPORTERS_STATE_KEY)
    if type(persisted) == "table" then
        teleportersHidden = persisted.hidden == true
        teleportersSaved = persisted.saved == true
        teleporterData = type(persisted.data) == "table" and persisted.data or {}
    end
end

local function syncTeleporterState()
    _G[HIDE_TELEPORTERS_STATE_KEY] = {
        hidden = teleportersHidden,
        saved = teleportersSaved,
        data = teleporterData,
    }
end

-- ============================================
-- IMPLEMENTACOES
-- ============================================

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

-- BOMBARDA - lanca o personagem para longe
local function bombarda()
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

local function getHorizontalVelocity(part)
    local vel = part.AssemblyLinearVelocity
    return Vector3.new(vel.X, 0, vel.Z)
end

local function restoreHorizontalVelocity(part, horizontal)
    local vel = part.AssemblyLinearVelocity
    part.AssemblyLinearVelocity = Vector3.new(horizontal.X, vel.Y, horizontal.Z)
end

local function saveTeleporters()
    if teleportersSaved and #teleporterData > 0 then
        return true
    end
    teleporterData = {}
    for _, name in ipairs({ "Teleporter1", "Teleporter2", "Teleporter3" }) do
        local tp = workspace:FindFirstChild(name)
        if tp then
            local entry = {
                model = tp,
                parent = tp.Parent,
                parts = {},
                guis = {},
                prompts = {},
            }
            for _, obj in ipairs(tp:GetDescendants()) do
                if obj:IsA("BasePart") then
                    table.insert(entry.parts, {
                        obj = obj,
                        transparency = obj.Transparency,
                        canCollide = obj.CanCollide,
                    })
                elseif obj:IsA("BillboardGui") or obj:IsA("SurfaceGui") then
                    table.insert(entry.guis, {
                        obj = obj,
                        enabled = obj.Enabled,
                    })
                elseif obj:IsA("ProximityPrompt") then
                    table.insert(entry.prompts, {
                        obj = obj,
                        enabled = obj.Enabled,
                        maxActivationDistance = obj.MaxActivationDistance,
                    })
                end
            end
            table.insert(teleporterData, entry)
        end
    end
    teleportersSaved = #teleporterData > 0
    syncTeleporterState()
    return teleportersSaved
end

local function setTeleportersHidden(hidden)
    if hidden then
        if teleportersHidden then return true end
        if not teleportersSaved and not saveTeleporters() then
            return false, "Teleporters nao encontrados"
        end
        for _, data in ipairs(teleporterData) do
            if data.model then
                for _, partData in ipairs(data.parts) do
                    if partData.obj then
                        partData.obj.Transparency = 1
                        partData.obj.CanCollide = false
                    end
                end
                for _, guiData in ipairs(data.guis) do
                    if guiData.obj then
                        guiData.obj.Enabled = false
                    end
                end
                for _, promptData in ipairs(data.prompts) do
                    if promptData.obj then
                        promptData.obj.Enabled = false
                        promptData.obj.MaxActivationDistance = 0
                    end
                end
            end
        end
        teleportersHidden = true
        syncTeleporterState()
        return true
    end

    if not teleportersSaved then
        teleportersHidden = false
        syncTeleporterState()
        return true
    end

    for _, data in ipairs(teleporterData) do
        if data.model then
            if data.parent and data.model.Parent ~= data.parent then
                data.model.Parent = data.parent
            end
            for _, partData in ipairs(data.parts) do
                if partData.obj then
                    partData.obj.Transparency = partData.transparency
                    partData.obj.CanCollide = partData.canCollide
                end
            end
            for _, guiData in ipairs(data.guis) do
                if guiData.obj then
                    guiData.obj.Enabled = guiData.enabled
                end
            end
            for _, promptData in ipairs(data.prompts) do
                if promptData.obj then
                    promptData.obj.Enabled = promptData.enabled
                    promptData.obj.MaxActivationDistance = promptData.maxActivationDistance
                end
            end
        end
    end

    teleportersHidden = false
    syncTeleporterState()
    return true
end

-- WINGARDIUM LEVIOSA - voo
local function wingardium()
    if flyAtivo then return end
    local hrp = getHRP()
    if not hrp then return end
    flyAtivo = true
    mobileJumpUntil = 0
    flyDownHeld = false

    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce  = Vector3.new(math.huge, math.huge, math.huge)
    flyBV.Velocity  = Vector3.new(0, 0, 0)
    flyBV.Parent    = hrp

    local hum = getHum()
    if hum then hum.PlatformStand = true end
    setMobileFlyControlsVisible(true)

    local idleHorizontalVelocity = getHorizontalVelocity(hrp)
    local hadHorizontalInput = false

    flyConn = RS.Heartbeat:Connect(function()
        local c = player.Character
        if not c then return end
        local h = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")
        if not h then return end
        local humNow = c:FindFirstChildOfClass("Humanoid")

        if useTouchFlightControls() then
            local moveDir = humNow and humNow.MoveDirection or Vector3.new(0, 0, 0)
            local horizontalVel = Vector3.new(moveDir.X, 0, moveDir.Z)
            local horizontalActive = horizontalVel.Magnitude > 0.01

            if horizontalActive and not hadHorizontalInput then
                idleHorizontalVelocity = getHorizontalVelocity(h)
            elseif not horizontalActive and hadHorizontalInput then
                restoreHorizontalVelocity(h, idleHorizontalVelocity)
            elseif not horizontalActive then
                idleHorizontalVelocity = getHorizontalVelocity(h)
            end

            if horizontalVel.Magnitude > 0.01 then
                horizontalVel = horizontalVel.Unit * 48
            else
                horizontalVel = Vector3.new(0, 0, 0)
            end

            local vertical = 0
            if (humNow and humNow.Jump) or mobileJumpUntil > os.clock() then
                vertical += 1
            end
            if flyDownHeld then
                vertical -= 1
            end

            flyBV.MaxForce = Vector3.new(
                horizontalActive and math.huge or 0,
                math.huge,
                horizontalActive and math.huge or 0
            )
            flyBV.Velocity = Vector3.new(horizontalVel.X, vertical * 42, horizontalVel.Z)
            hadHorizontalInput = horizontalActive
            return
        end

        local cam = workspace.CurrentCamera
        local camCF = cam and cam.CFrame or h.CFrame
        local look = camCF.LookVector
        local right = camCF.RightVector
        local flatForward = Vector3.new(look.X, 0, look.Z)
        local flatRight = Vector3.new(right.X, 0, right.Z)
        if flatForward.Magnitude < 0.01 then
            flatForward = Vector3.new(0, 0, -1)
        else
            flatForward = flatForward.Unit
        end
        if flatRight.Magnitude < 0.01 then
            flatRight = Vector3.new(1, 0, 0)
        else
            flatRight = flatRight.Unit
        end

        local move = Vector3.new(0, 0, 0)
        if UIS:IsKeyDown(Enum.KeyCode.Up) then
            move += flatForward
        end
        if UIS:IsKeyDown(Enum.KeyCode.Down) then
            move -= flatForward
        end
        if UIS:IsKeyDown(Enum.KeyCode.Left) then
            move -= flatRight
        end
        if UIS:IsKeyDown(Enum.KeyCode.Right) then
            move += flatRight
        end

        local vertical = 0
        if UIS:IsKeyDown(Enum.KeyCode.PageUp) then
            vertical += 1
        end
        if UIS:IsKeyDown(Enum.KeyCode.PageDown) then
            vertical -= 1
        end

        local horizontalVel = Vector3.new(0, 0, 0)
        local horizontalActive = move.Magnitude > 0.01

        if horizontalActive and not hadHorizontalInput then
            idleHorizontalVelocity = getHorizontalVelocity(h)
        elseif not horizontalActive and hadHorizontalInput then
            restoreHorizontalVelocity(h, idleHorizontalVelocity)
        elseif not horizontalActive then
            idleHorizontalVelocity = getHorizontalVelocity(h)
        end

        if move.Magnitude > 0.01 then
            horizontalVel = move.Unit * 48
        end
        flyBV.MaxForce = Vector3.new(
            horizontalActive and math.huge or 0,
            math.huge,
            horizontalActive and math.huge or 0
        )
        flyBV.Velocity = Vector3.new(horizontalVel.X, vertical * 42, horizontalVel.Z)
        hadHorizontalInput = horizontalActive
    end)
end

local function pararBombardaLoop()
    bombardaAtivo = false
    if bombardaThread then
        task.cancel(bombardaThread)
        bombardaThread = nil
    end
end

local function iniciarBombardaLoop()
    if bombardaAtivo then return end
    bombardaAtivo = true
    bombardaThread = task.spawn(function()
        while bombardaAtivo do
            bombarda()
            task.wait(BOMBARDA_INTERVAL)
        end
    end)
end

-- NOX - desativa voo
local function nox()
    flyAtivo = false
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV   then flyBV:Destroy();      flyBV   = nil end
    flyDownHeld = false
    mobileJumpUntil = 0
    setMobileFlyControlsVisible(false)
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

local function disableGod()
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
    disableGod()
    colloportus()
    pararBombardaLoop()

    impedAtivo = false
    local hum = getHum()
    if hum then
        hum.WalkSpeed = 16
        hum.JumpPower = 50
    end
end

local function isPolterImpelloAtivo()
    local api = _G.KAHPlayerActions
    if type(api) == "table" and type(api.isFlingEnabled) == "function" then
        local ok, ativo = pcall(api.isFlingEnabled)
        return ok and ativo == true or false
    end
    local persisted = rawget(_G, PLAYER_FLING_ACCESS_STATE_KEY)
    if type(persisted) == "table" and type(persisted.enabled) == "boolean" then
        return persisted.enabled == true
    end
    return false
end

local function setPolterImpelloAtivo(enabled)
    _G[PLAYER_FLING_ACCESS_STATE_KEY] = { enabled = enabled == true }
    local api = _G.KAHPlayerActions
    if type(api) ~= "table" or type(api.setFlingEnabled) ~= "function" then
        _G.KAHPlayerActionsFila = _G.KAHPlayerActionsFila or {}
        table.insert(_G.KAHPlayerActionsFila, function()
            local queuedApi = _G.KAHPlayerActions
            if type(queuedApi) == "table" and type(queuedApi.setFlingEnabled) == "function" then
                pcall(queuedApi.setFlingEnabled, enabled == true)
            end
        end)
        return enabled == true
    end
    local ok, result = pcall(api.setFlingEnabled, enabled == true)
    if not ok then
        error(result)
    end
    return result == true
end

local function applyPolterImpelloCommand(msg)
    local arg = tostring(msg or ""):match("^polter%s+impelli?o%s*(.-)%s*$") or ""
    local enabled = not isPolterImpelloAtivo()
    if arg == "on" or arg == "enable" or arg == "liberar" then
        enabled = true
    elseif arg == "off" or arg == "block" or arg == "bloquear" or arg == "disable" then
        enabled = false
    elseif arg == "toggle" then
        enabled = not isPolterImpelloAtivo()
    end
    setPolterImpelloAtivo(enabled)
end

-- ============================================
-- TABELA DE COMANDOS (sem ! na frente)
-- ============================================
local COMANDOS = {
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
        trigger = "bombarda",
        action  = function(msg)
            bombarda()
        end,
    },
    {
        trigger = "polter impello",
        action  = function(msg)
            applyPolterImpelloCommand(msg)
        end,
    },
    {
        trigger = "polter impellio",
        action  = function(msg)
            applyPolterImpelloCommand(msg)
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
local antFly = pg:FindFirstChild("AdminCommands_FlyMobile")
if antFly then antFly:Destroy() end

useTouchFlightControls = function()
    return UIS.TouchEnabled == true
end

local function ensureMobileFlyControls()
    if flyMobileGui and flyMobileGui.Parent then return end

    flyMobileGui = Instance.new("ScreenGui")
    flyMobileGui.Name = "AdminCommands_FlyMobile"
    flyMobileGui.ResetOnSpawn = false
    flyMobileGui.IgnoreGuiInset = true
    flyMobileGui.DisplayOrder = 999
    flyMobileGui.Enabled = false
    flyMobileGui.Parent = pg

    flyDownBtn = Instance.new("TextButton")
    flyDownBtn.Name = "DownButton"
    flyDownBtn.AnchorPoint = Vector2.new(1, 1)
    flyDownBtn.Size = UDim2.new(0, 58, 0, 58)
    flyDownBtn.Position = UDim2.new(1, -18, 1, -150)
    flyDownBtn.BackgroundColor3 = C.redDim
    flyDownBtn.Text = "DOWN"
    flyDownBtn.TextColor3 = C.red
    flyDownBtn.Font = Enum.Font.GothamBold
    flyDownBtn.TextSize = 12
    flyDownBtn.BorderSizePixel = 0
    flyDownBtn.AutoButtonColor = true
    flyDownBtn.ZIndex = 10
    flyDownBtn.Parent = flyMobileGui
    Instance.new("UICorner", flyDownBtn).CornerRadius = UDim.new(1, 0)
    Instance.new("UIStroke", flyDownBtn).Color = Color3.fromRGB(120, 28, 45)

    flyDownBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            flyDownHeld = true
        end
    end)

    flyDownBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            flyDownHeld = false
        end
    end)

    flyDownBtn.MouseLeave:Connect(function()
        flyDownHeld = false
    end)
end

setMobileFlyControlsVisible = function(visible)
    if not useTouchFlightControls() then return end
    ensureMobileFlyControls()
    flyDownHeld = false
    if flyMobileGui then
        flyMobileGui.Enabled = (visible == true)
    end
end

jumpRequestConn = UIS.JumpRequest:Connect(function()
    if flyAtivo and useTouchFlightControls() then
        mobileJumpUntil = os.clock() + 0.22
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name           = "AdminCommands_hud"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = pg
gui.Enabled        = false

local frame = Instance.new("Frame")
frame.Name             = "AdminFrame"
frame.Size             = UDim2.new(0, W, 0, H_FULL)
frame.Position         = UDim2.new(0, 20, 0, 120)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel  = 0
frame.Parent           = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color        = C.border

local function applyPanelVisibility()
    gui.Enabled = SHOW_ADMIN_UI and panelAtivo
end

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
    panelAtivo = false
    applyPanelVisibility()
    if _G.Hub then
        pcall(function() _G.Hub.setEstado(PANEL_TOGGLE_NAME, false) end)
    end
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
end

-- Helper para sincronizar estado do hub com efeito local
local function hubToggle(nome, ligarFn, desligarFn)
    return function(ativo)
        if ativo then ligarFn() else desligarFn() end
    end
end

local function setPanelAtivo(ativo)
    panelAtivo = (ativo == true)
    applyPanelVisibility()
    addLog(panelAtivo and "[PANEL] aberto" or "[PANEL] fechado", panelAtivo and C.green or C.muted)
end

local function setExecutarEmMim(ativo)
    EXECUTAR_EM_MIM = (ativo == true)
    addLog(EXECUTAR_EM_MIM and "[SELF] comandos proprios ON" or "[SELF] comandos proprios OFF", EXECUTAR_EM_MIM and C.green or C.muted)
end

local function pulseHubAction(rowName, action, logText)
    return function(ativo)
        if not ativo then return end
        if logText then
            addLog(logText, C.accent)
        end
        local ok, err = pcall(action)
        if not ok then
            addLog("[ERR] " .. tostring(err), C.red)
            warn("[KAH][WARN][AdminCommands][" .. tostring(rowName) .. "] " .. tostring(err))
        end
        task.defer(function()
            if _G.Hub then
                pcall(function() _G.Hub.setEstado(rowName, false) end)
            end
        end)
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

    registrarNoHub("Hide Teleporters", function(ativo)
        local ok, err = setTeleportersHidden(ativo == true)
        if not ok then
            addLog("[ERR] " .. tostring(err), C.red)
            task.defer(function()
                if _G.Hub then
                    pcall(function() _G.Hub.setEstado("Hide Teleporters", false) end)
                end
            end)
            return
        end
        addLog(
            (ativo and "[HUB] teleporters escondidos" or "[HUB] teleporters restaurados"),
            ativo and C.yellow or C.green
        )
    end, CATEGORIA, teleportersHidden, {
        statusProvider = function()
            return teleportersHidden and "HIDDEN" or "VISIBLE"
        end,
    })

    registrarNoHub(PANEL_TOGGLE_NAME, function(ativo)
        setPanelAtivo(ativo)
    end, CATEGORIA, false)

    registrarNoHub(SELF_TOGGLE_NAME, function(ativo)
        setExecutarEmMim(ativo)
    end, CATEGORIA, false)

    registrarNoHub("Accio", pulseHubAction("Accio", function()
        accio()
    end, "[HUB] accio"), CATEGORIA, false)

    registrarNoHub("Apparate", pulseHubAction("Apparate", function()
        local alvo = tostring(apparateTarget or ""):match("^%s*(.-)%s*$")
        if alvo == "" then
            error("Apparate sem alvo")
        end
        apparate(alvo)
    end, "[HUB] apparate"), CATEGORIA, false, {
        inlineText = {
            get = function() return apparateTarget end,
            set = function(v) apparateTarget = tostring(v or "") end,
            placeholder = "Player",
        }
    })

    registrarNoHub("Bombarda", function(ativo)
        if ativo then
            addLog("[HUB] bombarda loop ON", C.accent)
            iniciarBombardaLoop()
        else
            addLog("[HUB] bombarda loop OFF", C.muted)
            pararBombardaLoop()
        end
    end, CATEGORIA, false, {
        statusProvider = function()
            return bombardaAtivo and "LOOP" or "OFF"
        end,
    })

    registrarNoHub("Polter Impello", function(ativo)
        local ok, err = pcall(setPolterImpelloAtivo, ativo == true)
        if not ok then
            addLog("[ERR] " .. tostring(err), C.red)
            task.defer(function()
                if _G.Hub then
                    pcall(function() _G.Hub.setEstado("Polter Impello", isPolterImpelloAtivo()) end)
                end
            end)
            return
        end
        addLog(
            (ativo and "[HUB] polter impello liberado" or "[HUB] polter impello bloqueado"),
            ativo and C.accent or C.muted
        )
    end, CATEGORIA, isPolterImpelloAtivo(), {
        statusProvider = function()
            return isPolterImpelloAtivo() and "ON" or "OFF"
        end,
    })

    registrarNoHub("Impedimenta", pulseHubAction("Impedimenta", function()
        impedimenta()
    end, "[HUB] impedimenta"), CATEGORIA, false)

    registrarNoHub("Liberacorpus", pulseHubAction("Liberacorpus", function()
        liberacorpus()
    end, "[HUB] liberacorpus"), CATEGORIA, false)

    registrarNoHub("Wingardium / Nox", hubToggle("fly",
        function() wingardium() end,
        function() nox() end
    ), CATEGORIA, false)

    registrarNoHub("Protego", hubToggle("god",
        function() protego() end,
        function() disableGod() end
    ), CATEGORIA, false)

    registrarNoHub("Alohomora / Colloportus", hubToggle("noclip",
        function() alohomora() end,
        function() colloportus() end
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
        pararBombardaLoop()
        if jumpRequestConn then
            jumpRequestConn:Disconnect()
            jumpRequestConn = nil
        end
        if flyMobileGui and flyMobileGui.Parent then
            flyMobileGui:Destroy()
            flyMobileGui = nil
        end
        flyDownBtn = nil
    end,
}

