print('[KAH][LOAD] antiFling.lua')
-- ============================================
-- MODULO: ANTI FLING GUARD (Kahrrasco only)
-- ============================================

local VERSION = "1.0"
local MODULE_NAME = "Anti Fling Guard"
local CATEGORIA = "Player"
local STATE_KEY = "__kah_antifling_guard_state"
local GUI_NAME = "KAH_AntiFling_Gui"

if not _G.Hub and not _G.HubFila then
    print("[KAH][WARN][AntiFling] hub nao encontrado, abortando")
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")

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

local enabled = false
local destroyed = false
local conns = {}
local gui = nil
local statusLbl = nil
local guardBtn = nil
local sitBtn = nil
local lastActionAt = 0
local lastSafeAt = 0
local lastNotifyAt = 0
local lastPos = nil
local safeCF = nil

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

local function updateUi()
    if not statusLbl or not guardBtn then
        return
    end

    if enabled then
        guardBtn.Text = "GUARD: ON"
        guardBtn.BackgroundColor3 = Color3.fromRGB(18, 72, 38)
        guardBtn.TextColor3 = Color3.fromRGB(120, 255, 170)
        statusLbl.Text = "Protecao ativa."
        statusLbl.TextColor3 = Color3.fromRGB(150, 220, 180)
    else
        guardBtn.Text = "GUARD: OFF"
        guardBtn.BackgroundColor3 = Color3.fromRGB(68, 20, 26)
        guardBtn.TextColor3 = Color3.fromRGB(255, 150, 160)
        statusLbl.Text = "Protecao desligada."
        statusLbl.TextColor3 = Color3.fromRGB(170, 145, 155)
    end
end

local function setEnabled(v)
    enabled = (v == true)
    if enabled then
        local _, _, root = getCharacterBits()
        lastPos = root and root.Position or nil
        safeCF = root and root.CFrame or safeCF
        lastSafeAt = os.clock()
    end
    updateUi()
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
    if destroyed or not enabled then
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
        end)
    end
end

local function createGui()
    local pg = lp:FindFirstChildOfClass("PlayerGui")
    if not pg then
        local ok, waited = pcall(function()
            return lp:WaitForChild("PlayerGui", 5)
        end)
        if ok then
            pg = waited
        end
    end
    if not pg then
        return
    end

    local old = pg:FindFirstChild(GUI_NAME)
    if old then
        old:Destroy()
    end

    gui = Instance.new("ScreenGui")
    gui.Name = GUI_NAME
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = pg

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 156, 0, 90)
    frame.Position = UDim2.new(1, -172, 1, -168)
    frame.BackgroundColor3 = Color3.fromRGB(20, 19, 25)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    local st = Instance.new("UIStroke", frame)
    st.Color = Color3.fromRGB(90, 35, 45)

    local titleBar = Instance.new("TextButton")
    titleBar.Size = UDim2.new(1, -24, 0, 20)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundTransparency = 1
    titleBar.AutoButtonColor = false
    titleBar.Text = ""
    titleBar.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -34, 0, 16)
    title.Position = UDim2.new(0, 8, 0, 2)
    title.BackgroundTransparency = 1
    title.Text = "ANTI FLING"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 11
    title.TextColor3 = Color3.fromRGB(255, 140, 150)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 18, 0, 18)
    minBtn.Position = UDim2.new(1, -22, 0, 1)
    minBtn.BackgroundColor3 = Color3.fromRGB(34, 28, 36)
    minBtn.BorderSizePixel = 0
    minBtn.Text = "_"
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 12
    minBtn.TextColor3 = Color3.fromRGB(255, 170, 180)
    minBtn.Parent = frame
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

    guardBtn = Instance.new("TextButton")
    guardBtn.Size = UDim2.new(1, -12, 0, 24)
    guardBtn.Position = UDim2.new(0, 6, 0, 25)
    guardBtn.BorderSizePixel = 0
    guardBtn.Font = Enum.Font.GothamBold
    guardBtn.TextSize = 10
    guardBtn.Parent = frame
    Instance.new("UICorner", guardBtn).CornerRadius = UDim.new(0, 5)

    sitBtn = Instance.new("TextButton")
    sitBtn.Size = UDim2.new(1, -12, 0, 24)
    sitBtn.Position = UDim2.new(0, 6, 0, 52)
    sitBtn.BorderSizePixel = 0
    sitBtn.Font = Enum.Font.GothamBold
    sitBtn.TextSize = 10
    sitBtn.Text = "SENTAR"
    sitBtn.BackgroundColor3 = Color3.fromRGB(24, 45, 70)
    sitBtn.TextColor3 = Color3.fromRGB(130, 210, 255)
    sitBtn.Parent = frame
    Instance.new("UICorner", sitBtn).CornerRadius = UDim.new(0, 5)

    statusLbl = Instance.new("TextLabel")
    statusLbl.Size = UDim2.new(1, -12, 0, 12)
    statusLbl.Position = UDim2.new(0, 8, 1, -13)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Font = Enum.Font.Gotham
    statusLbl.TextSize = 9
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.Parent = frame

    local iconBtn = Instance.new("TextButton")
    iconBtn.Name = "MiniIcon"
    iconBtn.Size = UDim2.new(0, 36, 0, 36)
    iconBtn.Position = UDim2.new(1, -52, 1, -168)
    iconBtn.BackgroundColor3 = Color3.fromRGB(20, 19, 25)
    iconBtn.BorderSizePixel = 0
    iconBtn.Text = "AF"
    iconBtn.Font = Enum.Font.GothamBold
    iconBtn.TextSize = 11
    iconBtn.TextColor3 = Color3.fromRGB(255, 140, 150)
    iconBtn.Visible = false
    iconBtn.Active = true
    iconBtn.Parent = gui
    Instance.new("UICorner", iconBtn).CornerRadius = UDim.new(0, 6)
    local iconStroke = Instance.new("UIStroke", iconBtn)
    iconStroke.Color = Color3.fromRGB(90, 35, 45)

    local minimized = false
    local function clampToViewport(obj)
        if not obj then
            return
        end
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
        local x = math.clamp(obj.Position.X.Offset, 4, vp.X - obj.Size.X.Offset - 4)
        local y = math.clamp(obj.Position.Y.Offset, 4, vp.Y - obj.Size.Y.Offset - 4)
        obj.Position = UDim2.new(0, x, 0, y)
    end

    local function setMinimized(v)
        minimized = (v == true)
        if minimized then
            iconBtn.Position = UDim2.new(
                0,
                frame.Position.X.Offset + frame.Size.X.Offset - iconBtn.Size.X.Offset,
                0,
                frame.Position.Y.Offset
            )
            clampToViewport(iconBtn)
        else
            frame.Position = UDim2.new(
                0,
                iconBtn.Position.X.Offset - (frame.Size.X.Offset - iconBtn.Size.X.Offset),
                0,
                iconBtn.Position.Y.Offset
            )
            clampToViewport(frame)
        end
        frame.Visible = not minimized
        iconBtn.Visible = minimized
    end

    local dragFrame = false
    local frameDragStart = nil
    local frameStartPos = nil
    connect(titleBar.InputBegan, function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragFrame = true
            frameDragStart = inp.Position
            frameStartPos = frame.Position
        end
    end)
    connect(UIS.InputChanged, function(inp)
        if not dragFrame then
            return
        end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
            and inp.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = inp.Position - frameDragStart
        frame.Position = UDim2.new(
            frameStartPos.X.Scale,
            frameStartPos.X.Offset + delta.X,
            frameStartPos.Y.Scale,
            frameStartPos.Y.Offset + delta.Y
        )
        clampToViewport(frame)
    end)
    connect(UIS.InputEnded, function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragFrame = false
        end
    end)

    local dragIcon = false
    local iconDragStart = nil
    local iconStartPos = nil
    local iconMoved = false
    connect(iconBtn.InputBegan, function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragIcon = true
            iconMoved = false
            iconDragStart = inp.Position
            iconStartPos = iconBtn.Position
        end
    end)
    connect(UIS.InputChanged, function(inp)
        if not dragIcon then
            return
        end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
            and inp.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = inp.Position - iconDragStart
        if delta.Magnitude >= 6 then
            iconMoved = true
        end
        iconBtn.Position = UDim2.new(
            iconStartPos.X.Scale,
            iconStartPos.X.Offset + delta.X,
            iconStartPos.Y.Scale,
            iconStartPos.Y.Offset + delta.Y
        )
        clampToViewport(iconBtn)
    end)
    connect(UIS.InputEnded, function(inp)
        if not dragIcon then
            return
        end
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1
            and inp.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        dragIcon = false
        if not iconMoved then
            setMinimized(false)
        end
    end)

    connect(minBtn.MouseButton1Click, function()
        setMinimized(true)
    end)

    connect(guardBtn.MouseButton1Click, function()
        setEnabled(not enabled)
        syncHubState()
    end)

    connect(sitBtn.MouseButton1Click, function()
        local ok = setHumanoidSit()
        if ok then
            notify("Humanoid.Sit = true")
        else
            notify("Sem humanoid no momento")
        end
    end)

    clampToViewport(frame)
    updateUi()
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
    if gui and gui.Parent then
        pcall(function()
            gui:Destroy()
        end)
    end
    _G[STATE_KEY] = nil
    if _G.__kah_antifling_guard == apiRef then
        _G.__kah_antifling_guard = nil
    end
end

local function onToggle(ativo)
    setEnabled(ativo)
end

createGui()
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
end)

if _G.Hub then
    if _G.Hub.remover then
        pcall(function()
            _G.Hub.remover(MODULE_NAME)
        end)
    end
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, false)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = MODULE_NAME,
        toggleFn = onToggle,
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
    sitNow = setHumanoidSit,
    cleanup = cleanup,
    gui = gui,
}

_G.__kah_antifling_guard = _G[STATE_KEY]

print("[KAH][READY] ANTI FLING GUARD")
