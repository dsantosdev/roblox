-- ============================================
-- MÓDULO: TELEPORTER
-- ============================================

local VERSION   = "1.0.6"
local CATEGORIA = "Utility"
local MODULE_NAME = "Teleporte"

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local TS      = game:GetService("TweenService")
local HS      = game:GetService("HttpService")
local RS      = game:GetService("RunService")
local player  = Players.LocalPlayer

-- ============================================
-- INFO DO JOGO
-- ============================================
local PLACE_ID   = tostring(game.PlaceId)
local PLACE_NAME = (function()
    local ok, name = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    end)
    return (ok and name) or "Jogo " .. PLACE_ID
end)()

-- ============================================
-- PERSISTÊNCIA
-- ============================================
local SAVE_KEY = "tp_slots_" .. PLACE_ID .. ".json"

local function salvar(slots)
    if not writefile then return end
    local dados = {}
    for _, s in ipairs(slots) do
        local p  = s.cf.Position
        local lv = s.cf.LookVector
        table.insert(dados, { nome = s.nome, px = p.X, py = p.Y, pz = p.Z, lx = lv.X, ly = lv.Y, lz = lv.Z })
    end
    pcall(writefile, SAVE_KEY, HS:JSONEncode(dados))
end

local function carregar()
    if not (isfile and readfile and isfile(SAVE_KEY)) then return {} end
    local ok, dados = pcall(function() return HS:JSONDecode(readfile(SAVE_KEY)) end)
    if not ok or type(dados) ~= "table" then return {} end
    local slots = {}
    for _, d in ipairs(dados) do
        local cf = CFrame.new(d.px, d.py, d.pz) * CFrame.Angles(0, math.atan2(-d.lx, -d.lz), 0)
        table.insert(slots, { nome = d.nome, cf = cf })
    end
    return slots
end

local slots = carregar()

-- ============================================
-- HELPERS
-- ============================================
local function getHRP()
    local c = player.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function teleportar(cf)
    local hrp = getHRP()
    if not hrp then return end
    local lock = true
    local conn
    conn = RS.Heartbeat:Connect(function()
        if not lock then conn:Disconnect(); return end
        local h = getHRP()
        if h then h.CFrame = cf end
    end)
    task.delay(1.2, function() lock = false end)
end

-- ============================================
-- CORES
-- ============================================
local C = {
    bg      = Color3.fromRGB(10, 11, 15),
    panel   = Color3.fromRGB(18, 20, 30),
    header  = Color3.fromRGB(12, 14, 20),
    border  = Color3.fromRGB(28, 32, 48),
    accent  = Color3.fromRGB(0, 220, 255),
    green   = Color3.fromRGB(50, 220, 100),
    greenDim= Color3.fromRGB(15, 55, 25),
    red     = Color3.fromRGB(220, 50, 70),
    redDim  = Color3.fromRGB(55, 12, 18),
    yellow  = Color3.fromRGB(255, 200, 50),
    text    = Color3.fromRGB(180, 190, 210),
    muted   = Color3.fromRGB(65, 75, 100),
    rowBg   = Color3.fromRGB(18, 20, 28),
    rowHov  = Color3.fromRGB(22, 26, 38),
}

-- ============================================
-- CONSTANTES DE LAYOUT
-- ============================================
local W          = 240
local H_HDR      = 34
local H_SUBHDR   = 20   -- faixa do nome do jogo
local H_SAVEBTN  = 28
local H_SLOT     = 36
local H_SCROLL_MAX = 260
local PAD        = 6

-- ============================================
-- GUI
-- ============================================
local pg = player:WaitForChild("PlayerGui")
local ant = pg:FindFirstChild("TeleportModule_hud")
if ant then ant:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name          = "TeleportModule_hud"
gui.ResetOnSpawn  = false
gui.IgnoreGuiInset = true
gui.Parent        = pg

-- O frame se posiciona colado à direita do hub.
-- O hub está em (posX, posY) com largura 240.
-- Usamos um script de ancoragem dinâmica abaixo.
local frame = Instance.new("Frame")
frame.Name             = "TeleFrame"
frame.Size             = UDim2.new(0, W, 0, H_HDR)
frame.Position         = UDim2.new(0, 390, 0, 20)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel  = 0
frame.Parent           = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color        = C.border

-- Accent topo
local topLine = Instance.new("Frame")
topLine.Size             = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.accent
topLine.BorderSizePixel  = 0
topLine.ZIndex           = 5
topLine.Parent           = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

-- ============================================
-- HEADER
-- ============================================
local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, H_HDR)
header.BackgroundColor3 = C.header
header.BorderSizePixel  = 0
header.Active           = true
header.ZIndex           = 3
header.Parent           = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size               = UDim2.new(1, -80, 1, 0)
titleLbl.Position           = UDim2.new(0, 10, 0, 0)
titleLbl.Text               = "📍 TELEPORTE"
titleLbl.TextColor3         = C.accent
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 11
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 4
titleLbl.Parent             = header

local minBtn = Instance.new("TextButton")
minBtn.Size             = UDim2.new(0, 20, 0, 20)
minBtn.Position         = UDim2.new(1, -44, 0.5, -10)
minBtn.Text             = "—"
minBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
minBtn.TextColor3       = C.muted
minBtn.Font             = Enum.Font.GothamBold
minBtn.TextSize         = 10
minBtn.BorderSizePixel  = 0
minBtn.ZIndex           = 4
minBtn.Parent           = header
Instance.new("UIStroke", minBtn).Color        = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 3)

local closeBtn2 = Instance.new("TextButton")
closeBtn2.Size             = UDim2.new(0, 20, 0, 20)
closeBtn2.Position         = UDim2.new(1, -20, 0.5, -10)
closeBtn2.Text             = "✕"
closeBtn2.BackgroundColor3 = C.redDim
closeBtn2.TextColor3       = C.red
closeBtn2.Font             = Enum.Font.GothamBold
closeBtn2.TextSize         = 10
closeBtn2.BorderSizePixel  = 0
closeBtn2.ZIndex           = 4
closeBtn2.Parent           = header
Instance.new("UIStroke", closeBtn2).Color        = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn2).CornerRadius = UDim.new(0, 3)

-- ============================================
-- SUBHEADER — NOME DO JOGO
-- ============================================
local subHdr = Instance.new("Frame")
subHdr.Size             = UDim2.new(1, 0, 0, H_SUBHDR)
subHdr.Position         = UDim2.new(0, 0, 0, H_HDR)
subHdr.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
subHdr.BorderSizePixel  = 0
subHdr.ZIndex           = 2
subHdr.Parent           = frame

local subLine = Instance.new("Frame")
subLine.Size             = UDim2.new(1, 0, 0, 1)
subLine.Position         = UDim2.new(0, 0, 1, -1)
subLine.BackgroundColor3 = C.border
subLine.BorderSizePixel  = 0
subLine.ZIndex           = 3
subLine.Parent           = subHdr

local gameLbl = Instance.new("TextLabel")
gameLbl.Size               = UDim2.new(1, -16, 1, 0)
gameLbl.Position           = UDim2.new(0, 8, 0, 0)
gameLbl.Text               = "// " .. PLACE_NAME
gameLbl.TextColor3         = C.muted
gameLbl.Font               = Enum.Font.Code
gameLbl.TextSize           = 9
gameLbl.BackgroundTransparency = 1
gameLbl.TextXAlignment     = Enum.TextXAlignment.Left
gameLbl.TextTruncate       = Enum.TextTruncate.AtEnd
gameLbl.ZIndex             = 3
gameLbl.Parent             = subHdr

-- ============================================
-- BOTÃO SALVAR
-- ============================================
local SAVE_Y = H_HDR + H_SUBHDR + PAD

local saveBtn = Instance.new("TextButton")
saveBtn.Size             = UDim2.new(1, -PAD*2, 0, H_SAVEBTN)
saveBtn.Position         = UDim2.new(0, PAD, 0, SAVE_Y)
saveBtn.Text             = "+ SALVAR POSIÇÃO ATUAL"
saveBtn.BackgroundColor3 = C.greenDim
saveBtn.TextColor3       = C.green
saveBtn.Font             = Enum.Font.GothamBold
saveBtn.TextSize         = 10
saveBtn.BorderSizePixel  = 0
saveBtn.ZIndex           = 3
saveBtn.Parent           = frame
Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", saveBtn).Color        = Color3.fromRGB(30, 100, 50)

-- ============================================
-- SCROLL
-- ============================================
local SCROLL_Y = SAVE_Y + H_SAVEBTN + PAD

local scroll = Instance.new("ScrollingFrame")
scroll.Size                   = UDim2.new(1, -PAD*2, 0, 0)
scroll.Position               = UDim2.new(0, PAD, 0, SCROLL_Y)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel        = 0
scroll.ScrollBarThickness     = 3
scroll.ScrollBarImageColor3   = C.accent
scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
scroll.ZIndex                 = 3
scroll.Parent                 = frame

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.Padding   = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- ============================================
-- DRAG + PERSISTÊNCIA DE POSIÇÃO
-- ============================================
local POS_KEY_TP = "teleport_pos.json"
local minimizado = false
local hFullCache = nil
local _tpData = nil
local estadoJanela = "maximizado"
local function setEstadoJanela(v)
    estadoJanela = v
    if _G.KAHWindowState and _G.KAHWindowState.set then
        _G.KAHWindowState.set(MODULE_NAME, v)
    end
end
local function salvarPosTp()
    if writefile then
        pcall(writefile, POS_KEY_TP, HS:JSONEncode({
            x = frame.Position.X.Offset, y = frame.Position.Y.Offset,
            minimizado = minimizado, hCache = hFullCache, windowState = estadoJanela
        }))
    end
end
local function carregarPosTp()
    if isfile and readfile and isfile(POS_KEY_TP) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY_TP)) end)
        if ok and d then
            frame.Position = UDim2.new(0, d.x, 0, d.y)
            _tpData = d
        end
    end
end
carregarPosTp()

do
    local saved = (_G.KAHWindowState and _G.KAHWindowState.get) and _G.KAHWindowState.get(MODULE_NAME, nil) or nil
    if saved then
        estadoJanela = saved
    elseif _tpData and (_tpData.windowState == "maximizado" or _tpData.windowState == "minimizado" or _tpData.windowState == "fechado") then
        estadoJanela = _tpData.windowState
    elseif _tpData and _tpData.minimizado then
        estadoJanela = "minimizado"
    end
end

if _G.Snap then _G.Snap.registrar(frame, salvarPosTp) end

local dragInput, dragStartPos, dragStartMouse, dragging
header.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    dragging = true
    dragInput = i
    dragStartPos = frame.Position
    dragStartMouse = i.Position
end)
UIS.InputChanged:Connect(function(i)
    if not dragging then return end
    if i.UserInputType ~= Enum.UserInputType.MouseMovement
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if dragInput and dragInput.UserInputType == Enum.UserInputType.Touch
    and i.UserInputType == Enum.UserInputType.Touch
    and i ~= dragInput then
        return
    end
    local d = i.Position - dragStartMouse
    local nx = dragStartPos.X.Offset + d.X
    local ny = dragStartPos.Y.Offset + d.Y
    if _G.Snap then _G.Snap.mover(frame, nx, ny)
    else frame.Position = UDim2.new(0, nx, 0, ny) end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
    and i.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if dragging then
        if _G.Snap then _G.Snap.soltar(frame)
        else salvarPosTp() end
    end
    dragging = false
    dragInput = nil
end)

-- ============================================
-- RENDERIZAR SLOTS
-- ============================================
local function atualizarAltura()
    local contentH = #slots * (H_SLOT + 4)
    local scrollH  = math.min(contentH, H_SCROLL_MAX)
    if #slots == 0 then scrollH = 0 end
    scroll.Size = UDim2.new(1, -PAD*2, 0, scrollH)
    local extra = (#slots > 0) and (PAD) or 0
    frame.Size = UDim2.new(0, W, 0, SCROLL_Y + scrollH + extra)
end

local function renderSlots()
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    for i, slot in ipairs(slots) do
        local row = Instance.new("Frame")
        row.Name             = "Slot_" .. i
        row.Size             = UDim2.new(1, 0, 0, H_SLOT)
        row.BackgroundColor3 = C.rowBg
        row.BorderSizePixel  = 0
        row.LayoutOrder      = i
        row.ZIndex           = 4
        row.Parent           = scroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", row).Color        = C.border

        -- Área clicável do nome (teleporta)
        local nameBtn = Instance.new("TextButton")
        nameBtn.Name               = "NameBtn"
        nameBtn.Size               = UDim2.new(1, -72, 1, 0)
        nameBtn.Position           = UDim2.new(0, 0, 0, 0)
        nameBtn.BackgroundTransparency = 1
        nameBtn.Text               = ""
        nameBtn.ZIndex             = 6
        nameBtn.Parent             = row

        -- Nome
        local nomeLbl = Instance.new("TextLabel")
        nomeLbl.Name               = "NomeLbl"
        nomeLbl.Size               = UDim2.new(1, -10, 0.55, 0)
        nomeLbl.Position           = UDim2.new(0, 8, 0, 4)
        nomeLbl.Text               = slot.nome
        nomeLbl.TextColor3         = C.text
        nomeLbl.Font               = Enum.Font.GothamBold
        nomeLbl.TextSize           = 10
        nomeLbl.BackgroundTransparency = 1
        nomeLbl.TextXAlignment     = Enum.TextXAlignment.Left
        nomeLbl.TextTruncate       = Enum.TextTruncate.AtEnd
        nomeLbl.ZIndex             = 5
        nomeLbl.Parent             = row

        -- Descrição (coordenadas)
        local pos = slot.cf.Position
        local descLbl = Instance.new("TextLabel")
        descLbl.Name               = "DescLbl"
        descLbl.Size               = UDim2.new(1, -10, 0.4, 0)
        descLbl.Position           = UDim2.new(0, 8, 0.58, 0)
        descLbl.Text               = string.format("X%.0f  Y%.0f  Z%.0f", pos.X, pos.Y, pos.Z)
        descLbl.TextColor3         = C.muted
        descLbl.Font               = Enum.Font.Code
        descLbl.TextSize           = 8
        descLbl.BackgroundTransparency = 1
        descLbl.TextXAlignment     = Enum.TextXAlignment.Left
        descLbl.ZIndex             = 5
        descLbl.Parent             = row

        -- Botão renomear ✎
        local renBtn = Instance.new("TextButton")
        renBtn.Size             = UDim2.new(0, 22, 0, 22)
        renBtn.Position         = UDim2.new(1, -48, 0.5, -11)
        renBtn.Text             = "✎"
        renBtn.BackgroundColor3 = Color3.fromRGB(50, 40, 15)
        renBtn.TextColor3       = C.yellow
        renBtn.Font             = Enum.Font.GothamBold
        renBtn.TextSize         = 11
        renBtn.BorderSizePixel  = 0
        renBtn.ZIndex           = 7
        renBtn.Parent           = row
        Instance.new("UICorner", renBtn).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", renBtn).Color        = Color3.fromRGB(100, 80, 20)

        -- Botão deletar ✕
        local delBtn = Instance.new("TextButton")
        delBtn.Size             = UDim2.new(0, 22, 0, 22)
        delBtn.Position         = UDim2.new(1, -22, 0.5, -11)
        delBtn.Text             = "✕"
        delBtn.BackgroundColor3 = C.redDim
        delBtn.TextColor3       = C.red
        delBtn.Font             = Enum.Font.GothamBold
        delBtn.TextSize         = 10
        delBtn.BorderSizePixel  = 0
        delBtn.ZIndex           = 7
        delBtn.Parent           = row
        Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", delBtn).Color        = Color3.fromRGB(100, 20, 35)

        -- TextBox para renomear (oculta)
        local inputBox = Instance.new("TextBox")
        inputBox.Size               = UDim2.new(1, -80, 0, 22)
        inputBox.Position           = UDim2.new(0, 6, 0.5, -11)
        inputBox.Text               = slot.nome
        inputBox.BackgroundColor3   = Color3.fromRGB(20, 24, 38)
        inputBox.TextColor3         = C.accent
        inputBox.Font               = Enum.Font.GothamBold
        inputBox.TextSize           = 10
        inputBox.BorderSizePixel    = 0
        inputBox.ZIndex             = 8
        inputBox.Visible            = false
        inputBox.ClearTextOnFocus   = false
        inputBox.PlaceholderText    = "Nome do slot..."
        inputBox.PlaceholderColor3  = C.muted
        inputBox.Parent             = row
        Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", inputBox).Color        = C.accent

        -- Hover no nome → destaca em cyan
        nameBtn.MouseEnter:Connect(function()
            TS:Create(nomeLbl, TweenInfo.new(0.1), { TextColor3 = C.accent }):Play()
        end)
        nameBtn.MouseLeave:Connect(function()
            TS:Create(nomeLbl, TweenInfo.new(0.1), { TextColor3 = C.text }):Play()
        end)

        -- Clicar no nome → teleportar
        nameBtn.MouseButton1Click:Connect(function()
            teleportar(slot.cf)
            TS:Create(row, TweenInfo.new(0.08), { BackgroundColor3 = Color3.fromRGB(15, 40, 25) }):Play()
            task.delay(0.35, function()
                TS:Create(row, TweenInfo.new(0.2), { BackgroundColor3 = C.rowBg }):Play()
            end)
        end)

        -- Renomear
        local editando = false

        renBtn.MouseButton1Click:Connect(function()
            editando = not editando
            inputBox.Visible = editando
            nomeLbl.Visible  = not editando
            descLbl.Visible  = not editando
            nameBtn.Visible  = not editando
            if editando then
                inputBox.Text = ""
                inputBox:CaptureFocus()
            end
        end)

        inputBox.FocusLost:Connect(function()
            local novo = inputBox.Text:match("^%s*(.-)%s*$")
            if novo and #novo > 0 then
                slot.nome    = novo
                nomeLbl.Text = novo
                salvar(slots)
            end
            editando         = false
            inputBox.Visible = false
            nomeLbl.Visible  = true
            descLbl.Visible  = true
            nameBtn.Visible  = true
        end)

        -- Deletar
        delBtn.MouseButton1Click:Connect(function()
            table.remove(slots, i)
            salvar(slots)
            renderSlots()
            atualizarAltura()
        end)
    end

    atualizarAltura()
end

-- ============================================
-- BOTÃO SALVAR
-- ============================================
saveBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if not hrp then return end

    table.insert(slots, {
        nome = "Posição " .. (#slots + 1),
        cf   = hrp.CFrame,
    })
    salvar(slots)
    renderSlots()

    -- Feedback
    TS:Create(saveBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(20, 90, 45) }):Play()
    task.delay(0.4, function()
        TS:Create(saveBtn, TweenInfo.new(0.2), { BackgroundColor3 = C.greenDim }):Play()
    end)
end)

-- ============================================
-- MINIMIZAR
-- ============================================
minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    if minimizado then
        hFullCache = frame.Size.Y.Offset
        TS:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, H_HDR)
        }):Play()
        subHdr.Visible  = false
        saveBtn.Visible = false
        scroll.Visible  = false
        minBtn.Text = "▲"
    else
        subHdr.Visible  = true
        saveBtn.Visible = true
        scroll.Visible  = true
        TS:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, hFullCache or (SCROLL_Y + 100))
        }):Play()
        minBtn.Text = "—"
    end
    setEstadoJanela(minimizado and "minimizado" or "maximizado")
    salvarPosTp()
end)

closeBtn2.MouseButton1Click:Connect(function()
    setEstadoJanela("fechado")
    salvarPosTp()
    gui.Enabled = false
    if _G.Hub then
        pcall(function() _G.Hub.desligar(MODULE_NAME) end)
    end
end)

-- ============================================
-- REGISTRA NO HUB
-- ============================================
local booting = true
local function onToggle(ativo)
    if gui and gui.Parent then gui.Enabled = ativo end
    if not booting then
        if ativo then
            setEstadoJanela(minimizado and "minimizado" or "maximizado")
        else
            setEstadoJanela("fechado")
        end
        salvarPosTp()
    end
end

local iniciarAtivo = estadoJanela ~= "fechado"
gui.Enabled = iniciarAtivo

if _G.Hub then
    _G.Hub.registrar(MODULE_NAME, onToggle, CATEGORIA, iniciarAtivo)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = MODULE_NAME, toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = iniciarAtivo })
end

-- ============================================
-- INIT
-- ============================================
renderSlots()
atualizarAltura()

-- Restaura estado minimizado salvo
if estadoJanela == "minimizado" or (_tpData and _tpData.minimizado and estadoJanela ~= "maximizado") then
    hFullCache = _tpData.hCache or frame.Size.Y.Offset
    minimizado = true
    frame.Size = UDim2.new(0, W, 0, H_HDR)
    subHdr.Visible  = false
    saveBtn.Visible = false
    scroll.Visible  = false
    minBtn.Text = "▲"
end

booting = false
print(">>> TELEPORTE | " .. PLACE_NAME .. " (" .. PLACE_ID .. ") | " .. #slots .. " slots")
