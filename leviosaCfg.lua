print('[KAH][LOAD] leviosaCfg.lua')

-- ============================================
-- MODULE: LEVIOSA CFG
-- Painel flutuante (drag) que abre com Leviosa
-- e fecha com Finite Incantatem.
-- Controla: vel horizontal, vel vertical,
-- desaceleração, rebote claustrum, modo bola.
-- ============================================

local LVCFG_KEY = "__kah_leviosa_cfg_state"

do
    local old = _G[LVCFG_KEY]
    if old and type(old.cleanup) == "function" then pcall(old.cleanup) end
    _G[LVCFG_KEY] = nil
end

local Players  = game:GetService("Players")
local RS       = game:GetService("RunService")
local UIS      = game:GetService("UserInputService")
local TS       = game:GetService("TweenService")
local player   = Players.LocalPlayer

local function isKahrrascoUser()
    if not player then
        return false
    end
    local n = string.lower(tostring(player.Name or ""))
    local d = string.lower(tostring(player.DisplayName or ""))
    if n == "kahrrasco" or d == "kahrrasco" then
        return true
    end
    return tonumber(player.UserId) == 10384315642
end

if not isKahrrascoUser() then
    return
end

-- ============================================
-- CONFIG (valores default)
-- ============================================
_G.KAHLeviosaCfg = _G.KAHLeviosaCfg or {
    horizSpeed   = 48,
    vertSpeed    = 42,
    decel        = 0,
    bounceForce  = 1.8,
    bolaModo     = false,
    bolaGravity  = 0.25,
    bolaBouce    = 0.72,
    autoOpenWindow = true,
}
local cfg = _G.KAHLeviosaCfg
cfg.decel = 0
if cfg.autoOpenWindow == nil then
    cfg.autoOpenWindow = true
else
    cfg.autoOpenWindow = (cfg.autoOpenWindow == true)
end
local ENABLE_LEVIOSA_CFG_UI = false
if not ENABLE_LEVIOSA_CFG_UI then
    cfg.autoOpenWindow = false
end

-- ============================================
-- MODO BOLA
-- ============================================
local bolaConn = nil
local GROUND_Y_OFFSET = 3.1
local BOLA_REST_SPEED = 2.4
local BOLA_GROUND_EPS = 0.05
local BOLA_EXT_UP_MIN = 34
local BOLA_EXT_UP_GAIN = 0.45
local BOLA_EXT_UP_MAX = 30
local BOLA_WALL_PROBE_DIST = 2.8
local BOLA_WALL_BOUNCE_CD = 0.08
local BOLA_WALL_MIN_SPEED = 6
local BOLA_WALL_NORMAL_Y_MAX = 0.55
local BOLA_WALL_STUCK_SPEED_MAX = 2.2
local BOLA_WALL_STUCK_INTENT_MIN = 8
local BOLA_WALL_STUCK_TRIGGER_SEC = 0.12
local BOLA_WALL_PUSH_OUT = 0.65
local BOLA_WALL_PUSH_OUT_STUCK = 1.2
local BOLA_WALL_CORNER_ANGLE_A = 28
local BOLA_WALL_CORNER_ANGLE_B = 52
local BOLA_WALL_ESCAPE_ANGLE_STEP = 14
local BOLA_WALL_ESCAPE_MAX_SWEEP = 180
local BOLA_WALL_ESCAPE_CLEAR_PREF = 1.65
local BOLA_WALL_ESCAPE_CLEAR_GOOD = 2.35
local BOLA_PLAYER_BOUNCE_RADIUS = 4.3
local BOLA_PLAYER_BOUNCE_CD = 0.1
local BOLA_PLAYER_MIN_APPROACH = 2
local CLAUSTRUM_ZONE_VERTICES = {
    Vector3.new(-37.4992, 0, 32.0572),
    Vector3.new(59.4295, 0, 31.8768),
    Vector3.new(57.6074, 0, -34.6957),
    Vector3.new(-37.5256, 0, -34.4791),
}

local function claustrumBarrierIsActive()
    local s = _G.KAHCommandUiState
    if type(s) ~= "table" then
        return false
    end
    return s.leviosa == true and s.transitus ~= true
end

local function getHRP()
    local c = player.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function getHum()
    local c = player.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function makeBolaRayParams()
    local params = RaycastParams.new()
    pcall(function()
        params.FilterType = Enum.RaycastFilterType.Exclude
    end)
    pcall(function()
        params.FilterType = Enum.RaycastFilterType.Blacklist
    end)
    local ignore = {}
    local c = player.Character
    if c then
        table.insert(ignore, c)
    end
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true
    return params
end

local function stopBola()
    if bolaConn then bolaConn:Disconnect(); bolaConn = nil end
    local hrp = getHRP()
    if hrp then
        local bp = hrp:FindFirstChild("KAH_BolaBP")
        if bp then bp:Destroy() end
        local bg = hrp:FindFirstChild("KAH_BolaGrav")
        if bg then bg:Destroy() end
    end
    local hum = getHum()
    if hum then hum.PlatformStand = false end
end

local function startBola()
    stopBola()
    local hrp = getHRP()
    if not hrp then return end
    local hum = getHum()
    if hum then hum.PlatformStand = true end

    -- BodyPosition para simular queda com gravidade fake
    local bp = Instance.new("BodyPosition")
    bp.Name = "KAH_BolaBP"
    bp.MaxForce = Vector3.new(0, math.huge, 0)
    bp.Position = hrp.Position
    bp.D = 100
    bp.P = 5000
    bp.Parent = hrp

    -- BodyGyro pra manter orientação
    local bg = Instance.new("BodyGyro")
    bg.Name = "KAH_BolaGrav"
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.CFrame = hrp.CFrame
    bg.D = 100
    bg.P = 3000
    bg.Parent = hrp

    local velY = 0
    local posY = hrp.Position.Y
    local lastT = tick()
    local lastWallBounceAt = 0
    local lastPlayerBounceAt = 0
    local wallStuckSince = 0
    local lastMovingHv = Vector3.new(0, 0, 0)

    bolaConn = RS.Heartbeat:Connect(function()
        local hrpNow = getHRP()
        if not hrpNow then return end
        if not cfg.bolaModo then
            stopBola()
            return
        end

        local now = tick()
        local dt = math.min(now - lastT, 0.1)
        lastT = now
        local bounce = math.clamp(tonumber(cfg.bolaBouce) or 0.72, 0, 0.99)
        local rayParams = makeBolaRayParams()

        -- gravidade reduzida
        velY = velY - (196.2 * cfg.bolaGravity) * dt

        posY = posY + velY * dt

        -- detecta chao
        local ray = workspace:Raycast(
            hrpNow.Position,
            Vector3.new(0, -GROUND_Y_OFFSET - 0.5, 0),
            rayParams
        )
        local groundY = nil
        if ray then
            groundY = ray.Position.Y + GROUND_Y_OFFSET
        end

        if groundY and posY <= (groundY + BOLA_GROUND_EPS) then
            posY = groundY
            if velY < 0 then
                local impact = math.abs(velY)
                if impact <= BOLA_REST_SPEED or bounce <= 0 then
                    velY = 0
                else
                    velY = impact * bounce
                    if velY <= BOLA_REST_SPEED then
                        velY = 0
                    end
                end
            elseif math.abs(velY) <= BOLA_REST_SPEED then
                velY = 0
            end
        end

        -- teto
        local rayUp = workspace:Raycast(
            hrpNow.Position,
            Vector3.new(0, GROUND_Y_OFFSET + 0.5, 0),
            rayParams
        )
        if rayUp then
            local ceilY = rayUp.Position.Y - GROUND_Y_OFFSET
            if posY >= (ceilY - BOLA_GROUND_EPS) then
                posY = ceilY
                if velY > 0 then
                    velY = -math.abs(velY) * bounce
                    if math.abs(velY) <= BOLA_REST_SPEED then
                        velY = 0
                    end
                end
            end
        end

        -- impulso externo (colisão de outros jogadores / bombarda)
        local extVel = hrpNow.AssemblyLinearVelocity
        local extH = Vector3.new(extVel.X, 0, extVel.Z).Magnitude
        if extVel.Y > BOLA_EXT_UP_MIN and extH <= 8 and velY < extVel.Y then
            velY = math.min(extVel.Y * BOLA_EXT_UP_GAIN, BOLA_EXT_UP_MAX)
        end

        -- rebote horizontal (parede/player) sem perder velocidade
        do
            local av = hrpNow.AssemblyLinearVelocity
            local hv = Vector3.new(av.X, 0, av.Z)
            local hSpeed = hv.Magnitude
            local flyBv = hrpNow:FindFirstChildOfClass("BodyVelocity")
            local bouncedHoriz = false

            if hSpeed >= BOLA_WALL_STUCK_SPEED_MAX then
                lastMovingHv = hv
            end

            local function applyHorizontalReflection(reflected, speed, normal, markWall, pushOut)
                if typeof(reflected) ~= "Vector3" then
                    return false
                end
                if reflected.Magnitude <= 0.01 then
                    return false
                end
                local finalSpeed = math.max(0, tonumber(speed) or 0)
                if finalSpeed <= 0.01 then
                    return false
                end
                local pushValue = tonumber(pushOut) or BOLA_WALL_PUSH_OUT
                if typeof(normal) == "Vector3" and pushValue > 0 then
                    local push = Vector3.new(normal.X, 0, normal.Z)
                    if push.Magnitude > 0.01 then
                        reflected = reflected + (push.Unit * pushValue)
                    end
                end
                local newHv = reflected.Unit * finalSpeed
                hrpNow.AssemblyLinearVelocity = Vector3.new(newHv.X, av.Y, newHv.Z)
                if flyBv then
                    local bvVel = flyBv.Velocity
                    flyBv.Velocity = Vector3.new(newHv.X, bvVel.Y, newHv.Z)
                end
                if markWall then
                    lastWallBounceAt = now
                end
                wallStuckSince = 0
                return true
            end

            local function rotateYFlat(v, deg)
                if typeof(v) ~= "Vector3" then
                    return nil
                end
                local r = math.rad(tonumber(deg) or 0)
                local c = math.cos(r)
                local s = math.sin(r)
                return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
            end

            local function claustrumHitFromDir(dir)
                if not claustrumBarrierIsActive() then
                    return nil, nil
                end
                if typeof(dir) ~= "Vector3" then
                    return nil, nil
                end
                local flat = Vector3.new(dir.X, 0, dir.Z)
                if flat.Magnitude <= 0.01 then
                    return nil, nil
                end

                local d = flat.Unit
                local px = hrpNow.Position.X
                local pz = hrpNow.Position.Z
                local bestT = nil
                local bestNormal = nil
                local n = #CLAUSTRUM_ZONE_VERTICES

                for i = 1, n do
                    local a = CLAUSTRUM_ZONE_VERTICES[i]
                    local b = CLAUSTRUM_ZONE_VERTICES[(i % n) + 1]
                    local ex = b.X - a.X
                    local ez = b.Z - a.Z
                    local len2 = ex * ex + ez * ez
                    if len2 > 1e-8 then
                        local apx = a.X - px
                        local apz = a.Z - pz
                        local denom = (d.X * ez) - (d.Z * ex)
                        if math.abs(denom) > 1e-7 then
                            local t = ((apx * ez) - (apz * ex)) / denom
                            local u = ((apx * d.Z) - (apz * d.X)) / denom
                            if t >= 0 and u >= 0 and u <= 1 then
                                if bestT == nil or t < bestT then
                                    local len = math.sqrt(len2)
                                    local nh = Vector3.new(ez / len, 0, -ex / len)
                                    if nh.Magnitude > 0.01 then
                                        bestT = t
                                        bestNormal = nh.Unit
                                    end
                                end
                            end
                        end
                    end
                end

                if bestT == nil or bestNormal == nil then
                    return nil, nil
                end
                return bestT, bestNormal
            end

            local function wallHitDistanceFromDir(dir)
                if typeof(dir) ~= "Vector3" then
                    return 0, nil
                end
                local flat = Vector3.new(dir.X, 0, dir.Z)
                if flat.Magnitude <= 0.01 then
                    return 0, nil
                end

                local bestDist = BOLA_WALL_PROBE_DIST + 0.01
                local bestNormal = nil
                local origin = hrpNow.Position + Vector3.new(0, 0.4, 0)
                local rayWall = workspace:Raycast(
                    origin,
                    flat.Unit * BOLA_WALL_PROBE_DIST,
                    rayParams
                )
                if rayWall and rayWall.Instance then
                    local n = rayWall.Normal
                    if math.abs(n.Y) <= BOLA_WALL_NORMAL_Y_MAX then
                        local dist = (rayWall.Position - origin).Magnitude
                        local nh = Vector3.new(n.X, 0, n.Z)
                        if nh.Magnitude > 0.01 then
                            bestDist = dist
                            bestNormal = nh.Unit
                        end
                    end
                end

                local vDist, vNormal = claustrumHitFromDir(flat)
                if vDist and vNormal and vDist < bestDist then
                    bestDist = vDist
                    bestNormal = vNormal
                end

                return bestDist, bestNormal
            end

            local function findBestEscapeDirection(preferred, fallback)
                local pref = nil
                if typeof(preferred) == "Vector3" then
                    pref = Vector3.new(preferred.X, 0, preferred.Z)
                end
                local fb = nil
                if typeof(fallback) == "Vector3" then
                    fb = Vector3.new(fallback.X, 0, fallback.Z)
                end

                local prefUnit = nil
                if pref and pref.Magnitude > 0.01 then
                    prefUnit = pref.Unit
                end

                local bases = {}
                if prefUnit then
                    table.insert(bases, prefUnit)
                end
                if fb and fb.Magnitude > 0.01 then
                    local fbUnit = fb.Unit
                    table.insert(bases, fbUnit)
                    table.insert(bases, -fbUnit)
                end
                if #bases == 0 then
                    return nil, 0
                end

                local bestDir = nil
                local bestScore = -math.huge
                local bestClear = 0

                local step = math.max(1, tonumber(BOLA_WALL_ESCAPE_ANGLE_STEP) or 14)
                local maxSweep = math.max(step, tonumber(BOLA_WALL_ESCAPE_MAX_SWEEP) or 180)
                local maxI = math.floor(maxSweep / step)

                local function evaluate(cand)
                    if typeof(cand) ~= "Vector3" or cand.Magnitude <= 0.01 then
                        return false
                    end
                    local dir = cand.Unit
                    local clear = select(1, wallHitDistanceFromDir(dir))
                    local score = clear
                    if prefUnit then
                        local align = math.clamp(dir:Dot(prefUnit), -1, 1)
                        score = score + (align * 0.35)
                    end
                    if score > bestScore then
                        bestScore = score
                        bestClear = clear
                        bestDir = dir
                    end
                    return clear >= BOLA_WALL_ESCAPE_CLEAR_GOOD
                end

                for _, base in ipairs(bases) do
                    if evaluate(base) then
                        return base.Unit, bestClear
                    end
                    for i = 1, maxI do
                        local a = i * step
                        local d1 = rotateYFlat(base, a)
                        if evaluate(d1) then
                            return d1.Unit, bestClear
                        end
                        local d2 = rotateYFlat(base, -a)
                        if evaluate(d2) then
                            return d2.Unit, bestClear
                        end
                    end
                end

                if bestDir and bestClear >= BOLA_WALL_ESCAPE_CLEAR_PREF then
                    return bestDir, bestClear
                end
                return bestDir, bestClear
            end

            local function resolveWallBounceByRays(src)
                if typeof(src) ~= "Vector3" then
                    return nil, nil
                end
                local srcFlat = Vector3.new(src.X, 0, src.Z)
                if srcFlat.Magnitude <= 0.01 then
                    return nil, nil
                end
                local dir = srcFlat.Unit
                local probeDirs = {
                    dir,
                    rotateYFlat(dir, BOLA_WALL_CORNER_ANGLE_A),
                    rotateYFlat(dir, -BOLA_WALL_CORNER_ANGLE_A),
                    rotateYFlat(dir, BOLA_WALL_CORNER_ANGLE_B),
                    rotateYFlat(dir, -BOLA_WALL_CORNER_ANGLE_B),
                }
                local combined = Vector3.new(0, 0, 0)
                local bestNormal = nil
                local bestInto = nil

                for _, pd in ipairs(probeDirs) do
                    if typeof(pd) == "Vector3" and pd.Magnitude > 0.01 then
                        local dist, nh = wallHitDistanceFromDir(pd)
                        if dist <= BOLA_WALL_PROBE_DIST and typeof(nh) == "Vector3" and nh.Magnitude > 0.01 then
                            nh = nh.Unit
                            local into = srcFlat:Dot(nh)
                            if into < -0.05 then
                                local w = math.clamp(math.abs(into) / math.max(srcFlat.Magnitude, 0.01), 0.15, 1)
                                combined += nh * w
                                if (bestInto == nil) or (into < bestInto) then
                                    bestInto = into
                                    bestNormal = nh
                                end
                            end
                        end
                    end
                end

                local bounceNormal = nil
                if combined.Magnitude > 0.01 then
                    bounceNormal = combined.Unit
                elseif bestNormal then
                    bounceNormal = bestNormal
                end
                if not bounceNormal then
                    return nil, nil
                end

                local into = srcFlat:Dot(bounceNormal)
                if into >= -0.05 then
                    return nil, nil
                end

                local reflected = srcFlat - (2 * into) * bounceNormal
                if reflected.Magnitude <= 0.01 then
                    return nil, nil
                end
                return reflected, bounceNormal
            end

            local function tryWallBounce(sourceHv, preserveSpeed, isStuckRecover)
                if typeof(sourceHv) ~= "Vector3" then
                    return false
                end
                local src = Vector3.new(sourceHv.X, 0, sourceHv.Z)
                if src.Magnitude <= 0.01 then
                    return false
                end
                local reflected, nh = resolveWallBounceByRays(src)
                if typeof(reflected) ~= "Vector3" or typeof(nh) ~= "Vector3" then
                    return false
                end
                local reflectedFlat = Vector3.new(reflected.X, 0, reflected.Z)
                local prefClear = select(1, wallHitDistanceFromDir(reflectedFlat))
                if isStuckRecover or prefClear < BOLA_WALL_ESCAPE_CLEAR_PREF then
                    local escapeDir = select(1, findBestEscapeDirection(reflectedFlat, -src))
                    if typeof(escapeDir) == "Vector3" and escapeDir.Magnitude > 0.01 then
                        reflected = escapeDir
                    end
                end
                local outSpeed = preserveSpeed
                if not outSpeed or outSpeed <= 0 then
                    outSpeed = src.Magnitude
                end
                local push = isStuckRecover and BOLA_WALL_PUSH_OUT_STUCK or BOLA_WALL_PUSH_OUT
                return applyHorizontalReflection(reflected, outSpeed, nh, true, push)
            end

            -- bounce normal quando movimento horizontal está forte
            if hSpeed >= BOLA_WALL_MIN_SPEED and (now - lastWallBounceAt) >= BOLA_WALL_BOUNCE_CD then
                bouncedHoriz = tryWallBounce(hv, hSpeed)
            end

            -- monitor de travamento: encostou e ficou quase parado mirando na parede
            if (not bouncedHoriz) and (now - lastWallBounceAt) >= BOLA_WALL_BOUNCE_CD then
                local intentHv = nil
                if flyBv then
                    local bvH = Vector3.new(flyBv.Velocity.X, 0, flyBv.Velocity.Z)
                    if bvH.Magnitude >= BOLA_WALL_STUCK_INTENT_MIN then
                        intentHv = bvH
                    end
                end
                if (not intentHv) and lastMovingHv.Magnitude >= BOLA_WALL_STUCK_INTENT_MIN then
                    intentHv = lastMovingHv
                end

                if intentHv and hSpeed <= BOLA_WALL_STUCK_SPEED_MAX then
                    if wallStuckSince <= 0 then
                        wallStuckSince = now
                    elseif (now - wallStuckSince) >= BOLA_WALL_STUCK_TRIGGER_SEC then
                        bouncedHoriz = tryWallBounce(intentHv, intentHv.Magnitude, true)
                        if (not bouncedHoriz) and lastMovingHv.Magnitude >= BOLA_WALL_MIN_SPEED then
                            bouncedHoriz = tryWallBounce(lastMovingHv, lastMovingHv.Magnitude, true)
                        end
                        if not bouncedHoriz then
                            local hardIntent = intentHv or lastMovingHv
                            if hardIntent and hardIntent.Magnitude >= BOLA_WALL_MIN_SPEED then
                                local escapeDir, clear = findBestEscapeDirection(hardIntent, -hardIntent)
                                if escapeDir and clear > 0.25 then
                                    bouncedHoriz = applyHorizontalReflection(
                                        escapeDir,
                                        math.max(hardIntent.Magnitude, BOLA_WALL_MIN_SPEED),
                                        escapeDir,
                                        true,
                                        BOLA_WALL_PUSH_OUT_STUCK
                                    )
                                end
                            end
                        end
                        if not bouncedHoriz then
                            wallStuckSince = now
                        end
                    end
                else
                    wallStuckSince = 0
                end
            end

            -- rebote horizontal em players sem perder velocidade
            if (not bouncedHoriz)
                and hSpeed >= BOLA_WALL_MIN_SPEED
                and (now - lastPlayerBounceAt) >= BOLA_PLAYER_BOUNCE_CD then
                local selfPos = hrpNow.Position
                local bestNormal = nil
                local bestInto = nil

                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= player then
                        local ch = plr.Character
                        local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso"))
                        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                        if root and (not hum or hum.Health > 0) then
                            local away = Vector3.new(
                                selfPos.X - root.Position.X,
                                0,
                                selfPos.Z - root.Position.Z
                            )
                            local dist = away.Magnitude
                            if dist > 0.01 and dist <= BOLA_PLAYER_BOUNCE_RADIUS then
                                local normal = away.Unit
                                local into = hv:Dot(normal)
                                if into < -BOLA_PLAYER_MIN_APPROACH then
                                    if bestInto == nil or into < bestInto then
                                        bestInto = into
                                        bestNormal = normal
                                    end
                                end
                            end
                        end
                    end
                end

                if bestNormal and bestInto then
                    local reflected = hv - (2 * bestInto) * bestNormal
                    if applyHorizontalReflection(reflected, hSpeed, nil, false) then
                        lastPlayerBounceAt = now
                    end
                end
            end
        end

        bp.Position = Vector3.new(hrpNow.Position.X, posY, hrpNow.Position.Z)
    end)
end

local function setBolaModo(enabled)
    cfg.bolaModo = enabled
    if enabled then
        startBola()
    else
        stopBola()
        local hum = getHum()
        if hum then hum.PlatformStand = true end -- mantém leviosa
    end
end

-- ============================================
-- GUI
-- ============================================
local gui = nil
local guiVisible = false
local guiInputConns = {}
local launcherGui = nil
local launcherConns = {}
local C
local makeCorner
local makeStroke
local buildGui
local lastLeviosa

local function bindGuiInput(conn)
    if conn then
        table.insert(guiInputConns, conn)
    end
    return conn
end

local function clearGuiInputConns()
    for _, c in ipairs(guiInputConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    guiInputConns = {}
end

local function clearLauncherConns()
    for _, c in ipairs(launcherConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    launcherConns = {}
end

local function removeLauncher()
    clearLauncherConns()
    if launcherGui and launcherGui.Parent then
        launcherGui:Destroy()
    end
    launcherGui = nil
end

local function removeGui()
    clearGuiInputConns()
    if gui and gui.Parent then
        gui:Destroy()
    end
    gui = nil
    guiVisible = false
end

local function ensureLauncher(show)
    if not show then
        removeLauncher()
        return
    end
    if launcherGui and launcherGui.Parent then
        return
    end
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then
        return
    end

    launcherGui = Instance.new("ScreenGui")
    launcherGui.Name = "KAH_LeviosaCfgLauncher"
    launcherGui.ResetOnSpawn = false
    launcherGui.IgnoreGuiInset = true
    launcherGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    launcherGui.Parent = pg

    local btn = Instance.new("TextButton")
    btn.Name = "LauncherBtn"
    btn.Size = UDim2.new(0, 42, 0, 42)
    btn.Position = UDim2.new(1, -56, 0, 90)
    btn.BackgroundColor3 = C.card
    btn.BorderSizePixel = 0
    btn.Text = "LV"
    btn.TextColor3 = C.accent
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Active = true
    btn.Parent = launcherGui
    makeCorner(10, btn)
    makeStroke(C.border, 1.5, btn)

    local function clampBtn()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
        local x = math.clamp(btn.Position.X.Offset, 4, vp.X - btn.Size.X.Offset - 4)
        local y = math.clamp(btn.Position.Y.Offset, 4, vp.Y - btn.Size.Y.Offset - 4)
        btn.Position = UDim2.new(0, x, 0, y)
    end
    clampBtn()

    table.insert(launcherConns, btn.MouseButton1Click:Connect(function()
        removeLauncher()
        buildGui()
    end))

    local dragging = false
    local dragStart = nil
    local startPos = nil
    table.insert(launcherConns, btn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = inp.Position
            startPos = btn.Position
        end
    end))
    table.insert(launcherConns, UIS.InputChanged:Connect(function(inp)
        if not dragging then
            return
        end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
            and inp.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = inp.Position - dragStart
        btn.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
        clampBtn()
    end))
    table.insert(launcherConns, UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

C = {
    bg      = Color3.fromRGB(18, 20, 26),
    card    = Color3.fromRGB(26, 29, 38),
    border  = Color3.fromRGB(82, 173, 255),
    accent  = Color3.fromRGB(64, 156, 255),
    text    = Color3.fromRGB(220, 226, 235),
    muted   = Color3.fromRGB(130, 140, 158),
    track   = Color3.fromRGB(45, 50, 65),
    fill    = Color3.fromRGB(64, 156, 255),
    on      = Color3.fromRGB(50, 200, 120),
    off     = Color3.fromRGB(84, 89, 99),
    handle  = Color3.fromRGB(255, 255, 255),
}

makeCorner = function(r, p)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = p
    return c
end

makeStroke = function(color, thick, parent)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thick
    s.Transparency = 0.35
    s.Parent = parent
    return s
end

local ROW_H    = 38
local PADDING  = 14
local W        = 300
local TITLE_H  = 38

local sliderData = {}

local function buildSlider(parent, yPos, label, minV, maxV, initV, decimals, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -PADDING*2, 0, ROW_H)
    row.Position = UDim2.new(0, PADDING, 0, yPos)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0, 110, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextColor3 = C.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = label
    lbl.Parent = row

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0, 44, 1, 0)
    valLbl.Position = UDim2.new(1, -44, 0, 0)
    valLbl.BackgroundTransparency = 1
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextSize = 13
    valLbl.TextColor3 = C.accent
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = row

    local trackW = W - PADDING*2 - 110 - 48 - 8
    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, trackW, 0, 6)
    track.Position = UDim2.new(0, 114, 0.5, -3)
    track.BackgroundColor3 = C.track
    track.BorderSizePixel = 0
    track.Parent = row
    makeCorner(4, track)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = C.fill
    fill.BorderSizePixel = 0
    fill.Parent = track
    makeCorner(4, fill)

    local handle = Instance.new("Frame")
    handle.Size = UDim2.new(0, 14, 0, 14)
    handle.AnchorPoint = Vector2.new(0.5, 0.5)
    handle.Position = UDim2.new(0, 0, 0.5, 0)
    handle.BackgroundColor3 = C.handle
    handle.BorderSizePixel = 0
    handle.ZIndex = 3
    handle.Parent = track
    makeCorner(7, handle)

    local function setValue(v)
        v = math.clamp(v, minV, maxV)
        local t = (v - minV) / (maxV - minV)
        fill.Size = UDim2.new(t, 0, 1, 0)
        handle.Position = UDim2.new(t, 0, 0.5, 0)
        local fmt = "%." .. decimals .. "f"
        valLbl.Text = string.format(fmt, v)
        onChange(v)
    end

    setValue(initV)

    local dragging = false
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        local abs = track.AbsolutePosition
        local sz  = track.AbsoluteSize
        local mx  = inp.Position.X
        local t   = math.clamp((mx - abs.X) / sz.X, 0, 1)
        local v   = minV + t * (maxV - minV)
        local step = 1 / (10 ^ decimals)
        v = math.floor(v / step + 0.5) * step
        setValue(v)
    end)

    table.insert(sliderData, { setValue = setValue })
    return row
end

local function buildToggle(parent, yPos, label, initV, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -PADDING*2, 0, ROW_H)
    row.Position = UDim2.new(0, PADDING, 0, yPos)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -60, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextColor3 = C.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = label
    lbl.Parent = row

    local pill = Instance.new("TextButton")
    pill.Size = UDim2.new(0, 46, 0, 24)
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Position = UDim2.new(1, 0, 0.5, 0)
    pill.BorderSizePixel = 0
    pill.Text = ""
    pill.AutoButtonColor = false
    pill.BackgroundColor3 = initV and C.on or C.off
    pill.Parent = row
    makeCorner(12, pill)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = initV and UDim2.new(1, -13, 0.5, 0) or UDim2.new(0, 13, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    knob.ZIndex = 3
    knob.Parent = pill
    makeCorner(9, knob)

    local state = initV
    local function toggle()
        state = not state
        TS:Create(pill, TweenInfo.new(0.18), {BackgroundColor3 = state and C.on or C.off}):Play()
        TS:Create(knob, TweenInfo.new(0.18), {
            Position = state and UDim2.new(1,-13,0.5,0) or UDim2.new(0,13,0.5,0)
        }):Play()
        onChange(state)
    end

    pill.MouseButton1Click:Connect(toggle)
    return row, function(v)
        if v ~= state then toggle() end
    end
end

local function buildSectionLabel(parent, yPos, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -PADDING*2, 0, 22)
    lbl.Position = UDim2.new(0, PADDING, 0, yPos)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextColor3 = C.muted
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = string.upper(text)
    lbl.Parent = parent
end

buildGui = function()
    removeLauncher()
    removeGui()

    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end

    gui = Instance.new("ScreenGui")
    gui.Name = "KAH_LeviosaCfgGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = pg

    local H = TITLE_H + 8 + 22 + ROW_H*5 + 8 + 22 + ROW_H*3 + PADDING

    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local cardStartX = math.max(8, vp.X - (W + 16))

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.Size = UDim2.new(0, W, 0, H)
    card.Position = UDim2.new(0, cardStartX, 0, 80)
    card.BackgroundColor3 = C.bg
    card.BorderSizePixel = 0
    card.Active = true
    card.Parent = gui
    makeCorner(12, card)
    makeStroke(C.border, 1.5, card)

    local iconBtn = Instance.new("TextButton")
    iconBtn.Name = "LeviosaMiniIcon"
    iconBtn.Size = UDim2.new(0, 42, 0, 42)
    iconBtn.Position = UDim2.new(0, cardStartX + W - 42, 0, 80)
    iconBtn.BackgroundColor3 = C.card
    iconBtn.BorderSizePixel = 0
    iconBtn.Text = "LV"
    iconBtn.TextColor3 = C.accent
    iconBtn.Font = Enum.Font.GothamBold
    iconBtn.TextSize = 12
    iconBtn.Visible = false
    iconBtn.Active = true
    iconBtn.Parent = gui
    makeCorner(10, iconBtn)
    makeStroke(C.border, 1.5, iconBtn)

    local function clampToViewport(obj)
        local c = workspace.CurrentCamera
        local v = c and c.ViewportSize or Vector2.new(1920, 1080)
        local ox = math.clamp(obj.Position.X.Offset, 4, v.X - obj.Size.X.Offset - 4)
        local oy = math.clamp(obj.Position.Y.Offset, 4, v.Y - obj.Size.Y.Offset - 4)
        obj.Position = UDim2.new(0, ox, 0, oy)
    end

    local minimized = false
    local function setMinimized(v)
        minimized = v == true
        if minimized then
            iconBtn.Position = UDim2.new(
                0,
                card.Position.X.Offset + card.Size.X.Offset - iconBtn.Size.X.Offset,
                0,
                card.Position.Y.Offset
            )
            clampToViewport(iconBtn)
        else
            card.Position = UDim2.new(
                0,
                iconBtn.Position.X.Offset - (card.Size.X.Offset - iconBtn.Size.X.Offset),
                0,
                iconBtn.Position.Y.Offset
            )
            clampToViewport(card)
        end
        card.Visible = not minimized
        iconBtn.Visible = minimized
    end

    -- TITULO + drag
    local titleBar = Instance.new("TextButton")
    titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
    titleBar.BackgroundColor3 = C.card
    titleBar.BorderSizePixel = 0
    titleBar.AutoButtonColor = false
    titleBar.Text = ""
    titleBar.Parent = card
    makeCorner(12, titleBar)
    -- cobre só o topo (hack: frame extra cobre canto inferior)
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 12)
    titleFix.Position = UDim2.new(0, 0, 1, -12)
    titleFix.BackgroundColor3 = C.card
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -(PADDING*2 + 40), 1, 0)
    titleLbl.Position = UDim2.new(0, PADDING, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 15
    titleLbl.TextColor3 = C.text
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Text = "Leviosa Config"
    titleLbl.Parent = titleBar

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 8, 0, 8)
    dot.AnchorPoint = Vector2.new(1, 0.5)
    dot.Position = UDim2.new(1, -(PADDING + 34), 0.5, 0)
    dot.BackgroundColor3 = C.accent
    dot.BorderSizePixel = 0
    dot.Parent = titleBar
    makeCorner(4, dot)

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 22, 0, 22)
    minBtn.AnchorPoint = Vector2.new(1, 0.5)
    minBtn.Position = UDim2.new(1, -PADDING, 0.5, 0)
    minBtn.BackgroundColor3 = Color3.fromRGB(34, 38, 50)
    minBtn.BorderSizePixel = 0
    minBtn.Text = "_"
    minBtn.TextColor3 = C.text
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 14
    minBtn.Parent = titleBar
    makeCorner(6, minBtn)

    -- DRAG
    local dragging = false
    local dragStart, startPos

    titleBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = inp.Position
            startPos  = card.Position
        end
    end)
    bindGuiInput(UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    bindGuiInput(UIS.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = inp.Position - dragStart
        card.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
        clampToViewport(card)
    end))

    minBtn.MouseButton1Click:Connect(function()
        setMinimized(not minimized)
    end)

    iconBtn.MouseButton1Click:Connect(function()
        setMinimized(false)
    end)

    local iconDragging = false
    local iconDragStart = nil
    local iconStartPos = nil

    iconBtn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            iconDragging = true
            iconDragStart = inp.Position
            iconStartPos = iconBtn.Position
        end
    end)

    bindGuiInput(UIS.InputChanged:Connect(function(inp)
        if not iconDragging then
            return
        end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
            and inp.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = inp.Position - iconDragStart
        iconBtn.Position = UDim2.new(
            iconStartPos.X.Scale, iconStartPos.X.Offset + delta.X,
            iconStartPos.Y.Scale, iconStartPos.Y.Offset + delta.Y
        )
        clampToViewport(iconBtn)
    end))

    bindGuiInput(UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            iconDragging = false
        end
    end))

    -- CONTEUDO
    local content = Instance.new("ScrollingFrame")
    content.Size = UDim2.new(1, 0, 1, -TITLE_H)
    content.Position = UDim2.new(0, 0, 0, TITLE_H)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 0
    content.CanvasSize = UDim2.new(0, 0, 0, H - TITLE_H)
    content.Parent = card

    local y = 8

    -- secao VOO
    buildSectionLabel(content, y, "Voo")
    y = y + 22

    buildSlider(content, y, "Vel. Horizontal", 10, 200, cfg.horizSpeed, 0, function(v)
        cfg.horizSpeed = v
    end)
    y = y + ROW_H

    buildSlider(content, y, "Vel. Vertical", 5, 120, cfg.vertSpeed, 0, function(v)
        cfg.vertSpeed = v
    end)
    y = y + ROW_H

    buildSlider(content, y, "Desaceleração", 0, 5000, cfg.decel, 0, function(v)
        cfg.decel = v
    end)
    y = y + ROW_H

    buildSlider(content, y, "Rebote Parede", 0, 3, cfg.bounceForce, 2, function(v)
        cfg.bounceForce = v
    end)
    y = y + ROW_H

    buildToggle(content, y, "Abrir Janela Ao Ativar", cfg.autoOpenWindow, function(v)
        cfg.autoOpenWindow = (v == true)
        if lastLeviosa then
            if cfg.autoOpenWindow then
                ensureLauncher(false)
            else
                removeGui()
                ensureLauncher(true)
            end
        end
    end)
    y = y + ROW_H + 8

    -- secao BOLA
    buildSectionLabel(content, y, "Modo Bola")
    y = y + 22

    buildSlider(content, y, "Gravidade", 0.05, 1.5, cfg.bolaGravity, 2, function(v)
        cfg.bolaGravity = v
    end)
    y = y + ROW_H

    buildSlider(content, y, "Quique", 0.1, 0.99, cfg.bolaBouce, 2, function(v)
        cfg.bolaBouce = v
    end)
    y = y + ROW_H

    buildToggle(content, y, "Ativar Modo Bola", cfg.bolaModo, function(v)
        setBolaModo(v)
    end)
    y = y + ROW_H

    guiVisible = true
end

-- ============================================
-- HOOKS — observa mudança de leviosa via polling
-- (funciona sem alterar adminCommands)
-- ============================================
lastLeviosa = false
local watchConn = nil

local function onLeviosaOn()
    if not ENABLE_LEVIOSA_CFG_UI then
        ensureLauncher(false)
        removeGui()
        return
    end
    if cfg.autoOpenWindow then
        ensureLauncher(false)
        buildGui()
    else
        removeGui()
        ensureLauncher(true)
    end
end

local function onLeviosaOff()
    ensureLauncher(false)
    setBolaModo(false)
    removeGui()
end

watchConn = RS.Heartbeat:Connect(function()
    local s = _G.KAHCommandUiState
    if type(s) ~= "table" then return end
    local cur = s.leviosa == true
    if cur ~= lastLeviosa then
        lastLeviosa = cur
        if cur then
            onLeviosaOn()
        else
            onLeviosaOff()
        end
    end
end)

-- ============================================
-- PATCH NO WINGARDIUM — injeta cfg em tempo real
-- ============================================
-- O loop do wingardium lê flyBV direto, então
-- sobrescrevemos os valores via Heartbeat separado
-- usando os campos de cfg.
local patchConn = nil

patchConn = RS.Heartbeat:Connect(function()
    local s = _G.KAHCommandUiState
    if type(s) ~= "table" or s.leviosa ~= true or cfg.bolaModo then return end
    local c = player.Character
    if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")
    if not hrp then return end
    local bv = hrp:FindFirstChildOfClass("BodyVelocity")
    if not bv then return end

    local vel = bv.Velocity
    local hVec = Vector3.new(vel.X, 0, vel.Z)
    local hMag = hVec.Magnitude
    if hMag > 0.1 then
        local targetH = hVec.Unit * cfg.horizSpeed
        local vRatio = cfg.vertSpeed / 42
        local targetY = vel.Y * vRatio
        local newVel = Vector3.new(targetH.X, targetY, targetH.Z)
        if (newVel - vel).Magnitude > 0.05 then
            bv.Velocity = newVel
        end
    end
end)

-- ============================================
-- CLEANUP
-- ============================================
local function cleanup()
    if watchConn then watchConn:Disconnect(); watchConn = nil end
    if patchConn then patchConn:Disconnect(); patchConn = nil end
    setBolaModo(false)
    removeLauncher()
    removeGui()
end

_G[LVCFG_KEY] = {
    cleanup = cleanup,
    setBallMode = function(enabled)
        setBolaModo(enabled == true)
        return cfg.bolaModo == true
    end,
    getBallMode = function()
        return cfg.bolaModo == true
    end,
}

-- se leviosa já estiver ativo quando carregar
local s = _G.KAHCommandUiState
if type(s) == "table" and s.leviosa == true then
    lastLeviosa = true
    onLeviosaOn()
end

print('[KAH][LOAD] LEVIOSA CFG ativo')
