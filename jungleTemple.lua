-- ============================================
-- MODULE: JUNGLE TEMPLE (NO UI)
-- ============================================

local CATEGORIA = "Auto"
local MODULE_NAME = "JG Temple"
local STRONG_RUNNING_KEY = "__kah_stronghold_running"

if not _G.Hub and not _G.HubFila then
    return
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local CYCLE_COOLDOWN_SEC = 5 * 60
local RETRY_DELAY_SEC = 8
local CHECK_INTERVAL_SEC = 0.8
local STRONG_PRIORITY_SEC = 60

-- Offsets relativos ao centro dos podiums (calculados da sessao de referencia)
local OFFSET_POS1 = Vector3.new(0, -87, -55)
local OFFSET_POS2 = Vector3.new(-1, -87, 62)
local POS_ENTREGA = Vector3.new(24, 6, -4)

local enabled = false
local running = false
local loopThread = nil
local unlockConns = {}
local templeUnlockSignalAt = 0
local nextRunAt = 0
local lastStrongEnableTryAt = 0
local lastTempleOpenedAnnounceAt = 0
local centroCache = nil

local function nowClock()
    return os.clock()
end

local function parseClockSeconds(text)
    if type(text) ~= "string" then return nil end
    local m, s = string.match(text, "(%d+)%s*[mM]%s*(%d+)%s*[sS]")
    if m and s then
        return (tonumber(m) or 0) * 60 + (tonumber(s) or 0)
    end
    local mm, ss = string.match(text, "(%d+)%s*:%s*(%d+)")
    if mm and ss then
        return (tonumber(mm) or 0) * 60 + (tonumber(ss) or 0)
    end
    return nil
end

local function getByPath(root, ...)
    local cur = root
    for _, name in ipairs({...}) do
        if not cur then return nil end
        cur = cur:FindFirstChild(name)
    end
    return cur
end

local function readStrongholdSignSeconds()
    local body = getByPath(workspace, "Map", "Landmarks", "Stronghold", "Functional", "Sign", "SurfaceGui", "Frame", "Body")
    if body and body:IsA("TextLabel") then
        local secs = parseClockSeconds(body.Text)
        if secs ~= nil then return secs end
    end
    local sign = getByPath(workspace, "Map", "Landmarks", "Stronghold", "Functional", "Sign")
    if sign then
        for _, d in ipairs(sign:GetDescendants()) do
            if d:IsA("TextLabel") then
                local secs = parseClockSeconds(d.Text)
                if secs ~= nil then return secs end
            end
        end
    end
    return nil
end

local function isStrongExecuting()
    return _G[STRONG_RUNNING_KEY] == true
end

local function shouldPrioritizeStronghold()
    local secs = readStrongholdSignSeconds()
    if not secs then return false end
    if secs > STRONG_PRIORITY_SEC then return false end
    local now = nowClock()
    if (now - lastStrongEnableTryAt) >= 5 then
        lastStrongEnableTryAt = now
        if _G.Hub and _G.Hub.setEstado then
            pcall(function() _G.Hub.setEstado("Stronghold", true) end)
        end
    end
    return true
end

local function getHRP()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function tp(cf)
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

local function scanPodiums()
    local out = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == "JungleGemPodium" then
            out[#out + 1] = d
        end
    end
    return out
end

local function allPodiumsFilled(podiums)
    for _, p in ipairs(podiums) do
        if p:GetAttribute("GemAdded") ~= true then
            return false
        end
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
    if not items then return keys end
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
    return keys
end

local function getItemsByName(nomePartial)
    local out = {}
    local seen = {}
    local items = workspace:FindFirstChild("Items")
    if not items then return out end
    for _, d in ipairs(items:GetDescendants()) do
        local nm = string.lower(tostring(d.Name or ""))
        if string.find(nm, string.lower(nomePartial), 1, true) then
            local root = normalizeKeyRoot(d)
            if root and not seen[root] then
                seen[root] = true
                out[#out + 1] = root
            end
        end
    end
    return out
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

local function tryRequestAddGem(remoteFn, podium, key)
    if not remoteFn then return end
    pcall(function() remoteFn:InvokeServer() end)
    pcall(function() remoteFn:InvokeServer(podium) end)
    pcall(function() remoteFn:InvokeServer(key) end)
    pcall(function() remoteFn:InvokeServer(podium, key) end)
    pcall(function() remoteFn:InvokeServer(key, podium) end)
end

local function tryPrompts(obj)
    if type(fireproximityprompt) ~= "function" then return end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            pcall(function() fireproximityprompt(d) end)
            task.wait(0.03)
        end
    end
end

local function tryMouseClick(key)
    local main = getMainPart(key)
    if not main then return end
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(main.Position + Vector3.new(0, 3, 0))
        task.wait(0.2)
    end
    pcall(function()
        local mouse = player:GetMouse()
        moveObj(key, mouse.Hit)
        task.wait(0.1)
        mouse1press(main)
        task.wait(0.1)
        mouse1release(main)
    end)
end

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
                templeUnlockSignalAt = nowClock()
            end)
            table.insert(unlockConns, c)
        end
    end
    bindEvent("UnlockJungleTempleAnimation")
    bindEvent("AnimateJungleTempleStairs")
end

local function announceTempleOpened()
    local now = nowClock()
    if (now - lastTempleOpenedAnnounceAt) < 10 then return end
    lastTempleOpenedAnnounceAt = now
    pcall(function()
        local ev = RS:FindFirstChild("RequestBroadcastPing", true)
        if ev and ev:IsA("RemoteEvent") then ev:FireServer() end
    end)
    pcall(function()
        local tcs = game:GetService("TextChatService")
        local channels = tcs:FindFirstChild("TextChannels")
        local general = channels and (channels:FindFirstChild("RBXGeneral") or channels:FindFirstChild("General"))
        if general and general.SendAsync then
            general:SendAsync("Templo da Jungle esta aberto")
        end
    end)
end

local function collectAndDeliver()
    if not centroCache then return end

    local pos1 = centroCache + OFFSET_POS1
    local pos2 = centroCache + OFFSET_POS2

    -- TP pra posicao 1
    tp(CFrame.new(pos1 + Vector3.new(0, 3, 0)))
    task.wait(5)

    -- Coleta itens da posicao 1 (1 fragmento + 1 cultist gem)
    local itensPos1 = {}
    local fragmentos = getItemsByName("gem of the forest fragment")
    local cultists = getItemsByName("cultist gem")

    -- Pega o mais proximo de pos1
    local used = {}
    local frag1 = getKeyMaisProxima(pos1, fragmentos, used)
    if frag1 then used[frag1] = true table.insert(itensPos1, frag1) end
    local cult1 = getKeyMaisProxima(pos1, cultists, used)
    if cult1 then used[cult1] = true table.insert(itensPos1, cult1) end

    -- TP pra posicao 2
    tp(CFrame.new(pos2 + Vector3.new(0, 3, 0)))
    task.wait(5)

    -- Coleta itens da posicao 2 (1 fragmento + 2 cultist gems)
    local itensPos2 = {}
    local frag2 = getKeyMaisProxima(pos2, fragmentos, used)
    if frag2 then used[frag2] = true table.insert(itensPos2, frag2) end
    local cult2 = getKeyMaisProxima(pos2, cultists, used)
    if cult2 then used[cult2] = true table.insert(itensPos2, cult2) end
    local cult3 = getKeyMaisProxima(pos2, cultists, used)
    if cult3 then used[cult3] = true table.insert(itensPos2, cult3) end

    -- Junta todos os itens
    local todosItens = {}
    for _, v in ipairs(itensPos1) do table.insert(todosItens, v) end
    for _, v in ipairs(itensPos2) do table.insert(todosItens, v) end

    -- TP pra posicao de entrega e larga tudo lá
    tp(CFrame.new(POS_ENTREGA + Vector3.new(0, 3, 0)))
    task.wait(1)

    for _, item in ipairs(todosItens) do
        moveObj(item, CFrame.new(POS_ENTREGA))
        task.wait(0.2)
    end
end

local function openTempleCycle()
    local podiums = scanPodiums()
    if #podiums == 0 then return false end

    local keys = getKeys()
    if #keys < #podiums then return false end

    local centro = getCentro(podiums)
    if not centro then return false end
    centroCache = centro

    if allPodiumsFilled(podiums) then
        announceTempleOpened()
        task.spawn(collectAndDeliver)
        return true
    end

    tp(CFrame.new(centro + Vector3.new(0, 5, 0)))
    task.wait(0.8)

    local requestFn = nil
    local rf = RS:FindFirstChild("RequestAddJungleTempleGem", true)
    if rf and rf:IsA("RemoteFunction") then requestFn = rf end

    local used = {}
    local positioned = {}

    for i, podium in ipairs(podiums) do
        if podium:GetAttribute("GemAdded") == true then continue end
        local podiumCF = getCF(podium)
        if not podiumCF then return false end
        local key = getKeyMaisProxima(podiumCF.Position, keys, used)
        if not key then return false end
        moveObj(key, podiumCF * CFrame.new(0, 3, 0))
        used[key] = true
        positioned[i] = key
        task.wait(0.25)
    end

    task.wait(0.4)

    local cycleStartedAt = nowClock()

    for i, key in ipairs(positioned) do
        if not key then continue end
        local podium = podiums[i]
        if not podium or podium:GetAttribute("GemAdded") == true then continue end
        local podiumCF = getCF(podium)
        if not podiumCF then continue end
        moveObj(key, podiumCF * CFrame.new(0, 3, 0))
        task.wait(0.12)
        tryRequestAddGem(requestFn, podium, key)
        tryPrompts(podium)
        tryPrompts(key)
        tryMouseClick(key)
        task.wait(0.3)
    end

    local timeoutAt = nowClock() + 14
    while nowClock() < timeoutAt do
        if templeUnlockSignalAt >= cycleStartedAt then
            announceTempleOpened()
            task.spawn(collectAndDeliver)
            return true
        end
        if allPodiumsFilled(podiums) then
            announceTempleOpened()
            task.spawn(collectAndDeliver)
            return true
        end
        task.wait(0.25)
    end

    return false
end

local function stopRunner()
    if loopThread then
        task.cancel(loopThread)
        loopThread = nil
    end
    disconnectUnlockEvents()
    running = false
end

local function startRunner()
    if loopThread then return end
    bindUnlockEvents()
    nextRunAt = 0
    loopThread = task.spawn(function()
        while enabled do
            if #unlockConns == 0 then bindUnlockEvents() end
            if (not running) and nowClock() >= nextRunAt then
                if isStrongExecuting() then
                    nextRunAt = nowClock() + 1
                elseif shouldPrioritizeStronghold() then
                    nextRunAt = nowClock() + 2
                else
                    running = true
                    local okRun, opened = pcall(openTempleCycle)
                    running = false
                    if okRun and opened then
                        nextRunAt = nowClock() + CYCLE_COOLDOWN_SEC
                    else
                        nextRunAt = nowClock() + RETRY_DELAY_SEC
                    end
                end
            end
            task.wait(CHECK_INTERVAL_SEC)
        end
    end)
end

local function onToggle(ativo)
    enabled = (ativo == true)
    if enabled then startRunner()
    else stopRunner() end
end

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, false)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = MODULE_NAME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = false })
end