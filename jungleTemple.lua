print('[KAH][LOAD] jungleTemple.lua')
-- ============================================
-- MODULE: JUNGLE TEMPLE (NO UI)
-- ============================================

local CATEGORIA = "Farm"
local MODULE_NAME = "JG Temple"
local STRONG_RUNNING_KEY  = "__kah_stronghold_running"
local STRONG_API_KEY      = "__kah_stronghold_api"
local MODULE_STATE_KEY    = "__jungle_temple_module_state"

if not _G.Hub and not _G.HubFila then
    return
end

do
    local old = _G[MODULE_STATE_KEY]
    if old and old.cleanup then
        pcall(old.cleanup)
    end
    _G[MODULE_STATE_KEY] = nil
end

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ============================================
-- CONSTANTES
-- ============================================
local CYCLE_COOLDOWN_SEC  = 305
local TIMER_DURATION_SEC  = 305
local RETRY_DELAY_SEC     = 3
local CHECK_INTERVAL_SEC  = 0.8
local CHEST_PREWAIT_SEC   = 5
local CHEST_BURST_SEC     = 5
local PODIUM_CACHE_SEC    = 20
local TEMPLE_NEAR_DIST    = 80

-- ============================================
-- ESTADO
-- ============================================
local enabled             = false
local running             = false
local loopThread          = nil
local unlockConns         = {}
local templeUnlockSignalAt = 0
local nextRunAt           = 0
local timerStartedAt      = nil
local toggleGeneration    = 0
local postTempleBusy      = false
local lastTempleCenter    = nil
local lastStatusText      = ""
local podiumCache         = nil
local podiumCacheStamp    = 0
local lastFailReason      = ""

local strongHoldPause     = false
local strongHoldResumeAt  = 0

-- ============================================
-- LOG SYSTEM
-- ============================================
local LOG_ENABLED = false
local _logBuffer  = {}

local function log(tag, msg, ...)
    if not LOG_ENABLED then return end
    local ok, txt = pcall(string.format, "[JGT][%s] " .. tostring(msg), tag, ...)
    if not ok then txt = "[JGT][" .. tag .. "] " .. tostring(msg) end
    print(txt)
    _logBuffer[#_logBuffer + 1] = string.format("%.2f %s", os.clock(), txt)
end

_G["logToggle_" .. MODULE_NAME] = function()
    LOG_ENABLED = not LOG_ENABLED
    if LOG_ENABLED then
        _logBuffer = {}
        print("[LOG] " .. MODULE_NAME .. " → ATIVO")
    else
        local out = table.concat(_logBuffer, "\n")
        if setclipboard then
            setclipboard(out)
            print("[LOG] " .. MODULE_NAME .. " → DESATIVADO | " .. #_logBuffer .. " linhas copiadas para clipboard")
        else
            print(out)
        end
        _logBuffer = {}
    end
end

-- ============================================
-- HELPERS DE TEMPO
-- ============================================
local function nowClock()
    return os.clock()
end

local function parseClockSeconds(text)
    if type(text) ~= "string" then return nil end
    local m, s = string.match(text, "(%d+)%s*[mM]%s*(%d+)%s*[sS]")
    if m and s then return (tonumber(m) or 0) * 60 + (tonumber(s) or 0) end
    local mm, ss = string.match(text, "(%d+)%s*:%s*(%d+)")
    if mm and ss then return (tonumber(mm) or 0) * 60 + (tonumber(ss) or 0) end
    return nil
end

local function formatTimer(secs)
    secs = math.max(0, math.floor(secs))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- ============================================
-- STRONGHOLD — API DE NOTIFICAÇÃO
-- ============================================
local function onStrongholdStart()
    log("STRONG", "recebeu notificação de INÍCIO do Stronghold, pausando")
    strongHoldPause = true
end

local function onStrongholdFinish()
    log("STRONG", "recebeu notificação de FIM do Stronghold, retomando")
    strongHoldPause = false
    strongHoldResumeAt = nowClock() + 2
end

_G.__kah_jgtemple_api = {
    onStrongholdStart  = onStrongholdStart,
    onStrongholdFinish = onStrongholdFinish,
}

local function isStrongHolding()
    if strongHoldPause then return true end
    if nowClock() < strongHoldResumeAt then return true end
    if _G[STRONG_RUNNING_KEY] == true then return true end
    return false
end

-- ============================================
-- TP VIA KAHtp (com fallback local)
-- ============================================
local function getHRP()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function tpLocal(cf)
    local hrp = getHRP()
    if not hrp then return false end
    local lock = true
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not lock then conn:Disconnect() return end
        local h = getHRP()
        if h then h.CFrame = cf end
    end)
    task.delay(0.9, function() lock = false end)
    return true
end

local function usarTp(fn)
    if _G.KAHtp then
        fn(_G.KAHtp)
    else
        _G.KAHtpFila = _G.KAHtpFila or {}
        table.insert(_G.KAHtpFila, function() fn(_G.KAHtp) end)
    end
end

local function tpCF(cf)
    usarTp(function(api)
        if api and api.teleportar then api.teleportar(cf)
        else tpLocal(cf) end
    end)
end

-- ============================================
-- OBJETO HELPERS
-- ============================================
local function getMainPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        local main = obj:FindFirstChild("Main", true)
        if main and main:IsA("BasePart") then return main end
        if obj.PrimaryPart then return obj.PrimaryPart end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
    local main = obj:FindFirstChild("Main", true)
    if main and main:IsA("BasePart") then return main end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function getCF(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.CFrame end
    if obj:IsA("Model") then
        local ok, cf = pcall(function() return obj:GetPivot() end)
        if ok and cf then return cf end
    end
    local main = getMainPart(obj)
    return main and main.CFrame or nil
end

local function moveObj(obj, cf)
    if not obj or not cf then return false end
    if obj:IsA("BasePart") then obj.CFrame = cf return true end
    if obj:IsA("Model") then
        local ok = pcall(function() obj:PivotTo(cf) end)
        if ok then return true end
    end
    local main = getMainPart(obj)
    if main then main.CFrame = cf return true end
    return false
end

local function getObjectPos(obj)
    local cf = getCF(obj)
    return cf and cf.Position or nil
end

local function playerDistTo(pos)
    local hrp = getHRP()
    if not hrp or not pos then return math.huge end
    return (hrp.Position - pos).Magnitude
end

-- ============================================
-- TELEPORTER
-- ============================================
local function getTempleCFFromTeleporter()
    local tp = _G.KAHtp
    if type(tp) ~= "table" then
        log("TP", "KAHtp não disponível")
        return nil
    end
    if type(tp.getTemploCf) == "function" then
        local ok, cf = pcall(tp.getTemploCf)
        if ok and typeof(cf) == "CFrame" then
            log("TP", "getTemploCf retornou CF")
            return cf
        end
    end
    if type(tp.getSlotCf) == "function" then
        local ok1, cf1 = pcall(tp.getSlotCf, "Templo")
        if ok1 and typeof(cf1) == "CFrame" then
            log("TP", "getSlotCf('Templo') OK")
            return cf1
        end
        local ok2, cf2 = pcall(tp.getSlotCf, "Jungle")
        if ok2 and typeof(cf2) == "CFrame" then
            log("TP", "getSlotCf('Jungle') OK")
            return cf2
        end
    end
    if type(tp.templo) == "function" then
        log("TP", "fallback: teleportando para capturar posição")
        local before = getHRP()
        local beforePos = before and before.Position
        local ok = pcall(tp.templo)
        if ok then
            task.wait(0.15)
            local after = getHRP()
            if after and beforePos and (after.Position - beforePos).Magnitude > 1 then
                return after.CFrame
            end
        end
    end
    log("TP", "nenhum método retornou CF")
    return nil
end

local function teleportToTemple()
    local refPos = lastTempleCenter
    if refPos and playerDistTo(refPos) <= TEMPLE_NEAR_DIST then
        log("TP", "player já está perto do templo (dist=%.1f)", playerDistTo(refPos))
        return true
    end
    local cfFromTp = getTempleCFFromTeleporter()
    if cfFromTp then
        log("TP", "teleportando para CF do teleporter")
        tpCF(cfFromTp)
        task.wait(1.0)
        return true
    end
    if lastTempleCenter then
        log("TP", "usando lastTempleCenter")
        tpCF(CFrame.new(lastTempleCenter))
        task.wait(1.0)
        return true
    end
    log("TP", "sem referência de posição do templo")
    return false
end

-- ============================================
-- PODIUMS
-- ============================================
local function scanPodiums()
    if podiumCache and #podiumCache > 0 and (nowClock() - podiumCacheStamp) <= PODIUM_CACHE_SEC then
        local valid = {}
        for _, p in ipairs(podiumCache) do
            if p and p.Parent and p.Name == "JungleGemPodium" then
                valid[#valid + 1] = p
            end
        end
        if #valid > 0 then
            podiumCache = valid
            log("SCAN", "cache hit: %d podiums", #valid)
            return valid
        end
    end

    local out = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == "JungleGemPodium" then
            out[#out + 1] = d
        end
    end
    log("SCAN", "scan completo: %d podiums encontrados", #out)
    if #out > 0 then
        podiumCache = out
        podiumCacheStamp = nowClock()
    end
    return out
end

local function allPodiumsFilled(podiums)
    for _, p in ipairs(podiums) do
        if p:GetAttribute("GemAdded") ~= true then return false end
    end
    return true
end

local function getCentro(podiums)
    local sum = Vector3.new(0, 0, 0)
    local count = 0
    for _, p in ipairs(podiums) do
        local pos = getObjectPos(p)
        if pos then sum += pos count += 1 end
    end
    if count <= 0 then return nil end
    return sum / count
end

-- ============================================
-- KEYS
-- ============================================
local function normalizeKeyRoot(inst)
    if not inst then return nil end
    local model = inst:IsA("Model") and inst or inst:FindFirstAncestorWhichIsA("Model")
    if model then return model end
    if inst:IsA("BasePart") then return inst end
    return nil
end

local function getKeys()
    local keys = {}
    local seen = {}
    local items = workspace:FindFirstChild("Items")
    if not items then
        log("KEYS", "pasta Items não encontrada")
        return keys
    end
    for _, d in ipairs(items:GetDescendants()) do
        local nm = string.lower(tostring(d.Name or ""))
        if string.find(nm, "crystal skull key", 1, true) then
            local root = normalizeKeyRoot(d)
            if root and not seen[root] and getMainPart(root) then
                seen[root] = true
                keys[#keys + 1] = root
            end
        end
    end
    log("KEYS", "%d chaves encontradas", #keys)
    return keys
end

local function getKeyMaisProxima(targetPos, keys, used)
    local best, bestDist
    for _, key in ipairs(keys) do
        if not used[key] then
            local p = getObjectPos(key)
            if p then
                local d = (p - targetPos).Magnitude
                if not bestDist or d < bestDist then
                    best = key
                    bestDist = d
                end
            end
        end
    end
    return best
end

-- ============================================
-- INTERAÇÃO COM PODIUMS
-- Método confirmado: InvokeServer(key, podium)
-- ============================================
local function checkGemAdded(podium, label)
    local added = podium:GetAttribute("GemAdded") == true
    log("RESULT", "%s → GemAdded=%s", label, tostring(added))
    return added
end

local function tryInvokeServer(remoteFn, podium, key, label)
    if not remoteFn then
        log("INVOKE", "[%s] RemoteFunction não encontrada", label)
        return false
    end
    log("INVOKE", "[%s] InvokeServer(key, podium)", label)
    pcall(function() remoteFn:InvokeServer(key, podium) end)
    return checkGemAdded(podium, label)
end

-- ============================================
-- UNLOCK EVENTS
-- ============================================
local function disconnectUnlockEvents()
    for i = #unlockConns, 1, -1 do
        local c = unlockConns[i]
        if c then pcall(function() c:Disconnect() end) end
        unlockConns[i] = nil
    end
end

local function bindUnlockEvents()
    if #unlockConns > 0 then return end
    local function bindEvent(name)
        local ev = RS:FindFirstChild(name, true)
        if ev and ev:IsA("RemoteEvent") then
            local c = ev.OnClientEvent:Connect(function()
                log("EVENT", "RemoteEvent '%s' recebido", name)
                templeUnlockSignalAt = nowClock()
            end)
            table.insert(unlockConns, c)
            log("EVENT", "bind OK em '%s'", name)
        else
            log("EVENT", "RemoteEvent '%s' não encontrado", name)
        end
    end
    bindEvent("UnlockJungleTempleAnimation")
    bindEvent("AnimateJungleTempleStairs")
end

-- ============================================
-- PÓS-ABERTURA: CHEST FARM BURST + GEM COLLECTOR
-- ============================================
local function ativarCollector(gen)
    if not enabled or gen ~= toggleGeneration then return end
    log("POST", "ativando Gem Collector")
    if _G.GemCollector and _G.GemCollector.ativar then
        pcall(_G.GemCollector.ativar)
    elseif _G.Hub then
        pcall(function() _G.Hub.setEstado("Gem Collector", true) end)
    end
end

local function runChestFarmBurst(gen, seconds)
    if not enabled or gen ~= toggleGeneration then return end
    local burstSec = math.max(0, tonumber(seconds) or CHEST_BURST_SEC)
    log("POST", "Chest Farm burst por %.1fs", burstSec)
    local api = _G.__kah_chest_farm_api
    if type(api) == "table" and type(api.runFor) == "function" then
        pcall(api.runFor, burstSec)
        return
    end
    if _G.Hub and _G.Hub.setEstado then
        pcall(function() _G.Hub.setEstado("Chest Farm", true) end)
        local untilAt = os.clock() + burstSec
        while os.clock() < untilAt do
            if not enabled or gen ~= toggleGeneration then break end
            task.wait(0.1)
        end
        pcall(function() _G.Hub.setEstado("Chest Farm", false) end)
    else
        local untilAt = os.clock() + burstSec
        while os.clock() < untilAt do
            if not enabled or gen ~= toggleGeneration then break end
            task.wait(0.1)
        end
    end
end

local function waitWithGuard(gen, seconds)
    local sec = math.max(0, tonumber(seconds) or 0)
    local untilAt = os.clock() + sec
    while os.clock() < untilAt do
        if not enabled or gen ~= toggleGeneration then
            return false
        end
        task.wait(0.1)
    end
    return true
end

-- ============================================
-- ON TEMPLE OPENED
-- ============================================
local function onTempleOpened()
    if not enabled then return end
    log("OPEN", "templo aberto! iniciando pós-abertura")
    timerStartedAt   = nowClock()
    podiumCache      = nil
    podiumCacheStamp = 0
    -- Avisa no chat do jogo via módulo SendMessage
    if _G.KAHChat and _G.KAHChat.temploAberto then
        pcall(_G.KAHChat.temploAberto)
    end
    if postTempleBusy then return end
    postTempleBusy = true
    local gen = toggleGeneration
    task.spawn(function()
        pcall(function()
            if not waitWithGuard(gen, CHEST_PREWAIT_SEC) then return end
            runChestFarmBurst(gen, CHEST_BURST_SEC)
            ativarCollector(gen)
        end)
        postTempleBusy = false
    end)
end

-- ============================================
-- CYCLE PRINCIPAL
-- ============================================
local function openTempleCycle()
    if not enabled then return false, "desabilitado" end

    templeUnlockSignalAt = -1

    -- ── FASE 1: LOCALIZAR PODIUMS ──────────────────────────────
    local podiums = scanPodiums()

    if #podiums == 0 then
        log("CYCLE", "podiums não visíveis, teleportando para templo")
        local ok = teleportToTemple()
        if not ok then
            return false, "sem referência de posição do templo para teleportar"
        end
        for attempt = 1, 4 do
            task.wait(0.6)
            podiums = scanPodiums()
            log("CYCLE", "re-scan pós-tp (%d): %d podiums", attempt, #podiums)
            if #podiums > 0 then break end
        end
    end

    if #podiums == 0 then
        return false, "podiums não encontrados (área não carregada?)"
    end

    if allPodiumsFilled(podiums) then
        log("CYCLE", "todos podiums já preenchidos, templo já aberto")
        return true, nil
    end

    -- ── FASE 2: GARANTIR PROXIMIDADE ──────────────────────────
    local centro = getCentro(podiums)
    if not centro then
        return false, "falha ao calcular centro dos podiums"
    end
    lastTempleCenter = centro

    local distAtual = playerDistTo(centro)
    log("CYCLE", "centro: (%.1f, %.1f, %.1f) | dist player: %.1f",
        centro.X, centro.Y, centro.Z, distAtual)

    if distAtual > TEMPLE_NEAR_DIST then
        log("CYCLE", "player longe (%.1f > %d), teleportando para o templo", distAtual, TEMPLE_NEAR_DIST)
        tpCF(CFrame.new(centro))
        task.wait(1.0)
        if not enabled then return false, "desabilitado durante tp para templo" end
        task.wait(0.5)
    else
        log("CYCLE", "player já próximo (%.1f), sem teleporte necessário", distAtual)
    end

    -- ── FASE 3: VERIFICAR CHAVES ───────────────────────────────
    local keys = getKeys()
    if #keys < #podiums then
        log("CYCLE", "chaves insuficientes na 1ª tentativa (%d/%d), aguardando streaming...", #keys, #podiums)
        task.wait(1.5)
        keys = getKeys()
        log("CYCLE", "chaves após espera: %d", #keys)
    end
    if #keys < #podiums then
        return false, string.format("chaves insuficientes (%d/%d)", #keys, #podiums)
    end

    -- ── FASE 4: POSICIONAR E INTERAGIR ────────────────────────
    tpCF(CFrame.new(centro))
    task.wait(0.8)
    if not enabled then return false, "desabilitado durante tp para centro" end

    local requestFn = nil
    local rf = RS:FindFirstChild("RequestAddJungleTempleGem", true)
    if rf and rf:IsA("RemoteFunction") then
        requestFn = rf
        log("CYCLE", "RemoteFunction encontrada: %s", rf.Name)
    else
        log("CYCLE", "RemoteFunction NÃO encontrada")
    end

    -- Posiciona chaves nos podiums
    local used = {}
    local positioned = {}
    for i, podium in ipairs(podiums) do
        if not enabled then return false, "desabilitado durante posicionamento" end
        if podium:GetAttribute("GemAdded") == true then continue end
        local podiumCF = getCF(podium)
        if not podiumCF then
            return false, string.format("podium %d sem CFrame", i)
        end
        local key = getKeyMaisProxima(podiumCF.Position, keys, used)
        if not key then
            return false, string.format("sem chave disponível para podium %d", i)
        end
        log("CYCLE", "posicionando chave no podium %d", i)
        moveObj(key, podiumCF * CFrame.new(0, 3, 0))
        used[key] = true
        positioned[i] = key
        task.wait(0.05)
    end

    task.wait(0.1)

    -- Interage com cada podium — método confirmado: InvokeServer(key, podium)
    local cycleStartedAt = nowClock()

    for i, key in ipairs(positioned) do
        if not enabled then return false, "desabilitado durante interação" end
        if not key then continue end
        local podium = podiums[i]
        if not podium or podium:GetAttribute("GemAdded") == true then
            log("CYCLE", "podium %d já preenchido, pulando", i)
            continue
        end
        local podiumCF = getCF(podium)
        if podiumCF then
            moveObj(key, podiumCF * CFrame.new(0, 3, 0))
            task.wait(0.05)
        end
        log("CYCLE", "interagindo podium %d", i)
        tryInvokeServer(requestFn, podium, key, string.format("p%d", i))
        task.wait(0.05)
    end

    -- Aguarda sinal de abertura
    local timeoutAt = nowClock() + 14
    while nowClock() < timeoutAt do
        if not enabled then return false, "desabilitado aguardando sinal" end
        if templeUnlockSignalAt >= cycleStartedAt then
            onTempleOpened()
            return true, nil
        end
        task.wait(0.25)
    end

    log("CYCLE", "FALHA: timeout 14s sem RemoteEvent de abertura")
    return false, "timeout: nenhum método de interação funcionou (14s)"
end

-- ============================================
-- RUNNER
-- ============================================
local function stopRunner()
    running = false
    postTempleBusy = false
    if loopThread then
        task.cancel(loopThread)
        loopThread = nil
    end
    disconnectUnlockEvents()
end

local function startRunner()
    if loopThread then return end
    local runGen = toggleGeneration
    bindUnlockEvents()
    nextRunAt = 0
    loopThread = task.spawn(function()
        while enabled and runGen == toggleGeneration do
            if #unlockConns == 0 then bindUnlockEvents() end

            if (not running) and nowClock() >= nextRunAt then
                if isStrongHolding() then
                    log("RUNNER", "aguardando Stronghold terminar")
                    nextRunAt = nowClock() + CHECK_INTERVAL_SEC
                else
                    running = true
                    local okRun, opened, failReason = pcall(function()
                        local ok, reason = openTempleCycle()
                        return ok, reason
                    end)

                    local cycleOpened, cycleReason
                    if okRun then
                        cycleOpened = opened
                        cycleReason = failReason
                    else
                        cycleOpened = false
                        cycleReason = "erro interno: " .. tostring(opened)
                    end

                    running = false

                    if cycleOpened then
                        lastFailReason = ""
                        log("RUNNER", "ciclo bem-sucedido, cooldown %ds", CYCLE_COOLDOWN_SEC)
                        nextRunAt = nowClock() + CYCLE_COOLDOWN_SEC
                    else
                        lastFailReason = cycleReason or "motivo desconhecido"
                        log("RUNNER", "ciclo falhou: %s | retry em %ds", lastFailReason, RETRY_DELAY_SEC)
                        nextRunAt = nowClock() + RETRY_DELAY_SEC
                    end
                end
            end

            task.wait(CHECK_INTERVAL_SEC)
        end
        running = false
    end)
end

local function onToggle(ativo)
    local want = (ativo == true)
    if want == enabled then
        if want then
            if not loopThread then startRunner() end
        else
            if loopThread then stopRunner() end
        end
        return
    end
    enabled = want
    toggleGeneration += 1
    if enabled then
        podiumCache = nil
        podiumCacheStamp = 0
        log("TOGGLE", "módulo ATIVADO")
        startRunner()
    else
        log("TOGGLE", "módulo DESATIVADO")
        stopRunner()
    end
end

-- ============================================
-- STATUS PROVIDER
-- ============================================
local function statusProvider()
    if not enabled then
        lastStatusText = ""
        return ""
    end
    if isStrongHolding() then
        lastStatusText = "STRONG"
        return lastStatusText
    end
    if running then
        lastStatusText = "RUN"
        return lastStatusText
    end
    if timerStartedAt then
        local elapsed   = nowClock() - timerStartedAt
        local remaining = TIMER_DURATION_SEC - elapsed
        if remaining > 0 then
            lastStatusText = "CD " .. formatTimer(remaining)
            return lastStatusText
        end
        timerStartedAt = nil
    end
    local waitLeft = math.max(0, math.floor((nextRunAt or 0) - nowClock()))
    if waitLeft > 0 then
        local suffix = (lastFailReason ~= "") and (" !" .. lastFailReason:sub(1, 20)) or ""
        lastStatusText = "WAIT " .. formatTimer(waitLeft) .. suffix
    else
        lastStatusText = "RUN?"
    end
    return lastStatusText
end

-- ============================================
-- REGISTRO NO HUB
-- ============================================
local opts = { statusProvider = statusProvider }

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, false, opts)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = MODULE_NAME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = false, opts = opts })
end

_G[MODULE_STATE_KEY] = {
    cleanup = function()
        enabled = false
        toggleGeneration += 1
        stopRunner()
        _G.__kah_jgtemple_api = nil
    end,
}
