-- ── DungeonRunner v2.2 ───────────────────────────────────────────────────────
-- Fixes aplicados:
-- • Bridge agora funciona em qualquer rotação da dungeon (sem fixo 55/17)
-- • Andar até porta 1 reduzido para ~1/3 (17 studs lateral)
-- • Spawn detectado imediatamente mesmo durante o andar (check extra logo após walkTo)
-- Cache em _G continua funcionando normalmente
-- ─────────────────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer

-- ── Configuração ──────────────────────────────────────────────────────────────
local SCAN_INTERVAL = 0.5       -- segundos entre verificações de cultists
local COOLDOWN_AFTER = 2.0      -- segundos com 0 vivos antes de prosseguir
local SPAWN_TIMEOUT = 60        -- tempo máximo esperando o primeiro spawn
local WALK_TIMEOUT = 14         -- tempo máximo para andar até a porta 1
local WALK_DIST = 17            -- distância lateral para andar (1/3 do original)
local BRIDGE_DIST = 55          -- distância para dentro da entrada (funciona em qualquer rotação)

-- Faixas de Y por andar
local FLOORS = {
    { name="Térreo",   yMin=2,  yMax=15, radius=150, color=Color3.fromRGB(30,180,80) },
    { name="1º Andar", yMin=20, yMax=42, radius=150, color=Color3.fromRGB(200,150,20) },
    { name="2º Andar", yMin=43, yMax=65, radius=150, color=Color3.fromRGB(140,60,200) },
}

-- ── Funções de caminho no workspace ───────────────────────────────────────────
local function getByPath(...)
    local cur = workspace
    for _, name in ipairs({...}) do
        if not cur then return nil end
        cur = cur:FindFirstChild(name)
    end
    return cur
end

local BASE = {"Map","Landmarks","Stronghold","Functional"}

local function getSH(...)
    local args = {}
    for _, v in ipairs(BASE) do table.insert(args, v) end
    for _, v in ipairs({...}) do table.insert(args, v) end
    return getByPath(table.unpack(args))
end

local function getDoorCenter(pathR, pathL)
    local function partPos(...)
        local obj = getSH(...)
        if not obj then return nil end
        if obj:IsA("BasePart") then return obj.Position end
        local p = obj:FindFirstChildWhichIsA("BasePart", true)
        return p and p.Position
    end
    local rp = partPos(table.unpack(pathR))
    local lp = partPos(table.unpack(pathL))
    if rp and lp then return (rp + lp) * 0.5 end
    return rp or lp
end

-- ── Cache de pontos por partida ───────────────────────────────────────────────
local CACHE_KEY = "__dr_pts_" .. tostring(game.PlaceId) .. "_" .. tostring(game.JobId ~= "" and game.JobId or "single")

local function loadCache()
    local v = _G[CACHE_KEY]
    if type(v) == "table" and typeof(v.door1) == "Vector3" then return v end
    return nil
end

local function saveCache(pts)
    _G[CACHE_KEY] = {
        entry = pts.entry,
        bridge = pts.bridge,
        door1 = pts.door1,
        walk1 = pts.walk1,
        door2 = pts.door2,
        floor3 = pts.floor3,
        floor1Ctr = pts.floor1Ctr,
        floor2Ctr = pts.floor2Ctr,
    }
end

local function clearCache() _G[CACHE_KEY] = nil end

-- ── Resolução dos pontos ──────────────────────────────────────────────────────
local function resolvePoints()
    local deadline = os.clock() + 4
    while os.clock() < deadline do
        if getSH("EntryDoors","DoorRight","Main")
        and getSH("Doors","LockedDoorsFloor1","DoorRight","Main") then break end
        task.wait(0.15)
    end

    local entryCtr = getDoorCenter(
        {"EntryDoors","DoorRight","Main"},
        {"EntryDoors","DoorLeft","Main"})

    local floor1Ctr = getDoorCenter(
        {"Doors","LockedDoorsFloor1","DoorRight","Main"},
        {"Doors","LockedDoorsFloor1","DoorLeft","Main"})

    local floor2Ctr = getDoorCenter(
        {"Doors","LockedDoorsFloor2","DoorRight","Main"},
        {"Doors","LockedDoorsFloor2","DoorLeft","Main"})

    if not entryCtr or not floor1Ctr then
        return nil, "portas não encontradas no workspace"
    end

    local corr = Vector3.new(floor1Ctr.X - entryCtr.X, 0, floor1Ctr.Z - entryCtr.Z)
    corr = corr.Magnitude > 0.01 and corr.Unit or Vector3.new(0,0,-1)
    local right = Vector3.new(corr.Z, 0, -corr.X)

    local entry = Vector3.new(
        entryCtr.X - corr.X * 4,
        entryCtr.Y + 1.5,
        entryCtr.Z - corr.Z * 4)

    local bridge = Vector3.new(
        entryCtr.X + corr.X * BRIDGE_DIST,
        entryCtr.Y + 1.5,
        entryCtr.Z + corr.Z * BRIDGE_DIST)

    local door1 = Vector3.new(
        floor1Ctr.X - corr.X * 2,
        floor1Ctr.Y + 1.5,
        floor1Ctr.Z - corr.Z * 2)

    local walk1 = Vector3.new(
        door1.X + right.X * WALK_DIST,
        door1.Y,
        door1.Z + right.Z * WALK_DIST)

    local door2
    if floor2Ctr then
        door2 = Vector3.new(floor2Ctr.X, floor2Ctr.Y + 1.5, floor2Ctr.Z)
    else
        door2 = Vector3.new(door1.X, door1.Y + 21, door1.Z)
    end

    local floor3
    if floor2Ctr then
        floor3 = Vector3.new(
            floor2Ctr.X + corr.X * 4,
            floor2Ctr.Y + 1.5,
            floor2Ctr.Z + corr.Z * 4)
    else
        floor3 = door2
    end

    return {
        entry = entry,
        bridge = bridge,
        door1 = door1,
        walk1 = walk1,
        door2 = door2,
        floor3 = floor3,
        floor1Ctr = floor1Ctr,
        floor2Ctr = floor2Ctr or door2,
    }
end

local function getDiamondTP()
    local items = workspace:FindFirstChild("Items")
    local chest = (items and items:FindFirstChild("Stronghold Diamond Chest", true))
        or workspace:FindFirstChild("Stronghold Diamond Chest", true)
    if not chest then return nil end
    local p
    if chest:IsA("Model") then
        local ok, piv = pcall(function() return chest:GetPivot() end)
        p = ok and piv and piv.Position
        if not p then
            local part = chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart",true)
            p = part and part.Position
        end
    elseif chest:IsA("BasePart") then
        p = chest.Position
    end
    if not p then return nil end
    return Vector3.new(p.X, p.Y + 2, p.Z + 4)
end

local cachedPoints = loadCache()

local function getPoints(force)
    if not force and cachedPoints and typeof(cachedPoints.door1) == "Vector3" then
        return cachedPoints, true
    end
    local pts, err = resolvePoints()
    if not pts then return nil, false, err end
    cachedPoints = pts
    saveCache(pts)
    return pts, false
end

-- ── Movimento ─────────────────────────────────────────────────────────────────
local function tpTo(pos, lookAt)
    if not pos then return end
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if lookAt and (lookAt - pos).Magnitude > 0.5 then
        root.CFrame = CFrame.new(pos, lookAt)
    else
        root.CFrame = CFrame.new(pos)
    end
    task.wait(0.25)
end

local function walkTo(pos, timeout)
    if not pos then return false end
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return false end
    timeout = timeout or WALK_TIMEOUT
    local arrived = false
    local conn = hum.MoveToFinished:Connect(function() arrived = true end)
    hum:MoveTo(pos)
    local t = 0
    while not arrived and t < timeout do task.wait(0.1); t = t + 0.1 end
    conn:Disconnect()
    return arrived
end

-- ── Contagem de cultists ──────────────────────────────────────────────────────
local function countCultists(floorIdx)
    local floor = FLOORS[floorIdx]
    if not floor then return 0 end
    local center
    if cachedPoints then
        center = (floorIdx == 1) and cachedPoints.floor1Ctr or cachedPoints.floor2Ctr
    end
    local alive = 0
    local deadline = os.clock() + 0.004
    for _, obj in ipairs(workspace:GetDescendants()) do
        if os.clock() > deadline then break end
        if obj and obj.Parent and obj.Name:lower():find("cultist") then
            local pos
            if obj:IsA("BasePart") then pos = obj.Position
            elseif obj:IsA("Model") then
                local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)
                pos = pp and pp.Position
            end
            if pos then
                local inY = pos.Y >= floor.yMin and pos.Y <= floor.yMax
                local inR = true
                if center then
                    inR = math.sqrt((pos.X-center.X)^2+(pos.Z-center.Z)^2) <= floor.radius
                end
                if inY and inR then
                    local hum = obj:FindFirstChildOfClass("Humanoid")
                        or (obj:IsA("Model") and obj:FindFirstDescendant("Humanoid"))
                    if not (hum and hum.Health <= 0) then alive = alive + 1 end
                end
            end
        end
    end
    return alive
end

-- ── GUI ───────────────────────────────────────────────────────────────────────
local oldGui = game:GetService("CoreGui"):FindFirstChild("DungeonRunnerV2")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonRunnerV2"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = game:GetService("CoreGui")

local FULL_H, MIN_H, W = 420, 34, 300
local connections = {}
local uiDestroyed = false

local main = Instance.new("Frame", gui)
main.Name = "Main"
main.Size = UDim2.new(0,W,0,FULL_H)
main.Position = UDim2.new(1,-(W+10),0.5,-FULL_H/2)
main.BackgroundColor3 = Color3.fromRGB(14,16,22)
main.BorderSizePixel = 0; main.ClipsDescendants = true; main.Active = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0,6)
local ms = Instance.new("UIStroke", main)
ms.Color = Color3.fromRGB(30,35,55); ms.Thickness = 1

local topLine = Instance.new("Frame", main)
topLine.Size = UDim2.new(1,0,0,2)
topLine.BackgroundColor3 = Color3.fromRGB(0,200,255)
topLine.BorderSizePixel = 0; topLine.ZIndex = 8

local header = Instance.new("Frame", main)
header.Size = UDim2.new(1,0,0,MIN_H)
header.BackgroundColor3 = Color3.fromRGB(10,12,18)
header.BorderSizePixel = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0,6)
local hf = Instance.new("Frame", header)
hf.Size = UDim2.new(1,0,0,10); hf.Position = UDim2.new(0,0,1,-10)
hf.BackgroundColor3 = Color3.fromRGB(10,12,18); hf.BorderSizePixel = 0

local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size = UDim2.new(1,-80,1,0); titleLbl.Position = UDim2.new(0,10,0,0)
titleLbl.BackgroundTransparency = 1
titleLbl.TextColor3 = Color3.fromRGB(0,200,255)
titleLbl.Text = "DUNGEON RUNNER"
titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 11
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local minBtn = Instance.new("TextButton", header)
minBtn.Size = UDim2.new(0,22,0,22); minBtn.Position = UDim2.new(1,-50,0.5,-11)
minBtn.BackgroundColor3 = Color3.fromRGB(30,35,55)
minBtn.TextColor3 = Color3.fromRGB(160,170,200)
minBtn.Text = "–"; minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 13
minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,4)

local closeBtn = Instance.new("TextButton", header)
closeBtn.Size = UDim2.new(0,22,0,22); closeBtn.Position = UDim2.new(1,-25,0.5,-11)
closeBtn.BackgroundColor3 = Color3.fromRGB(60,15,20)
closeBtn.TextColor3 = Color3.fromRGB(255,60,80)
closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 11
closeBtn.BorderSizePixel = 0
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(80,20,28)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    main.Size = minimized and UDim2.new(0,W,0,MIN_H) or UDim2.new(0,W,0,FULL_H)
    minBtn.Text = minimized and "□" or "–"
    if not minimized then titleLbl.Text = "DUNGEON RUNNER" end
end)

closeBtn.MouseButton1Click:Connect(function()
    uiDestroyed = true
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    gui:Destroy()
end)

-- Drag
local dragging, dragStart, dragOrigin = false, nil, nil
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = i.Position; dragOrigin = main.Position
    end
end)
header.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
local dc = UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        main.Position = UDim2.new(dragOrigin.X.Scale, dragOrigin.X.Offset+d.X,
                                   dragOrigin.Y.Scale, dragOrigin.Y.Offset+d.Y)
    end
end)
table.insert(connections, dc)

-- Labels
local function makeLbl(y, h, col, sz, bold)
    local l = Instance.new("TextLabel", main)
    l.Size = UDim2.new(1,-12,0,h); l.Position = UDim2.new(0,6,0,y)
    l.BackgroundTransparency = 1
    l.TextColor3 = col or Color3.fromRGB(160,170,200)
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize = sz or 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextWrapped = true; l.ZIndex = 3
    return l
end

local stepLbl = makeLbl(40,18, Color3.fromRGB(0,200,255), 12, true)
local floorLbl = makeLbl(62,14, Color3.fromRGB(150,160,190), 11, false)
local aliveLbl = makeLbl(80,14, Color3.fromRGB(100,200,100), 11, false)
local timerLbl = makeLbl(98,14, Color3.fromRGB(120,120,140), 10, false)

local sep = Instance.new("Frame", main)
sep.Size = UDim2.new(1,-12,0,1); sep.Position = UDim2.new(0,6,0,118)
sep.BackgroundColor3 = Color3.fromRGB(30,35,55); sep.BorderSizePixel = 0; sep.ZIndex = 3

local logBox = Instance.new("ScrollingFrame", main)
logBox.Size = UDim2.new(1,-8,0,172); logBox.Position = UDim2.new(0,4,0,124)
logBox.BackgroundColor3 = Color3.fromRGB(9,11,16)
logBox.BorderSizePixel = 0; logBox.ScrollBarThickness = 2
logBox.CanvasSize = UDim2.new(0,0,0,0)
logBox.AutomaticCanvasSize = Enum.AutomaticSize.Y; logBox.ZIndex = 3
Instance.new("UICorner", logBox).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", logBox).Color = Color3.fromRGB(25,30,45)
Instance.new("UIListLayout", logBox).Padding = UDim.new(0,1)
local lp3 = Instance.new("UIPadding", logBox)
lp3.PaddingTop = UDim.new(0,3); lp3.PaddingLeft = UDim.new(0,5); lp3.PaddingRight = UDim.new(0,4)

-- Botão Start/Stop
local ssBtn = Instance.new("TextButton", main)
ssBtn.Size = UDim2.new(1,-8,0,28); ssBtn.Position = UDim2.new(0,4,0,302)
ssBtn.BackgroundColor3 = Color3.fromRGB(15,60,25)
ssBtn.TextColor3 = Color3.fromRGB(60,255,100)
ssBtn.Text = "▶ INICIAR ROTA"
ssBtn.Font = Enum.Font.GothamBold; ssBtn.TextSize = 11
ssBtn.BorderSizePixel = 0; ssBtn.ZIndex = 3
Instance.new("UICorner", ssBtn).CornerRadius = UDim.new(0,5)
Instance.new("UIStroke", ssBtn).Color = Color3.fromRGB(20,80,35)

-- TPs manuais
local tpFrame = Instance.new("Frame", main)
tpFrame.Size = UDim2.new(1,-8,0,56); tpFrame.Position = UDim2.new(0,4,0,336)
tpFrame.BackgroundTransparency = 1; tpFrame.ZIndex = 3
local tpGrid = Instance.new("UIGridLayout", tpFrame)
tpGrid.CellSize = UDim2.new(0,140,0,24); tpGrid.CellPadding = UDim2.new(0,4,0,4)

local TP_KEYS = {
    {"TP Entrada","entry"},{"TP Bridge","bridge"},
    {"TP Porta 1","door1"},{"TP Porta 2","door2"},
    {"TP Andar 3","floor3"},{"TP Diamante","diamond"},
}
for _, def in ipairs(TP_KEYS) do
    local b = Instance.new("TextButton", tpFrame)
    b.BackgroundColor3 = Color3.fromRGB(20,24,38)
    b.TextColor3 = Color3.fromRGB(140,150,180)
    b.Text = def[1]; b.Font = Enum.Font.Gotham; b.TextSize = 10
    b.BorderSizePixel = 0; b.ZIndex = 3
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,4)
    Instance.new("UIStroke", b).Color = Color3.fromRGB(30,35,55)
    local key = def[2]
    b.MouseButton1Click:Connect(function()
        task.spawn(function()
            local pts = getPoints()
            if not pts then return end
            local pos = key == "diamond" and getDiamondTP() or pts[key]
            if pos then tpTo(pos) else log("Ponto não encontrado: "..key, Color3.fromRGB(255,120,80)) end
        end)
    end)
end

-- Botão limpar cache
local clearBtn = Instance.new("TextButton", main)
clearBtn.Size = UDim2.new(1,-8,0,18); clearBtn.Position = UDim2.new(0,4,0,396)
clearBtn.BackgroundColor3 = Color3.fromRGB(16,20,32)
clearBtn.TextColor3 = Color3.fromRGB(70,80,120)
clearBtn.Text = "↺ limpar cache de pontos"
clearBtn.Font = Enum.Font.Gotham; clearBtn.TextSize = 10
clearBtn.BorderSizePixel = 0; clearBtn.ZIndex = 3
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0,4)
clearBtn.MouseButton1Click:Connect(function()
    clearCache(); cachedPoints = nil
    log("Cache limpo — próximo START recalcula.", Color3.fromRGB(200,180,50))
end)

-- ── Logger ────────────────────────────────────────────────────────────────────
local MAX_LOG = 60
local function log(msg, color)
    if uiDestroyed then return end
    color = color or Color3.fromRGB(140,150,180)
    local kids = logBox:GetChildren()
    local cnt = 0
    for _, c in ipairs(kids) do if c:IsA("TextLabel") then cnt = cnt + 1 end end
    if cnt >= MAX_LOG then
        for _, c in ipairs(kids) do if c:IsA("TextLabel") then c:Destroy(); break end end
    end
    local row = Instance.new("TextLabel", logBox)
    row.Size = UDim2.new(1,0,0,13); row.BackgroundTransparency = 1
    row.TextColor3 = color
    row.Text = string.format("[%.0fs] %s", os.clock() % 10000, msg)
    row.Font = Enum.Font.Code; row.TextSize = 10
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.TextTruncate = Enum.TextTruncate.AtEnd; row.ZIndex = 4
    task.defer(function()
        if logBox and logBox.Parent then
            logBox.CanvasPosition = Vector2.new(0, logBox.AbsoluteCanvasSize.Y)
        end
    end)
end

local function setStep(txt, col)
    if uiDestroyed then return end
    stepLbl.Text = txt
    stepLbl.TextColor3 = col or Color3.fromRGB(0,200,255)
    if minimized then titleLbl.Text = "DR | "..txt:sub(1,20) end
end

-- ── Runner ────────────────────────────────────────────────────────────────────
local running = false

local function stopRunner()
    running = false
    ssBtn.Text = "▶ INICIAR ROTA"
    ssBtn.BackgroundColor3 = Color3.fromRGB(15,60,25)
    ssBtn.TextColor3 = Color3.fromRGB(60,255,100)
end

local function runAll()
    local pts, fromCache, err = getPoints()
    if not pts then
        log("ERRO: "..tostring(err), Color3.fromRGB(255,80,80))
        setStep("Erro ao resolver pontos", Color3.fromRGB(255,80,80))
        stopRunner(); return
    end
    if fromCache then
        log("Pontos em cache (sessão atual).", Color3.fromRGB(80,200,120))
    else
        log(string.format("Pontos calculados. entry=%s door1=%s",
            tostring(pts.entry), tostring(pts.door1)), Color3.fromRGB(80,200,120))
    end

    if not running then return end
    setStep("TP Entrada", Color3.fromRGB(0,200,255))
    log("TP Entrada", Color3.fromRGB(100,200,255))
    tpTo(pts.entry)

    if not running then return end
    setStep("TP Bridge", Color3.fromRGB(0,200,255))
    log("TP Bridge (dentro)", Color3.fromRGB(100,200,255))
    tpTo(pts.bridge)
    task.wait(0.3)

    if not running then return end
    setStep("Andando → Porta 1...", Color3.fromRGB(0,200,255))
    log("Andando até Porta 1 (ativa spawn)", Color3.fromRGB(200,200,80))
    walkTo(pts.walk1 or pts.door1, WALK_TIMEOUT)
    task.wait(0.1)  -- pequeno delay pra física estabilizar

    local nextTPs = { pts.door2, pts.floor3, nil }

    for floorIdx = 1, 3 do
        if not running then return end
        local floor = FLOORS[floorIdx]
        local nextTP = nextTPs[floorIdx]

        floorLbl.Text = string.format("Andar: %s (Y %d–%d)", floor.name, floor.yMin, floor.yMax)
        floorLbl.TextColor3 = floor.color
        setStep("Aguardando spawn: "..floor.name, floor.color)

        log("Aguardando spawn no "..floor.name.."...", floor.color)
        local spawnStart = os.clock()
        local seenAny = false

        -- CHECK IMEDIATO (captura spawns que ocorreram durante o andar)
        local alive = countCultists(floorIdx)
        if alive > 0 then
            seenAny = true
            log(string.format("%s: %d cultists detectados imediatamente!", floor.name, alive), floor.color)
        end

        -- Se ainda não viu, entra no loop de espera
        while not seenAny and (os.clock() - spawnStart) < SPAWN_TIMEOUT do
            if not running then return end
            task.wait(SCAN_INTERVAL)
            alive = countCultists(floorIdx)
            local elapsed = math.floor(os.clock() - spawnStart)
            aliveLbl.Text = string.format("Aguardando spawn... (%ds/%ds)", elapsed, SPAWN_TIMEOUT)
            aliveLbl.TextColor3 = Color3.fromRGB(200,180,50)

            if alive > 0 then
                seenAny = true
                log(string.format("%s: %d cultists detectados!", floor.name, alive), floor.color)
            end
        end

        if not running then return end

        if not seenAny then
            log("TIMEOUT: nenhum cultist no "..floor.name.." após "..SPAWN_TIMEOUT.."s. Verifique posição.", Color3.fromRGB(255,120,50))
            setStep("TIMEOUT — sem spawn no "..floor.name, Color3.fromRGB(255,120,50))
            stopRunner(); return
        end

        setStep("Matando: "..floor.name, floor.color)
        local zeroStreak = 0

        while running do
            task.wait(SCAN_INTERVAL)
            alive = countCultists(floorIdx)
            aliveLbl.Text = string.format("Vivos: %d", alive)
            aliveLbl.TextColor3 = alive > 0 and Color3.fromRGB(255,80,80) or Color3.fromRGB(80,255,100)

            if alive == 0 then
                zeroStreak = zeroStreak + SCAN_INTERVAL
                timerLbl.Text = string.format("Cooldown %.1fs/%.1fs", zeroStreak, COOLDOWN_AFTER)
                timerLbl.TextColor3 = Color3.fromRGB(200,180,50)
                if zeroStreak >= COOLDOWN_AFTER then break end
            else
                zeroStreak = 0
                timerLbl.Text = ""
            end
        end
        if not running then return end

        timerLbl.Text = ""
        log(floor.name.." limpo!", Color3.fromRGB(80,255,120))

        if nextTP then
            local label = (floorIdx == 1) and "Porta 2" or "Andar 3"
            setStep("TP "..label, floor.color)
            log("TP "..label, floor.color)
            tpTo(nextTP)
            task.wait(0.4)
        end
    end

    if not running then return end

    setStep("TP Baú Diamante!", Color3.fromRGB(255,215,0))
    log("Indo ao Baú Diamante...", Color3.fromRGB(255,215,0))
    floorLbl.Text = "Rota completa"; floorLbl.TextColor3 = Color3.fromRGB(255,215,0)
    aliveLbl.Text = ""; timerLbl.Text = ""

    local diamondPos = getDiamondTP()
    if not diamondPos then
        log("Baú não encontrado, aguardando 4s...", Color3.fromRGB(255,180,50))
        task.wait(4)
        diamondPos = getDiamondTP()
    end

    if diamondPos then
        tpTo(diamondPos)
        log("Baú Diamante alcançado!", Color3.fromRGB(255,215,0))
        setStep("Concluído!", Color3.fromRGB(80,255,120))
    else
        log("Baú não encontrado.", Color3.fromRGB(255,100,80))
        setStep("Baú não encontrado", Color3.fromRGB(255,100,80))
    end

    stopRunner()
end

-- Botão Start/Stop
ssBtn.MouseButton1Click:Connect(function()
    if not running then
        running = true
        ssBtn.Text = "■ PARAR"
        ssBtn.BackgroundColor3 = Color3.fromRGB(60,15,20)
        ssBtn.TextColor3 = Color3.fromRGB(255,60,80)
        aliveLbl.Text = ""; timerLbl.Text = ""
        floorLbl.Text = ""
        task.spawn(runAll)
    else
        running = false
        setStep("Parado", Color3.fromRGB(140,140,160))
        log("Runner parado.", Color3.fromRGB(200,80,80))
        stopRunner()
    end
end)

-- Init
setStep("Aguardando início", Color3.fromRGB(100,110,140))
if cachedPoints and typeof(cachedPoints.door1) == "Vector3" then
    log("Cache carregado: pontos prontos.", Color3.fromRGB(80,200,120))
else
    log("Pressione INICIAR para calcular pontos.", Color3.fromRGB(100,110,140))
end