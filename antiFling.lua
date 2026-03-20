print('[KAH][LOAD] antiFling.lua')
-- ============================================
-- MODULO: ANTI FLING GUARD (Kahrrasco only)
-- ============================================

local VERSION = "1.0"
local MODULE_NAME = "Anti Fling Guard"
local SIT_MODULE_NAME = "Sentar"
local CATEGORIA = "Player"
local STATE_KEY = "__kah_antifling_guard_state"

if not _G.Hub and not _G.HubFila then
    print("[KAH][WARN][AntiFling] hub nao encontrado, abortando")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local lp = Players.LocalPlayer
if not lp then
    return
end

local function isKahrrascoUser()
    local n = string.lower(tostring(lp.Name or ""))
    local d = string.lower(tostring(lp.DisplayName or ""))
    if n == "kahrrasco" or d == "kahrrasco" then
        return true
    end
    return tonumber(lp.UserId) == 10384315642
end

if not isKahrrascoUser() then
    return
end

do
    local old = _G[STATE_KEY]
    if old and old.cleanup then
        pcall(old.cleanup)
    end
    _G[STATE_KEY] = nil
end

local LINEAR_SPIKE = tonumber(_G.KAH_ANTIFLING_LINEAR_SPIKE) or 140
local ANGULAR_SPIKE = tonumber(_G.KAH_ANTIFLING_ANGULAR_SPIKE) or 220
local DISPLACE_SPIKE = tonumber(_G.KAH_ANTIFLING_DISPLACE_SPIKE) or 40
local NEAR_RADIUS = tonumber(_G.KAH_ANTIFLING_NEAR_RADIUS) or 16
local ACTION_COOLDOWN = tonumber(_G.KAH_ANTIFLING_ACTION_COOLDOWN) or 0.65
local SAFE_SNAPSHOT_INTERVAL = tonumber(_G.KAH_ANTIFLING_SAFE_INTERVAL) or 0.22
local AUTO_SIT_ON_THREAT = true
local AUTO_SIT_LOOP_INTERVAL = 0.18

local enabled = false
local sitEnabled = false
local destroyed = false
local conns = {}
local lastActionAt = 0
local lastSafeAt = 0
local lastNotifyAt = 0
local lastPos = nil
local safeCF = nil
local lastSitLoopAt = 0

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(conns, c)
    return c
end

local function getCharacterBits()
    local char = lp.Character
    if not char then
        return nil, nil, nil
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    return char, hum, root
end

local function notify(text)
    local now = os.clock()
    if (now - lastNotifyAt) < 1.5 then
        return
    end
    lastNotifyAt = now
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Anti Fling",
            Text = tostring(text or ""),
            Duration = 2.0,
        })
    end)
end

local function sanitizePlayerName(raw)
    local s = tostring(raw or "")
    s = s:gsub("^%s*@+", "")
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function setHumanoidSit()
    local _, hum = getCharacterBits()
    if hum then
        pcall(function()
            hum.Sit = true
        end)
        return true
    end
    return false
end

local function zeroCharacterVelocity(char)
    if not char then
        return
    end
    for _, inst in ipairs(char:GetDescendants()) do
        if inst:IsA("BasePart") then
            pcall(function()
                inst.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                inst.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)
        end
    end
end

local function findNearbyThreat(refPos)
    if typeof(refPos) ~= "Vector3" then
        return nil
    end

    local best = nil
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local c = plr.Character
            local root = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
            if root and root:IsA("BasePart") then
                local dist = (root.Position - refPos).Magnitude
                if dist <= NEAR_RADIUS then
                    local speed = root.AssemblyLinearVelocity.Magnitude
                    local spin = root.AssemblyAngularVelocity.Magnitude
                    local score = speed + (spin * 0.15)
                    if (not best) or score > best.score then
                        best = {
                            player = plr,
                            dist = dist,
                            speed = speed,
                            spin = spin,
                            score = score,
                        }
                    end
                end
            end
        end
    end
    return best
end

local function setEnabled(v)
    enabled = (v == true)
    if enabled then
        local _, _, root = getCharacterBits()
        lastPos = root and root.Position or nil
        safeCF = root and root.CFrame or safeCF
        lastSafeAt = os.clock()
    end
end

local function setSitEnabled(v)
    sitEnabled = (v == true)
    if sitEnabled then
        setHumanoidSit()
        lastSitLoopAt = os.clock()
    end
end

local function applyProtection(attackerName)
    local now = os.clock()
    if (now - lastActionAt) < ACTION_COOLDOWN then
        return
    end
    lastActionAt = now

    local char, hum, root = getCharacterBits()
    if not char or not hum or not root then
        return
    end

    if AUTO_SIT_ON_THREAT then
        pcall(function()
            hum.Sit = true
        end)
    end

    zeroCharacterVelocity(char)

    if typeof(safeCF) == "CFrame" and (root.Position - safeCF.Position).Magnitude > 8 then
        pcall(function()
            root.CFrame = safeCF
        end)
    end

    task.delay(0.08, function()
        if destroyed or not enabled then
            return
        end
        local c2, h2 = getCharacterBits()
        if c2 then
            zeroCharacterVelocity(c2)
        end
        if AUTO_SIT_ON_THREAT and h2 then
            pcall(function()
                h2.Sit = true
            end)
        end
    end)

    local cleanName = sanitizePlayerName(attackerName)
    if cleanName ~= "" then
        notify("Tentativa de fling: " .. cleanName)
    else
        notify("Tentativa de fling detectada")
    end
end

local function onHeartbeat(dt)
    if destroyed then
        return
    end

    if sitEnabled then
        local nowSit = os.clock()
        if (nowSit - lastSitLoopAt) >= AUTO_SIT_LOOP_INTERVAL then
            setHumanoidSit()
            lastSitLoopAt = nowSit
        end
    end

    if not enabled then
        return
    end

    local char, hum, root = getCharacterBits()
    if not char or not hum or not root then
        return
    end
    if hum.Health <= 0 then
        return
    end

    local pos = root.Position
    if typeof(lastPos) ~= "Vector3" then
        lastPos = pos
        safeCF = root.CFrame
        lastSafeAt = os.clock()
        return
    end

    local linear = root.AssemblyLinearVelocity.Magnitude
    local angular = root.AssemblyAngularVelocity.Magnitude
    local speed2d = (pos - lastPos).Magnitude / math.max(tonumber(dt) or 0.016, 0.008)
    lastPos = pos

    local now = os.clock()
    if linear < 24 and angular < 36 and (now - lastSafeAt) >= SAFE_SNAPSHOT_INTERVAL then
        safeCF = root.CFrame
        lastSafeAt = now
    end

    local nearby = findNearbyThreat(pos)
    local nearThreat = nearby and ((nearby.speed > 60) or (nearby.spin > 110)) or false

    local extreme = (linear >= LINEAR_SPIKE) or (angular >= ANGULAR_SPIKE) or (speed2d >= DISPLACE_SPIKE)
    local veryExtreme = (linear >= (LINEAR_SPIKE * 1.8)) or (angular >= (ANGULAR_SPIKE * 1.8))

    if (extreme and nearThreat) or veryExtreme then
        local nearPlayer = nearby and nearby.player
        local attackerLabel = nil
        if nearPlayer then
            attackerLabel = nearPlayer.DisplayName or nearPlayer.Name
            if attackerLabel == nil or attackerLabel == "" then
                attackerLabel = nearPlayer.Name
            end
        end
        applyProtection(attackerLabel)
    end
end

local function syncHubState()
    if _G.Hub and _G.Hub.setEstado then
        pcall(function()
            _G.Hub.setEstado(MODULE_NAME, enabled)
            _G.Hub.setEstado(SIT_MODULE_NAME, sitEnabled)
        end)
    end
end

local function cleanup()
    if destroyed then
        return
    end
    destroyed = true
    local apiRef = _G[STATE_KEY]
    for _, c in ipairs(conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    table.clear(conns)
    if _G.Hub and _G.Hub.remover then
        pcall(function()
            _G.Hub.remover(MODULE_NAME)
            _G.Hub.remover(SIT_MODULE_NAME)
        end)
    end
    _G[STATE_KEY] = nil
    if _G.__kah_antifling_guard == apiRef then
        _G.__kah_antifling_guard = nil
    end
end

local function onToggle(ativo)
    setEnabled(ativo)
    syncHubState()
end

local function onSitToggle(ativo)
    setSitEnabled(ativo)
    syncHubState()
end

connect(RunService.Heartbeat, onHeartbeat)
connect(lp.CharacterAdded, function(char)
    task.wait(0.2)
    if destroyed then
        return
    end
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    lastPos = root and root.Position or nil
    safeCF = root and root.CFrame or nil
    lastSafeAt = os.clock()
    if sitEnabled then
        task.delay(0.1, function()
            if not destroyed and sitEnabled then
                setHumanoidSit()
            end
        end)
    end
end)

if _G.Hub then
    if _G.Hub.remover then
        pcall(function()
            _G.Hub.remover(MODULE_NAME)
            _G.Hub.remover(SIT_MODULE_NAME)
        end)
    end
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, false)
    _G.Hub.registrar(SIT_MODULE_NAME, onSitToggle, CATEGORIA, false)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = MODULE_NAME,
        toggleFn = onToggle,
        categoria = CATEGORIA,
        jaAtivo = false
    })
    table.insert(_G.HubFila, {
        nome = SIT_MODULE_NAME,
        toggleFn = onSitToggle,
        categoria = CATEGORIA,
        jaAtivo = false
    })
end

_G[STATE_KEY] = {
    setEnabled = function(v)
        setEnabled(v == true)
        syncHubState()
    end,
    isEnabled = function()
        return enabled
    end,
    setSitEnabled = function(v)
        setSitEnabled(v == true)
        syncHubState()
    end,
    isSitEnabled = function()
        return sitEnabled
    end,
    sitNow = setHumanoidSit,
    cleanup = cleanup,
}

_G.__kah_antifling_guard = _G[STATE_KEY]

print("[KAH][READY] ANTI FLING GUARD")
