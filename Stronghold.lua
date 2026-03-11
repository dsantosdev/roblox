-- ============================================================
--  STRONGHOLD AUTO - Xeno Executor
--  Verso 2 - Passo a Passo + Anti-Lag
-- ============================================================

-- ============================================================
-- POSIES (extradas do relatrio do servidor)
--
-- EntryDoors (porta externa):
--   DoorRight: X=-60,   Y=13.94, Z=-622.4
--   DoorLeft:  X=-71,   Y=13.94, Z=-622.4
--    Frente da porta (fora):  X=-65.5, Y=15, Z=-612
--
-- LockedDoorsFloor1 (1 andar):
--   DoorRight: X=0.3,  Y=13.94, Z=-656.1
--   DoorLeft:  X=-7.5, Y=13.94, Z=-663.9
--    Chegada (fora): X=-3.6, Y=15, Z=-648
--
-- LockedDoorsFloor2 (2 andar):
--   DoorRight: X=-79.7, Y=42.64, Z=-664
--   DoorLeft:  X=-79.7, Y=42.64, Z=-653
--    Chegada (fora): X=-68, Y=44, Z=-658.5
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
local fortalezaFinalizada = false -- true aps bas abertos (pula passos j feitos)
local finalGateRefPos  = nil
local finalGateRefSet  = false
local thirdGateOpened  = false
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

-- Checa se fortaleza est "em andamento mas no finalizada"
-- (entrada aberta = j entrou, mas ainda no finalizou)
local function fortalezaAberta()
    local ed
    pcall(function() ed = workspace.Map.Landmarks.Stronghold.Functional.EntryDoors end)
    if not ed then return false end
    return ed:GetAttribute("DoorOpen") == true
end

-- ============================================================
-- PATHFINDER COM MEMRIA
-- Explora em direo ao destino, detecta travamento por parede,
-- grava waypoints que funcionaram. Na prxima run usa a rota
-- gravada direto, sem explorar.
-- ============================================================
local learnedRoute = nil  -- nil = ainda no aprendeu, tabela = rota gravada

-- Distncia 2D (ignora Y) entre dois Vector3
local function dist2D(a, b)
    return math.sqrt((a.X - b.X)^2 + (a.Z - b.Z)^2)
end

-- Verifica se o player realmente se moveu (no preso em parede)
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

    setStatus("  Usando rota memorizada...", Color3.fromRGB(120,220,255))
    for i, wp in ipairs(learnedRoute) do
        setStatus(string.format("  Waypoint %d/%d...", i, #learnedRoute), Color3.fromRGB(120,220,255))
        hum:MoveTo(wp)
        -- espera chegar ou timeout proporcional  distncia
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

-- Explorao com aprendizado:
-- Move em direo ao alvo usando pequenos passos.
-- Se travar, tenta desvios laterais.
-- Grava todos os waypoints que avanaram de verdade.
-- Ao chegar, poda a rota (remove pontos redundantes) e salva.
local function exploreToTarget(setStatus, startPos, targetPos)
    local char = lp.Character
    if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    local STEP       = 5     -- studs por passo (menor = mais preciso)
    local STUCK_TIME = 0.4   -- segundos sem mover = preso (mais rpido)
    local MAX_TRIES  = 200   -- iteraes mximas
    local GOAL_DIST  = 4     -- studs para considerar chegou

    local walkY      = (startPos and startPos.Y) or root.Position.Y
    local waypoints  = { startPos }  -- pontos que realmente avanaram
    local tries      = 0

    -- Direes de desvio quando preso: direita, esquerda, trs+direita, trs+esquerda
    local function desvios(dir)
        return {
            Vector3.new( dir.Z, 0, -dir.X),   -- 90 direita
            Vector3.new(-dir.Z, 0,  dir.X),   -- 90 esquerda
            Vector3.new( dir.Z, 0,  dir.X),   -- diagonal direita-frente
            Vector3.new(-dir.Z, 0, -dir.X),   -- diagonal esquerda-frente
        }
    end

    setStatus(" Explorando rota (1 vez)...", Color3.fromRGB(255,200,80))

    while dist2D(root.Position, targetPos) > GOAL_DIST and tries < MAX_TRIES do
        tries += 1
        local curPos = root.Position
        local toTarget = (Vector3.new(targetPos.X, curPos.Y, targetPos.Z) - curPos)
        local dirNorm  = toTarget.Magnitude > 0 and toTarget.Unit or Vector3.new(0,0,-1)

        -- Tenta mover em direo ao alvo
        local nextPos = curPos + dirNorm * STEP
        nextPos = Vector3.new(nextPos.X, walkY, nextPos.Z)
        hum:MoveTo(nextPos)
        task.wait(STUCK_TIME)

        if playerMoved(root, curPos, 1.5) then
            -- Avanou: grava waypoint
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

    -- Poda rota: remove waypoints intermedirios que esto na mesma linha reta
    -- (se ABC so colineares, remove B)
    local function colinear(a, b, c, thresh)
        thresh = thresh or 2.5
        -- distncia do ponto B  linha AC
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
    setStatus(string.format(" Rota aprendida! %d waypoints.", #pruned), Color3.fromRGB(80,255,120))
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

local function tpToLook(pos, lookAt)
    local char = lp.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if lookAt and (lookAt - pos).Magnitude > 0.1 then
        root.CFrame = CFrame.new(pos, lookAt)
    else
        root.CFrame = CFrame.new(pos)
    end
    task.wait(0.25)
end

-- ============================================================
-- ANDAR com espera real por chegada (MoveToFinished)
-- timeout: segundos mximos antes de desistir (evita travar)
-- ============================================================
local function moveToAndWait(targetPos, timeout)
    local char = lp.Character
    if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    timeout = timeout or 15
    local arrived = false

    -- calcula distncia e estima tempo mnimo pela velocidade real
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

-- Pequeno impulso inicial para destravar coliso/corpo antes do pathfinder.
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

-- Variante para destravar indo na diagonal esquerda (frente + esquerda),
-- assumindo que o personagem ja esteja virado para o alvo.
local function jumpAndMoveDiagonalLeft(seconds)
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

        local left = Vector3.new(-flat.Z, 0, flat.X)
        local diag = flat + left
        if diag.Magnitude < 0.01 then
            diag = flat
        else
            diag = diag.Unit
        end

        hum:Move(diag, false)
        RunService.Heartbeat:Wait()
    end
    hum:Move(Vector3.new(0, 0, 0), false)
end

-- ============================================================
-- CHAT - 3 mtodos em sequncia (TextChatService  Legacy  Bubble)
-- ============================================================
local function sendChat(msg)
    -- Mtodo 1: TextChatService (novo sistema Roblox)
    local ok1 = pcall(function()
        local tcs  = game:GetService("TextChatService")
        local chan  = tcs:FindFirstChild("TextChannels")
        local geral = chan and (chan:FindFirstChild("RBXGeneral") or chan:FindFirstChild("General"))
        if geral and geral.SendAsync then
            geral:SendAsync(msg)
        end
    end)
    task.wait(0.1)
    -- Mtodo 2: Legacy SayMessageRequest
    if not ok1 then
        pcall(function()
            local r   = game:GetService("ReplicatedStorage")
            local d   = r:FindFirstChild("DefaultChatSystemChatEvents")
            local say = d and d:FindFirstChild("SayMessageRequest")
            if say then say:FireServer(msg, "All") end
        end)
        task.wait(0.1)
    end
    -- Mtodo 3: Bubble chat local (fallback garantido)
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

local function tpNearPrompt(pp)
    if not pp then return end
    local part = pp.Parent and pp.Parent.Parent
    if part and part:IsA("BasePart") then
        tpToLook(part.Position + Vector3.new(0, 2, 0), part.Position)
        task.wait(0.12)
    end
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

    -- Entry points are resolved from the door facing direction, choosing the side
    -- farther from floor1 so we always stay outside ("de frente", not sideways).
    local entryFront = frontFromDoorPair("entry", 12.0, 1.0, FALLBACK_ENTRY_FRONT, floor1Center, true)
    local toDoor = Vector3.new(entryCenter.X - entryFront.X, 0, entryCenter.Z - entryFront.Z)
    local toDoorDir = toDoor.Magnitude > 0.01 and toDoor.Unit or Vector3.new(0, 0, -1)
    local routeStart = entryFront + (toDoorDir * 4.0)

    -- Floor1 side should face the entry path.
    local routeTarget = frontFromDoorPair("floor1", 16.0, 1.0, FALLBACK_ROUTE_TARGET, entryCenter, false)

    -- Floor2 side should face the path coming from floor1 and stay farther away.
    local floor2Center = getDoorCenter("floor2") or FALLBACK_FLOOR2_FRONT
    local floor2Front = frontFromDoorPair("floor2", 31.5, 1.0, FALLBACK_FLOOR2_FRONT, routeTarget, false)

    pushDebugLog("points entry=" .. fmtVec3(entryFront) .. " start=" .. fmtVec3(routeStart) .. " target=" .. fmtVec3(routeTarget) .. " floor2=" .. fmtVec3(floor2Front))
    return {
        entryFront = entryFront,
        entryCenter = entryCenter,
        routeStart = routeStart,
        routeTarget = routeTarget,
        floor2Front = floor2Front,
        floor2Center = floor2Center,
    }
end

local DOOR_STATE_PATHS = {
    entry = {"Map","Landmarks","Stronghold","Functional","EntryDoors"},
    floor1 = {"Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor1"},
    floor2 = {"Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor2"},
}

local function getDoorOpenState(kind)
    local p = DOOR_STATE_PATHS[kind]
    if not p then return nil end
    local d = getByPath(table.unpack(p))
    if not d then return nil end
    local v = d:GetAttribute("DoorOpen")
    if v == nil then return nil end
    return v == true
end

local function logDoorSequence(tag)
    local e  = getDoorOpenState("entry")
    local d1 = getDoorOpenState("floor1")
    local d2 = getDoorOpenState("floor2")
    pushDebugLog(string.format(
        "doorseq[%s] entry=%s floor1=%s floor2=%s gate3=%s mode=%s diff=%.2f",
        tostring(tag),
        tostring(e),
        tostring(d1),
        tostring(d2),
        tostring(thirdGateOpened),
        tostring(finalGateLastMode),
        tonumber(finalGateLastDiff) or 0
    ))
end

-- ============================================================
-- ESTADO DA ENTRADA:
--   "ready"     DoorOpen=false + Interaction="Door" + no DoorLocked
--   "cooldown"  DoorOpen=false + sem Interaction  (entre runs)
--   "open"      DoorOpen=true  (j aberta nesta run)
-- ============================================================
local function entryState()
    local ed
    pcall(function() ed = workspace.Map.Landmarks.Stronghold.Functional.EntryDoors end)
    if not ed then return "cooldown" end
    local isOpen      = ed:GetAttribute("DoorOpen")
    local isLocked    = ed:GetAttribute("DoorLocked") or ed:GetAttribute("DoorLockedClient")
    local interaction = ed:GetAttribute("Interaction")  -- presente s quando disponvel
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
    local polls = 0
    local lastEntry = nil
    local lastFloor1 = nil
    local lastFloor2 = nil
    local lastGate = nil
    local startedAt = os.clock()
    pushDebugLog("gate wait started")
    while hits < need do
        task.wait(interval)
        polls += 1
        local entryOpen = getDoorOpenState("entry")
        local floor1Open = getDoorOpenState("floor1")
        local floor2Open = getDoorOpenState("floor2")
        local openNow = isFloor3Open()

        if entryOpen ~= lastEntry or floor1Open ~= lastFloor1 or floor2Open ~= lastFloor2 or openNow ~= lastGate then
            pushDebugLog(string.format(
                "doorseq[poll:%d] entry=%s floor1=%s floor2=%s gate3=%s mode=%s diff=%.2f",
                polls,
                tostring(entryOpen),
                tostring(floor1Open),
                tostring(floor2Open),
                tostring(openNow),
                tostring(finalGateLastMode),
                tonumber(finalGateLastDiff) or 0
            ))
            lastEntry = entryOpen
            lastFloor1 = floor1Open
            lastFloor2 = floor2Open
            lastGate = openNow
        end

        pushDebugLog(string.format(
            "gate poll #%d open=%s mode=%s diff=%.2f",
            polls,
            tostring(openNow),
            tostring(finalGateLastMode),
            tonumber(finalGateLastDiff) or 0
        ))
        if openNow then
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
-- ABRE BAS
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
-- DEFINIO DOS PASSOS
-- ============================================================
local function startTimer_fn(timerFrame, updateLayout)
    timerActive = true
    timerEnd    = os.clock() + (20 * 60)
    timerFrame.Visible = true
    updateLayout()
end

local steps = {}

-- skipWait = true quando chamado pelo boto individual (ignora verificao de disponibilidade)
steps[1] = {
    label = "1  Aguardar Entrada",
    run = function(setStatus, _startTimer, skipWait)
        local points = resolveStrongholdPoints()
        pushDebugLog("step1 entryFront=" .. fmtVec3(points.entryFront))
        logDoorSequence("step1_begin")
        if skipWait then
            -- modo teste: teleporta direto, mostra estado da porta
            local state = entryState()
            local stateMsg = state == "ready"    and " [PRONTA]"
                          or state == "open"     and " [J ABERTA]"
                          or                        " [EM COOLDOWN]"
            tpToLook(points.entryFront, points.entryCenter)
            setStatus(" Na frente da entrada" .. stateMsg, Color3.fromRGB(80,255,120))
        else
            -- Pula se entrada j aberta (run em andamento)
            if fortalezaAberta() and not fortalezaFinalizada then
                setStatus(" Entrada j aberta, pulando passo 1...", Color3.fromRGB(180,180,80))
                return
            end
            setStatus(" Verificando porta de entrada...")
            local state = entryState()
            if state == "cooldown" then
                setStatus(" Fortaleza em cooldown. Aguardando prxima abertura...", Color3.fromRGB(255,130,50))
                repeat task.wait(3) until entryState() ~= "cooldown"
            end
            tpToLook(points.entryFront, points.entryCenter)
            setStatus(" Na frente da entrada.", Color3.fromRGB(80,255,120))
        end
        logDoorSequence("step1_end")
    end
}

steps[2] = {
    label = "2  Abrir + Chat",
    run = function(setStatus, _startTimer, skipWait)
        logDoorSequence("step2_begin")
        -- Pula se entrada j aberta e chat j enviado
        if not skipWait and fortalezaAberta() and chatEnviado and not fortalezaFinalizada then
            setStatus(" Porta j aberta + chat j enviado, pulando passo 2...", Color3.fromRGB(180,180,80))
            return
        end
        if not fortalezaAberta() then
            setStatus(" Abrindo porta de entrada...")
            local entryRightPrompt = getByPath("Map","Landmarks","Stronghold","Functional","EntryDoors","DoorRight","Main","ProximityAttachment","ProximityInteraction")
            local entryLeftPrompt = getByPath("Map","Landmarks","Stronghold","Functional","EntryDoors","DoorLeft","Main","ProximityAttachment","ProximityInteraction")
            tpNearPrompt(entryRightPrompt)
            firePrompt(entryRightPrompt)
            task.wait(0.3)
            tpNearPrompt(entryLeftPrompt)
            firePrompt(entryLeftPrompt)
            task.wait(0.4)
        else
            setStatus("  Porta j aberta.")
        end
        if not chatEnviado then
            sendChat("Estou iniciando a Fortaleza")
            chatEnviado = true
            setStatus(" Chat enviado.", Color3.fromRGB(80,255,120))
        else
            setStatus(" Chat j enviado anteriormente.", Color3.fromRGB(180,180,80))
        end
        logDoorSequence("step2_end")
    end
}

steps[3] = {
    label = "3  1 Andar",
    run = function(setStatus, _startTimer, skipWait)
        local points = resolveStrongholdPoints()
        local routeStart = points.routeStart
        local routeTarget = points.routeTarget
        pushDebugLog("step3 start routeStart=" .. fmtVec3(routeStart) .. " routeTarget=" .. fmtVec3(routeTarget))
        logDoorSequence("step3_begin")

        -- Pula se porta1 j aberta e fortaleza em andamento
        local ld1
        pcall(function() ld1 = workspace.Map.Landmarks.Stronghold.Functional.Doors.LockedDoorsFloor1 end)
        local porta1Aberta = ld1 and ld1:GetAttribute("DoorOpen") == true
        if not skipWait and porta1Aberta and not fortalezaFinalizada then
            setStatus(" Porta 1 j aberta, pulando passo 3...", Color3.fromRGB(180,180,80))
            return
        end

        -- Teleporta do ponto fixo e aguarda cair no cho
        setStatus(" Teleportando para frente da entrada...")
        tpToLook(routeStart, routeTarget)
        task.wait(1.2)  -- aguarda personagem pousar no cho antes de mover
        setStatus(" Pulando e movendo diagonal esquerda para destravar...", Color3.fromRGB(120,220,255))
        jumpAndMoveDiagonalLeft(1)

        if learnedRoute and learnedRoute[1] and dist2D(learnedRoute[1], routeStart) > 12 then
            learnedRoute = nil
            setStatus(" Fortaleza mudou de posio, recalculando rota...", Color3.fromRGB(255,200,80))
        end

        -- Navega at a frente da porta 1 (isso j spawna os cultistas pelo caminho)
        if learnedRoute then
            setStatus("  Seguindo rota memorizada at porta 1...", Color3.fromRGB(120,220,255))
            followLearnedRoute(setStatus)
        else
            setStatus(" Explorando rota at porta 1 (1 vez)...", Color3.fromRGB(255,200,80))
            exploreToTarget(setStatus, routeStart, routeTarget)
        end

        setStatus(" Na frente da porta 1. Cultistas spawnados.", Color3.fromRGB(80,255,120))
        logDoorSequence("step3_end")
    end
}

steps[4] = {
    label = "4  2 Andar + Aguardar Gate",
    run = function(setStatus, startTimer, skipWait)
        thirdGateOpened = false
        local points = resolveStrongholdPoints()
        pushDebugLog("step4 start floor2Front=" .. fmtVec3(points.floor2Front))
        logDoorSequence("step4_begin")
        -- Pula se j finalizou
        if not skipWait and fortalezaFinalizada then
            setStatus(" Fortaleza j finalizada, pulando...", Color3.fromRGB(180,180,80))
            return
        end

        -- Teleporta para frente da porta 2 e abre
        setStatus(" Teleportando para frente da porta 2...")
        tpToLook(points.floor2Front, points.floor2Center)
        task.wait(0.8)
        setStatus(" Abrindo porta do 2 andar...")
        firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor2","DoorRight","Main","ProximityAttachment","ProximityInteraction"))
        task.wait(0.2)
        firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor2","DoorLeft","Main","ProximityAttachment","ProximityInteraction"))
        task.wait(0.3)
        logDoorSequence("step4_after_open2")

        if skipWait then
            setStatus(" Porta 2 aberta (modo teste).", Color3.fromRGB(80,255,120))
            return
        end

        -- Aguarda aqui mesmo (frente da porta 2) at o FinalGate abrir
        resetFinalGateProbe()
        setStatus("  Aguardando FinalGate... (mate os mobs!)", Color3.fromRGB(255,120,80))
        local gateOpened = waitUntilFloor3OpenStable(0.7, 4, 180)
        if not gateOpened then
            setStatus("Timeout aguardando porta 3.", Color3.fromRGB(255,100,100))
            pushDebugLog("step4 aborted: gate did not open in time")
            return
        end
        thirdGateOpened = true

        -- Timer inicia no momento exato que o gate abre
        startTimer()
        pushDebugLog("step4 gate opened, timer started")
        logDoorSequence("step4_gate_open")
        setStatus(" FinalGate abriu! Timer iniciado. Teleportando para o ba...", Color3.fromRGB(80,255,120))
        task.wait(0.5)

        -- Teleporta direto para frente do Diamond Chest
        local chest = workspace.Items:FindFirstChild("Stronghold Diamond Chest", true)
            or workspace:FindFirstChild("Stronghold Diamond Chest", true)
        if chest then
            local bp = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart")
            if bp then
                tpTo(bp.Position + Vector3.new(0, 2, 4))
                setStatus(" Na frente do Diamond Chest!", Color3.fromRGB(80,255,120))
            end
        else
            setStatus("  Diamond Chest no encontrado.", Color3.fromRGB(255,100,100))
        end
    end
}

steps[5] = {
    label = "5  Abrir Bas",
    run = function(setStatus, startTimer, skipWait)
        if skipWait then
            setStatus("  Modo teste: use o passo 4 para aguardar o gate.", Color3.fromRGB(180,180,80))
            return
        end

        if not thirdGateOpened then
            setStatus(" Porta 3 ainda fechada. No vou para o ba.", Color3.fromRGB(255,120,80))
            pushDebugLog("step5 blocked: gate3 not opened")
            return
        end

        local chestFarmWasOn = false
        local chestFarmForcedOn = false
        if _G.Hub and _G.Hub.getEstado then
            chestFarmWasOn = _G.Hub.getEstado("Chest Farm") == true
        end

        if not chestFarmWasOn and _G.Hub and _G.Hub.setEstado then
            setStatus(" Ativando Chest Farm temporariamente...", Color3.fromRGB(120,220,255))
            chestFarmForcedOn = _G.Hub.setEstado("Chest Farm", true) == true
            task.wait(0.2)
        end

        -- Abre o Diamond Chest e aguarda confirmao de abertura.
        setStatus(" Abrindo Diamond Chest...")
        openChestByName("Stronghold Diamond Chest")
        local opened = waitChestOpenedByName("Stronghold Diamond Chest", 15)
        if opened then
            setStatus(" Diamond Chest aberto.", Color3.fromRGB(80,255,120))
        else
            setStatus(" Diamond Chest sem confirmao (timeout).", Color3.fromRGB(255,140,80))
        end

        setStatus(" Abrindo ba prximo...")
        openNearestChest()
        task.wait(0.4)

        if chestFarmForcedOn and _G.Hub and _G.Hub.setEstado then
            setStatus(" Restaurando Chest Farm...", Color3.fromRGB(120,220,255))
            _G.Hub.setEstado("Chest Farm", false)
            task.wait(0.2)
        end

        fortalezaFinalizada = true
        chatEnviado = false
        thirdGateOpened = false
        setStatus(" Bas abertos! Fortaleza concluda.", Color3.fromRGB(80,255,120))
    end
}

-- ============================================================
-- GUI
-- ============================================================
local C = {
    bg       = Color3.fromRGB(9, 6, 3),
    header   = Color3.fromRGB(17, 11, 6),
    border   = Color3.fromRGB(66, 46, 18),
    accent   = Color3.fromRGB(245, 160, 28),
    green    = Color3.fromRGB(245, 160, 28),
    greenDim = Color3.fromRGB(55, 36, 12),
    red      = Color3.fromRGB(255, 176, 60),
    redDim   = Color3.fromRGB(58, 34, 10),
    yellow   = Color3.fromRGB(255, 205, 90),
    text     = Color3.fromRGB(244, 228, 194),
    muted    = Color3.fromRGB(161, 130, 89),
    rowBg    = Color3.fromRGB(27, 18, 9),
    rowHov   = Color3.fromRGB(37, 24, 12),
    btnOn    = Color3.fromRGB(124, 73, 15),
    btnOnHov = Color3.fromRGB(148, 88, 20),
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

-- Ttulo
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
Instance.new("UIStroke", closeBtn).Color = C.border

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
timerLbl.Text = "20:00"; timerLbl.TextColor3 = C.yellow
timerLbl.Font = Enum.Font.GothamBold; timerLbl.TextSize = 17

local timerBar = Instance.new("Frame", timerFrame)
timerBar.Size = UDim2.new(1,0,0,3); timerBar.Position = UDim2.new(0,0,1,-3)
timerBar.BackgroundColor3 = C.green; timerBar.BorderSizePixel = 0
Instance.new("UICorner", timerBar).CornerRadius = UDim.new(0,2)

-- Botes de passo (grid 2x3)
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
-- posio dinmica via updateLayout

-- Botes principais
local startBtn = Instance.new("TextButton", main)
startBtn.Size = UDim2.new(1,-20,0,36)
startBtn.BackgroundColor3 = C.btnOn
startBtn.Text = "INICIAR TUDO"; startBtn.TextColor3 = Color3.fromRGB(255,255,255)
startBtn.Font = Enum.Font.GothamBold; startBtn.TextSize = 13
startBtn.BorderSizePixel = 0
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0,7)
Instance.new("UIStroke", startBtn).Color = Color3.fromRGB(140, 88, 22)

local stopBtn = Instance.new("TextButton", main)
stopBtn.Size = UDim2.new(1,-20,0,36)
stopBtn.BackgroundColor3 = C.redDim
stopBtn.Text = "PARAR"; stopBtn.TextColor3 = Color3.fromRGB(255,255,255)
stopBtn.Font = Enum.Font.GothamBold; stopBtn.TextSize = 13
stopBtn.BorderSizePixel = 0; stopBtn.Visible = false
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0,7)
Instance.new("UIStroke", stopBtn).Color = C.border

-- Funo para reposicionar btns de ao
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
-- LGICA DE EXECUO
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
        -- skipWait=true: botes individuais nunca ficam presos esperando disponibilidade
        pcall(function() steps[i].run(setStatus, startTimerFn, true) end)
        if not uiDestroyed then isRunning = false; lockBtns(false) end
    end)
    table.insert(threads, t)
end

local function runAll()
    if isRunning then return end
    isRunning = true
    thirdGateOpened = false
    resetFinalGateProbe()
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
-- EVENTOS DOS BOTES
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
closeBtn.MouseEnter:Connect(function() closeBtn.BackgroundColor3 = Color3.fromRGB(86,52,16) end)
closeBtn.MouseLeave:Connect(function() closeBtn.BackgroundColor3 = C.redDim end)

-- ============================================================
-- TIMER HEARTBEAT (leve)
-- ============================================================
local hb = RunService.Heartbeat:Connect(function()
    if uiDestroyed or not timerActive then return end
    local rem = timerEnd - os.clock()
    if rem <= 0 then
        timerActive = false
        timerLbl.Text = "00:00 RESET!"; timerLbl.TextColor3 = Color3.fromRGB(235,70,55)
        timerBar.Size = UDim2.new(0,0,0,3); ts.Color = Color3.fromRGB(235,70,55)
        return
    end
    local frac = math.clamp(rem/(20*60),0,1)
    timerLbl.Text = string.format("%02d:%02d", math.floor(rem/60), math.floor(rem%60))
    timerBar.Size = UDim2.new(frac,0,0,3)
    local c = frac > 0.5 and C.accent
           or frac > 0.2 and C.yellow
           or Color3.fromRGB(235,70,55)
    timerBar.BackgroundColor3 = c; ts.Color = c
    timerLbl.TextColor3 = frac > 0.5 and C.accent
                       or frac > 0.2 and C.yellow
                       or Color3.fromRGB(245,95,80)
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
