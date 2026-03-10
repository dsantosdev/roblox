-- ============================================
-- MÓDULO: PLAYERS
-- ============================================
local VERSION = "1.0"
local CATEGORIA = "Player"

-- Não executa sem o hub
if not _G.Hub and not _G.HubFila then
    print('>>> follow_player: hub não encontrado, abortando')
    return
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local player = Players.LocalPlayer

-- ============================================
-- LÓGICA
-- ============================================
local followConn = nil
local targetPlayer = nil
local followMode = "follow"
local orbitAngle = 0
local ORBIT_RAIO = 5 -- studs de raio
local ORBIT_VEL = 1.5 -- radianos/segundo
local OFFSET_FOLLOW = Vector3.new(0, 0, 3)
local OFFSET_HEAD = Vector3.new(0, 3.5, 0)

local function getHRP(p)
    local c = p and p.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function getHead(p)
    local c = p and p.Character
    return c and c:FindFirstChild("Head")
end

local function pararFollow()
    if followConn then
        followConn:Disconnect();
        followConn = nil
    end
    targetPlayer = nil
    orbitAngle = 0
end

local function iniciarFollow(target, mode)
    pararFollow()
    targetPlayer = target
    followMode = mode or "follow"

    followConn = RS.Heartbeat:Connect(function(dt)
        if not targetPlayer or not targetPlayer.Parent then
            pararFollow()
            return
        end

        local myHRP = getHRP(player)
        local targetHRP = getHRP(targetPlayer)
        if not myHRP or not targetHRP then
            return
        end

        if followMode == "head" then
            local head = getHead(targetPlayer)
            local base = head and head.CFrame or targetHRP.CFrame
            myHRP.CFrame = CFrame.new(base.Position + OFFSET_HEAD)

        elseif followMode == "inside" then
            -- Fundido no corpo, mesma posição exata
            myHRP.CFrame = targetHRP.CFrame

        elseif followMode == "orbit" then
            -- Orbita em círculo ao redor do alvo
            orbitAngle = orbitAngle + ORBIT_VEL * dt
            local cx = targetHRP.Position.X + math.cos(orbitAngle) * ORBIT_RAIO
            local cz = targetHRP.Position.Z + math.sin(orbitAngle) * ORBIT_RAIO
            local cy = targetHRP.Position.Y
            -- Olha para o alvo enquanto orbita
            myHRP.CFrame = CFrame.new(Vector3.new(cx, cy, cz), targetHRP.Position)

        else -- follow padrão
            myHRP.CFrame = targetHRP.CFrame * CFrame.new(OFFSET_FOLLOW)
        end
    end)
end

-- ============================================
-- CORES
-- ============================================
local C = {
    bg = Color3.fromRGB(10, 11, 15),
    header = Color3.fromRGB(12, 14, 20),
    border = Color3.fromRGB(28, 32, 48),
    accent = Color3.fromRGB(0, 220, 255),
    green = Color3.fromRGB(50, 220, 100),
    greenDim = Color3.fromRGB(15, 55, 25),
    red = Color3.fromRGB(220, 50, 70),
    redDim = Color3.fromRGB(55, 12, 18),
    text = Color3.fromRGB(180, 190, 210),
    muted = Color3.fromRGB(65, 75, 100),
    rowBg = Color3.fromRGB(18, 20, 28),
    rowActive = Color3.fromRGB(15, 35, 25),
    panel = Color3.fromRGB(15, 17, 23)
}

-- ============================================
-- LAYOUT
-- ============================================
local W = 220
local H_HDR = 34
local H_ROW = 36
local H_STATUS = 22
local PAD = 6
local H_MAX_SCROLL = 240

-- ============================================
-- GUI
-- ============================================
local pg = player:WaitForChild("PlayerGui")
local ant = pg:FindFirstChild("FollowModule_hud")
if ant then
    ant:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "FollowModule_hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Name = "FollowFrame"
frame.Size = UDim2.new(0, W, 0, H_HDR)
frame.Position = UDim2.new(0, 20, 0, 260)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color = C.border

-- Accent topo
local topLine = Instance.new("Frame")
topLine.Size = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.accent
topLine.BorderSizePixel = 0
topLine.ZIndex = 5
topLine.Parent = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, H_HDR)
header.BackgroundColor3 = C.header
header.BorderSizePixel = 0
header.ZIndex = 3
header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 1, 0)
titleLbl.Position = UDim2.new(0, 10, 0, 0)
titleLbl.Text = "🎯 FOLLOW PLAYER"
titleLbl.TextColor3 = C.accent
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 11
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.ZIndex = 4
titleLbl.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 20)
minBtn.Position = UDim2.new(1, -44, 0.5, -10)
minBtn.Text = "—"
minBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
minBtn.TextColor3 = C.muted
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 10
minBtn.BorderSizePixel = 0
minBtn.ZIndex = 4
minBtn.Parent = header
Instance.new("UIStroke", minBtn).Color = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 3)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -20, 0.5, -10)
closeBtn.Text = "✕"
closeBtn.BackgroundColor3 = C.redDim
closeBtn.TextColor3 = C.red
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 10
closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 4
closeBtn.Parent = header
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 3)

-- Status bar
local statusBar = Instance.new("Frame")
statusBar.Size = UDim2.new(1, 0, 0, H_STATUS)
statusBar.Position = UDim2.new(0, 0, 0, H_HDR)
statusBar.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
statusBar.BorderSizePixel = 0
statusBar.ZIndex = 2
statusBar.Parent = frame

local statusLine = Instance.new("Frame")
statusLine.Size = UDim2.new(1, 0, 0, 1)
statusLine.Position = UDim2.new(0, 0, 1, -1)
statusLine.BackgroundColor3 = C.border
statusLine.BorderSizePixel = 0
statusLine.ZIndex = 3
statusLine.Parent = statusBar

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -16, 1, 0)
statusLbl.Position = UDim2.new(0, 8, 0, 0)
statusLbl.Text = "// AGUARDANDO SELEÇÃO"
statusLbl.TextColor3 = C.muted
statusLbl.Font = Enum.Font.Code
statusLbl.TextSize = 9
statusLbl.BackgroundTransparency = 1
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.ZIndex = 3
statusLbl.Parent = statusBar

-- Botão parar (aparece só quando seguindo)
local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(1, -PAD * 2, 0, 26)
stopBtn.Position = UDim2.new(0, PAD, 0, H_HDR + H_STATUS + PAD)
stopBtn.Text = "⬛  PARAR DE SEGUIR"
stopBtn.BackgroundColor3 = C.redDim
stopBtn.TextColor3 = C.red
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 10
stopBtn.BorderSizePixel = 0
stopBtn.ZIndex = 3
stopBtn.Visible = false
stopBtn.Parent = frame
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", stopBtn).Color = Color3.fromRGB(100, 20, 35)

-- ScrollingFrame da lista
local SCROLL_Y = H_HDR + H_STATUS + PAD

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -PAD * 2, 0, 0)
scroll.Position = UDim2.new(0, PAD, 0, SCROLL_Y)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C.accent
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ZIndex = 3
scroll.Parent = frame

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- ============================================
-- DRAG + PERSISTÊNCIA DE POSIÇÃO
-- ============================================
local HS = game:GetService("HttpService")
local POS_KEY_FOLLOW = "follow_pos.json"
local _followData = nil
local function salvarPos()
    if writefile then
        local __ok, __e = pcall(writefile, POS_KEY_FOLLOW, HS:JSONEncode({
            x = frame.Position.X.Offset,
            y = frame.Position.Y.Offset,
            minimizado = minimizado, hCache = hFullCache
        }))
        if not __ok then
            warn("salvarPos erro:", __e)
        end
    end
end
local function carregarPos()
    if isfile and readfile and isfile(POS_KEY_FOLLOW) then
        local ok, d = pcall(function()
            return HS:JSONDecode(readfile(POS_KEY_FOLLOW))
        end)
        if ok and d then
            frame.Position = UDim2.new(0, d.x, 0, d.y)
            _followData = d
        end
    end
end
carregarPos()

if _G.Snap then _G.Snap.registrar(frame, salvarPos) end

local dragging, dragStart, startPos
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = i.Position; startPos = frame.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        local nx = startPos.X.Offset + d.X
        local ny = startPos.Y.Offset + d.Y
        if _G.Snap then _G.Snap.mover(frame, nx, ny)
        else frame.Position = UDim2.new(0, nx, 0, ny) end
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        if dragging then
            if _G.Snap then _G.Snap.soltar(frame)
            else salvarPos() end
        end
        dragging = false
    end
end)

-- ============================================
-- RENDERIZAR LISTA DE PLAYERS
-- ============================================
local selectedRow = nil -- referência à row selecionada

local function atualizarAltura(n)
    local contentH = n * (H_ROW + 4)
    local scrollH = math.min(contentH, H_MAX_SCROLL)
    if n == 0 then
        scrollH = 0
    end
    scroll.Size = UDim2.new(1, -PAD * 2, 0, scrollH)

    local stopExtra = stopBtn.Visible and (26 + PAD) or 0
    frame.Size = UDim2.new(0, W, 0, SCROLL_Y + scrollH + stopExtra + PAD)
end

local function setStatus(text, cor)
    statusLbl.Text = "// " .. text
    statusLbl.TextColor3 = cor or C.muted
end

local function renderPlayers()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("Frame") then
            c:Destroy()
        end
    end
    selectedRow = nil

    local lista = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            table.insert(lista, p)
        end
    end

    if #lista == 0 then
        setStatus("SEM OUTROS JOGADORES", C.red)
        atualizarAltura(0)
        return
    end

    for i, p in ipairs(lista) do
        local row = Instance.new("Frame")
        row.Name = "Player_" .. p.Name
        row.Size = UDim2.new(1, 0, 0, H_ROW)
        row.BackgroundColor3 = C.rowBg
        row.BorderSizePixel = 0
        row.LayoutOrder = i
        row.ZIndex = 4
        row.Parent = scroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
        local rowStroke = Instance.new("UIStroke", row)
        rowStroke.Color = C.border
        rowStroke.Thickness = 1

        -- Indicador lateral
        local leftBar = Instance.new("Frame")
        leftBar.Name = "LeftBar"
        leftBar.Size = UDim2.new(0, 2, 1, -8)
        leftBar.Position = UDim2.new(0, 0, 0, 4)
        leftBar.BackgroundColor3 = C.border
        leftBar.BorderSizePixel = 0
        leftBar.ZIndex = 5
        leftBar.Parent = row
        Instance.new("UICorner", leftBar).CornerRadius = UDim.new(0, 2)

        -- Nome do jogador
        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(1, -100, 0.55, 0)
        nameLbl.Position = UDim2.new(0, 12, 0, 4)
        nameLbl.Text = p.DisplayName
        nameLbl.TextColor3 = C.text
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 11
        nameLbl.BackgroundTransparency = 1
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.ZIndex = 5
        nameLbl.Parent = row

        -- @username
        local userLbl = Instance.new("TextLabel")
        userLbl.Size = UDim2.new(1, -100, 0.38, 0)
        userLbl.Position = UDim2.new(0, 12, 0.58, 0)
        userLbl.Text = "@" .. p.Name
        userLbl.TextColor3 = C.muted
        userLbl.Font = Enum.Font.Code
        userLbl.TextSize = 8
        userLbl.BackgroundTransparency = 1
        userLbl.TextXAlignment = Enum.TextXAlignment.Left
        userLbl.ZIndex = 5
        userLbl.Parent = row

        -- 4 botões de modo: follow | head | inside | orbit
        local btnDefs = {{
            icon = "👣",
            mode = "follow",
            bg = Color3.fromRGB(15, 35, 55),
            stroke = Color3.fromRGB(20, 70, 130),
            tip = "Seguir"
        }, {
            icon = "🪑",
            mode = "head",
            bg = Color3.fromRGB(40, 25, 55),
            stroke = Color3.fromRGB(80, 40, 120),
            tip = "Cabeça"
        }, {
            icon = "👻",
            mode = "inside",
            bg = Color3.fromRGB(15, 40, 40),
            stroke = Color3.fromRGB(20, 100, 100),
            tip = "Dentro"
        }, {
            icon = "🔵",
            mode = "orbit",
            bg = Color3.fromRGB(35, 25, 10),
            stroke = Color3.fromRGB(120, 80, 20),
            tip = "Orbitar"
        }}

        local modeBtns = {}
        for bi, def in ipairs(btnDefs) do
            local mb = Instance.new("TextButton")
            mb.Size = UDim2.new(0, 20, 0, 20)
            mb.Position = UDim2.new(1, -96 + (bi - 1) * 24, 0.5, -10)
            mb.Text = def.icon
            mb.BackgroundColor3 = def.bg
            mb.TextColor3 = Color3.fromRGB(220, 220, 220)
            mb.Font = Enum.Font.GothamBold
            mb.TextSize = 11
            mb.BorderSizePixel = 0
            mb.ZIndex = 7
            mb.Parent = row
            Instance.new("UICorner", mb).CornerRadius = UDim.new(0, 4)
            Instance.new("UIStroke", mb).Color = def.stroke
            modeBtns[def.mode] = mb
        end

        -- Hover na row
        row.MouseEnter:Connect(function()
            if targetPlayer ~= p then
                TS:Create(row, TweenInfo.new(0.1), {
                    BackgroundColor3 = Color3.fromRGB(22, 26, 38)
                }):Play()
            end
        end)
        row.MouseLeave:Connect(function()
            if targetPlayer ~= p then
                TS:Create(row, TweenInfo.new(0.1), {
                    BackgroundColor3 = C.rowBg
                }):Play()
            end
        end)

        -- Cores por modo
        local modeColors = {
            follow = {
                row = C.rowActive,
                bar = C.green,
                text = C.green,
                status = "👣 SEGUINDO "
            },
            head = {
                row = Color3.fromRGB(25, 15, 35),
                bar = Color3.fromRGB(180, 100, 255),
                text = Color3.fromRGB(200, 150, 255),
                status = "🪑 NA CABEÇA DE "
            },
            inside = {
                row = Color3.fromRGB(10, 30, 30),
                bar = Color3.fromRGB(0, 200, 180),
                text = Color3.fromRGB(0, 220, 200),
                status = "👻 DENTRO DE "
            },
            orbit = {
                row = Color3.fromRGB(30, 25, 10),
                bar = Color3.fromRGB(255, 180, 30),
                text = Color3.fromRGB(255, 200, 60),
                status = "🔵 ORBITANDO "
            }
        }

        local function ativarRow(mode)
            if selectedRow and selectedRow ~= row then
                TS:Create(selectedRow, TweenInfo.new(0.15), {
                    BackgroundColor3 = C.rowBg
                }):Play()
                local lb = selectedRow:FindFirstChild("LeftBar")
                if lb then
                    TS:Create(lb, TweenInfo.new(0.15), {
                        BackgroundColor3 = C.border
                    }):Play()
                end
            end

            selectedRow = row
            local mc = modeColors[mode]
            TS:Create(row, TweenInfo.new(0.15), {
                BackgroundColor3 = mc.row
            }):Play()
            TS:Create(leftBar, TweenInfo.new(0.15), {
                BackgroundColor3 = mc.bar
            }):Play()
            TS:Create(nameLbl, TweenInfo.new(0.15), {
                TextColor3 = mc.text
            }):Play()

            iniciarFollow(p, mode)
            setStatus(mc.status .. p.DisplayName, mc.text)

            stopBtn.Visible = true
            stopBtn.Position = UDim2.new(0, PAD, 0, H_HDR + H_STATUS + PAD)
            scroll.Position = UDim2.new(0, PAD, 0, H_HDR + H_STATUS + PAD + 26 + PAD)
            atualizarAltura(#lista)
        end

        for _, def in ipairs(btnDefs) do
            modeBtns[def.mode].MouseButton1Click:Connect(function()
                ativarRow(def.mode)
            end)
        end
    end

    atualizarAltura(#lista)

    -- Recoloca scroll na posição padrão se não há seguindo
    if not targetPlayer then
        scroll.Position = UDim2.new(0, PAD, 0, SCROLL_Y)
    end
end

-- ============================================
-- PARAR DE SEGUIR
-- ============================================
local function pararUI()
    pararFollow()
    setStatus("AGUARDANDO SELEÇÃO", C.muted)
    stopBtn.Visible = false
    scroll.Position = UDim2.new(0, PAD, 0, SCROLL_Y)
    if selectedRow then
        TS:Create(selectedRow, TweenInfo.new(0.15), {
            BackgroundColor3 = C.rowBg
        }):Play()
        local lb = selectedRow:FindFirstChild("LeftBar")
        if lb then
            TS:Create(lb, TweenInfo.new(0.15), {
                BackgroundColor3 = C.border
            }):Play()
        end
        selectedRow = nil
    end
    renderPlayers()
end

stopBtn.MouseButton1Click:Connect(pararUI)

-- ============================================
-- ATUALIZA LISTA QUANDO ALGUÉM ENTRA/SAI
-- ============================================
Players.PlayerAdded:Connect(function()
    task.wait(0.5)
    renderPlayers()
end)

Players.PlayerRemoving:Connect(function(p)
    if targetPlayer == p then
        pararUI()
    end
    task.wait(0.2)
    renderPlayers()
end)

-- ============================================
-- MINIMIZAR
-- ============================================
local minimizado = false
local hFullCache = nil

minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    salvarPos()
    if minimizado then
        hFullCache = frame.Size.Y.Offset
        TS:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, H_HDR)
        }):Play()
        statusBar.Visible = false
        stopBtn.Visible = false
        scroll.Visible = false
        minBtn.Text = "▲"
    else
        statusBar.Visible = true
        scroll.Visible = true
        if targetPlayer then
            stopBtn.Visible = true
        end
        TS:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, hFullCache or (SCROLL_Y + 100))
        }):Play()
        minBtn.Text = "—"
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    salvarPos()
    pararFollow()
    gui.Enabled = false
    if _G.Hub then
        pcall(function()
            _G.Hub.desligar("Follow Player")
        end)
    end
end)

-- ============================================
-- REGISTRA NO HUB
-- ============================================
local function onToggle(ativo)
    if not ativo then
        pararFollow()
    end
    if gui and gui.Parent then
        gui.Enabled = ativo
    end
end

if _G.Hub then
    _G.Hub.registrar("Follow Player", onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, {
        nome = "Follow Player",
        toggleFn = onToggle,
        categoria = CATEGORIA,
        jaAtivo = true
    })
end

-- Restaura estado minimizado salvo
if _followData and _followData.minimizado then
    hFullCache = _followData.hCache or frame.Size.Y.Offset
    minimizado = true
    frame.Size = UDim2.new(0, W, 0, H_HDR)
    statusBar.Visible = false
    stopBtn.Visible   = false
    scroll.Visible    = false
    minBtn.Text = "▲"
end

renderPlayers()
print(">>> FOLLOW PLAYER ATIVO")
