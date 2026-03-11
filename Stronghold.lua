-- ============================================================
--  STRONGHOLD AUTO - Xeno Executor
--  Versão 2 - Passo a Passo + Anti-Lag
-- ============================================================

-- ============================================================
-- POSIÇÕES (extraídas do relatório do servidor)
--
-- EntryDoors (porta externa):
--   DoorRight: X=-60,   Y=13.94, Z=-622.4
--   DoorLeft:  X=-71,   Y=13.94, Z=-622.4
--   → Frente da porta (fora):  X=-65.5, Y=15, Z=-612
--
-- LockedDoorsFloor1 (1° andar):
--   DoorRight: X=0.3,  Y=13.94, Z=-656.1
--   DoorLeft:  X=-7.5, Y=13.94, Z=-663.9
--   → Chegada (fora): X=-3.6, Y=15, Z=-648
--
-- LockedDoorsFloor2 (2° andar):
--   DoorRight: X=-79.7, Y=42.64, Z=-664
--   DoorLeft:  X=-79.7, Y=42.64, Z=-653
--   → Chegada (fora): X=-68, Y=44, Z=-658.5
--
-- FinalGate:  X=-2.08, Y=56.94, Z=-643
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local lp = Players.LocalPlayer
local localUserId = tostring(lp.UserId)

-- ============================================================
-- ESTADO
-- ============================================================
local timerActive      = false
local timerEnd         = 0
local uiDestroyed      = false
local connections      = {}
local threads          = {}
local chatEnviado      = false   -- evita mandar chat 2x
local fortalezaFinalizada = false -- true após baús abertos (pula passos já feitos)

-- Checa se fortaleza está "em andamento mas não finalizada"
-- (entrada aberta = já entrou, mas ainda não finalizou)
local function fortalezaAberta()
    local ed
    pcall(function() ed = workspace.Map.Landmarks.Stronghold.Functional.EntryDoors end)
    if not ed then return false end
    return ed:GetAttribute("DoorOpen") == true
end

-- ============================================================
-- PATHFINDER COM MEMÓRIA
-- Explora em direção ao destino, detecta travamento por parede,
-- grava waypoints que funcionaram. Na próxima run usa a rota
-- gravada direto, sem explorar.
-- ============================================================
local learnedRoute = nil  -- nil = ainda não aprendeu, tabela = rota gravada

-- Distância 2D (ignora Y) entre dois Vector3
local function dist2D(a, b)
    return math.sqrt((a.X - b.X)^2 + (a.Z - b.Z)^2)
end

-- Verifica se o player realmente se moveu (não preso em parede)
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

    setStatus("🗺  Usando rota memorizada...", Color3.fromRGB(120,220,255))
    for i, wp in ipairs(learnedRoute) do
        setStatus(string.format("🗺  Waypoint %d/%d...", i, #learnedRoute), Color3.fromRGB(120,220,255))
        hum:MoveTo(wp)
        -- espera chegar ou timeout proporcional à distância
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

-- Exploração com aprendizado:
-- Move em direção ao alvo usando pequenos passos.
-- Se travar, tenta desvios laterais.
-- Grava todos os waypoints que avançaram de verdade.
-- Ao chegar, poda a rota (remove pontos redundantes) e salva.
local function exploreToTarget(setStatus, startPos, targetPos)
    local char = lp.Character
    if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    local STEP       = 5     -- studs por passo (menor = mais preciso)
    local STUCK_TIME = 0.4   -- segundos sem mover = preso (mais rápido)
    local MAX_TRIES  = 200   -- iterações máximas
    local GOAL_DIST  = 4     -- studs para considerar chegou

    local waypoints  = { startPos }  -- pontos que realmente avançaram
    local tries      = 0

    -- Direções de desvio quando preso: direita, esquerda, trás+direita, trás+esquerda
    local function desvios(dir)
        return {
            Vector3.new( dir.Z, 0, -dir.X),   -- 90° direita
            Vector3.new(-dir.Z, 0,  dir.X),   -- 90° esquerda
            Vector3.new( dir.Z, 0,  dir.X),   -- diagonal direita-frente
            Vector3.new(-dir.Z, 0, -dir.X),   -- diagonal esquerda-frente
        }
    end

    setStatus("🔍 Explorando rota (1ª vez)...", Color3.fromRGB(255,200,80))

    while dist2D(root.Position, targetPos) > GOAL_DIST and tries < MAX_TRIES do
        tries += 1
        local curPos = root.Position
        local toTarget = (Vector3.new(targetPos.X, curPos.Y, targetPos.Z) - curPos)
        local dirNorm  = toTarget.Magnitude > 0 and toTarget.Unit or Vector3.new(0,0,-1)

        -- Tenta mover em direção ao alvo
        local nextPos = curPos + dirNorm * STEP
        nextPos = Vector3.new(nextPos.X, 15, nextPos.Z)
        hum:MoveTo(nextPos)
        task.wait(STUCK_TIME)

        if playerMoved(root, curPos, 1.5) then
            -- Avançou: grava waypoint
            local last = waypoints[#waypoints]
            if dist2D(root.Position, last) > 3 then
                table.insert(waypoints, root.Position)
            end
        else
            -- Preso: tenta desvios
            local moved = false
            for _, d in ipairs(desvios(dirNorm)) do
                local alt = curPos + d * STEP
                alt = Vector3.new(alt.X, 15, alt.Z)
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
    table.insert(waypoints, Vector3.new(targetPos.X, 15, targetPos.Z))

    -- Poda rota: remove waypoints intermediários que estão na mesma linha reta
    -- (se A→B→C são colineares, remove B)
    local function colinear(a, b, c, thresh)
        thresh = thresh or 2.5
        -- distância do ponto B à linha A→C
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
    setStatus(string.format("✅ Rota aprendida! %d waypoints.", #pruned), Color3.fromRGB(80,255,120))
    task.wait(0.5)
end

-- Ponto de partida e destino fixos do passo 3
local ROUTE_START  = Vector3.new(-65.5, 15, -616)   -- teleporte de entrada
local ROUTE_TARGET = Vector3.new(-3.6,  15, -644)   -- frente da porta 1 (Z=-644, porta fica em Z=-656)

-- ============================================================
-- LIMPEZA TOTAL
-- ============================================================
local function cleanup()
    timerActive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
    for _, t in ipairs(threads) do pcall(function() task.cancel(t) end) end
    threads = {}
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
-- timeout: segundos máximos antes de desistir (evita travar)
-- ============================================================
local function moveToAndWait(targetPos, timeout)
    local char = lp.Character
    if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    timeout = timeout or 15
    local arrived = false

    -- calcula distância e estima tempo mínimo pela velocidade real
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

-- Pequeno impulso inicial para destravar colisão/corpo antes do pathfinder.
-- Faz um pulo e anda para frente por alguns segundos.
local function jumpAndWalkForward(seconds)
    local char = lp.Character
    if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    local secs = math.max(0, tonumber(seconds) or 1)
    hum.Jump = true
    task.wait(0.1)

    local dir = root.CFrame.LookVector
    local flat = Vector3.new(dir.X, 0, dir.Z)
    if flat.Magnitude < 0.01 then
        flat = Vector3.new(0, 0, -1)
    else
        flat = flat.Unit
    end

    local speed = hum.WalkSpeed > 0 and hum.WalkSpeed or 16
    local target = root.Position + flat * (speed * secs)
    target = Vector3.new(target.X, root.Position.Y, target.Z)
    hum:MoveTo(target)
    task.wait(secs)
end

-- ============================================================
-- CHAT - 3 métodos em sequência (TextChatService → Legacy → Bubble)
-- ============================================================
local function sendChat(msg)
    -- Método 1: TextChatService (novo sistema Roblox)
    local ok1 = pcall(function()
        local tcs  = game:GetService("TextChatService")
        local chan  = tcs:FindFirstChild("TextChannels")
        local geral = chan and (chan:FindFirstChild("RBXGeneral") or chan:FindFirstChild("General"))
        if geral and geral.SendAsync then
            geral:SendAsync(msg)
        end
    end)
    task.wait(0.1)
    -- Método 2: Legacy SayMessageRequest
    if not ok1 then
        pcall(function()
            local r   = game:GetService("ReplicatedStorage")
            local d   = r:FindFirstChild("DefaultChatSystemChatEvents")
            local say = d and d:FindFirstChild("SayMessageRequest")
            if say then say:FireServer(msg, "All") end
        end)
        task.wait(0.1)
    end
    -- Método 3: Bubble chat local (fallback garantido)
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

-- ============================================================
-- ESTADO DA ENTRADA:
--   "ready"    → DoorOpen=false + Interaction="Door" + não DoorLocked
--   "cooldown" → DoorOpen=false + sem Interaction  (entre runs)
--   "open"     → DoorOpen=true  (já aberta nesta run)
-- ============================================================
local function entryState()
    local ed
    pcall(function() ed = workspace.Map.Landmarks.Stronghold.Functional.EntryDoors end)
    if not ed then return "cooldown" end
    local isOpen      = ed:GetAttribute("DoorOpen")
    local isLocked    = ed:GetAttribute("DoorLocked") or ed:GetAttribute("DoorLockedClient")
    local interaction = ed:GetAttribute("Interaction")  -- presente só quando disponível
    if isOpen == true  then return "open" end
    if isLocked        then return "cooldown" end
    if interaction == "Door" then return "ready" end
    -- sem Interaction = em cooldown/aguardando reset do servidor
    return "cooldown"
end

local function isEntryReady()
    return entryState() == "ready"
end

-- ============================================================
-- VERIFICA 3ª PORTA
-- ============================================================
local function isFloor3Open()
    -- A Floor3.EnemySpawnDoor.Door não tem atributo DoorOpen.
    -- O sinal real é o FinalGate: quando a onda 3 termina, o servidor
    -- dispara StrongholdOpenGate e move o FinalGate do OriginalCF.
    -- Detectamos isso comparando a CFrame atual com o OriginalCF gravado.
    local gate
    pcall(function()
        gate = workspace.Map.Landmarks.Stronghold.Functional.FinalGate
    end)
    if not gate then return false end

    local part = gate:FindFirstChildWhichIsA("BasePart")
        or gate:FindFirstChildWhichIsA("UnionOperation")
        or gate:FindFirstChildWhichIsA("MeshPart")
    if not part then return false end

    -- OriginalCF está gravado como atributo no FinalGate
    local origCF = gate:GetAttribute("OriginalCF")
    if not origCF then
        -- sem OriginalCF = gate já foi destruído ou movido pelo servidor
        return true
    end

    -- Compara posição atual com original (threshold 2 studs)
    local diff = (part.CFrame.Position - origCF.Position).Magnitude
    return diff > 2
end

-- ============================================================
-- ABRE BAÚS
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
-- DEFINIÇÃO DOS PASSOS
-- ============================================================
local function startTimer_fn(timerFrame, updateLayout)
    timerActive = true
    timerEnd    = os.clock() + (20 * 60)
    timerFrame.Visible = true
    updateLayout()
end

local steps = {}

-- skipWait = true quando chamado pelo botão individual (ignora verificação de disponibilidade)
steps[1] = {
    label = "1 · Aguardar Entrada",
    run = function(setStatus, _startTimer, skipWait)
        if skipWait then
            -- modo teste: teleporta direto, mostra estado da porta
            local state = entryState()
            local stateMsg = state == "ready"    and " [PRONTA]"
                          or state == "open"     and " [JÁ ABERTA]"
                          or                        " [EM COOLDOWN]"
            tpTo(Vector3.new(-65.5, 15, -612))
            setStatus("✅ Na frente da entrada" .. stateMsg, Color3.fromRGB(80,255,120))
        else
            -- Pula se entrada já aberta (run em andamento)
            if fortalezaAberta() and not fortalezaFinalizada then
                setStatus("⏩ Entrada já aberta, pulando passo 1...", Color3.fromRGB(180,180,80))
                return
            end
            setStatus("⏳ Verificando porta de entrada...")
            local state = entryState()
            if state == "cooldown" then
                setStatus("⌛ Fortaleza em cooldown. Aguardando próxima abertura...", Color3.fromRGB(255,130,50))
                repeat task.wait(3) until entryState() ~= "cooldown"
            end
            tpTo(Vector3.new(-65.5, 15, -612))
            setStatus("✅ Na frente da entrada.", Color3.fromRGB(80,255,120))
        end
    end
}

steps[2] = {
    label = "2 · Abrir + Chat",
    run = function(setStatus, _startTimer, skipWait)
        -- Pula se entrada já aberta e chat já enviado
        if not skipWait and fortalezaAberta() and chatEnviado and not fortalezaFinalizada then
            setStatus("⏩ Porta já aberta + chat já enviado, pulando passo 2...", Color3.fromRGB(180,180,80))
            return
        end
        if not fortalezaAberta() then
            setStatus("🚪 Abrindo porta de entrada...")
            firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","EntryDoors","DoorRight","Main","ProximityAttachment","ProximityInteraction"))
            task.wait(0.3)
            firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","EntryDoors","DoorLeft","Main","ProximityAttachment","ProximityInteraction"))
            task.wait(0.4)
        else
            setStatus("ℹ️  Porta já aberta.")
        end
        if not chatEnviado then
            sendChat("Estou iniciando a Fortaleza")
            chatEnviado = true
            setStatus("✅ Chat enviado.", Color3.fromRGB(80,255,120))
        else
            setStatus("⏩ Chat já enviado anteriormente.", Color3.fromRGB(180,180,80))
        end
    end
}

steps[3] = {
    label = "3 · 1° Andar",
    run = function(setStatus, _startTimer, skipWait)
        -- Pula se porta1 já aberta e fortaleza em andamento
        local ld1
        pcall(function() ld1 = workspace.Map.Landmarks.Stronghold.Functional.Doors.LockedDoorsFloor1 end)
        local porta1Aberta = ld1 and ld1:GetAttribute("DoorOpen") == true
        if not skipWait and porta1Aberta and not fortalezaFinalizada then
            setStatus("⏩ Porta 1 já aberta, pulando passo 3...", Color3.fromRGB(180,180,80))
            return
        end

        -- Teleporta do ponto fixo e aguarda cair no chão
        setStatus("🏃 Teleportando para frente da entrada...")
        tpTo(ROUTE_START)
        task.wait(1.2)  -- aguarda personagem pousar no chão antes de mover
        setStatus("⬆️ Pulando e avançando para destravar...", Color3.fromRGB(120,220,255))
        jumpAndWalkForward(1)

        -- Navega até a frente da porta 1 (isso já spawna os cultistas pelo caminho)
        if learnedRoute then
            setStatus("🗺  Seguindo rota memorizada até porta 1...", Color3.fromRGB(120,220,255))
            followLearnedRoute(setStatus)
        else
            setStatus("🔍 Explorando rota até porta 1 (1ª vez)...", Color3.fromRGB(255,200,80))
            exploreToTarget(setStatus, ROUTE_START, ROUTE_TARGET)
        end

        setStatus("✅ Na frente da porta 1. Cultistas spawnados.", Color3.fromRGB(80,255,120))
    end
}

steps[4] = {
    label = "4 · 2° Andar + Aguardar Gate",
    run = function(setStatus, startTimer, skipWait)
        -- Pula se já finalizou
        if not skipWait and fortalezaFinalizada then
            setStatus("⏩ Fortaleza já finalizada, pulando...", Color3.fromRGB(180,180,80))
            return
        end

        -- Teleporta para frente da porta 2 e abre
        setStatus("🏃 Teleportando para frente da porta 2...")
        tpTo(Vector3.new(-68, 44, -658.5))
        task.wait(0.8)
        setStatus("🚪 Abrindo porta do 2° andar...")
        firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor2","DoorRight","Main","ProximityAttachment","ProximityInteraction"))
        task.wait(0.2)
        firePrompt(getByPath("Map","Landmarks","Stronghold","Functional","Doors","LockedDoorsFloor2","DoorLeft","Main","ProximityAttachment","ProximityInteraction"))
        task.wait(0.3)

        if skipWait then
            setStatus("✅ Porta 2 aberta (modo teste).", Color3.fromRGB(80,255,120))
            return
        end

        -- Aguarda aqui mesmo (frente da porta 2) até o FinalGate abrir
        setStatus("⚔️  Aguardando FinalGate... (mate os mobs!)", Color3.fromRGB(255,120,80))
        repeat task.wait(1) until isFloor3Open()

        -- Timer inicia no momento exato que o gate abre
        if not timerActive then
            startTimer()
        end
        setStatus("✅ FinalGate abriu! Timer iniciado. Teleportando para o baú...", Color3.fromRGB(80,255,120))
        task.wait(0.5)

        -- Teleporta direto para frente do Diamond Chest
        local chest = workspace.Items:FindFirstChild("Stronghold Diamond Chest", true)
            or workspace:FindFirstChild("Stronghold Diamond Chest", true)
        if chest then
            local bp = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart")
            if bp then
                tpTo(bp.Position + Vector3.new(0, 2, 4))
                setStatus("✅ Na frente do Diamond Chest!", Color3.fromRGB(80,255,120))
            end
        else
            setStatus("⚠️  Diamond Chest não encontrado.", Color3.fromRGB(255,100,100))
        end
    end
}

steps[5] = {
    label = "5 · Abrir Baús",
    run = function(setStatus, startTimer, skipWait)
        if skipWait then
            setStatus("ℹ️  Modo teste: use o passo 4 para aguardar o gate.", Color3.fromRGB(180,180,80))
            return
        end

        local chestFarmWasOn = false
        local chestFarmForcedOn = false
        if _G.Hub and _G.Hub.getEstado then
            chestFarmWasOn = _G.Hub.getEstado("Chest Farm") == true
        end

        if not chestFarmWasOn and _G.Hub and _G.Hub.setEstado then
            setStatus("🔁 Ativando Chest Farm temporariamente...", Color3.fromRGB(120,220,255))
            chestFarmForcedOn = _G.Hub.setEstado("Chest Farm", true) == true
            task.wait(0.2)
        end

        -- Abre o Diamond Chest e aguarda confirmação de abertura.
        setStatus("📦 Abrindo Diamond Chest...")
        openChestByName("Stronghold Diamond Chest")
        local opened = waitChestOpenedByName("Stronghold Diamond Chest", 15)
        if opened then
            setStatus("✅ Diamond Chest aberto.", Color3.fromRGB(80,255,120))
        else
            setStatus("⚠️ Diamond Chest sem confirmação (timeout).", Color3.fromRGB(255,140,80))
        end

        setStatus("📦 Abrindo baú próximo...")
        openNearestChest()
        task.wait(0.4)

        if chestFarmForcedOn and _G.Hub and _G.Hub.setEstado then
            setStatus("↩️ Restaurando Chest Farm...", Color3.fromRGB(120,220,255))
            _G.Hub.setEstado("Chest Farm", false)
            task.wait(0.2)
        end

        fortalezaFinalizada = true
        chatEnviado = false
        setStatus("🎉 Baús abertos! Fortaleza concluída.", Color3.fromRGB(80,255,120))
    end
}

-- ============================================================
-- GUI
-- ============================================================
local sg = Instance.new("ScreenGui")
sg.Name           = "StrongholdAutoGUI"
sg.ResetOnSpawn   = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = true
sg.Parent         = lp.PlayerGui

local main = Instance.new("Frame", sg)
main.Name             = "Main"
main.Size             = UDim2.new(0, 360, 0, 310)
main.Position         = UDim2.new(0.5, -180, 0.5, -155)
main.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
main.BorderSizePixel  = 0
main.Active           = true
main.Draggable        = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local ms = Instance.new("UIStroke", main)
ms.Color = Color3.fromRGB(150, 45, 245); ms.Thickness = 1.5

-- Título
local titleBar = Instance.new("Frame", main)
titleBar.Size             = UDim2.new(1, 0, 0, 38)
titleBar.BackgroundColor3 = Color3.fromRGB(20, 8, 35)
titleBar.BorderSizePixel  = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)
local tf = Instance.new("Frame", titleBar)
tf.Size = UDim2.new(1,0,0,10); tf.Position = UDim2.new(0,0,1,-10)
tf.BackgroundColor3 = Color3.fromRGB(20, 8, 35); tf.BorderSizePixel = 0

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size = UDim2.new(1,-46,1,0); titleLbl.Position = UDim2.new(0,12,0,0)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = "⚔  STRONGHOLD AUTO"
titleLbl.TextColor3 = Color3.fromRGB(185, 95, 255)
titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size = UDim2.new(0,28,0,28); closeBtn.Position = UDim2.new(1,-34,0,5)
closeBtn.BackgroundColor3 = Color3.fromRGB(165, 30, 30)
closeBtn.Text = "✕"; closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 12
closeBtn.BorderSizePixel = 0
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,6)

-- Status
local statusLbl = Instance.new("TextLabel", main)
statusLbl.Size = UDim2.new(1,-20,0,36); statusLbl.Position = UDim2.new(0,10,0,45)
statusLbl.BackgroundTransparency = 1; statusLbl.Text = "Pronto."
statusLbl.TextColor3 = Color3.fromRGB(175,175,195)
statusLbl.Font = Enum.Font.Gotham; statusLbl.TextSize = 12
statusLbl.TextWrapped = true; statusLbl.TextXAlignment = Enum.TextXAlignment.Left

local sep1 = Instance.new("Frame", main)
sep1.Size = UDim2.new(1,-20,0,1); sep1.Position = UDim2.new(0,10,0,87)
sep1.BackgroundColor3 = Color3.fromRGB(50,22,75); sep1.BorderSizePixel = 0

-- Timer
local timerFrame = Instance.new("Frame", main)
timerFrame.Size = UDim2.new(1,-20,0,38); timerFrame.Position = UDim2.new(0,10,0,94)
timerFrame.BackgroundColor3 = Color3.fromRGB(13,32,13)
timerFrame.BorderSizePixel = 0; timerFrame.Visible = false
Instance.new("UICorner", timerFrame).CornerRadius = UDim.new(0,6)
local ts = Instance.new("UIStroke", timerFrame)
ts.Color = Color3.fromRGB(55,175,55); ts.Thickness = 1

local timerLbl = Instance.new("TextLabel", timerFrame)
timerLbl.Size = UDim2.new(1,0,1,0); timerLbl.BackgroundTransparency = 1
timerLbl.Text = "⏱  20:00"; timerLbl.TextColor3 = Color3.fromRGB(75,250,115)
timerLbl.Font = Enum.Font.GothamBold; timerLbl.TextSize = 17

local timerBar = Instance.new("Frame", timerFrame)
timerBar.Size = UDim2.new(1,0,0,3); timerBar.Position = UDim2.new(0,0,1,-3)
timerBar.BackgroundColor3 = Color3.fromRGB(75,195,75); timerBar.BorderSizePixel = 0
Instance.new("UICorner", timerBar).CornerRadius = UDim.new(0,2)

-- Botões de passo (grid 2x3)
local btnGrid = Instance.new("Frame", main)
btnGrid.Name = "BtnGrid"
btnGrid.Size = UDim2.new(1,-20,0,130); btnGrid.Position = UDim2.new(0,10,0,94)
btnGrid.BackgroundTransparency = 1

local gl = Instance.new("UIGridLayout", btnGrid)
gl.CellSize = UDim2.new(0.5,-4,0,36); gl.CellPadding = UDim2.new(0,6,0,5)
gl.FillDirection = Enum.FillDirection.Horizontal; gl.SortOrder = Enum.SortOrder.LayoutOrder

local function updateLayout()
    if timerFrame.Visible then
        btnGrid.Position = UDim2.new(0,10,0,140)
        main.Size = UDim2.new(0,360,0,350)
    else
        btnGrid.Position = UDim2.new(0,10,0,94)
        main.Size = UDim2.new(0,360,0,310)
    end
end

local stepBtns = {}
for i, step in ipairs(steps) do
    local btn = Instance.new("TextButton", btnGrid)
    btn.BackgroundColor3 = Color3.fromRGB(26,16,46)
    btn.Text = step.label; btn.TextColor3 = Color3.fromRGB(195,160,255)
    btn.Font = Enum.Font.Gotham; btn.TextSize = 11
    btn.BorderSizePixel = 0; btn.LayoutOrder = i
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,5)
    local ss = Instance.new("UIStroke", btn)
    ss.Color = Color3.fromRGB(75,35,125); ss.Thickness = 1
    stepBtns[i] = btn
end

-- Separador 2
local sep2 = Instance.new("Frame", main)
sep2.Size = UDim2.new(1,-20,0,1)
sep2.BackgroundColor3 = Color3.fromRGB(50,22,75); sep2.BorderSizePixel = 0
-- posição dinâmica via updateLayout

-- Botões principais
local startBtn = Instance.new("TextButton", main)
startBtn.Size = UDim2.new(1,-20,0,36)
startBtn.BackgroundColor3 = Color3.fromRGB(105,30,195)
startBtn.Text = "▶  INICIAR TUDO"; startBtn.TextColor3 = Color3.fromRGB(255,255,255)
startBtn.Font = Enum.Font.GothamBold; startBtn.TextSize = 13
startBtn.BorderSizePixel = 0
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0,7)

local stopBtn = Instance.new("TextButton", main)
stopBtn.Size = UDim2.new(1,-20,0,36)
stopBtn.BackgroundColor3 = Color3.fromRGB(145,22,22)
stopBtn.Text = "■  PARAR"; stopBtn.TextColor3 = Color3.fromRGB(255,255,255)
stopBtn.Font = Enum.Font.GothamBold; stopBtn.TextSize = 13
stopBtn.BorderSizePixel = 0; stopBtn.Visible = false
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0,7)

-- Função para reposicionar btns de ação
local function layoutMainBtns()
    local baseY = timerFrame.Visible and 280 or 235
    sep2.Position  = UDim2.new(0,10,0,baseY)
    startBtn.Position = UDim2.new(0,10,0,baseY+8)
    stopBtn.Position  = UDim2.new(0,10,0,baseY+8)
    main.Size = UDim2.new(0,360,0,baseY+58)
end

-- ============================================================
-- LÓGICA DE EXECUÇÃO
-- ============================================================
local isRunning = false

local function setStatus(txt, color)
    if uiDestroyed then return end
    statusLbl.Text       = txt
    statusLbl.TextColor3 = color or Color3.fromRGB(175,175,195)
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
        -- skipWait=true: botões individuais nunca ficam presos esperando disponibilidade
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
-- EVENTOS DOS BOTÕES
-- ============================================================
for i, btn in ipairs(stepBtns) do
    btn.MouseButton1Click:Connect(function() runStep(i) end)
    btn.MouseEnter:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(42,26,70) end)
    btn.MouseLeave:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(26,16,46) end)
end

startBtn.MouseButton1Click:Connect(runAll)
startBtn.MouseEnter:Connect(function() startBtn.BackgroundColor3 = Color3.fromRGB(135,48,220) end)
startBtn.MouseLeave:Connect(function() startBtn.BackgroundColor3 = Color3.fromRGB(105,30,195) end)

stopBtn.MouseButton1Click:Connect(function()
    isRunning = false; cleanup()
    setStatus("⛔ Parado.", Color3.fromRGB(255,85,85))
    startBtn.Visible = true; stopBtn.Visible = false; lockBtns(false)
end)

closeBtn.MouseButton1Click:Connect(function()
    uiDestroyed = true; isRunning = false; cleanup(); sg:Destroy()
end)
closeBtn.MouseEnter:Connect(function() closeBtn.BackgroundColor3 = Color3.fromRGB(205,50,50) end)
closeBtn.MouseLeave:Connect(function() closeBtn.BackgroundColor3 = Color3.fromRGB(165,30,30) end)

-- ============================================================
-- TIMER HEARTBEAT (leve)
-- ============================================================
local hb = RunService.Heartbeat:Connect(function()
    if uiDestroyed or not timerActive then return end
    local rem = timerEnd - os.clock()
    if rem <= 0 then
        timerActive = false
        timerLbl.Text = "⏱  00:00  — RESET!"; timerLbl.TextColor3 = Color3.fromRGB(255,65,65)
        timerBar.Size = UDim2.new(0,0,0,3); ts.Color = Color3.fromRGB(255,65,65)
        return
    end
    local frac = math.clamp(rem/(20*60),0,1)
    timerLbl.Text = string.format("⏱  %02d:%02d", math.floor(rem/60), math.floor(rem%60))
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

-- Layout inicial
layoutMainBtns()
