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
local PLAYER_HAUNT_ACCESS_STATE_KEY = "__player_actions_haunt_access"

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
local HS              = game:GetService("HttpService")
local UIS             = game:GetService("UserInputService")
local TS              = game:GetService("TweenService")
local RS              = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Chat            = game:GetService("Chat")
local player          = Players.LocalPlayer
local PLAYER_CATEGORY = "Player"
local PLAYER_MOVEMENT_CFG_KEY = "player_movement_cfg.json"
local ADMIN_COMMAND_CFG_KEY = "admin_commands_cfg.json"
local DEFAULT_IMPERO_TARGET = "Dieisson"
local ADMIN_ROW_NAMES = {
    SELF_TOGGLE_NAME,
    "Send Commands To Chat",
    "Command Target",
    "Impero ad Target",
    "Impero Orbitus",
    "Impero Sequor",
    "Impero Caput",
    "Impero Internus",
    "Impero Visus",
    "Finite Imperium",
    "Accio Servus",
    "Appareo",
    "Polter Impello",
    "Spectro Haunt",
    "Leviosa",
    "Protego",
    "Transitus",
    "Sanatio",
    "Aegis",
    "Portus Claudo",
    "Celeritas",
    "Impedimenta",
    "Finite Incantatem",
}
local PLAYER_ROW_NAMES = {
    "Speed",
    "Infinite Jump",
}

local speedValue = 100
local speedAtivo = false
local infiniteJumpAtivo = false
local movementCharConn = nil
local adminRowsRegistered = false
local commandChatAtivo = false
local commandTargetAtivo = false
local commandTarget = ""
local imperoTargetAtivo = false
local imperoTarget = ""
local impelloPowerValue = 120000
local celeritasAtivo = false
local altusAtivo = false
local altusPowerValue = 100
local sanatioAtivo = false
local aegisAtivo = false
local healConn = nil
local sanatioFx = nil
local aegisFx = nil
local commandUiState = {
    leviosa = false,
    celeritas = false,
    polterImpello = false,
    spectroHaunt = false,
    transitus = false,
    aegis = false,
    portusClosed = false,
    altus = false,
    impedimenta = false,
    imperium = "",
}
local refreshAdminRowLabels = function() end
local callPlayerAction
local getImperiumMode
local syncImperiumUiState = function() end
local setPolterImpelloAtivo

local function loadMovementCfg()
    if not (isfile and readfile and isfile(PLAYER_MOVEMENT_CFG_KEY)) then
        return
    end
    local ok, data = pcall(function()
        return HS:JSONDecode(readfile(PLAYER_MOVEMENT_CFG_KEY))
    end)
    if not ok or type(data) ~= "table" then
        return
    end
    if tonumber(data.speedValue) then
        speedValue = math.clamp(math.floor(tonumber(data.speedValue) + 0.5), 0, 500)
    end
    speedAtivo = data.speedEnabled == true
    infiniteJumpAtivo = data.infiniteJumpEnabled == true
end

local function saveMovementCfg()
    if not writefile then return end
    pcall(writefile, PLAYER_MOVEMENT_CFG_KEY, HS:JSONEncode({
        speedValue = speedValue,
        speedEnabled = speedAtivo == true,
        infiniteJumpEnabled = infiniteJumpAtivo == true,
    }))
end

loadMovementCfg()

local function loadAdminCommandCfg()
    if not (isfile and readfile and isfile(ADMIN_COMMAND_CFG_KEY)) then
        return
    end
    local ok, data = pcall(function()
        return HS:JSONDecode(readfile(ADMIN_COMMAND_CFG_KEY))
    end)
    if not ok or type(data) ~= "table" then
        return
    end
    commandChatAtivo = data.chatEnabled == true
    commandTargetAtivo = data.commandTargetEnabled == true
    commandTarget = tostring(data.commandTarget or "")
    imperoTargetAtivo = data.imperoTargetEnabled == true
    imperoTarget = tostring(data.imperoTarget or "")
    if tonumber(data.impelloPower) then
        impelloPowerValue = math.clamp(math.floor(tonumber(data.impelloPower) + 0.5), 10000, 500000)
    end
    if tonumber(data.altusPower) then
        altusPowerValue = math.clamp(math.floor(tonumber(data.altusPower) + 0.5), 50, 500)
    end
end

local function saveAdminCommandCfg()
    if not writefile then return end
    pcall(writefile, ADMIN_COMMAND_CFG_KEY, HS:JSONEncode({
        chatEnabled = commandChatAtivo == true,
        commandTargetEnabled = commandTargetAtivo == true,
        commandTarget = commandTarget,
        imperoTargetEnabled = imperoTargetAtivo == true,
        imperoTarget = imperoTarget,
        impelloPower = impelloPowerValue,
        altusPower = altusPowerValue,
    }))
end

loadAdminCommandCfg()

local function canShowAdminUi()
    local allowed = {
        kahrrasco = true,
    }
    local name = string.lower(tostring(player.Name or "")):match("^%s*(.-)%s*$")
    local display = string.lower(tostring(player.DisplayName or "")):match("^%s*(.-)%s*$")
    return allowed[name] == true
        or allowed[display] == true
        or string.find(name, "kahrrasco", 1, true) ~= nil
        or string.find(display, "kahrrasco", 1, true) ~= nil
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
    if not nome or nome == "" then return nil end
    local nomeLower = nome:lower()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower():find(nomeLower, 1, true)
        or p.DisplayName:lower():find(nomeLower, 1, true) then
            return p
        end
    end
    return nil
end

local function trim(text)
    return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function playerMatchesTarget(target)
    target = trim(target):lower()
    if target == "" then
        return true
    end
    local selfName = string.lower(tostring(player.Name or ""))
    local selfDisplay = string.lower(tostring(player.DisplayName or ""))
    return selfName == target
        or selfDisplay == target
        or string.find(selfName, target, 1, true) ~= nil
        or string.find(selfDisplay, target, 1, true) ~= nil
end

local function getSenderPlayer(remetente)
    return getPlayerByName(trim(remetente or ""))
end

local function startsWithCommand(msgLower, cmd)
    local trigger = string.lower(trim(cmd))
    if msgLower == trigger then
        return ""
    end
    if msgLower:sub(1, #trigger + 1) == trigger .. " " then
        return trim(msgLower:sub(#trigger + 2))
    end
    return nil
end

local function sendChatCommand(message)
    local msg = trim(message)
    if msg == "" then
        return false
    end

    if _G.KAHChat and type(_G.KAHChat.enviar) == "function" then
        local ok, sent = pcall(_G.KAHChat.enviar, msg)
        if ok and sent then
            return true
        end
    end

    local ok = false
    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local chan = TextChatService:FindFirstChild("TextChannels")
            local geral = chan and (chan:FindFirstChild("RBXGeneral") or chan:FindFirstChild("General"))
            if geral and geral.SendAsync then
                geral:SendAsync(msg)
                ok = true
            end
        end
    end)
    if ok then return true end

    pcall(function()
        local r = game:GetService("ReplicatedStorage")
        local d = r:FindFirstChild("DefaultChatSystemChatEvents")
        local say = d and d:FindFirstChild("SayMessageRequest")
        if say then
            say:FireServer(msg, "All")
            ok = true
        end
    end)
    if ok then return true end

    pcall(function()
        local head = player.Character and player.Character:FindFirstChild("Head")
        if head then
            Chat:Chat(head, msg, Enum.ChatColor.White)
            ok = true
        end
    end)
    return ok
end

local function buildChatCommand(baseText, opts)
    opts = type(opts) == "table" and opts or {}
    local text = trim(baseText)
    local parts = {}
    local explicitTarget = trim(opts.explicitTarget or "")
    if opts.appendTarget and (commandTargetAtivo or explicitTarget ~= "") then
        local target = trim(opts.explicitTarget or commandTarget)
        if target ~= "" then
            table.insert(parts, target)
        end
    end
    if opts.appendAdTarget then
        local adTarget = trim(opts.explicitAdTarget or "")
        if adTarget == "" and imperoTargetAtivo then
            adTarget = trim(imperoTarget)
        end
        if adTarget == "" then
            adTarget = DEFAULT_IMPERO_TARGET
        end
        table.insert(parts, "ad")
        table.insert(parts, adTarget)
    end
    if opts.extraArg ~= nil then
        local extra = trim(opts.extraArg)
        if extra ~= "" then
            table.insert(parts, extra)
        end
    end
    if #parts > 0 then
        return text .. " " .. table.concat(parts, " ")
    end
    return text
end

local function getChatSelfTarget()
    local display = trim(player.DisplayName or "")
    if display ~= "" then
        return display
    end
    return trim(player.Name or "")
end

local function getImperoAdTarget()
    local target = imperoTargetAtivo and trim(imperoTarget) or ""
    if target == "" then
        return DEFAULT_IMPERO_TARGET
    end
    return target
end

local function getCommandTargetOptions()
    local function withAllOption(options)
        local final = {
            { value = "", label = "Todos" },
        }
        for _, option in ipairs(options or {}) do
            table.insert(final, option)
        end
        return final
    end

    local api = _G.KAHPlayerActions
    if type(api) == "table" then
        local fn = api.getTargetOptions or api.getSelectablePlayers
        if type(fn) == "function" then
            local ok, options = pcall(fn)
            if ok and type(options) == "table" then
                return withAllOption(options)
            end
        end
    end

    local fallback = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local displayName = trim(p.DisplayName or "")
            local userName = trim(p.Name or "")
            local label = displayName ~= "" and displayName or userName
            table.insert(fallback, {
                value = label,
                label = label,
            })
        end
    end
    table.sort(fallback, function(a, b)
        return string.lower(tostring(a.label or a.value or "")) < string.lower(tostring(b.label or b.value or ""))
    end)
    return withAllOption(fallback)
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
commandUiState.portusClosed = teleportersHidden == true

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

local function getPlayerRoot(plr)
    local char = plr and plr.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")) or nil
end

local function teleportSelfNearPlayer(plr)
    local hrpAlvo = getPlayerRoot(plr)
    local hrp = getHRP()
    if not hrp or not hrpAlvo then
        return false, "Jogador nao encontrado"
    end
    hrp.CFrame = hrpAlvo.CFrame * CFrame.new(0, 0, 3)
    return true
end

local function getPrimaryAdminPlayer()
    local alvo = getPlayerByName("Kahrrasco")
    if alvo then
        return alvo
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if isAdmin(p.Name) then
            return p
        end
    end
    return nil
end

local function teleportSelfToSender(remetente)
    local remetentePlayer = getSenderPlayer(remetente)
    if remetentePlayer then
        return teleportSelfNearPlayer(remetentePlayer)
    end
    local alvo = getPrimaryAdminPlayer()
    if alvo then
        return teleportSelfNearPlayer(alvo)
    end
    return false, "Admin alvo nao encontrado"
end

-- ACCIO SERVUS - no local, aproxima voce do admin principal
local function accio()
    local alvo = getPrimaryAdminPlayer()
    if not alvo then
        return false, "Admin alvo nao encontrado"
    end
    return teleportSelfNearPlayer(alvo)
end

-- APPAREO - teleporta voce ate jogador pelo nome
local function apparate(nome)
    local alvoNome = trim(nome)
    if alvoNome == "" then
        return false, "Appareo sem alvo"
    end
    local alvo = getPlayerByName(alvoNome)
    if not alvo then
        return false, "Jogador nao encontrado"
    end
    return teleportSelfNearPlayer(alvo)
end

-- BOMBARDA - lanca o personagem para longe
local function bombarda(power)
    local hrp = getHRP()
    if not hrp then return end
    local direcao = hrp.CFrame.LookVector
    local forcePower = math.clamp(math.floor(tonumber(power) or impelloPowerValue), 10000, 500000)
    -- aplica impulso via VectorForce temporario
    local att = Instance.new("Attachment", hrp)
    local vf  = Instance.new("VectorForce")
    vf.Attachment0 = att
    vf.Force       = direcao * forcePower
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
    local function isAlive(obj)
        return typeof(obj) == "Instance" and obj.Parent ~= nil
    end

    local function hasValidSavedData()
        if not teleportersSaved or #teleporterData == 0 then
            return false
        end
        for _, data in ipairs(teleporterData) do
            if isAlive(data.model) then
                return true
            end
            for _, bucketName in ipairs({ "parts", "guis", "prompts", "effects" }) do
                for _, item in ipairs(data[bucketName] or {}) do
                    if isAlive(item.obj) then
                        return true
                    end
                end
            end
        end
        return false
    end

    local function isTeleporterName(name)
        local lowered = string.lower(tostring(name or ""))
        return string.find(lowered, "teleporter", 1, true) ~= nil
            or string.find(lowered, "portal", 1, true) ~= nil
    end

    local function collectTeleporterRoots()
        local roots = {}
        local seen = {}

        local function addRoot(obj)
            if typeof(obj) ~= "Instance" or seen[obj] then
                return
            end
            seen[obj] = true
            table.insert(roots, obj)
        end

        for _, name in ipairs({ "Teleporter1", "Teleporter2", "Teleporter3" }) do
            local exact = workspace:FindFirstChild(name, true)
            if exact then
                addRoot(exact)
            end
        end

        for _, obj in ipairs(workspace:GetDescendants()) do
            if isTeleporterName(obj.Name) then
                local root = obj
                while root.Parent and root.Parent ~= workspace and isTeleporterName(root.Parent.Name) do
                    root = root.Parent
                end
                addRoot(root)
            end
        end

        return roots
    end

    local function buildTeleporterEntry(root)
        local entry = {
            model = root,
            parent = root.Parent,
            parts = {},
            guis = {},
            prompts = {},
            effects = {},
        }

        local function collectObject(obj)
            if obj:IsA("BasePart") then
                table.insert(entry.parts, {
                    obj = obj,
                    transparency = obj.Transparency,
                    canCollide = obj.CanCollide,
                    canTouch = obj.CanTouch,
                    canQuery = obj.CanQuery,
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
            elseif obj:IsA("ParticleEmitter")
                or obj:IsA("Beam")
                or obj:IsA("Trail")
                or obj:IsA("PointLight")
                or obj:IsA("SurfaceLight")
                or obj:IsA("SpotLight") then
                table.insert(entry.effects, {
                    obj = obj,
                    enabled = obj.Enabled,
                })
            end
        end

        collectObject(root)
        for _, obj in ipairs(root:GetDescendants()) do
            collectObject(obj)
        end

        if #entry.parts == 0 and #entry.guis == 0 and #entry.prompts == 0 and #entry.effects == 0 then
            return nil
        end

        return entry
    end

    if hasValidSavedData() then
        return true
    end

    teleporterData = {}
    teleportersSaved = false
    for _, root in ipairs(collectTeleporterRoots()) do
        local entry = buildTeleporterEntry(root)
        if entry then
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
        if not saveTeleporters() then
            return false, "Teleporters nao encontrados"
        end
        for _, data in ipairs(teleporterData) do
            if data.model then
                for _, partData in ipairs(data.parts) do
                    if partData.obj then
                        partData.obj.Transparency = 1
                        partData.obj.CanCollide = false
                        partData.obj.CanTouch = false
                        partData.obj.CanQuery = false
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
                for _, effectData in ipairs(data.effects or {}) do
                    if effectData.obj then
                        effectData.obj.Enabled = false
                    end
                end
                if data.parent and data.model.Parent ~= nil then
                    data.model.Parent = nil
                end
            end
        end
        teleportersHidden = true
        commandUiState.portusClosed = true
        syncTeleporterState()
        refreshAdminRowLabels()
        return true
    end

    if not teleportersSaved then
        teleportersHidden = false
        commandUiState.portusClosed = false
        syncTeleporterState()
        refreshAdminRowLabels()
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
                    partData.obj.CanTouch = partData.canTouch ~= false
                    partData.obj.CanQuery = partData.canQuery ~= false
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
            for _, effectData in ipairs(data.effects or {}) do
                if effectData.obj then
                    effectData.obj.Enabled = effectData.enabled
                end
            end
        end
    end

    teleportersHidden = false
    commandUiState.portusClosed = false
    syncTeleporterState()
    refreshAdminRowLabels()
    return true
end

-- WINGARDIUM LEVIOSA - voo
local function wingardium()
    if flyAtivo then return end
    local hrp = getHRP()
    if not hrp then return end
    flyAtivo = true
    commandUiState.leviosa = true
    refreshAdminRowLabels()
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

local function setImpelloAtivo(enabled)
    if enabled then
        iniciarBombardaLoop()
    else
        pararBombardaLoop()
    end
end

-- NOX - desativa voo
local function nox()
    flyAtivo = false
    commandUiState.leviosa = false
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV   then flyBV:Destroy();      flyBV   = nil end
    flyDownHeld = false
    mobileJumpUntil = 0
    setMobileFlyControlsVisible(false)
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    refreshAdminRowLabels()
end

local function clearEffectInstance(ref)
    if ref and ref.Parent then
        pcall(function() ref:Destroy() end)
    end
    return nil
end

local function clearSanatioFx()
    sanatioFx = clearEffectInstance(sanatioFx)
end

local function clearAegisFx()
    aegisFx = clearEffectInstance(aegisFx)
end

local function ensureSanatioFx()
    local char = player.Character
    if not char then return end
    if sanatioFx and sanatioFx.Parent == char then return end
    clearSanatioFx()

    local highlight = Instance.new("Highlight")
    highlight.Name = "KAH_SanatioFx"
    highlight.Adornee = char
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color3.fromRGB(90, 255, 170)
    highlight.FillTransparency = 0.78
    highlight.OutlineColor = Color3.fromRGB(190, 255, 220)
    highlight.OutlineTransparency = 0.18
    highlight.Parent = char
    sanatioFx = highlight
end

local function ensureAegisFx()
    local char = player.Character
    if not char then return end
    if aegisFx and aegisFx.Parent == char then return end
    clearAegisFx()

    local forceField = Instance.new("ForceField")
    forceField.Name = "KAH_AegisFx"
    forceField.Visible = true
    forceField.Parent = char
    aegisFx = forceField
end

local function refreshRecoveryLoop()
    if healConn then
        healConn:Disconnect()
        healConn = nil
    end
    if not (sanatioAtivo or aegisAtivo) then
        clearSanatioFx()
        clearAegisFx()
        return
    end

    if sanatioAtivo then
        ensureSanatioFx()
    else
        clearSanatioFx()
    end
    if aegisAtivo then
        ensureAegisFx()
    else
        clearAegisFx()
    end

    healConn = RS.Heartbeat:Connect(function()
        local hum = getHum()
        if hum then
            hum.Health = hum.MaxHealth
        end
        if sanatioAtivo then
            ensureSanatioFx()
        end
        if aegisAtivo then
            ensureAegisFx()
        end
    end)
end

local function setSanatioAtivo(enabled)
    sanatioAtivo = (enabled == true)
    refreshRecoveryLoop()
end

local function setAegisAtivo(enabled)
    aegisAtivo = (enabled == true)
    commandUiState.aegis = aegisAtivo
    refreshRecoveryLoop()
    refreshAdminRowLabels()
end

local function protego()
    setSanatioAtivo(true)
    setAegisAtivo(true)
end

local function isProtegoAtivo()
    return sanatioAtivo == true and aegisAtivo == true
end

local function setProtegoAtivo(enabled)
    setSanatioAtivo(enabled == true)
    setAegisAtivo(enabled == true)
end

-- ALOHOMORA - noclip
local function alohomora()
    if noclipAtivo then return end
    noclipAtivo = true
    commandUiState.transitus = true
    noclipConn  = RS.Stepped:Connect(function()
        local c = player.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = false
            end
        end
    end)
    refreshAdminRowLabels()
end

-- COLLOPORTUS - desativa noclip
local function colloportus()
    noclipAtivo = false
    commandUiState.transitus = false
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    local c = player.Character
    if not c then
        refreshAdminRowLabels()
        return
    end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = true
        end
    end
    refreshAdminRowLabels()
end

local function getDesiredWalkSpeed()
    if impedAtivo then
        return 0
    end
    local base = speedAtivo and speedValue or 16
    if celeritasAtivo then
        base = math.max(base, 100)
    end
    return base
end

local function applySpeedState()
    local hum = getHum()
    if hum then
        hum.WalkSpeed = getDesiredWalkSpeed()
    end
end

local function applyJumpState()
    local hum = getHum()
    if hum then
        local jumpPower = altusAtivo and altusPowerValue or 50
        local jumpHeight = altusAtivo and math.max(7.2, altusPowerValue / 6.5) or 7.2
        if impedAtivo then
            jumpPower = 0
            jumpHeight = 0
        end
        hum.JumpPower = jumpPower
        pcall(function()
            hum.JumpHeight = jumpHeight
        end)
    end
end

local function applyMovementStateSoon()
    task.spawn(function()
        for _ = 1, 20 do
            local hum = getHum()
            if hum then
                applySpeedState()
                applyJumpState()
                refreshRecoveryLoop()
                return
            end
            task.wait(0.1)
        end
    end)
end

if movementCharConn then
    movementCharConn:Disconnect()
    movementCharConn = nil
end
movementCharConn = player.CharacterAdded:Connect(function()
    mobileJumpUntil = 0
    applyMovementStateSoon()
end)

-- IMPEDIMENTA - trava o personagem no lugar
local function impedimenta()
    impedAtivo = true
    commandUiState.impedimenta = true
    applySpeedState()
    applyJumpState()
    refreshAdminRowLabels()
end

-- LIBERACORPUS - libera tudo
local function liberacorpus()
    impedAtivo = false
    commandUiState.impedimenta = false
    applySpeedState()
    applyJumpState()
    refreshAdminRowLabels()
end

local function finiteIncantatem()
    nox()
    colloportus()
    setImpelloAtivo(false)
    setSanatioAtivo(false)
    setAegisAtivo(false)
    celeritasAtivo = false
    commandUiState.celeritas = false
    altusAtivo = false
    commandUiState.altus = false
    liberacorpus()
    pcall(setTeleportersHidden, false)
    pcall(setPolterImpelloAtivo, false)
    pcall(callPlayerAction, "finiteImperium")
    commandUiState.polterImpello = false
    commandUiState.imperium = ""
    applySpeedState()
    applyJumpState()
    refreshAdminRowLabels()
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

setPolterImpelloAtivo = function(enabled)
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

local function isSpectroHauntAtivo()
    local api = _G.KAHPlayerActions
    if type(api) == "table" and type(api.isHauntEnabled) == "function" then
        local ok, ativo = pcall(api.isHauntEnabled)
        return ok and ativo == true or false
    end
    local persisted = rawget(_G, PLAYER_HAUNT_ACCESS_STATE_KEY)
    if type(persisted) == "table" and type(persisted.enabled) == "boolean" then
        return persisted.enabled == true
    end
    return false
end

local function setSpectroHauntAtivo(enabled)
    _G[PLAYER_HAUNT_ACCESS_STATE_KEY] = { enabled = enabled == true }
    local api = _G.KAHPlayerActions
    if type(api) ~= "table" or type(api.setHauntEnabled) ~= "function" then
        _G.KAHPlayerActionsFila = _G.KAHPlayerActionsFila or {}
        table.insert(_G.KAHPlayerActionsFila, function()
            local queuedApi = _G.KAHPlayerActions
            if type(queuedApi) == "table" and type(queuedApi.setHauntEnabled) == "function" then
                pcall(queuedApi.setHauntEnabled, enabled == true)
            end
        end)
        return enabled == true
    end
    local ok, result = pcall(api.setHauntEnabled, enabled == true)
    if not ok then error(result) end
    return result == true
end

local function queuePlayerActionCall(methodName, args)
    local packedArgs = type(args) == "table" and args or {}
    _G.KAHPlayerActionsFila = _G.KAHPlayerActionsFila or {}
    table.insert(_G.KAHPlayerActionsFila, function()
        local queuedApi = _G.KAHPlayerActions
        local queuedFn = type(queuedApi) == "table" and queuedApi[methodName] or nil
        if type(queuedFn) == "function" then
            pcall(queuedFn, table.unpack(packedArgs))
        end
    end)
end

callPlayerAction = function(methodName, ...)
    local api = _G.KAHPlayerActions
    local fn = type(api) == "table" and api[methodName] or nil
    local args = { ... }
    if type(fn) ~= "function" then
        queuePlayerActionCall(methodName, args)
        return true
    end
    local ok, result, extra = pcall(fn, table.unpack(args))
    if not ok then
        error(result)
    end
    if result == nil then
        return true
    end
    return result, extra
end

getImperiumMode = function()
    local api = _G.KAHPlayerActions
    local fn = type(api) == "table" and api.getImperiumState or nil
    if type(fn) ~= "function" then
        return ""
    end
    local ok, state = pcall(fn)
    if not ok or type(state) ~= "table" then
        return ""
    end
    local mode = trim(state.mode or ""):lower()
    if mode == "orbit" or mode == "follow" or mode == "head" or mode == "inside" or mode == "visus" then
        return mode
    end
    return ""
end

syncImperiumUiState = function()
    commandUiState.imperium = getImperiumMode()
    refreshAdminRowLabels()
end

local function parseImperoArgs(remetente, rawArg)
    local lowerArg = trim(rawArg)
    local targetA, targetB = lowerArg:match("^(.-)%s+ad%s+(.+)$")
    targetA = trim(targetA or lowerArg)
    targetB = trim(targetB or "")
    if targetA == "" then
        targetA = trim(remetente)
    end
    if targetB == "" then
        targetB = DEFAULT_IMPERO_TARGET
    end
    return targetA, targetB
end

local function getFiniteImperoTarget(remetente, rawArg)
    local targetA = trim(rawArg)
    if targetA == "" then
        targetA = trim(remetente)
    end
    return targetA
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

local function getPolterImpelloStatus()
    if not commandChatAtivo then
        return "ATIVE CHAT"
    end
    return ""
end

-- ============================================
-- TABELA DE COMANDOS (sem ! na frente)
-- ============================================
local function applyToTarget(targetArg, fn)
    if not playerMatchesTarget(targetArg) then
        return false
    end
    fn()
    return true
end

local function setCeleritasAtivo(enabled)
    celeritasAtivo = (enabled == true)
    commandUiState.celeritas = celeritasAtivo
    applySpeedState()
    refreshAdminRowLabels()
end

local function setAltusAtivo(enabled)
    altusAtivo = (enabled == true)
    commandUiState.altus = altusAtivo
    applyJumpState()
    refreshAdminRowLabels()
end

local function setAltusPowerValue(value)
    altusPowerValue = math.clamp(math.floor(tonumber(value) or altusPowerValue), 50, 500)
    saveAdminCommandCfg()
    if altusAtivo then
        applyJumpState()
    end
end

local COMANDOS = {
    {
        nomes = { "accio servus", "accio" },
        action = function(remetente, targetArg)
            return applyToTarget(targetArg, function()
                teleportSelfToSender(remetente)
            end)
        end,
    },
    {
        nomes = { "appareo", "apparate" },
        action = function(remetente, targetArg)
            local alvo = trim(targetArg)
            if alvo ~= "" then
                return apparate(alvo)
            end
            return teleportSelfToSender(remetente)
        end,
    },
    {
        nomes = { "impero orbitus" },
        action = function(remetente, targetArg)
            local targetA, targetB = parseImperoArgs(remetente, targetArg)
            if not playerMatchesTarget(targetA) then
                return false
            end
            return callPlayerAction("imperoOrbitus", targetB)
        end,
    },
    {
        nomes = { "impero sequor" },
        action = function(remetente, targetArg)
            local targetA, targetB = parseImperoArgs(remetente, targetArg)
            if not playerMatchesTarget(targetA) then
                return false
            end
            return callPlayerAction("imperoSequor", targetB)
        end,
    },
    {
        nomes = { "impero caput" },
        action = function(remetente, targetArg)
            local targetA, targetB = parseImperoArgs(remetente, targetArg)
            if not playerMatchesTarget(targetA) then
                return false
            end
            return callPlayerAction("imperoCaput", targetB)
        end,
    },
    {
        nomes = { "impero internus" },
        action = function(remetente, targetArg)
            local targetA, targetB = parseImperoArgs(remetente, targetArg)
            if not playerMatchesTarget(targetA) then
                return false
            end
            return callPlayerAction("imperoInternus", targetB)
        end,
    },
    {
        nomes = { "impero visus" },
        action = function(remetente, targetArg)
            local targetA, targetB = parseImperoArgs(remetente, targetArg)
            if not playerMatchesTarget(targetA) then
                return false
            end
            return callPlayerAction("imperoVisus", targetB)
        end,
    },
    {
        nomes = { "finite orbitus" },
        action = function(remetente, targetArg)
            if not playerMatchesTarget(getFiniteImperoTarget(remetente, targetArg)) then
                return false
            end
            return callPlayerAction("finiteOrbitus")
        end,
    },
    {
        nomes = { "finite sequor" },
        action = function(remetente, targetArg)
            if not playerMatchesTarget(getFiniteImperoTarget(remetente, targetArg)) then
                return false
            end
            return callPlayerAction("finiteSequor")
        end,
    },
    {
        nomes = { "finite caput" },
        action = function(remetente, targetArg)
            if not playerMatchesTarget(getFiniteImperoTarget(remetente, targetArg)) then
                return false
            end
            return callPlayerAction("finiteCaput")
        end,
    },
    {
        nomes = { "finite internus" },
        action = function(remetente, targetArg)
            if not playerMatchesTarget(getFiniteImperoTarget(remetente, targetArg)) then
                return false
            end
            return callPlayerAction("finiteInternus")
        end,
    },
    {
        nomes = { "finite visus" },
        action = function(remetente, targetArg)
            if not playerMatchesTarget(getFiniteImperoTarget(remetente, targetArg)) then
                return false
            end
            return callPlayerAction("finiteVisus")
        end,
    },
    {
        nomes = { "finite imperium" },
        action = function(remetente, targetArg)
            if not playerMatchesTarget(getFiniteImperoTarget(remetente, targetArg)) then
                return false
            end
            return callPlayerAction("finiteImperium")
        end,
    },
    {
        nomes = { "impello" },
        action = function()
            setImpelloAtivo(not bombardaAtivo)
            return true
        end,
    },
    {
        nomes = { "polter impello", "polter impellio" },
        action = function(_, _)
            applyPolterImpelloCommand("polter impello toggle")
            return true
        end,
    },
    {
        nomes = { "concedo polter impello", "concedo polter impellio" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setPolterImpelloAtivo(true)
            end)
        end,
    },
    {
        nomes = { "revoco polter impello", "revoco polter impellio" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setPolterImpelloAtivo(false)
            end)
        end,
    },
    {
        nomes = { "concedo spectro haunt", "concedo spectro" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setSpectroHauntAtivo(true)
            end)
        end,
    },
    {
        nomes = { "revoco spectro haunt", "revoco spectro" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setSpectroHauntAtivo(false)
            end)
        end,
    },
    {
        nomes = { "finite leviosa", "nox" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                nox()
            end)
        end,
    },
    {
        nomes = { "leviosa", "wingardium" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                wingardium()
            end)
        end,
    },
    {
        nomes = { "protego" },
        action = function()
            setProtegoAtivo(not isProtegoAtivo())
            return true
        end,
    },
    {
        nomes = { "transitus", "alohomora" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                alohomora()
            end)
        end,
    },
    {
        nomes = { "colloportus" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                colloportus()
            end)
        end,
    },
    {
        nomes = { "portus aperio" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setTeleportersHidden(false)
            end)
        end,
    },
    {
        nomes = { "portus claudo" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setTeleportersHidden(true)
            end)
        end,
    },
    {
        nomes = { "finite celeritas" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setCeleritasAtivo(false)
            end)
        end,
    },
    {
        nomes = { "celeritas" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setCeleritasAtivo(not celeritasAtivo)
            end)
        end,
    },
    {
        nomes = { "sanatio" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setSanatioAtivo(true)
            end)
        end,
    },
    {
        nomes = { "finite aegis" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setAegisAtivo(false)
            end)
        end,
    },
    {
        nomes = { "aegis" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                setAegisAtivo(true)
            end)
        end,
    },
    {
        nomes = { "impedimenta" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                impedimenta()
            end)
        end,
    },
    {
        nomes = { "liber corpus", "liberacorpus" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                liberacorpus()
            end)
        end,
    },
    {
        nomes = { "finite incantatem" },
        action = function(_, targetArg)
            return applyToTarget(targetArg, function()
                finiteIncantatem()
            end)
        end,
    },
}

local function executarComandoAdmin(remetente, mensagem)
    local msgLower = trim(string.lower(mensagem or ""))
    for _, cmd in ipairs(COMANDOS) do
        for _, nome in ipairs(cmd.nomes) do
            local arg = startsWithCommand(msgLower, nome)
            if arg ~= nil then
                local ok, result = pcall(cmd.action, remetente, arg)
                if not ok then
                    return nome, false, result
                end
                return nome, true, result
            end
        end
    end
    return nil
end

-- ============================================
-- PROCESSAR MENSAGEM
-- So executa se vier de um admin
-- ============================================
local monitorAtivo = false

local function processarMensagem(remetente, mensagem)
    if not monitorAtivo then return end
    if not isAdmin(remetente) then return end  -- ignora quem nao e admin

    local nome, ok, err = executarComandoAdmin(remetente, mensagem)
    if nome and not ok then
        warn(">>> AdminCommands [" .. tostring(nome) .. "]: " .. tostring(err))
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
-- Pre-declare upvalues that escape the GUI build block
local gui, addLog, activateMonitor, deactivateMonitor, applyPanelVisibility, refreshPanelSummary
do  -- GUI build block
local W        = 250
local H_HDR    = 34
local H_STATUS = 20
local H_SUBTAB = 24
local H_TOGGLE = 34
local H_PAGE   = 170
local PAD      = 6
local H_FULL   = H_HDR + H_STATUS + H_SUBTAB + H_PAGE + PAD * 3

local function getMinimizedWidth()
    if _G.KAHUiDefaults and _G.KAHUiDefaults.getMinWidth then
        local ok, v = pcall(_G.KAHUiDefaults.getMinWidth)
        if ok and tonumber(v) then return math.clamp(math.floor(tonumber(v)), 220, 420) end
    end
    return 240
end

local pg  = player:WaitForChild("PlayerGui")
do
    local ant = pg:FindFirstChild("AdminCommands_hud")
    if ant then ant:Destroy() end
    local antFly = pg:FindFirstChild("AdminCommands_FlyMobile")
    if antFly then antFly:Destroy() end
end

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
    if infiniteJumpAtivo and not flyAtivo then
        local hum = getHum()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

gui = Instance.new("ScreenGui")
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

applyPanelVisibility = function()
    gui.Enabled = SHOW_ADMIN_UI and panelAtivo
end

-- Linha accent topo
do
    local topLine = Instance.new("Frame")
    topLine.Size             = UDim2.new(1, 0, 0, 2)
    topLine.BackgroundColor3 = C.accent
    topLine.BorderSizePixel  = 0
    topLine.ZIndex           = 5
    topLine.Parent           = frame
    Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)
end

-- Header
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, H_HDR)
header.BackgroundColor3 = C.header
header.BorderSizePixel  = 0
header.Active           = true
header.ZIndex           = 3
header.Parent           = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

do
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
end

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

local subTabBar = Instance.new("Frame")
subTabBar.Size             = UDim2.new(1, -PAD * 2, 0, H_SUBTAB)
subTabBar.Position         = UDim2.new(0, PAD, 0, H_HDR + H_STATUS + PAD)
subTabBar.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
subTabBar.BorderSizePixel  = 0
subTabBar.ZIndex           = 3
subTabBar.Parent           = frame
Instance.new("UICorner", subTabBar).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", subTabBar).Color        = C.border

local subTabLayout = Instance.new("UIListLayout")
subTabLayout.FillDirection = Enum.FillDirection.Horizontal
subTabLayout.Padding = UDim.new(0, 4)
subTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
subTabLayout.Parent = subTabBar

local subTabPadding = Instance.new("UIPadding")
subTabPadding.PaddingLeft = UDim.new(0, 4)
subTabPadding.PaddingRight = UDim.new(0, 4)
subTabPadding.PaddingTop = UDim.new(0, 2)
subTabPadding.PaddingBottom = UDim.new(0, 2)
subTabPadding.Parent = subTabBar

local pageHolder = Instance.new("Frame")
pageHolder.Size             = UDim2.new(1, -PAD * 2, 0, H_PAGE)
pageHolder.Position         = UDim2.new(0, PAD, 0, H_HDR + H_STATUS + PAD + H_SUBTAB + PAD)
pageHolder.BackgroundTransparency = 1
pageHolder.BorderSizePixel  = 0
pageHolder.ZIndex           = 3
pageHolder.Parent           = frame

local pageOverview = Instance.new("Frame")
pageOverview.Name = "OverviewPage"
pageOverview.Size = UDim2.new(1, 0, 1, 0)
pageOverview.BackgroundTransparency = 1
pageOverview.Visible = true
pageOverview.ZIndex = 3
pageOverview.Parent = pageHolder

local pageTargets = Instance.new("Frame")
pageTargets.Name = "TargetsPage"
pageTargets.Size = UDim2.new(1, 0, 1, 0)
pageTargets.BackgroundTransparency = 1
pageTargets.Visible = false
pageTargets.ZIndex = 3
pageTargets.Parent = pageHolder

local pageLog = Instance.new("Frame")
pageLog.Name = "LogPage"
pageLog.Size = UDim2.new(1, 0, 1, 0)
pageLog.BackgroundTransparency = 1
pageLog.Visible = false
pageLog.ZIndex = 3
pageLog.Parent = pageHolder

local pageButtons = {}
local pageFrames = {
    Overview = pageOverview,
    Targets = pageTargets,
    Log = pageLog,
}

local function setSubTabActive(pageName)
    for name, page in pairs(pageFrames) do
        page.Visible = (name == pageName)
        local btn = pageButtons[name]
        if btn then
            btn.BackgroundColor3 = (name == pageName) and C.accentDim or Color3.fromRGB(18, 20, 30)
            btn.TextColor3 = (name == pageName) and C.accent or C.muted
        end
    end
end

local function makeSubTabButton(pageName)
    local btn = Instance.new("TextButton")
    btn.Name = pageName .. "Tab"
    btn.Size = UDim2.new(0, 74, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
    btn.TextColor3 = C.muted
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.Text = string.upper(pageName)
    btn.BorderSizePixel = 0
    btn.ZIndex = 4
    btn.Parent = subTabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(function()
        setSubTabActive(pageName)
    end)
    pageButtons[pageName] = btn
end

makeSubTabButton("Overview")
makeSubTabButton("Targets")
makeSubTabButton("Log")

local toggleFrame = Instance.new("Frame")
toggleFrame.Size             = UDim2.new(1, 0, 0, H_TOGGLE)
toggleFrame.Position         = UDim2.new(0, 0, 0, 0)
toggleFrame.BackgroundColor3 = C.rowBg
toggleFrame.BorderSizePixel  = 0
toggleFrame.ZIndex           = 3
toggleFrame.Parent           = pageOverview
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
tgLbl.Text               = "Admin Monitor"
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

local overviewInfo = Instance.new("Frame")
overviewInfo.Size = UDim2.new(1, 0, 1, -(H_TOGGLE + PAD))
overviewInfo.Position = UDim2.new(0, 0, 0, H_TOGGLE + PAD)
overviewInfo.BackgroundColor3 = Color3.fromRGB(8, 9, 13)
overviewInfo.BorderSizePixel = 0
overviewInfo.ZIndex = 3
overviewInfo.Parent = pageOverview
Instance.new("UICorner", overviewInfo).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", overviewInfo).Color = C.border

local overviewLabels = {}
for i = 1, 5 do
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -16, 0, 18)
    lbl.Position = UDim2.new(0, 8, 0, 6 + (i - 1) * 19)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = i == 1 and C.accent or C.text
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 4
    lbl.Parent = overviewInfo
    overviewLabels[i] = lbl
end

local targetsFrame = Instance.new("Frame")
targetsFrame.Size = UDim2.new(1, 0, 1, 0)
targetsFrame.BackgroundColor3 = Color3.fromRGB(8, 9, 13)
targetsFrame.BorderSizePixel = 0
targetsFrame.ZIndex = 3
targetsFrame.Parent = pageTargets
Instance.new("UICorner", targetsFrame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", targetsFrame).Color = C.border

local targetLabels = {}
for i = 1, 6 do
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -16, 0, 20)
    lbl.Position = UDim2.new(0, 8, 0, 8 + (i - 1) * 23)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = (i == 6) and C.muted or C.text
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 4
    lbl.Parent = targetsFrame
    targetLabels[i] = lbl
end

-- Log de spells executadas
local logScroll = Instance.new("ScrollingFrame")
logScroll.Size                 = UDim2.new(1, 0, 1, 0)
logScroll.Position             = UDim2.new(0, 0, 0, 0)
logScroll.BackgroundColor3     = Color3.fromRGB(8, 9, 13)
logScroll.BorderSizePixel      = 0
logScroll.ScrollBarThickness   = 3
logScroll.ScrollBarImageColor3 = C.accent
logScroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
logScroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
logScroll.ZIndex               = 3
logScroll.Parent               = pageLog
Instance.new("UICorner", logScroll).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", logScroll).Color        = C.border

do
    local logLayout = Instance.new("UIListLayout", logScroll)
    logLayout.Padding   = UDim.new(0, 1)
    logLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local logPad = Instance.new("UIPadding", logScroll)
    logPad.PaddingLeft   = UDim.new(0, 4)
    logPad.PaddingTop    = UDim.new(0, 3)
    logPad.PaddingBottom = UDim.new(0, 3)
end

local logCount = 0
addLog = function(texto, cor)
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

refreshPanelSummary = function()
    local chatState = commandChatAtivo and "ON" or "OFF"
    local selfState = EXECUTAR_EM_MIM and "ON" or "OFF"
    local commandTargetText = commandTargetAtivo and trim(commandTarget) or "Todos"
    if commandTargetText == "" then
        commandTargetText = "Todos"
    end
    local imperoTargetText = imperoTargetAtivo and trim(imperoTarget) or DEFAULT_IMPERO_TARGET
    if imperoTargetText == "" then
        imperoTargetText = DEFAULT_IMPERO_TARGET
    end
    local imperiumText = trim(commandUiState.imperium or "")
    if imperiumText == "" then
        imperiumText = "none"
    end
    overviewLabels[1].Text = "monitor = " .. (monitorAtivo and "ACTIVE" or "IDLE")
    overviewLabels[2].Text = "chat = " .. chatState .. " | self = " .. selfState
    overviewLabels[3].Text = "command target = " .. commandTargetText
    overviewLabels[4].Text = "impero ad = " .. imperoTargetText
    overviewLabels[5].Text = "polter = " .. (commandUiState.polterImpello and "Revoco Polter Impello" or "Concedo Polter Impello") .. " | imperium = " .. imperiumText

    targetLabels[1].Text = "A target: " .. commandTargetText
    targetLabels[2].Text = "B target: " .. imperoTargetText
    targetLabels[3].Text = "Send Commands To Chat: " .. chatState
    targetLabels[4].Text = "Execute on Self: " .. selfState
    targetLabels[5].Text = "Polter Impello row: " .. (commandUiState.polterImpello and "Revoco Polter Impello" or "Concedo Polter Impello")
    targetLabels[6].Text = "Sem A alvo, Impero usa voce; sem B alvo, usa " .. DEFAULT_IMPERO_TARGET
end

setSubTabActive("Overview")
refreshPanelSummary()

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
    refreshPanelSummary()
end

activateMonitor = function(logText, logColor)
    if monitorAtivo then return end
    monitorAtivo = true
    setVisual(true)
    conectarChat()
    if logText then
        addLog(logText, logColor or C.green)
    end
    refreshPanelSummary()
end

deactivateMonitor = function(logText, logColor)
    if monitorAtivo then
        desconectarChat()
        monitorAtivo = false
    end
    finiteIncantatem()
    setVisual(false)
    if logText then
        addLog(logText, logColor or C.muted)
    end
    refreshPanelSummary()
end

processarMensagem = function(remetente, mensagem)
    if not monitorAtivo then return end
    if not isAdmin(remetente) then return end
    if not EXECUTAR_EM_MIM and player.Name == remetente then return end
    local msgLower = trim(string.lower(mensagem or ""))
    if msgLower == "adminoff" then
        if remetente == "Kahrrasco" then
            deactivateMonitor("[REMOTE OFF] monitor desligado por Kahrrasco", C.red)
        end
        return
    end
    local nome, ok, result = executarComandoAdmin(remetente, mensagem)
    if nome and (ok == false or result ~= false) then
        syncImperiumUiState()
        addLog("[CMD] " .. remetente .. ": " .. tostring(mensagem), C.accent)
        if not ok then
            addLog("  erro: " .. tostring(result), C.red)
            warn("[KAH][WARN][AdminCommands][" .. tostring(nome) .. "] " .. tostring(result))
        end
    end
end

-- ============================================
-- MINIMIZAR / FECHAR + DRAG
-- ============================================
do
    local minimizado = false
    local hCache     = H_FULL

    local function setMinimizado(v)
        minimizado = v
        if minimizado then
            hCache = frame.Size.Y.Offset
            frame.Size         = UDim2.new(0, getMinimizedWidth(), 0, H_HDR)
            statusBar.Visible  = false
            subTabBar.Visible  = false
            pageHolder.Visible = false
            minBtn.Text        = "A"
        else
            statusBar.Visible   = true
            subTabBar.Visible   = true
            pageHolder.Visible  = true
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

    -- DRAG
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
end
end -- end GUI do block

local registerAdminRows
local unregisterAdminRows
local registerPlayerRows
local resetAdminHubState

-- ============================================
-- REGISTRA NO HUB
-- ============================================
local function onToggle(ativo)
    if ativo then
        if registerAdminRows then
            registerAdminRows()
        end
        activateMonitor("[AUTO] Admin Commands ativado", C.green)
    else
        deactivateMonitor("[OFF] Efeitos cancelados", C.muted)
        if resetAdminHubState then
            resetAdminHubState()
        end
        if unregisterAdminRows then
            unregisterAdminRows()
        end
    end
end

local function setPanelAtivo(ativo)
    panelAtivo = (ativo == true)
    applyPanelVisibility()
    addLog(panelAtivo and "[PANEL] aberto" or "[PANEL] fechado", panelAtivo and C.green or C.muted)
    refreshPanelSummary()
end

local function setExecutarEmMim(ativo)
    EXECUTAR_EM_MIM = (ativo == true)
    addLog(EXECUTAR_EM_MIM and "[SELF] comandos proprios ON" or "[SELF] comandos proprios OFF", EXECUTAR_EM_MIM and C.green or C.muted)
    refreshAdminRowLabels()
    refreshPanelSummary()
end

local function ensureSelfExecutionForUntargetedChat()
    if commandTargetAtivo or EXECUTAR_EM_MIM then
        return
    end
    if _G.Hub then
        local ok, applied = pcall(function()
            return _G.Hub.setEstado(SELF_TOGGLE_NAME, true)
        end)
        if ok and applied == true then
            return
        end
    end
    setExecutarEmMim(true)
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

local function runLocalAdminAction(action)
    local ok, err = action()
    if ok == false then
        error(err or "Falha ao executar comando")
    end
end

local function normalizeChatSpellSpec(spellSpec)
    if type(spellSpec) == "function" then
        return normalizeChatSpellSpec(spellSpec())
    end
    if type(spellSpec) == "table" then
        return {
            text = tostring(spellSpec.text or spellSpec[1] or ""),
            appendTarget = spellSpec.appendTarget == true,
            explicitTarget = spellSpec.explicitTarget,
            appendAdTarget = spellSpec.appendAdTarget == true,
            explicitAdTarget = spellSpec.explicitAdTarget,
            extraArg = spellSpec.extraArg,
        }
    end
    return {
        text = tostring(spellSpec or ""),
        appendTarget = false,
    }
end

local function sendHubChatSpell(spellSpec)
    ensureSelfExecutionForUntargetedChat()
    local spec = normalizeChatSpellSpec(spellSpec)
    local mensagem = buildChatCommand(spec.text, spec)
    if not sendChatCommand(mensagem) then
        error("Falha ao enviar comando no chat")
    end
    addLog("[CHAT] " .. mensagem, C.accent)
end

local function setHubDisplayName(rawName, displayName)
    if _G.Hub and _G.Hub.setNomeVisual then
        pcall(function()
            _G.Hub.setNomeVisual(rawName, displayName)
        end)
    end
end

local function syncCommandUiStateFromLocal()
    commandUiState.leviosa = flyAtivo == true
    commandUiState.celeritas = celeritasAtivo == true
    commandUiState.transitus = noclipAtivo == true
    commandUiState.aegis = aegisAtivo == true
    commandUiState.portusClosed = teleportersHidden == true
    commandUiState.altus = altusAtivo == true
    commandUiState.impedimenta = impedAtivo == true
    commandUiState.imperium = getImperiumMode()
    refreshAdminRowLabels()
    refreshPanelSummary()
end

refreshAdminRowLabels = function()
    setHubDisplayName("Leviosa", commandUiState.leviosa and "Finite Leviosa" or "Leviosa")
    setHubDisplayName("Impero Orbitus", commandUiState.imperium == "orbit" and "Finite Orbitus" or "Impero Orbitus")
    setHubDisplayName("Impero Sequor", commandUiState.imperium == "follow" and "Finite Sequor" or "Impero Sequor")
    setHubDisplayName("Impero Caput", commandUiState.imperium == "head" and "Finite Caput" or "Impero Caput")
    setHubDisplayName("Impero Internus", commandUiState.imperium == "inside" and "Finite Internus" or "Impero Internus")
    setHubDisplayName("Impero Visus", commandUiState.imperium == "visus" and "Finite Visus" or "Impero Visus")
    setHubDisplayName("Celeritas", commandUiState.celeritas and "Finite Celeritas" or "Celeritas")
    setHubDisplayName("Transitus", commandUiState.transitus and "Colloportus" or "Transitus")
    setHubDisplayName("Aegis", commandUiState.aegis and "Finite Aegis" or "Aegis")
    setHubDisplayName("Portus Claudo", commandUiState.portusClosed and "Portus Aperio" or "Portus Claudo")
    setHubDisplayName("Impedimenta", commandUiState.impedimenta and "Liber Corpus" or "Impedimenta")
    setHubDisplayName("Polter Impello", commandUiState.polterImpello and "Revoco Polter Impello" or "Concedo Polter Impello")
end

local function makePairedSpellToggle(stateKey, spellOn, spellOff, localOn, localOff)
    return function(ativo)
        if commandChatAtivo then
            local anterior = commandUiState[stateKey]
            commandUiState[stateKey] = (ativo == true)
            refreshAdminRowLabels()
            local ok, err = pcall(sendHubChatSpell, (ativo == true) and spellOn or spellOff)
            if not ok then
                commandUiState[stateKey] = anterior
                refreshAdminRowLabels()
                error(err)
            end
            return
        end
        if ativo then
            runLocalAdminAction(localOn)
        else
            runLocalAdminAction(localOff)
        end
        syncCommandUiStateFromLocal()
    end
end

local function makePulseSpellAction(rowName, spellText, localAction)
    return pulseHubAction(rowName, function()
        if commandChatAtivo then
            sendHubChatSpell(spellText)
            return
        end
        runLocalAdminAction(localAction)
        syncCommandUiStateFromLocal()
    end)
end

local function makeToggleSpellAction(chatOnSpec, chatOffSpec, localOn, localOff)
    return function(ativo)
        if commandChatAtivo then
            sendHubChatSpell(ativo and chatOnSpec or chatOffSpec)
            return
        end
        if ativo then
            runLocalAdminAction(localOn)
        else
            runLocalAdminAction(localOff)
        end
        syncCommandUiStateFromLocal()
    end
end

local function buildImperoChatSpec(commandText, includeAdTarget)
    local explicitTarget = commandTargetAtivo and trim(commandTarget) or ""
    if explicitTarget == "" then
        explicitTarget = getChatSelfTarget()
    end
    return {
        text = commandText,
        appendTarget = true,
        explicitTarget = explicitTarget,
        appendAdTarget = includeAdTarget == true,
        explicitAdTarget = includeAdTarget and getImperoAdTarget() or nil,
    }
end

local function makeImperoToggle(modeKey, startMethod, stopMethod, startText, stopText)
    return function(ativo)
        if commandChatAtivo then
            local previousMode = commandUiState.imperium
            commandUiState.imperium = ativo and modeKey or ""
            refreshAdminRowLabels()
            local ok, err = pcall(sendHubChatSpell, buildImperoChatSpec(ativo and startText or stopText, ativo))
            if not ok then
                commandUiState.imperium = previousMode
                refreshAdminRowLabels()
                error(err)
            end
            return
        end
        local ok, err = callPlayerAction(ativo and startMethod or stopMethod, ativo and getImperoAdTarget() or nil)
        if ok == false then
            error(err)
        end
        syncImperiumUiState()
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

local function withAdminSubtab(subtabName, opts)
    local merged = {}
    if type(opts) == "table" then
        for key, value in pairs(opts) do
            merged[key] = value
        end
    end
    merged.subtab = subtabName
    return merged
end

local function withAdminPinned(opts)
    local merged = {}
    if type(opts) == "table" then
        for key, value in pairs(opts) do
            merged[key] = value
        end
    end
    merged.pinAboveSubtabs = true
    return merged
end

local function unregisterHubRow(nome)
    if _G.Hub and _G.Hub.remover then
        pcall(function() _G.Hub.remover(nome) end)
        return
    end
    if not _G.HubFila then
        return
    end
    for i = #_G.HubFila, 1, -1 do
        if _G.HubFila[i] and _G.HubFila[i].nome == nome then
            table.remove(_G.HubFila, i)
        end
    end
end

resetAdminHubState = function()
    setPanelAtivo(false)
    setExecutarEmMim(false)
    syncCommandUiStateFromLocal()
end

registerPlayerRows = function()
    registrarNoHub("Speed", function(ativo)
        speedAtivo = (ativo == true)
        saveMovementCfg()
        applySpeedState()
    end, PLAYER_CATEGORY, speedAtivo, {
        inlineNumber = {
            get = function() return speedValue end,
            set = function(v)
                speedValue = math.clamp(math.floor(tonumber(v) or speedValue), 0, 500)
                saveMovementCfg()
                applySpeedState()
            end,
            min = 0, max = 500,
        }
    })

    registrarNoHub("Infinite Jump", function(ativo)
        infiniteJumpAtivo = (ativo == true)
        saveMovementCfg()
    end, PLAYER_CATEGORY, infiniteJumpAtivo)
end

registerAdminRows = function()
    if not SHOW_ADMIN_UI or adminRowsRegistered then
        return
    end
    adminRowsRegistered = true
    unregisterHubRow(PANEL_TOGGLE_NAME)
    commandUiState.imperium = getImperiumMode()

    registrarNoHub(SELF_TOGGLE_NAME, function(ativo)
        setExecutarEmMim(ativo)
    end, CATEGORIA, false, withAdminPinned())

    registrarNoHub("Send Commands To Chat", function(ativo)
        commandChatAtivo = (ativo == true)
        saveAdminCommandCfg()
        if not commandChatAtivo then
            commandUiState.polterImpello = false
            if _G.Hub then
                pcall(function() _G.Hub.setEstado("Polter Impello", false) end)
            end
            syncCommandUiStateFromLocal()
        else
            refreshPanelSummary()
        end
    end, CATEGORIA, commandChatAtivo, withAdminPinned())

    registrarNoHub("Command Target", function(ativo)
        commandTargetAtivo = (ativo == true)
        saveAdminCommandCfg()
        refreshPanelSummary()
    end, CATEGORIA, commandTargetAtivo, withAdminPinned({
        inlineDropdown = {
            toggle = true,
            get = function() return commandTarget end,
            set = function(v)
                commandTarget = trim(v)
                saveAdminCommandCfg()
                refreshPanelSummary()
            end,
            getOptions = getCommandTargetOptions,
            placeholder = "Todos",
            emptyText = "Sem players",
        }
    }))

    registrarNoHub("Impero ad Target", function(ativo)
        imperoTargetAtivo = (ativo == true)
        saveAdminCommandCfg()
        refreshPanelSummary()
    end, CATEGORIA, imperoTargetAtivo, withAdminPinned({
        inlineDropdown = {
            toggle = true,
            get = function() return imperoTarget end,
            set = function(v)
                imperoTarget = trim(v)
                saveAdminCommandCfg()
                refreshPanelSummary()
            end,
            getOptions = getCommandTargetOptions,
            placeholder = DEFAULT_IMPERO_TARGET,
            emptyText = "Sem players",
        }
    }))

    registrarNoHub("Impero Orbitus", makeImperoToggle(
        "orbit",
        "imperoOrbitus",
        "finiteOrbitus",
        "Impero Orbitus",
        "Finite Orbitus"
    ), CATEGORIA, commandUiState.imperium == "orbit", withAdminSubtab("Impero"))

    registrarNoHub("Impero Sequor", makeImperoToggle(
        "follow",
        "imperoSequor",
        "finiteSequor",
        "Impero Sequor",
        "Finite Sequor"
    ), CATEGORIA, commandUiState.imperium == "follow", withAdminSubtab("Impero"))

    registrarNoHub("Impero Caput", makeImperoToggle(
        "head",
        "imperoCaput",
        "finiteCaput",
        "Impero Caput",
        "Finite Caput"
    ), CATEGORIA, commandUiState.imperium == "head", withAdminSubtab("Impero"))

    registrarNoHub("Impero Internus", makeImperoToggle(
        "inside",
        "imperoInternus",
        "finiteInternus",
        "Impero Internus",
        "Finite Internus"
    ), CATEGORIA, commandUiState.imperium == "inside", withAdminSubtab("Impero"))

    registrarNoHub("Impero Visus", makeImperoToggle(
        "visus",
        "imperoVisus",
        "finiteVisus",
        "Impero Visus",
        "Finite Visus"
    ), CATEGORIA, commandUiState.imperium == "visus", withAdminSubtab("Impero"))

    registrarNoHub("Finite Imperium", pulseHubAction("Finite Imperium", function()
        if commandChatAtivo then
            local previousMode = commandUiState.imperium
            commandUiState.imperium = ""
            refreshAdminRowLabels()
            local ok, err = pcall(sendHubChatSpell, buildImperoChatSpec("Finite Imperium", false))
            if not ok then
                commandUiState.imperium = previousMode
                refreshAdminRowLabels()
                error(err)
            end
            return
        end
        local ok, err = callPlayerAction("finiteImperium")
        if ok == false then
            error(err)
        end
        syncImperiumUiState()
    end), CATEGORIA, false, withAdminSubtab("Impero"))

    registrarNoHub("Accio Servus", makePulseSpellAction("Accio Servus", function()
        return {
            text = "Accio Servus",
            appendTarget = true,
        }
    end, function()
        return accio()
    end), CATEGORIA, false, withAdminSubtab("Spells"))

    registrarNoHub("Appareo", makePulseSpellAction("Appareo", function()
        return {
            text = "Appareo",
            appendTarget = true,
        }
    end, function()
        local alvo = commandTargetAtivo and trim(commandTarget) or ""
        if alvo == "" then
            return false, "Appareo sem alvo ativo"
        end
        return apparate(alvo)
    end), CATEGORIA, false, withAdminSubtab("Spells"))

    registrarNoHub("Polter Impello", function(ativo)
        if not commandChatAtivo then
            commandUiState.polterImpello = false
            refreshAdminRowLabels()
            refreshPanelSummary()
            if ativo and _G.Hub then
                task.defer(function()
                    pcall(function() _G.Hub.setEstado("Polter Impello", false) end)
                end)
            end
            if not ativo then
                return
            end
            error("Ative Send Commands To Chat para usar Polter Impello")
        end
        local previous = commandUiState.polterImpello
        commandUiState.polterImpello = (ativo == true)
        refreshAdminRowLabels()
        refreshPanelSummary()
        local ok, err = pcall(sendHubChatSpell, {
            text = (ativo == true) and "Concedo Polter Impello" or "Revoco Polter Impello",
            appendTarget = true,
        })
        if not ok then
            commandUiState.polterImpello = previous
            refreshAdminRowLabels()
            refreshPanelSummary()
            error(err)
        end
    end, CATEGORIA, false, withAdminSubtab("Access", {
        statusProvider = function()
            return getPolterImpelloStatus()
        end,
    }))

    registrarNoHub("Spectro Haunt", makePairedSpellToggle("spectroHaunt",
        function()
            return {
                text = "Concedo Spectro Haunt",
                appendTarget = true,
            }
        end,
        function()
            return {
                text = "Revoco Spectro Haunt",
                appendTarget = true,
            }
        end,
        function()
            setSpectroHauntAtivo(true)
            commandUiState.spectroHaunt = isSpectroHauntAtivo()
            return true
        end,
        function()
            setSpectroHauntAtivo(false)
            commandUiState.spectroHaunt = isSpectroHauntAtivo()
            return true
        end
    ), CATEGORIA, commandUiState.spectroHaunt, withAdminSubtab("Access", {
        statusProvider = function()
            return isSpectroHauntAtivo() and "GRANTED" or "BLOCKED"
        end,
    }))

    registrarNoHub("Leviosa", makePairedSpellToggle("leviosa",
        "Leviosa",
        "Finite Leviosa",
        function()
            wingardium()
            return true
        end,
        function()
            nox()
            return true
        end
    ), CATEGORIA, commandUiState.leviosa, withAdminSubtab("Spells"))

    registrarNoHub("Protego", makeToggleSpellAction(
        "Protego",
        "Protego",
        function()
            setProtegoAtivo(true)
            return true
        end,
        function()
            setProtegoAtivo(false)
            return true
        end
    ), CATEGORIA, isProtegoAtivo(), withAdminSubtab("Spells"))

    registrarNoHub("Transitus", makePairedSpellToggle("transitus",
        "Transitus",
        "Colloportus",
        function()
            alohomora()
            return true
        end,
        function()
            colloportus()
            return true
        end
    ), CATEGORIA, commandUiState.transitus, withAdminSubtab("Spells"))

    registrarNoHub("Sanatio", makePulseSpellAction("Sanatio", "Sanatio", function()
        setSanatioAtivo(true)
        return true
    end), CATEGORIA, false, withAdminSubtab("Spells"))

    registrarNoHub("Aegis", makePairedSpellToggle("aegis",
        "Aegis",
        "Finite Aegis",
        function()
            setAegisAtivo(true)
            return true
        end,
        function()
            setAegisAtivo(false)
            return true
        end
    ), CATEGORIA, commandUiState.aegis, withAdminSubtab("Spells"))

    registrarNoHub("Portus Claudo", makePairedSpellToggle("portusClosed",
        "Portus Claudo",
        "Portus Aperio",
        function()
            return setTeleportersHidden(true)
        end,
        function()
            return setTeleportersHidden(false)
        end
    ), CATEGORIA, commandUiState.portusClosed, withAdminSubtab("Spells", {
        statusProvider = function()
            return commandUiState.portusClosed and "CLOSED" or "OPEN"
        end,
    }))

    registrarNoHub("Celeritas", makePairedSpellToggle("celeritas",
        function()
            return {
                text = "Celeritas",
                appendTarget = true,
            }
        end,
        "Finite Celeritas",
        function()
            setCeleritasAtivo(true)
            return true
        end,
        function()
            setCeleritasAtivo(false)
            return true
        end
    ), CATEGORIA, commandUiState.celeritas, withAdminSubtab("Spells", {
        statusProvider = function()
            return commandUiState.celeritas and "FAST" or "OFF"
        end,
    }))

    registrarNoHub("Impedimenta", makePairedSpellToggle("impedimenta",
        "Impedimenta",
        "Liber Corpus",
        function()
            impedimenta()
            return true
        end,
        function()
            liberacorpus()
            return true
        end
    ), CATEGORIA, commandUiState.impedimenta, withAdminSubtab("Spells"))

    registrarNoHub("Finite Incantatem", makePulseSpellAction("Finite Incantatem", "Finite Incantatem", function()
        finiteIncantatem()
        return true
    end), CATEGORIA, false, withAdminSubtab("Spells"))

    syncCommandUiStateFromLocal()
    if _G.Hub then
        pcall(function() _G.Hub.setEstado("Send Commands To Chat", commandChatAtivo) end)
    end
    refreshAdminRowLabels()
end

unregisterAdminRows = function()
    adminRowsRegistered = false
    unregisterHubRow(PANEL_TOGGLE_NAME)
    for _, nome in ipairs(ADMIN_ROW_NAMES) do
        unregisterHubRow(nome)
    end
end

for _, nome in ipairs(PLAYER_ROW_NAMES) do
    unregisterHubRow(nome)
end
registerPlayerRows()

if SHOW_ADMIN_UI then
    unregisterAdminRows()
    unregisterHubRow(MODULE_NAME)
    registerAdminRows()
end
activateMonitor(nil, nil)

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
        finiteIncantatem()
        resetAdminHubState()
        unregisterAdminRows()
        unregisterHubRow(MODULE_NAME)
        for _, nome in ipairs(PLAYER_ROW_NAMES) do
            unregisterHubRow(nome)
        end
        if jumpRequestConn then
            jumpRequestConn:Disconnect()
            jumpRequestConn = nil
        end
        if movementCharConn then
            movementCharConn:Disconnect()
            movementCharConn = nil
        end
        if flyMobileGui and flyMobileGui.Parent then
            flyMobileGui:Destroy()
            flyMobileGui = nil
        end
        flyDownBtn = nil
    end,
}
