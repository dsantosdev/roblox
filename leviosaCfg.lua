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
}
local cfg = _G.KAHLeviosaCfg

-- ============================================
-- MODO BOLA
-- ============================================
local bolaConn = nil
local GROUND_Y_OFFSET = 3.1
local BOLA_REST_SPEED = 2.4
local BOLA_GROUND_EPS = 0.05
local BOLA_EXT_UP_MIN = 22
local BOLA_WALL_PROBE_DIST = 2.8
local BOLA_WALL_BOUNCE_CD = 0.08
local BOLA_WALL_MIN_SPEED = 6
local BOLA_WALL_NORMAL_Y_MAX = 0.55

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
        if extVel.Y > BOLA_EXT_UP_MIN and velY < extVel.Y then
            velY = extVel.Y * 0.65
        end

        -- rebote horizontal nas paredes sem perder velocidade
        do
            local av = hrpNow.AssemblyLinearVelocity
            local hv = Vector3.new(av.X, 0, av.Z)
            local hSpeed = hv.Magnitude
            if hSpeed >= BOLA_WALL_MIN_SPEED and (now - lastWallBounceAt) >= BOLA_WALL_BOUNCE_CD then
                local dir = hv.Unit
                local rayWall = workspace:Raycast(
                    hrpNow.Position + Vector3.new(0, 0.4, 0),
                    dir * BOLA_WALL_PROBE_DIST,
                    rayParams
                )
                if rayWall and rayWall.Instance and rayWall.Instance.CanCollide then
                    local n = rayWall.Normal
                    if math.abs(n.Y) <= BOLA_WALL_NORMAL_Y_MAX then
                        local nh = Vector3.new(n.X, 0, n.Z)
                        if nh.Magnitude > 0.01 then
                            nh = nh.Unit
                            local into = hv:Dot(nh)
                            if into < -0.05 then
                                local reflected = hv - (2 * into) * nh
                                if reflected.Magnitude > 0.01 then
                                    local newHv = reflected.Unit * hSpeed
                                    hrpNow.AssemblyLinearVelocity = Vector3.new(newHv.X, av.Y, newHv.Z)
                                    local flyBv = hrpNow:FindFirstChildOfClass("BodyVelocity")
                                    if flyBv then
                                        local bvVel = flyBv.Velocity
                                        flyBv.Velocity = Vector3.new(newHv.X, bvVel.Y, newHv.Z)
                                    end
                                    lastWallBounceAt = now
                                end
                            end
                        end
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

local function removeGui()
    if gui and gui.Parent then
        gui:Destroy()
    end
    gui = nil
    guiVisible = false
end

local C = {
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

local function makeCorner(r, p)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = p
    return c
end

local function makeStroke(color, thick, parent)
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

local function buildGui()
    removeGui()

    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end

    gui = Instance.new("ScreenGui")
    gui.Name = "KAH_LeviosaCfgGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = pg

    -- ROWS: secao voo, 4 sliders, secao bola, 2 sliders, 1 toggle = ~10 rows
    local sections = {
        { label = "VOO",  rows = 4 },
        { label = "BOLA", rows = 3 },
    }
    local totalRows = 7
    local H = TITLE_H + 8 + 22 + ROW_H*4 + 8 + 22 + ROW_H*3 + PADDING

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.Size = UDim2.new(0, W, 0, H)
    card.Position = UDim2.new(1, -(W+16), 0, 80)
    card.BackgroundColor3 = C.bg
    card.BorderSizePixel = 0
    card.Active = true
    card.Parent = gui
    makeCorner(12, card)
    makeStroke(C.border, 1.5, card)

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
    titleLbl.Size = UDim2.new(1, -PADDING*2, 1, 0)
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
    dot.Position = UDim2.new(1, -PADDING, 0.5, 0)
    dot.BackgroundColor3 = C.accent
    dot.BorderSizePixel = 0
    dot.Parent = titleBar
    makeCorner(4, dot)

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
        local delta = inp.Position - dragStart
        card.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end)

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
local lastLeviosa = false
local watchConn = nil

local function onLeviosaOn()
    buildGui()
end

local function onLeviosaOff()
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
    local hMag = Vector3.new(vel.X, 0, vel.Z).Magnitude

    -- reescala velocidade horizontal para cfg
    if hMag > 0.1 then
        local ratio = cfg.horizSpeed / 48
        local newH = Vector3.new(vel.X, 0, vel.Z) * ratio
        -- vertical: reescala proporcionalmente
        local vRatio = cfg.vertSpeed / 42
        local newVel = Vector3.new(newH.X, vel.Y * vRatio, newH.Z)
        -- só aplica se diferença relevante
        if (newVel - vel).Magnitude > 0.5 then
            bv.Velocity = newVel
        end
    end

    -- desaceleração: se MaxForce horizontal for 0 (idle), injeta resistência
    local mf = bv.MaxForce
    if mf.X == 0 and cfg.decel > 0 then
        bv.MaxForce = Vector3.new(cfg.decel, math.huge, cfg.decel)
        bv.Velocity = Vector3.new(0, vel.Y, 0)
    end
end)

-- ============================================
-- CLEANUP
-- ============================================
local function cleanup()
    if watchConn then watchConn:Disconnect(); watchConn = nil end
    if patchConn then patchConn:Disconnect(); patchConn = nil end
    setBolaModo(false)
    removeGui()
end

_G[LVCFG_KEY] = { cleanup = cleanup }

-- se leviosa já estiver ativo quando carregar
local s = _G.KAHCommandUiState
if type(s) == "table" and s.leviosa == true then
    lastLeviosa = true
    onLeviosaOn()
end

print('[KAH][LOAD] LEVIOSA CFG ativo')
