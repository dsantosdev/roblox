-- ============================================================
--  STRONGHOLD AUTO - Xeno Executor
--  VersÃƒÆ’Ã‚Â£o 2 - Passo a Passo + Anti-Lag
-- ============================================================

-- ============================================================
-- POSIÃƒÆ’Ã¢â‚¬Â¡ÃƒÆ’Ã¢â‚¬Â¢ES (extraÃƒÆ’Ã‚Â­das do relatÃƒÆ’Ã‚Â³rio do servidor)
--
-- EntryDoors (porta externa):
--   DoorRight: X=-60,   Y=13.94, Z=-622.4
--   DoorLeft:  X=-71,   Y=13.94, Z=-622.4
--   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Frente da porta (fora):  X=-65.5, Y=15, Z=-612
--
-- LockedDoorsFloor1 (1Ãƒâ€šÃ‚Â° andar):
--   DoorRight: X=0.3,  Y=13.94, Z=-656.1
--   DoorLeft:  X=-7.5, Y=13.94, Z=-663.9
--   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Chegada (fora): X=-3.6, Y=15, Z=-648
--
-- LockedDoorsFloor2 (2Ãƒâ€šÃ‚Â° andar):
--   DoorRight: X=-79.7, Y=42.64, Z=-664
--   DoorLeft:  X=-79.7, Y=42.64, Z=-653
--   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Chegada (fora): X=-68, Y=44, Z=-658.5
--
-- FinalGate:  X=-2.08, Y=56.94, Z=-643
-- ============================================================

local VERSION   = "1.1.0"
local CATEGORIA = "World"
local MODULE_NAME = "Stronghold"
local MODULE_STATE_KEY = "__stronghold_module_state"

if not _G.Hub and not _G.HubFila then
    print('>>> stronghold: hub nao encontrado, abortando')
    return
end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local HS         = game:GetService("HttpService")

local lp = Players.LocalPlayer
local localUserId = tostring(lp.UserId)

do
    local oldState = _G[MODULE_STATE_KEY]
    if oldState then
        if oldState.cleanup then pcall(oldState.cleanup) end
        if oldState.gui and oldState.gui.Parent then
            pcall(function() oldState.gui:Destroy() end)
        end
    end
    _G[MODULE_STATE_KEY] = nil
end

-- ============================================================
-- ESTADO
-- ============================================================
local timerActive      = false
local timerEnd         = 0
local uiDestroyed      = false
local connections      = {}
local threads          = {}
local chatEnviado      = false   -- evita mandar chat 2x
local fortalezaFinalizada = false -- true apÃƒÆ’Ã‚Â³s baÃƒÆ’Ã‚Âºs abertos (pula passos jÃƒÆ’Ã‚Â¡ feitos)
local finalGateRefPos  = nil
local finalGateRefSet  = false
local finalGateLastDiff = 0
local finalGateLastMode = ""

local DEBUG_LOG_KEY = "__kah_stronghold_log"
local debugLines = {}
local MAX_DEBUG_LINES = 140

local function fmtVec3(v)
    if not v then return "nil" end
    return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local function pushDebugLog(msg)
    local line = os.date("%H:%M:%S") .. " | " .. tostring(msg)
    print(">>> stronghold: " .. line)
    table.insert(debugLines, line)
    if #debugLines > MAX_DEBUG_LINES then
        table.remove(debugLines, 1)
    end

    local dump = table.concat(debugLines, "\n")
    _G[DEBUG_LOG_KEY] = dump
    if setclipboard then
        pcall(setclipboard, dump)
    end
end

-- Checa se fortaleza estÃƒÆ’Ã‚Â¡ "em andamento mas nÃƒÆ’Ã‚Â£o finalizada"
-- (entrada aberta = jÃƒÆ’Ã‚Â¡ entrou, mas ainda nÃƒÆ’Ã‚Â£o finalizou)
local function fortalezaAberta()
    local ed
    pcall(function() ed = workspace.Map.Landmarks.Stronghold.Functional.EntryDoors end)
    if not ed then return false end
    return ed:GetAttribute("DoorOpen") == true
end

-- ============================================================
-- PATHFINDER COM MEMÃƒÆ’Ã¢â‚¬Å“RIA
-- Explora em direÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o ao destino, detecta travamento por parede,
-- grava waypoints que funcionaram. Na prÃƒÆ’Ã‚Â³xima run usa a rota
-- gravada direto, sem explorar.
-- ============================================================
local learnedRoute = nil  -- nil = ainda nÃƒÆ’Ã‚Â£o aprendeu, tabela = rota gravada

-- DistÃƒÆ’Ã‚Â¢ncia 2D (ignora Y) entre dois Vector3
local function dist2D(a, b)
    return math.sqrt((a.X - b.X)^2 + (a.Z - b.Z)^2)
end

-- Verifica se o player realmente se moveu (nÃƒÆ’Ã‚Â£o preso em parede)
local function playerMoved(root, fromPos, minDist)
    minDist = minDist or 1.5
    return dist2D(root.Position, fromPos) >= minDist
end

-- Executa a rota gravada (waypoints conhecidos)
local function followLearnedRoute(setStatus)
    local char = lp.Character
    if not char then return false end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return false end

    setStatus("ÃƒÂ°Ã…Â¸Ã¢â‚¬â€Ã‚Âº  Usando rota memorizada...", Color3.fromRGB(120,220,255))
    for i, wp in ipairs(learnedRoute) do
        setStatus(string.format("ÃƒÂ°Ã…Â¸Ã¢â‚¬â€Ã‚Âº  Waypoint %d/%d...", i, #learnedRoute), Color3.fromRGB(120,220,255))
        hum:MoveTo(wp)
        -- espera chegar ou timeout proporcional ÃƒÆ’Ã‚Â  distÃƒÆ’Ã‚Â¢ncia
        local speed = hum.WalkSpeed > 0 and hum.WalkSpeed or 16
        local d     = dist2D(root.Position, wp)
        local tmax  = (d / speed) * 1.8 + 2
        local t     = 0
        local arrived = false
        local conn = hum.MoveToFinished:Connect(function() arrived = true end)
        while not arrived and t < tmax do task.wait(0.1); t += 0.1 end
        conn:Disconnect()
    end
    return true
end

-- ExploraÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o com aprendizado:
-- Move em direÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o ao alvo usando pequenos passos.
-- Se travar, tenta desvios laterais.
-- Grava todos os waypoints que avanÃƒÆ’Ã‚Â§aram de verdade.
-- Ao chegar, poda a rota (remove pontos redundantes) e salva.
local function exploreToTarget(setStatus, startPos, targetPos)
    local char = lp.Character
    if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    local STEP       = 5     -- studs por passo (menor = mais preciso)
    local STUCK_TIME = 0.4   -- segundos sem mover = preso (mais rÃƒÆ’Ã‚Â¡pido)
    local MAX_TRIES  = 200   -- iteraÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Âµes mÃƒÆ’Ã‚Â¡ximas
    local GOAL_DIST  = 4     -- studs para considerar chegou

    local walkY      = (startPos and startPos.Y) or root.Position.Y
    local waypoints  = { startPos }  -- pontos que realmente avanÃƒÆ’Ã‚Â§aram
    local tries      = 0

    -- DireÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Âµes de desvio quando preso: direita, esquerda, trÃƒÆ’Ã‚Â¡s+direita, trÃƒÆ’Ã‚Â¡s+esquerda
    local function desvios(dir)
        return {
            Vector3.new( dir.Z, 0, -dir.X),   -- 90Ãƒâ€šÃ‚Â° direita
            Vector3.new(-dir.Z, 0,  dir.X),   -- 90Ãƒâ€šÃ‚Â° esquerda
            Vector3.new( dir.Z, 0,  dir.X),   -- diagonal direita-frente
            Vector3.new(-dir.Z, 0, -dir.X),   -- diagonal esquerda-frente
        }
    end

    setStatus("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â Explorando rota (1Ãƒâ€šÃ‚Âª vez)...", Color3.fromRGB(255,200,80))

    while dist2D(root.Position, targetPos) > GOAL_DIST and tries < MAX_TRIES do
        tries += 1
        local curPos = root.Position
        local toTarget = (Vector3.new(targetPos.X, curPos.Y, targetPos.Z) - curPos)
        local dirNorm  = toTarget.Magnitude > 0 and toTarget.Unit or Vector3.new(0,0,-1)

        -- Tenta mover em direÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o ao alvo
        local nextPos = curPos + dirNorm * STEP
        nextPos = Vector3.new(nextPos.X, walkY, nextPos.Z)
        hum:MoveTo(nextPos)
        task.wait(STUCK_TIME)

        if playerMoved(root, curPos, 1.5) then
            -- AvanÃƒÆ’Ã‚Â§ou: grava waypoint
            local last = waypoints[#waypoints]
            if dist2D(root.Position, last) > 3 then
                table.insert(waypoints, root.Position)
            end
        else
            -- Preso: tenta desvios
            local moved = false
            for _, d in ipairs(desvios(dirNorm)) do
                local alt = curPos + d * STEP
                alt = Vector3.new(alt.X, walkY, alt.Z)
                hum:MoveTo(alt)
                task.wait(STUCK_TIME)
                if playerMoved(root, curPos, 1.5) then
                    local last = waypoints[#waypoints]
                    if dist2D(root.Position, last) > 3 then
                        table.insert(waypoints, root.Position)
                    end
                    moved = true
                    break
                end
            end
            if not moved then
                -- completamente preso, tenta pular e continuar
                hum.Jump = true
                task.wait(0.5)
            end
        end
    end

    -- Chegou ao destino: adiciona ponto final
    table.insert(waypoints, Vector3.new(targetPos.X, targetPos.Y, targetPos.Z))

    -- Poda rota: remove waypoints intermediÃƒÆ’Ã‚Â¡rios que estÃƒÆ’Ã‚Â£o na mesma linha reta
    -- (se AÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢BÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢C sÃƒÆ’Ã‚Â£o colineares, remove B)
    local function colinear(a, b, c, thresh)
        thresh = thresh or 2.5
        -- distÃƒÆ’Ã‚Â¢ncia do ponto B ÃƒÆ’Ã‚Â  linha AÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢C
        local ac = Vector3.new(c.X - a.X, 0, c.Z - a.Z)
        local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
        if ac.Magnitude < 0.01 then return true end
        local cross = math.abs(ac.X * ab.Z - ac.Z * ab.X) / ac.Magnitude
        return cross < thresh
    end

    local pruned = { waypoints[1] }
    local i = 2
    while i <= #waypoints - 1 do
        if not colinear(pruned[#pruned], waypoints[i], waypoints[i+1]) then
            table.insert(pruned, waypoints[i])
        end
        i += 1
    end
    table.insert(pruned, waypoints[#waypoints])

    learnedRoute = pruned
    setStatus(string.format("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Rota aprendida! %d waypoints.", #pruned), Color3.fromRGB(80,255,120))
    task.wait(0.5)
end

-- Fallbacks usados quando o mapa ainda nao carregou ou o caminho da porta muda.
local FALLBACK_ENTRY_FRONT = Vector3.new(-65.5, 15, -612)
local FALLBACK_ROUTE_START = Vector3.new(-65.5, 15, -616)
local FALLBACK_ROUTE_TARGET = Vector3.new(-3.6, 15, -644)
local FALLBACK_FLOOR2_FRONT = Vector3.new(-68, 44, -658.5)

-- ============================================================
-- LIMPEZA TOTAL
-- ============================================================
local function stopExecution()
    timerActive = false
    for _, t in ipairs(threads) do pcall(function() task.cancel(t) end) end
    threads = {}
end

local function cleanup()
    stopExecution()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
end

-- ============================================================
-- TELEPORTE
-- ============================================================
local function tpTo(pos)
    local char = lp.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    root.CFrame = CFrame.new(pos)
    task.wait(0.25)
end

-- ============================================================
-- ANDAR com espera real por chegada (MoveToFinished)
-- timeout: segundos mÃƒÆ’Ã‚Â¡ximos antes de desistir (evita travar)
-- ============================================================
local function moveToAndWait(targetPos, timeout)
    local char = lp.Character
    if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    timeout = timeout or 15
    local arrived = false

    -- calcula distÃƒÆ’Ã‚Â¢ncia e estima tempo mÃƒÆ’Ã‚Â­nimo pela velocidade real
    local speed = hum.WalkSpeed > 0 and hum.WalkSpeed or 16
    local dist  = (targetPos - root.Position).Magnitude
    local estSecs = (dist / speed) + 1.5  -- +1.5s de margem

    hum:MoveTo(targetPos)

    -- Aguarda MoveToFinished OU timeout (o que vier primeiro)
    local conn
    conn = hum.MoveToFinished:Connect(function(reached)
        arrived = true
    end)

    local elapsed = 0
    local maxWait = math.max(estSecs, timeout)
    while not arrived and elapsed < maxWait do
        task.wait(0.1)
        elapsed += 0.1
    end
    conn:Disconnect()
end

-- walkTo mantido como alias para compatibilidade
local function walkTo(targetPos, duration)
    moveToAndWait(targetPos, duration or 10)
end

-- Pequeno impulso inicial para destravar colisÃƒÆ’Ã‚Â£o/corpo antes do pathfinder.
-- Faz um pulo e anda para frente por alguns segundos.
local function jumpAndWalkForward(seconds)
    local char = lp.Character
    if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    local secs = math.max(0, tonumber(seconds) or 1)
    hum.Jump = true
    task.wait(0.2)

    local deadline = os.clock() + secs
    while os.clock() < deadline do
        root = char:FindFirstChild("HumanoidRootPart")
        if not root then break end

        local dir = root.CFrame.LookVector
        local flat = Vector3.new(dir.X, 0, dir.Z)
        if flat.Magnitude < 0.01 then
            flat = Vector3.new(0, 0, -1)
        else
            flat = flat.Unit
        end

        hum:Move(flat, false)
        RunService.Heartbeat:Wait()
    end
    hum:Move(Vector3.new(0, 0, 0), false)
end

-- ============================================================
-- CHAT - 3 mÃƒÆ’Ã‚Â©todos em sequÃƒÆ’Ã‚Âªncia (TextChatService ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Legacy ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Bubble)
-- ============================================================
local function sendChat(msg)
    -- MÃƒÆ’Ã‚Â©todo 1: TextChatService (novo sistema Roblox)
    local ok1 = pcall(function()
        local tcs  = game:GetService("TextChatService")
        local chan  = tcs:FindFirstChild("TextChannels")
        local geral = chan and (chan:FindFirstChild("RBXGeneral") or chan:FindFirstChild("General"))
        if geral and geral.SendAsync then
            geral:SendAsync(msg)
        end
    end)
    task.wait(0.1)
    -- MÃƒÆ’Ã‚Â©todo 2: Legacy SayMessageRequest
    if not ok1 then
        pcall(function()
            local r   = game:GetService("ReplicatedStorage")
            local d   = r:FindFirstChild("DefaultChatSystemChatEvents")
            local say = d and d:FindFirstChild("SayMessageRequest")
            if say then say:FireServer(msg, "All") end
        end)
        task.wait(0.1)
    end
    -- MÃƒÆ’Ã‚Â©todo 3: Bubble chat local (fallback garantido)
    pcall(function()
        local ChatSvc = game:GetService("Chat")
        local head    = lp.Character and lp.Character:FindFirstChild("Head")
        if head then ChatSvc:Chat(head, msg, Enum.ChatColor.White) end
    end)
end

-- ============================================================
-- FIRE PROXIMITY PROMPT
-- ============================================================
local function firePrompt(pp)
    if pp then pcall(function() fireproximityprompt(pp) end) end
end

-- ============================================================
-- NAVEGA PATH NO WORKSPACE
-- ============================================================
local function getByPath(...)
    local cur = workspace
    for _, name in ipairs({...}) do
        cur = cur:FindFirstChild(name)
        if not cur then return nil end
    end
    return cur
end

local DOOR_PATHS = {
    entry = {
        right = {"Map","Landmarks","Stronghold","Functional","EntryDoors","DoorRight","Main"},
        left  = {"Map","Landmarks","Stronghold","Functional","EntryDoors","DoorLeft","Main"},
    },
    floor1 = {
        right = {"Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor1","DoorRight","Main"},
        left  = {"Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor1","DoorLeft","Main"},
    },
    floor2 = {
        right = {"Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor2","DoorRight","Main"},
        left  = {"Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor2","DoorLeft","Main"},
    },
}

local function asBasePart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    return obj:FindFirstChildWhichIsA("BasePart")
end

local function getDoorPair(kind)
    local def = DOOR_PATHS[kind]
    if not def then return nil, nil end
    local right = asBasePart(getByPath(table.unpack(def.right)))
    local left  = asBasePart(getByPath(table.unpack(def.left)))
    return right, left
end

local function getDoorCenter(kind)
    local right, left = getDoorPair(kind)
    if right and left then
        return (right.Position + left.Position) * 0.5
    end
    local one = right or left
    return one and one.Position or nil
end

local function doorsReady()
    local er, el = getDoorPair("entry")
    local f1r, f1l = getDoorPair("floor1")
    local f2r, f2l = getDoorPair("floor2")
    return (er or el) and (f1r or f1l) and (f2r or f2l)
end

local function flatLook(part)
    if not part then return nil end
    local lv = part.CFrame.LookVector
    local v = Vector3.new(lv.X, 0, lv.Z)
    if v.Magnitude < 0.01 then return nil end
    return v.Unit
end

local function frontFromDoorPair(kind, forwardDist, yOffset, fallback, refPos, preferFar)
    local right, left = getDoorPair(kind)
    if not right and not left then
        return fallback
    end

    local center
    if right and left then
        center = (right.Position + left.Position) * 0.5
    else
        center = (right or left).Position
    end

    local forward
    if right and left then
        local fr = flatLook(right)
        local fl = flatLook(left)
        local sum = Vector3.new(0, 0, 0)
        if fr then sum += fr end
        if fl then sum += fl end
        if sum.Magnitude >= 0.01 then
            forward = sum.Unit
        end
    end
    if not forward then
        forward = flatLook(right or left)
    end
    if not forward then
        return fallback
    end

    local up = Vector3.new(0, yOffset or 1, 0)
    local a = center + (forward * forwardDist) + up
    local b = center - (forward * forwardDist) + up

    if refPos then
        local da = (a - refPos).Magnitude
        local db = (b - refPos).Magnitude
        if preferFar then
            return (da >= db) and a or b
        end
        return (da <= db) and a or b
    end
    return a
end

local function resolveStrongholdPoints()
    local deadline = os.clock() + 2.5
    while os.clock() < deadline and not doorsReady() do
        task.wait(0.15)
    end

    local floor1Center = getDoorCenter("floor1") or FALLBACK_ROUTE_TARGET
    local entryCenter = getDoorCenter("entry") or FALLBACK_ROUTE_START

    -- Entry side must be outside, so choose the side farthest from floor1.
    local entryFront = frontFromDoorPair("entry", 10.0, 1.0, FALLBACK_ENTRY_FRONT, floor1Center, true)
    local routeStart = frontFromDoorPair("entry", 6.4, 1.0, FALLBACK_ROUTE_START, floor1Center, true)

    -- Floor1 side should face the entry path, so choose nearest to entry center.
    local routeTarget = frontFromDoorPair("floor1", 16.0, 1.0, FALLBACK_ROUTE_TARGET, entryCenter, false)

    -- Floor2 side should face the path coming from floor1.
    local floor2Front = frontFromDoorPair("floor2", 11.5, 1.0, FALLBACK_FLOOR2_FRONT, routeTarget, false)

    pushDebugLog("points entry=" .. fmtVec3(entryFront) .. " start=" .. fmtVec3(routeStart) .. " target=" .. fmtVec3(routeTarget) .. " floor2=" .. fmtVec3(floor2Front))
    return {
        entryFront = entryFront,
        routeStart = routeStart,
        routeTarget = routeTarget,
        floor2Front = floor2Front,
    }
end

-- ============================================================
-- ESTADO DA ENTRADA:
--   "ready"    ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ DoorOpen=false + Interaction="Door" + nÃƒÆ’Ã‚Â£o DoorLocked
--   "cooldown" ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ DoorOpen=false + sem Interaction  (entre runs)
--   "open"     ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ DoorOpen=true  (jÃƒÆ’Ã‚Â¡ aberta nesta run)
-- ============================================================
local function entryState()
    local ed
    pcall(function() ed = workspace.Map.Landmarks.Stronghold.Functional.EntryDoors end)
    if not ed then return "cooldown" end
    local isOpen      = ed:GetAttribute("DoorOpen")
    local isLocked    = ed:GetAttribute("DoorLocked") or ed:GetAttribute("DoorLockedClient")
    local interaction = ed:GetAttribute("Interaction")  -- presente sÃƒÆ’Ã‚Â³ quando disponÃƒÆ’Ã‚Â­vel
    if isOpen == true  then return "open" end
    if isLocked        then return "cooldown" end
    if interaction == "Door" then return "ready" end
    -- sem Interaction = em cooldown/aguardando reset do servidor
    return "cooldown"
end

local function isEntryReady()
    return entryState() == "ready"
end

local function resetFinalGateProbe()
    finalGateRefPos = nil
    finalGateRefSet = false
    finalGateLastDiff = 0
    finalGateLastMode = ""
end

local function getGatePosition(gate)
    if not gate then return nil end
    if gate:IsA("Model") then
        local ok, pivot = pcall(function() return gate:GetPivot() end)
        if ok and pivot then
            return pivot.Position
        end
    end
    if gate:IsA("BasePart") then
        return gate.Position
    end
    local part = gate:FindFirstChildWhichIsA("BasePart")
        or gate:FindFirstChildWhichIsA("UnionOperation")
        or gate:FindFirstChildWhichIsA("MeshPart")
    return part and part.Position or nil
end

-- ============================================================
-- VERIFICA 3A PORTA
-- ============================================================
local function isFloor3Open()
    local gate
    pcall(function()
        gate = workspace.Map.Landmarks.Stronghold.Functional.FinalGate
    end)
    if not gate then return false end

    local gatePos = getGatePosition(gate)
    if not gatePos then return false end

    local origCF = gate:GetAttribute("OriginalCF")
    if typeof(origCF) == "CFrame" then
        finalGateRefPos = origCF.Position
        finalGateRefSet = true
        local diff = (gatePos - origCF.Position).Magnitude
        finalGateLastDiff = diff
        finalGateLastMode = "origCF"
        return diff > 8
    end

    if not finalGateRefSet or not finalGateRefPos then
        finalGateRefPos = gatePos
        finalGateRefSet = true
        finalGateLastDiff = 0
        finalGateLastMode = "captured"
        return false
    end

    local diff = (gatePos - finalGateRefPos).Magnitude
    finalGateLastDiff = diff
    finalGateLastMode = "localRef"
    return diff > 8
end

local function waitUntilFloor3OpenStable(checkEverySec, hitsNeeded, timeoutSec)
    local interval = tonumber(checkEverySec) or 1
    local need = tonumber(hitsNeeded) or 2
    local hits = 0
    local startedAt = os.clock()
    pushDebugLog("gate wait started")
    while hits < need do
        task.wait(interval)
        if isFloor3Open() then
            hits += 1
            pushDebugLog(string.format("gate signal %d/%d mode=%s diff=%.2f", hits, need, tostring(finalGateLastMode), tonumber(finalGateLastDiff) or 0))
        else
            hits = 0
        end
        if timeoutSec and (os.clock() - startedAt) >= timeoutSec then
            pushDebugLog("gate wait timeout")
            return false
        end
    end
    pushDebugLog("gate wait opened")
    return true
end
-- ABRE BAÃƒÆ’Ã…Â¡S
-- ============================================================
local function openChestByName(name)
    local chest = workspace.Items:FindFirstChild(name, true)
        or workspace:FindFirstChild(name, true)
    if not chest then return end
    local bp = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart")
    if bp then tpTo(bp.Position + Vector3.new(4, 2, 0)) end
    task.wait(0.4)
    local pp = chest:FindFirstChildOfClass("ProximityPrompt", true)
    if pp then firePrompt(pp) end
end

local function openNearestChest()
    local diamond = workspace.Items:FindFirstChild("Stronghold Diamond Chest", true)
        or workspace:FindFirstChild("Stronghold Diamond Chest", true)
    if not diamond then return end
    local origin = (diamond.PrimaryPart or diamond:FindFirstChildWhichIsA("BasePart")).Position
    local best, bestDist = nil, math.huge
    for _, item in ipairs(workspace.Items:GetDescendants()) do
        if item:IsA("ProximityPrompt") then
            local root = item.Parent and item.Parent.Parent
            if root and root ~= diamond and root:GetAttribute("Interaction") == "ItemChest" then
                local bp = item.Parent:IsA("BasePart") and item.Parent
                    or item.Parent:FindFirstChildWhichIsA("BasePart")
                if bp then
                    local d = (bp.Position - origin).Magnitude
                    if d < bestDist and d < 60 then bestDist = d; best = item end
                end
            end
        end
    end
    if best then
        local bp = best.Parent:IsA("BasePart") and best.Parent or best.Parent:FindFirstChildWhichIsA("BasePart")
        if bp then tpTo(bp.Position + Vector3.new(4, 2, 0)) end
        task.wait(0.4)
        firePrompt(best)
    end
end

local function getChestModelByName(name)
    local found = workspace.Items:FindFirstChild(name, true)
        or workspace:FindFirstChild(name, true)
    if not found then return nil end

    local cur = found
    while cur and cur ~= workspace do
        if cur:IsA("Model") then
            return cur
        end
        cur = cur.Parent
    end
    return nil
end

local function isChestOpened(chestModel)
    if not chestModel then return false end
    return chestModel:GetAttribute("LocalOpened") == true
        or chestModel:GetAttribute(localUserId .. "Opened") == true
end

local function waitChestOpenedByName(name, timeoutSec)
    local timeoutAt = os.clock() + (timeoutSec or 12)
    while os.clock() < timeoutAt do
        local chestModel = getChestModelByName(name)
        if chestModel and isChestOpened(chestModel) then
            return true
        end
        task.wait(0.2)
    end
    return false
end

-- ============================================================
-- DEFINIÃƒÆ’Ã¢â‚¬Â¡ÃƒÆ’Ã†â€™O DOS PASSOS
-- ============================================================
local function startTimer_fn(timerFrame, updateLayout)
    timerActive = true
    timerEnd    = os.clock() + (20 * 60)
    timerFrame.Visible = true
    updateLayout()
end

local steps = {}

-- skipWait = true quando chamado pelo botÃƒÆ’Ã‚Â£o individual (ignora verificaÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o de disponibilidade)
steps[1] = {
    label = "1 Ãƒâ€šÃ‚Â· Aguardar Entrada",
    run = function(setStatus, _startTimer, skipWait)
        local points = resolveStrongholdPoints()
        pushDebugLog("step1 entryFront=" .. fmtVec3(points.entryFront))
        if skipWait then
            -- modo teste: teleporta direto, mostra estado da porta
            local state = entryState()
            local stateMsg = state == "ready"    and " [PRONTA]"
                          or state == "open"     and " [JÃƒÆ’Ã‚Â ABERTA]"
                          or                        " [EM COOLDOWN]"
            tpTo(points.entryFront)
            setStatus("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Na frente da entrada" .. stateMsg, Color3.fromRGB(80,255,120))
        else
            -- Pula se entrada jÃƒÆ’Ã‚Â¡ aberta (run em andamento)
            if fortalezaAberta() and not fortalezaFinalizada then
                setStatus("ÃƒÂ¢Ã‚ÂÃ‚Â© Entrada jÃƒÆ’Ã‚Â¡ aberta, pulando passo 1...", Color3.fromRGB(180,180,80))
                return
            end
            setStatus("ÃƒÂ¢Ã‚ÂÃ‚Â³ Verificando porta de entrada...")
            local state = entryState()
            if state == "cooldown" then
                setStatus("ÃƒÂ¢Ã…â€™Ã¢â‚¬Âº Fortaleza em cooldown. Aguardando prÃƒÆ’Ã‚Â³xima abertura...", Color3.fromRGB(255,130,50))
                repeat task.wait(3) until entryState() ~= "cooldown"
            end
            tpTo(points.entryFront)
            setStatus("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Na frente da entrada.", Color3.fromRGB(80,255,120))
        end
    end
}

steps[2] = {
    label = "2 Ãƒâ€šÃ‚Â· Abrir + Chat",
    run = function(setStatus, _startTimer, skipWait)
        -- Pula se entrada jÃƒÆ’Ã‚Â¡ aberta e chat jÃƒÆ’Ã‚Â¡ enviado
        if not skipWait and fortalezaAberta() and chatEnviado and not fortalezaFinalizada then
            setStatus("ÃƒÂ¢Ã‚ÂÃ‚Â© Porta jÃƒÆ’Ã‚Â¡ aberta + chat jÃƒÆ’Ã‚Â¡ enviado, pulando passo 2...", Color3.fromRGB(180,180,80))
            return
        end
        if not fortalezaAberta() then
            setStatus("ÃƒÂ°Ã…Â¸Ã…Â¡Ã‚Âª Abrindo porta de entrada...")
            firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","EntryDoors","DoorRight","Main","ProximityAttachment","ProximityInteraction"))
            task.wait(0.3)
            firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","EntryDoors","DoorLeft","Main","ProximityAttachment","ProximityInteraction"))
            task.wait(0.4)
        else
            setStatus("ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¹ÃƒÂ¯Ã‚Â¸Ã‚Â  Porta jÃƒÆ’Ã‚Â¡ aberta.")
        end
        if not chatEnviado then
            sendChat("Estou iniciando a Fortaleza")
            chatEnviado = true
            setStatus("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Chat enviado.", Color3.fromRGB(80,255,120))
        else
            setStatus("ÃƒÂ¢Ã‚ÂÃ‚Â© Chat jÃƒÆ’Ã‚Â¡ enviado anteriormente.", Color3.fromRGB(180,180,80))
        end
    end
}

steps[3] = {
    label = "3 Ãƒâ€šÃ‚Â· 1Ãƒâ€šÃ‚Â° Andar",
    run = function(setStatus, _startTimer, skipWait)
        local points = resolveStrongholdPoints()
        local routeStart = points.routeStart
        local routeTarget = points.routeTarget
        pushDebugLog("step3 start routeStart=" .. fmtVec3(routeStart) .. " routeTarget=" .. fmtVec3(routeTarget))

        -- Pula se porta1 jÃƒÆ’Ã‚Â¡ aberta e fortaleza em andamento
        local ld1
        pcall(function() ld1 = workspace.Map.Landmarks.Stronghold.Functional.Doors.LockedDoorsFloor1 end)
        local porta1Aberta = ld1 and ld1:GetAttribute("DoorOpen") == true
        if not skipWait and porta1Aberta and not fortalezaFinalizada then
            setStatus("ÃƒÂ¢Ã‚ÂÃ‚Â© Porta 1 jÃƒÆ’Ã‚Â¡ aberta, pulando passo 3...", Color3.fromRGB(180,180,80))
            return
        end

        -- Teleporta do ponto fixo e aguarda cair no chÃƒÆ’Ã‚Â£o
        setStatus("ÃƒÂ°Ã…Â¸Ã‚ÂÃ†â€™ Teleportando para frente da entrada...")
        tpTo(routeStart)
        task.wait(1.2)  -- aguarda personagem pousar no chÃƒÆ’Ã‚Â£o antes de mover
        setStatus("ÃƒÂ¢Ã‚Â¬Ã¢â‚¬Â ÃƒÂ¯Ã‚Â¸Ã‚Â Pulando e avanÃƒÆ’Ã‚Â§ando para destravar...", Color3.fromRGB(120,220,255))
        jumpAndWalkForward(1)

        if learnedRoute and learnedRoute[1] and dist2D(learnedRoute[1], routeStart) > 12 then
            learnedRoute = nil
            setStatus("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â­ Fortaleza mudou de posiÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o, recalculando rota...", Color3.fromRGB(255,200,80))
        end

        -- Navega atÃƒÆ’Ã‚Â© a frente da porta 1 (isso jÃƒÆ’Ã‚Â¡ spawna os cultistas pelo caminho)
        if learnedRoute then
            setStatus("ÃƒÂ°Ã…Â¸Ã¢â‚¬â€Ã‚Âº  Seguindo rota memorizada atÃƒÆ’Ã‚Â© porta 1...", Color3.fromRGB(120,220,255))
            followLearnedRoute(setStatus)
        else
            setStatus("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â Explorando rota atÃƒÆ’Ã‚Â© porta 1 (1Ãƒâ€šÃ‚Âª vez)...", Color3.fromRGB(255,200,80))
            exploreToTarget(setStatus, routeStart, routeTarget)
        end

        setStatus("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Na frente da porta 1. Cultistas spawnados.", Color3.fromRGB(80,255,120))
    end
}

steps[4] = {
    label = "4 Ãƒâ€šÃ‚Â· 2Ãƒâ€šÃ‚Â° Andar + Aguardar Gate",
    run = function(setStatus, startTimer, skipWait)
        local points = resolveStrongholdPoints()
        pushDebugLog("step4 start floor2Front=" .. fmtVec3(points.floor2Front))
        -- Pula se jÃƒÆ’Ã‚Â¡ finalizou
        if not skipWait and fortalezaFinalizada then
            setStatus("ÃƒÂ¢Ã‚ÂÃ‚Â© Fortaleza jÃƒÆ’Ã‚Â¡ finalizada, pulando...", Color3.fromRGB(180,180,80))
            return
        end

        -- Teleporta para frente da porta 2 e abre
        setStatus("ÃƒÂ°Ã…Â¸Ã‚ÂÃ†â€™ Teleportando para frente da porta 2...")
        tpTo(points.floor2Front)
        task.wait(0.8)
        setStatus("ÃƒÂ°Ã…Â¸Ã…Â¡Ã‚Âª Abrindo porta do 2Ãƒâ€šÃ‚Â° andar...")
        firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor2","DoorRight","Main","ProximityAttachment","ProximityInteraction"))
        task.wait(0.2)
        firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor2","DoorLeft","Main","ProximityAttachment","ProximityInteraction"))
        task.wait(0.3)

        if skipWait then
            setStatus("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Porta 2 aberta (modo teste).", Color3.fromRGB(80,255,120))
            return
        end

        -- Aguarda aqui mesmo (frente da porta 2) atÃƒÆ’Ã‚Â© o FinalGate abrir
        resetFinalGateProbe()
        setStatus("ÃƒÂ¢Ã…Â¡Ã¢â‚¬ÂÃƒÂ¯Ã‚Â¸Ã‚Â  Aguardando FinalGate... (mate os mobs!)", Color3.fromRGB(255,120,80))
        local gateOpened = waitUntilFloor3OpenStable(0.7, 4, 180)
        if not gateOpened then
            setStatus("Timeout aguardando porta 3.", Color3.fromRGB(255,100,100))
            pushDebugLog("step4 aborted: gate did not open in time")
            return
        end

        -- Timer inicia no momento exato que o gate abre
        if not timerActive then
            startTimer()
        end
        pushDebugLog("step4 gate opened, timer started")
        setStatus("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ FinalGate abriu! Timer iniciado. Teleportando para o baÃƒÆ’Ã‚Âº...", Color3.fromRGB(80,255,120))
        task.wait(0.5)

        -- Teleporta direto para frente do Diamond Chest
        local chest = workspace.Items:FindFirstChild("Stronghold Diamond Chest", true)
            or workspace:FindFirstChild("Stronghold Diamond Chest", true)
        if chest then
            local bp = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart")
            if bp then
                tpTo(bp.Position + Vector3.new(0, 2, 4))
                setStatus("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Na frente do Diamond Chest!", Color3.fromRGB(80,255,120))
            end
        else
            setStatus("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â  Diamond Chest nÃƒÆ’Ã‚Â£o encontrado.", Color3.fromRGB(255,100,100))
        end
    end
}

steps[5] = {
    label = "5 Ãƒâ€šÃ‚Â· Abrir BaÃƒÆ’Ã‚Âºs",
    run = function(setStatus, startTimer, skipWait)
        if skipWait then
            setStatus("ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¹ÃƒÂ¯Ã‚Â¸Ã‚Â  Modo teste: use o passo 4 para aguardar o gate.", Color3.fromRGB(180,180,80))
            return
        end

        local chestFarmWasOn = false
        local chestFarmForcedOn = false
        if _G.Hub and _G.Hub.getEstado then
            chestFarmWasOn = _G.Hub.getEstado("Chest Farm") == true
        end

        if not chestFarmWasOn and _G.Hub and _G.Hub.setEstado then
            setStatus("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â Ativando Chest Farm temporariamente...", Color3.fromRGB(120,220,255))
            chestFarmForcedOn = _G.Hub.setEstado("Chest Farm", true) == true
            task.wait(0.2)
        end

        -- Abre o Diamond Chest e aguarda confirmaÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o de abertura.
        setStatus("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¦ Abrindo Diamond Chest...")
        openChestByName("Stronghold Diamond Chest")
        local opened = waitChestOpenedByName("Stronghold Diamond Chest", 15)
        if opened then
            setStatus("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Diamond Chest aberto.", Color3.fromRGB(80,255,120))
        else
            setStatus("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â Diamond Chest sem confirmaÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o (timeout).", Color3.fromRGB(255,140,80))
        end

        setStatus("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â¦ Abrindo baÃƒÆ’Ã‚Âº prÃƒÆ’Ã‚Â³ximo...")
        openNearestChest()
        task.wait(0.4)

        if chestFarmForcedOn and _G.Hub and _G.Hub.setEstado then
            setStatus("ÃƒÂ¢Ã¢â‚¬Â Ã‚Â©ÃƒÂ¯Ã‚Â¸Ã‚Â Restaurando Chest Farm...", Color3.fromRGB(120,220,255))
            _G.Hub.setEstado("Chest Farm", false)
            task.wait(0.2)
        end

        fortalezaFinalizada = true
        chatEnviado = false
        setStatus("ÃƒÂ°Ã…Â¸Ã…Â½Ã¢â‚¬Â° BaÃƒÆ’Ã‚Âºs abertos! Fortaleza concluÃƒÆ’Ã‚Â­da.", Color3.fromRGB(80,255,120))
    end
}

-- ============================================================
-- GUI
-- ============================================================
local C = {
    bg       = Color3.fromRGB(10, 11, 15),
    header   = Color3.fromRGB(12, 14, 20),
    border   = Color3.fromRGB(28, 32, 48),
    accent   = Color3.fromRGB(0, 220, 255),
    green    = Color3.fromRGB(50, 220, 100),
    greenDim = Color3.fromRGB(15, 55, 25),
    red      = Color3.fromRGB(220, 50, 70),
    redDim   = Color3.fromRGB(55, 12, 18),
    yellow   = Color3.fromRGB(255, 200, 50),
    text     = Color3.fromRGB(180, 190, 210),
    muted    = Color3.fromRGB(65, 75, 100),
    rowBg    = Color3.fromRGB(18, 20, 28),
    rowHov   = Color3.fromRGB(22, 26, 38),
    btnOn    = Color3.fromRGB(25, 50, 85),
    btnOnHov = Color3.fromRGB(35, 70, 110),
}

local POS_KEY = "stronghold_pos.json"
local _strongholdPosData = nil
local booting = true
local estadoJanela = "maximizado"
local minimizado = false
local hCache = nil

local pg = lp:WaitForChild("PlayerGui")
do local a = pg:FindFirstChild("Stronghold_hud"); if a then a:Destroy() end end

local sg = Instance.new("ScreenGui")
sg.Name           = "Stronghold_hud"
sg.ResetOnSpawn   = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = true
sg.Parent         = pg

sg.DescendantAdded:Connect(function(d)
    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
        d.TextStrokeTransparency = 1
    end
end)

local main = Instance.new("Frame", sg)
main.Name             = "Main"
main.Size             = UDim2.new(0, 360, 0, 310)
main.Position         = UDim2.new(0, 280, 0, 40)
main.BackgroundColor3 = C.bg
main.BorderSizePixel  = 0
main.Active           = true
main.Draggable        = false
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local ms = Instance.new("UIStroke", main)
ms.Color = C.border; ms.Thickness = 1.2

-- TÃƒÆ’Ã‚Â­tulo
local titleBar = Instance.new("Frame", main)
titleBar.Size             = UDim2.new(1, 0, 0, 38)
titleBar.BackgroundColor3 = C.header
titleBar.BorderSizePixel  = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)
local tf = Instance.new("Frame", titleBar)
tf.Size = UDim2.new(1,0,0,10); tf.Position = UDim2.new(0,0,1,-10)
tf.BackgroundColor3 = C.header; tf.BorderSizePixel = 0

local topLine = Instance.new("Frame", main)
topLine.Size = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.accent
topLine.BorderSizePixel = 0
topLine.ZIndex = 6
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size = UDim2.new(1,-72,1,0); titleLbl.Position = UDim2.new(0,12,0,0)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = "STRONGHOLD AUTO"
titleLbl.TextColor3 = C.accent
titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 12
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0,22,0,22); minBtn.Position = UDim2.new(1,-50,0.5,-11)
minBtn.BackgroundColor3 = C.border
minBtn.Text = "-"; minBtn.TextColor3 = C.muted
minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 10
minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,4)

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0,22,0,22); closeBtn.Position = UDim2.new(1,-24,0.5,-11)
closeBtn.BackgroundColor3 = C.redDim
closeBtn.Text = "X"; closeBtn.TextColor3 = C.red
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 10
closeBtn.BorderSizePixel = 0
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(100,20,35)

-- Status
local statusLbl = Instance.new("TextLabel", main)
statusLbl.Size = UDim2.new(1,-20,0,36); statusLbl.Position = UDim2.new(0,10,0,45)
statusLbl.BackgroundTransparency = 1; statusLbl.Text = "Pronto."
statusLbl.TextColor3 = C.text
statusLbl.Font = Enum.Font.Gotham; statusLbl.TextSize = 12
statusLbl.TextWrapped = true; statusLbl.TextXAlignment = Enum.TextXAlignment.Left

local sep1 = Instance.new("Frame", main)
sep1.Size = UDim2.new(1,-20,0,1); sep1.Position = UDim2.new(0,10,0,87)
sep1.BackgroundColor3 = C.border; sep1.BorderSizePixel = 0

-- Timer
local timerFrame = Instance.new("Frame", main)
timerFrame.Size = UDim2.new(1,-20,0,38); timerFrame.Position = UDim2.new(0,10,0,94)
timerFrame.BackgroundColor3 = C.greenDim
timerFrame.BorderSizePixel = 0; timerFrame.Visible = false
Instance.new("UICorner", timerFrame).CornerRadius = UDim.new(0,6)
local ts = Instance.new("UIStroke", timerFrame)
ts.Color = C.green; ts.Thickness = 1

local timerLbl = Instance.new("TextLabel", timerFrame)
timerLbl.Size = UDim2.new(1,0,1,0); timerLbl.BackgroundTransparency = 1
timerLbl.Text = "20:00"; timerLbl.TextColor3 = Color3.fromRGB(75,250,115)
timerLbl.Font = Enum.Font.GothamBold; timerLbl.TextSize = 17

local timerBar = Instance.new("Frame", timerFrame)
timerBar.Size = UDim2.new(1,0,0,3); timerBar.Position = UDim2.new(0,0,1,-3)
timerBar.BackgroundColor3 = C.green; timerBar.BorderSizePixel = 0
Instance.new("UICorner", timerBar).CornerRadius = UDim.new(0,2)

-- BotÃƒÆ’Ã‚Âµes de passo (grid 2x3)
local btnGrid = Instance.new("Frame", main)
btnGrid.Name = "BtnGrid"
btnGrid.Size = UDim2.new(1,-20,0,130); btnGrid.Position = UDim2.new(0,10,0,94)
btnGrid.BackgroundTransparency = 1

local gl = Instance.new("UIGridLayout", btnGrid)
gl.CellSize = UDim2.new(0.5,-4,0,36); gl.CellPadding = UDim2.new(0,6,0,5)
gl.FillDirection = Enum.FillDirection.Horizontal; gl.SortOrder = Enum.SortOrder.LayoutOrder

local function updateLayout()
    if minimizado then return end
    if timerFrame.Visible then
        btnGrid.Position = UDim2.new(0,10,0,140)
        main.Size = UDim2.new(0,360,0,350)
    else
        btnGrid.Position = UDim2.new(0,10,0,94)
        main.Size = UDim2.new(0,360,0,310)
    end
    hCache = main.Size.Y.Offset
end

local stepBtns = {}
for i, step in ipairs(steps) do
    local btn = Instance.new("TextButton", btnGrid)
    btn.BackgroundColor3 = C.rowBg
    btn.Text = step.label; btn.TextColor3 = C.text
    btn.Font = Enum.Font.Gotham; btn.TextSize = 11
    btn.BorderSizePixel = 0; btn.LayoutOrder = i
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,5)
    local ss = Instance.new("UIStroke", btn)
    ss.Color = C.border; ss.Thickness = 1
    stepBtns[i] = btn
end

-- Separador 2
local sep2 = Instance.new("Frame", main)
sep2.Size = UDim2.new(1,-20,0,1)
sep2.BackgroundColor3 = C.border; sep2.BorderSizePixel = 0
-- posiÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o dinÃƒÆ’Ã‚Â¢mica via updateLayout

-- BotÃƒÆ’Ã‚Âµes principais
local startBtn = Instance.new("TextButton", main)
startBtn.Size = UDim2.new(1,-20,0,36)
startBtn.BackgroundColor3 = C.btnOn
startBtn.Text = "INICIAR TUDO"; startBtn.TextColor3 = Color3.fromRGB(255,255,255)
startBtn.Font = Enum.Font.GothamBold; startBtn.TextSize = 13
startBtn.BorderSizePixel = 0
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0,7)
Instance.new("UIStroke", startBtn).Color = Color3.fromRGB(35, 90, 130)

local stopBtn = Instance.new("TextButton", main)
stopBtn.Size = UDim2.new(1,-20,0,36)
stopBtn.BackgroundColor3 = C.redDim
stopBtn.Text = "PARAR"; stopBtn.TextColor3 = Color3.fromRGB(255,255,255)
stopBtn.Font = Enum.Font.GothamBold; stopBtn.TextSize = 13
stopBtn.BorderSizePixel = 0; stopBtn.Visible = false
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0,7)
Instance.new("UIStroke", stopBtn).Color = Color3.fromRGB(100, 20, 35)

-- FunÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o para reposicionar btns de aÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o
local function layoutMainBtns()
    if minimizado then return end
    local baseY = timerFrame.Visible and 280 or 235
    sep2.Position  = UDim2.new(0,10,0,baseY)
    startBtn.Position = UDim2.new(0,10,0,baseY+8)
    stopBtn.Position  = UDim2.new(0,10,0,baseY+8)
    main.Size = UDim2.new(0,360,0,baseY+58)
    hCache = main.Size.Y.Offset
end

-- ============================================================
-- LÃƒÆ’Ã¢â‚¬Å“GICA DE EXECUÃƒÆ’Ã¢â‚¬Â¡ÃƒÆ’Ã†â€™O
-- ============================================================
local isRunning = false

local function setEstadoJanela(v)
    estadoJanela = v
    if _G.KAHWindowState and _G.KAHWindowState.set then
        _G.KAHWindowState.set(MODULE_NAME, v)
    end
end

local function salvarPos()
    if not writefile then return end
    pcall(writefile, POS_KEY, HS:JSONEncode({
        x = main.Position.X.Offset,
        y = main.Position.Y.Offset,
        minimizado = minimizado,
        hCache = hCache,
        windowState = estadoJanela,
    }))
end

local function carregarPos()
    if isfile and readfile and isfile(POS_KEY) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY)) end)
        if ok and d then
            main.Position = UDim2.new(0, d.x or 280, 0, d.y or 40)
            _strongholdPosData = d
        end
    end
end
carregarPos()

do
    local saved = (_G.KAHWindowState and _G.KAHWindowState.get) and _G.KAHWindowState.get(MODULE_NAME, nil) or nil
    if saved then
        estadoJanela = saved
    elseif _strongholdPosData and (_strongholdPosData.windowState == "maximizado" or _strongholdPosData.windowState == "minimizado" or _strongholdPosData.windowState == "fechado") then
        estadoJanela = _strongholdPosData.windowState
    elseif _strongholdPosData and _strongholdPosData.minimizado then
        estadoJanela = "minimizado"
    end
end

if _G.Snap then _G.Snap.registrar(main, salvarPos) end

local dragInput, dragStartPos, dragStartMouse
titleBar.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 and i.UserInputType ~= Enum.UserInputType.Touch then return end
    dragInput = i
    dragStartPos = main.Position
    dragStartMouse = i.Position
end)
UIS.InputChanged:Connect(function(i)
    if not dragInput then return end
    if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
    local d = i.Position - dragStartMouse
    local nx = dragStartPos.X.Offset + d.X
    local ny = dragStartPos.Y.Offset + d.Y
    if _G.Snap then _G.Snap.mover(main, nx, ny)
    else main.Position = UDim2.new(0, nx, 0, ny) end
end)
UIS.InputEnded:Connect(function(i)
    if i ~= dragInput then return end
    dragInput = nil
    if _G.Snap then _G.Snap.soltar(main)
    else salvarPos() end
end)

local function applyWindowMode()
    if minimizado then
        statusLbl.Visible = false
        sep1.Visible = false
        timerFrame.Visible = false
        btnGrid.Visible = false
        sep2.Visible = false
        startBtn.Visible = false
        stopBtn.Visible = false
        main.Size = UDim2.new(0, 360, 0, 38)
        minBtn.Text = "^"
    else
        statusLbl.Visible = true
        sep1.Visible = true
        btnGrid.Visible = true
        sep2.Visible = true
        timerFrame.Visible = timerActive
        startBtn.Visible = not isRunning
        stopBtn.Visible = isRunning
        minBtn.Text = "-"
        updateLayout()
        layoutMainBtns()
    end
end

local function setStatus(txt, color)
    if uiDestroyed then return end
    statusLbl.Text       = txt
    statusLbl.TextColor3 = color or C.text
end

local function startTimerFn()
    timerActive = true
    timerEnd    = os.clock() + (20 * 60)
    timerFrame.Visible = true
    updateLayout()
    layoutMainBtns()
end

local function lockBtns(lock)
    for _, b in ipairs(stepBtns) do b.Active = not lock end
    startBtn.Active = not lock
end

local function runStep(i)
    if isRunning then return end
    isRunning = true
    lockBtns(true)
    local t = task.spawn(function()
        -- skipWait=true: botÃƒÆ’Ã‚Âµes individuais nunca ficam presos esperando disponibilidade
        pcall(function() steps[i].run(setStatus, startTimerFn, true) end)
        if not uiDestroyed then isRunning = false; lockBtns(false) end
    end)
    table.insert(threads, t)
end

local function runAll()
    if isRunning then return end
    isRunning = true
    startBtn.Visible = false; stopBtn.Visible = true
    lockBtns(true)
    local t = task.spawn(function()
        for i = 1, #steps do
            if not isRunning then break end
            pcall(function() steps[i].run(setStatus, startTimerFn) end)
            task.wait(0.05)
        end
        if not uiDestroyed then
            isRunning = false
            startBtn.Visible = true; stopBtn.Visible = false
            lockBtns(false)
        end
    end)
    table.insert(threads, t)
end

-- ============================================================
-- EVENTOS DOS BOTÃƒÆ’Ã¢â‚¬Â¢ES
-- ============================================================
for i, btn in ipairs(stepBtns) do
    btn.MouseButton1Click:Connect(function() runStep(i) end)
    btn.MouseEnter:Connect(function() btn.BackgroundColor3 = C.rowHov end)
    btn.MouseLeave:Connect(function() btn.BackgroundColor3 = C.rowBg end)
end

minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    setEstadoJanela(minimizado and "minimizado" or "maximizado")
    applyWindowMode()
    salvarPos()
end)

startBtn.MouseButton1Click:Connect(runAll)
startBtn.MouseEnter:Connect(function() startBtn.BackgroundColor3 = C.btnOnHov end)
startBtn.MouseLeave:Connect(function() startBtn.BackgroundColor3 = C.btnOn end)

stopBtn.MouseButton1Click:Connect(function()
    isRunning = false; stopExecution()
    setStatus("Parado.", Color3.fromRGB(255,85,85))
    startBtn.Visible = true; stopBtn.Visible = false; lockBtns(false)
end)

closeBtn.MouseButton1Click:Connect(function()
    if _G.Hub then
        pcall(function() _G.Hub.desligar(MODULE_NAME) end)
    else
        setEstadoJanela("fechado")
        salvarPos()
        sg.Enabled = false
    end
end)
closeBtn.MouseEnter:Connect(function() closeBtn.BackgroundColor3 = Color3.fromRGB(75,18,26) end)
closeBtn.MouseLeave:Connect(function() closeBtn.BackgroundColor3 = C.redDim end)

-- ============================================================
-- TIMER HEARTBEAT (leve)
-- ============================================================
local hb = RunService.Heartbeat:Connect(function()
    if uiDestroyed or not timerActive then return end
    local rem = timerEnd - os.clock()
    if rem <= 0 then
        timerActive = false
        timerLbl.Text = "00:00 RESET!"; timerLbl.TextColor3 = Color3.fromRGB(255,65,65)
        timerBar.Size = UDim2.new(0,0,0,3); ts.Color = Color3.fromRGB(255,65,65)
        return
    end
    local frac = math.clamp(rem/(20*60),0,1)
    timerLbl.Text = string.format("%02d:%02d", math.floor(rem/60), math.floor(rem%60))
    timerBar.Size = UDim2.new(frac,0,0,3)
    local c = frac > 0.5 and Color3.fromRGB(75,195,75)
           or frac > 0.2 and Color3.fromRGB(235,185,45)
           or Color3.fromRGB(235,55,55)
    timerBar.BackgroundColor3 = c; ts.Color = c
    timerLbl.TextColor3 = frac > 0.5 and Color3.fromRGB(80,255,120)
                       or frac > 0.2 and Color3.fromRGB(255,210,65)
                       or Color3.fromRGB(255,75,75)
end)
table.insert(connections, hb)

local function onToggle(ativo)
    if ativo then
        sg.Enabled = true
        applyWindowMode()
    else
        isRunning = false
        stopExecution()
        lockBtns(false)
        startBtn.Visible = true
        stopBtn.Visible = false
        sg.Enabled = false
    end

    if not booting then
        if ativo then
            setEstadoJanela(minimizado and "minimizado" or "maximizado")
        else
            setEstadoJanela("fechado")
        end
        salvarPos()
    end
end

local iniciarAtivo = estadoJanela ~= "fechado"
if estadoJanela == "minimizado" or (_strongholdPosData and _strongholdPosData.minimizado and estadoJanela ~= "maximizado") then
    minimizado = true
    hCache = (_strongholdPosData and _strongholdPosData.hCache) or 350
else
    minimizado = false
    hCache = (_strongholdPosData and _strongholdPosData.hCache) or 350
end

sg.Enabled = iniciarAtivo
if iniciarAtivo then
    applyWindowMode()
else
    stopExecution()
end

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, iniciarAtivo)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = MODULE_NAME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = iniciarAtivo })
end

booting = false
salvarPos()
pushDebugLog("module ready; clipboard logging active")

_G[MODULE_STATE_KEY] = {
    gui = sg,
    cleanup = function()
        uiDestroyed = true
        isRunning = false
        cleanup()
    end,
}