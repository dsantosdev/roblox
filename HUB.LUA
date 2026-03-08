-- ============================================
-- HUB CENTRAL — ABAS MULTI-LINHA
-- ============================================

local Players = game:GetService('Players')
local UIS     = game:GetService('UserInputService')
local HS      = game:GetService('HttpService')
local TS      = game:GetService('TweenService')
local player  = Players.LocalPlayer

-- Destroi hub anterior
do
    local pg = player:WaitForChild("PlayerGui")
    local ant = pg:FindFirstChild("HubCentral_hud")
    if ant then ant:Destroy() end
    _G.Hub = nil
    _G.HubFila = nil
end

-- ============================================
-- CONFIG
-- ============================================
local CONFIG_PATH  = "hub_config.json"
local cfgPadrao    = { posX = 10, posY = -320 }

local function salvarCfg(c)
    if writefile then pcall(writefile, CONFIG_PATH, HS:JSONEncode(c)) end
end
local function carregarCfg()
    if isfile and readfile and isfile(CONFIG_PATH) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(CONFIG_PATH)) end)
        if ok and d then return d end
    end
    return cfgPadrao
end
local cfg = carregarCfg()

-- ============================================
-- CONSTANTES
-- ============================================
local W            = 240
local H_HDR        = 34
local H_TAB        = 24
local H_ROW        = 34
local PAD          = 6
local TABS_LINHA   = 4

-- ============================================
-- CORES
-- ============================================
local C = {
    panel     = Color3.fromRGB(15, 17, 23),
    header    = Color3.fromRGB(12, 14, 20),
    border    = Color3.fromRGB(28, 32, 48),
    accent    = Color3.fromRGB(0, 220, 255),
    green     = Color3.fromRGB(50, 255, 100),
    greenDim  = Color3.fromRGB(15, 60, 25),
    red       = Color3.fromRGB(255, 40, 70),
    redDim    = Color3.fromRGB(60, 10, 18),
    text      = Color3.fromRGB(180, 190, 210),
    muted     = Color3.fromRGB(65, 75, 100),
    rowBg     = Color3.fromRGB(18, 20, 28),
    rowActive = Color3.fromRGB(15, 35, 25),
    tabBg     = Color3.fromRGB(10, 12, 18),
    tabActive = Color3.fromRGB(18, 22, 32),
}

-- ============================================
-- ESTADO
-- ============================================
local minimizado = false
local cats       = {}   -- lista de categorias
local catAtiva   = nil

-- Retorna quantas linhas de tab existem dado N categorias
local function numLinhas(n)
    return math.max(1, math.ceil(n / TABS_LINHA))
end

-- Altura total da barra de tabs
local function hTabBar()
    return numLinhas(#cats) * H_TAB
end

-- Altura total do frame para uma categoria
local function hFrame(cat)
    local rows = cat and #cat.modulos or 0
    return H_HDR + hTabBar() + PAD + rows * (H_ROW + 2) + PAD
end

-- ============================================
-- GUI
-- ============================================
local gui = Instance.new("ScreenGui")
gui.Name          = "HubCentral_hud"
gui.ResetOnSpawn  = false
gui.IgnoreGuiInset = true
gui.Parent        = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name            = "HubFrame"
frame.Size            = UDim2.new(0, W, 0, H_HDR)
frame.Position        = UDim2.new(0, cfg.posX or 10, 1, cfg.posY or -320)
frame.BackgroundColor3 = C.panel
frame.BorderSizePixel = 0
frame.ClipsDescendants = false
frame.Parent          = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", frame).Color        = C.border

-- Linha accent topo
local topLine = Instance.new("Frame")
topLine.Size             = UDim2.new(1, 0, 0, 2)
topLine.BackgroundColor3 = C.accent
topLine.BorderSizePixel  = 0
topLine.ZIndex           = 5
topLine.Parent           = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

-- HEADER
local header = Instance.new("Frame")
header.Name             = "Header"
header.Size             = UDim2.new(1, 0, 0, H_HDR)
header.Position         = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = C.header
header.BorderSizePixel  = 0
header.ZIndex           = 3
header.Parent           = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

local dot = Instance.new("Frame")
dot.Size             = UDim2.new(0, 7, 0, 7)
dot.Position         = UDim2.new(0, 12, 0.5, -3)
dot.BackgroundColor3 = C.green
dot.BorderSizePixel  = 0
dot.ZIndex           = 4
dot.Parent           = header
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size               = UDim2.new(1, -80, 1, 0)
titleLbl.Position           = UDim2.new(0, 26, 0, 0)
titleLbl.Text               = "XENOPANEL"
titleLbl.TextColor3         = C.accent
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 12
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 4
titleLbl.Parent             = header

local badge = Instance.new("TextLabel")
badge.Size             = UDim2.new(0, 44, 0, 14)
badge.Position         = UDim2.new(1, -94, 0.5, -7)
badge.Text             = "ONLINE"
badge.TextColor3       = C.green
badge.Font             = Enum.Font.GothamBold
badge.TextSize         = 8
badge.BackgroundColor3 = C.greenDim
badge.BorderSizePixel  = 0
badge.ZIndex           = 4
badge.Parent           = header
Instance.new("UIStroke", badge).Color          = Color3.fromRGB(40, 120, 60)
Instance.new("UICorner", badge).CornerRadius   = UDim.new(0, 2)

local minBtn = Instance.new("TextButton")
minBtn.Size             = UDim2.new(0, 20, 0, 20)
minBtn.Position         = UDim2.new(1, -46, 0.5, -10)
minBtn.Text             = "—"
minBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
minBtn.TextColor3       = C.muted
minBtn.Font             = Enum.Font.GothamBold
minBtn.TextSize         = 11
minBtn.BorderSizePixel  = 0
minBtn.ZIndex           = 4
minBtn.Parent           = header
Instance.new("UIStroke", minBtn).Color        = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 2)

local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0, 20, 0, 20)
closeBtn.Position         = UDim2.new(1, -22, 0.5, -10)
closeBtn.Text             = "✕"
closeBtn.BackgroundColor3 = C.redDim
closeBtn.TextColor3       = C.red
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 10
closeBtn.BorderSizePixel  = 0
closeBtn.ZIndex           = 4
closeBtn.Parent           = header
Instance.new("UIStroke", closeBtn).Color        = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 2)

-- TABBAR (container de linhas de abas)
local tabBar = Instance.new("Frame")
tabBar.Name             = "TabBar"
tabBar.Size             = UDim2.new(1, 0, 0, H_TAB)  -- atualizado dinamicamente
tabBar.Position         = UDim2.new(0, 0, 0, H_HDR)
tabBar.BackgroundColor3 = C.tabBg
tabBar.BorderSizePixel  = 0
tabBar.ZIndex           = 2
tabBar.Visible          = false
tabBar.Parent           = frame

-- ============================================
-- DOT PULSE
-- ============================================
task.spawn(function()
    while gui and gui.Parent do
        TS:Create(dot, TweenInfo.new(0.8, Enum.EasingStyle.Sine), {
            BackgroundTransparency = 0.7,
            Size     = UDim2.new(0, 5, 0, 5),
            Position = UDim2.new(0, 13, 0.5, -2),
        }):Play()
        task.wait(0.8)
        TS:Create(dot, TweenInfo.new(0.8, Enum.EasingStyle.Sine), {
            BackgroundTransparency = 0,
            Size     = UDim2.new(0, 7, 0, 7),
            Position = UDim2.new(0, 12, 0.5, -3),
        }):Play()
        task.wait(0.8)
    end
end)

-- ============================================
-- ATUALIZAR LAYOUT (chame após qualquer mudança estrutural)
-- ============================================
local function atualizarLayout()
    local nLinhas = numLinhas(#cats)
    local tabH    = nLinhas * H_TAB
    local tabW    = math.floor(W / TABS_LINHA)

    -- 1. Redimensiona tabBar
    tabBar.Size = UDim2.new(1, 0, 0, tabH)

    -- 2. Garante que existam frames de linha suficientes, remove extras
    for i = 1, nLinhas do
        local nomeLinha = "TabLine_" .. i
        local linha = tabBar:FindFirstChild(nomeLinha)
        if not linha then
            linha = Instance.new("Frame")
            linha.Name             = nomeLinha
            linha.Size             = UDim2.new(1, 0, 0, H_TAB)
            linha.Position         = UDim2.new(0, 0, 0, (i - 1) * H_TAB)
            linha.BackgroundColor3 = C.tabBg
            linha.BorderSizePixel  = 0
            linha.ZIndex           = 3
            linha.Parent           = tabBar
            -- separador
            local sep = Instance.new("Frame")
            sep.Size             = UDim2.new(1, 0, 0, 1)
            sep.Position         = UDim2.new(0, 0, 1, -1)
            sep.BackgroundColor3 = C.border
            sep.BorderSizePixel  = 0
            sep.ZIndex           = 4
            sep.Parent           = linha
        end
    end

    -- 3. Distribui cada tabBtn na linha/coluna correta
    for i, cat in ipairs(cats) do
        local linhaIdx = math.ceil(i / TABS_LINHA)
        local coluna   = (i - 1) % TABS_LINHA
        local linhaFrame = tabBar:FindFirstChild("TabLine_" .. linhaIdx)

        -- largura: última da linha (ou última geral) pega o restante
        local isUltima = (coluna == TABS_LINHA - 1) or (i == #cats)
        local w = isUltima and (W - tabW * coluna) or tabW

        cat.tabBtn.Parent   = linhaFrame
        cat.tabBtn.Position = UDim2.new(0, coluna * tabW, 0, 0)
        cat.tabBtn.Size     = UDim2.new(0, w, 1, 0)
    end

    -- 4. Reposiciona todos os containers de módulos abaixo da tabBar
    local containerY = H_HDR + tabH
    for _, cat in ipairs(cats) do
        cat.container.Position = UDim2.new(0, 0, 0, containerY)
    end

    -- 5. Redimensiona frame para a aba ativa
    if not minimizado and catAtiva then
        local h = hFrame(catAtiva)
        frame.Size = UDim2.new(0, W, 0, h)
    end
end

-- ============================================
-- CRIAR ROW
-- ============================================
local function criarRow(modulo, container, index)
    local posY = PAD + (index - 1) * (H_ROW + 2)

    local row = Instance.new("Frame")
    row.Name             = "Row_" .. modulo.nome
    row.Size             = UDim2.new(1, -12, 0, H_ROW)
    row.Position         = UDim2.new(0, 6, 0, posY)
    row.BackgroundColor3 = C.rowBg
    row.BorderSizePixel  = 0
    row.ZIndex           = 4
    row.Parent           = container
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)

    local leftBar = Instance.new("Frame")
    leftBar.Name             = "LeftBar"
    leftBar.Size             = UDim2.new(0, 2, 1, -6)
    leftBar.Position         = UDim2.new(0, 0, 0, 3)
    leftBar.BackgroundColor3 = C.border
    leftBar.BorderSizePixel  = 0
    leftBar.ZIndex           = 5
    leftBar.Parent           = row
    Instance.new("UICorner", leftBar).CornerRadius = UDim.new(0, 2)

    local nomeLbl = Instance.new("TextLabel")
    nomeLbl.Name               = "NomeLabel"
    nomeLbl.Size               = UDim2.new(1, -60, 1, 0)
    nomeLbl.Position           = UDim2.new(0, 12, 0, 0)
    nomeLbl.Text               = modulo.nome
    nomeLbl.TextColor3         = C.text
    nomeLbl.Font               = Enum.Font.GothamBold
    nomeLbl.TextSize           = 11
    nomeLbl.BackgroundTransparency = 1
    nomeLbl.TextXAlignment     = Enum.TextXAlignment.Left
    nomeLbl.ZIndex             = 5
    nomeLbl.Parent             = row

    local track = Instance.new("Frame")
    track.Name             = "Track"
    track.Size             = UDim2.new(0, 34, 0, 16)
    track.Position         = UDim2.new(1, -44, 0.5, -8)
    track.BackgroundColor3 = Color3.fromRGB(25, 28, 40)
    track.BorderSizePixel  = 0
    track.ZIndex           = 5
    track.Parent           = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
    local trackStroke = Instance.new("UIStroke", track)
    trackStroke.Color     = C.border
    trackStroke.Thickness = 1

    local knob = Instance.new("Frame")
    knob.Name             = "Knob"
    knob.Size             = UDim2.new(0, 12, 0, 12)
    knob.Position         = UDim2.new(0, 2, 0.5, -6)
    knob.BackgroundColor3 = C.muted
    knob.BorderSizePixel  = 0
    knob.ZIndex           = 6
    knob.Parent           = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local btn = Instance.new("TextButton")
    btn.Size               = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text               = ""
    btn.ZIndex             = 7
    btn.Parent             = row

    btn.MouseButton1Click:Connect(function()
        modulo.ativo = not modulo.ativo

        if modulo.ativo then
            TS:Create(knob,    TweenInfo.new(0.15), { Position = UDim2.new(1, -14, 0.5, -6), BackgroundColor3 = C.green }):Play()
            TS:Create(track,   TweenInfo.new(0.15), { BackgroundColor3 = C.greenDim }):Play()
            TS:Create(leftBar, TweenInfo.new(0.15), { BackgroundColor3 = C.green }):Play()
            TS:Create(row,     TweenInfo.new(0.15), { BackgroundColor3 = C.rowActive }):Play()
            TS:Create(nomeLbl, TweenInfo.new(0.15), { TextColor3 = C.green }):Play()
            trackStroke.Color = Color3.fromRGB(30, 100, 50)
        else
            TS:Create(knob,    TweenInfo.new(0.15), { Position = UDim2.new(0, 2, 0.5, -6), BackgroundColor3 = C.muted }):Play()
            TS:Create(track,   TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(25, 28, 40) }):Play()
            TS:Create(leftBar, TweenInfo.new(0.15), { BackgroundColor3 = C.border }):Play()
            TS:Create(row,     TweenInfo.new(0.15), { BackgroundColor3 = C.rowBg }):Play()
            TS:Create(nomeLbl, TweenInfo.new(0.15), { TextColor3 = C.text }):Play()
            trackStroke.Color = C.border
        end

        pcall(modulo.toggleFn, modulo.ativo)
    end)

    return row
end

-- ============================================
-- ATIVAR ABA
-- ============================================
local function ativarAba(cat)
    for _, c in ipairs(cats) do
        c.container.Visible = false
        c.tabBtn.BackgroundColor3 = C.tabBg
        c.tabBtn.TextColor3 = C.muted
        local ind = c.tabBtn:FindFirstChild("Ind")
        if ind then ind.Visible = false end
    end

    cat.container.Visible     = true
    cat.tabBtn.BackgroundColor3 = C.tabActive
    cat.tabBtn.TextColor3       = C.accent
    catAtiva = cat

    -- Indicador accent
    local ind = cat.tabBtn:FindFirstChild("Ind")
    if not ind then
        ind = Instance.new("Frame")
        ind.Name             = "Ind"
        ind.Size             = UDim2.new(1, 0, 0, 2)
        ind.Position         = UDim2.new(0, 0, 1, -2)
        ind.BackgroundColor3 = C.accent
        ind.BorderSizePixel  = 0
        ind.ZIndex           = 6
        ind.Parent           = cat.tabBtn
    end
    ind.Visible = true

    if not minimizado then
        frame.Size = UDim2.new(0, W, 0, hFrame(cat))
    end
end

-- ============================================
-- REGISTRAR MÓDULO
-- ============================================
local function registrar(nome, toggleFn, categoria, jaAtivo)
    categoria = categoria or "Geral"

    -- Evita duplicata
    for _, c in ipairs(cats) do
        for _, m in ipairs(c.modulos) do
            if m.nome == nome then return end
        end
    end

    -- Obtém ou cria categoria
    local cat
    for _, c in ipairs(cats) do
        if c.nome == categoria then cat = c; break end
    end

    if not cat then
        -- Cria tabBtn e container
        local tabBtn = Instance.new("TextButton")
        tabBtn.Name             = "Tab_" .. categoria
        tabBtn.Text             = categoria:upper()
        tabBtn.BackgroundColor3 = C.tabBg
        tabBtn.TextColor3       = C.muted
        tabBtn.Font             = Enum.Font.GothamBold
        tabBtn.TextSize         = 9
        tabBtn.BorderSizePixel  = 0
        tabBtn.ZIndex           = 4
        tabBtn.Size             = UDim2.new(0, W, 1, 0)
        tabBtn.Position         = UDim2.new(0, 0, 0, 0)
        tabBtn.Parent           = tabBar

        local container = Instance.new("Frame")
        container.Name               = "Cont_" .. categoria
        container.BackgroundTransparency = 1
        container.ZIndex             = 2
        container.Visible            = false
        container.Parent             = frame
        container.Size     = UDim2.new(1, 0, 1, 0)
        container.Position = UDim2.new(0, 0, 0, H_HDR + H_TAB)

        cat = { nome = categoria, tabBtn = tabBtn, container = container, modulos = {}, rows = {} }
        table.insert(cats, cat)

        tabBtn.MouseButton1Click:Connect(function() ativarAba(cat) end)

        tabBar.Visible = true
        atualizarLayout()
    end

    -- Adiciona módulo — começa ativo se jaAtivo=true
    local modulo = { nome = nome, toggleFn = toggleFn, ativo = jaAtivo == true }
    table.insert(cat.modulos, modulo)
    local row = criarRow(modulo, cat.container, #cat.modulos)
    table.insert(cat.rows, row)

    -- Se já ativo, atualiza visual do toggle para ON
    if modulo.ativo then
        local lb    = row:FindFirstChild("LeftBar")
        local tr    = row:FindFirstChild("Track")
        local kn    = tr and tr:FindFirstChild("Knob")
        local nl    = row:FindFirstChild("NomeLabel")
        local ts    = tr and tr:FindFirstChildOfClass("UIStroke")
        if lb then lb.BackgroundColor3 = C.green end
        if tr then tr.BackgroundColor3 = C.greenDim end
        if kn then kn.Position = UDim2.new(1,-14,0.5,-6); kn.BackgroundColor3 = C.green end
        if nl then nl.TextColor3 = C.green end
        if ts then ts.Color = Color3.fromRGB(30,100,50) end
        row.BackgroundColor3 = C.rowActive
    end

    -- Primeira aba ou aba ativa crescendo
    if not catAtiva then
        ativarAba(cat)
    elseif catAtiva == cat and not minimizado then
        frame.Size = UDim2.new(0, W, 0, hFrame(cat))
    end
end

-- ============================================
-- DESLIGAR (Diamond auto-off)
-- ============================================
local function desligar(nome)
    for _, cat in ipairs(cats) do
        for i, m in ipairs(cat.modulos) do
            if m.nome == nome and m.ativo then
                m.ativo = false
                local row = cat.rows[i]
                if not row then return end
                local lb = row:FindFirstChild("LeftBar")
                local tr = row:FindFirstChild("Track")
                local kn = tr and tr:FindFirstChild("Knob")
                local nl = row:FindFirstChild("NomeLabel")
                TS:Create(row, TweenInfo.new(0.15), { BackgroundColor3 = C.rowBg }):Play()
                if lb then TS:Create(lb, TweenInfo.new(0.15), { BackgroundColor3 = C.border }):Play() end
                if nl then TS:Create(nl, TweenInfo.new(0.15), { TextColor3 = C.text }):Play() end
                if tr then TS:Create(tr, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(25, 28, 40) }):Play() end
                if kn then TS:Create(kn, TweenInfo.new(0.15), { Position = UDim2.new(0, 2, 0.5, -6), BackgroundColor3 = C.muted }):Play() end
                return
            end
        end
    end
end

-- ============================================
-- MINIMIZAR
-- ============================================
local function toggleMinimizar()
    minimizado = not minimizado
    if minimizado then
        TS:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, H_HDR)
        }):Play()
        tabBar.Visible = false
        if catAtiva then catAtiva.container.Visible = false end
        minBtn.Text = "▲"
    else
        tabBar.Visible = true
        if catAtiva then catAtiva.container.Visible = true end
        TS:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            Size = UDim2.new(0, W, 0, catAtiva and hFrame(catAtiva) or H_HDR)
        }):Play()
        minBtn.Text = "—"
    end
end

-- ============================================
-- DRAG
-- ============================================
local dragging, dragStart, startPos

header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = i.Position; startPos = frame.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                   startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        if dragging then
            cfg.posX = frame.Position.X.Offset
            cfg.posY = frame.Position.Y.Offset
            salvarCfg(cfg)
        end
        dragging = false
    end
end)

-- ============================================
-- EVENTOS
-- ============================================
minBtn.MouseButton1Click:Connect(toggleMinimizar)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- ============================================
-- API GLOBAL
-- ============================================
_G.Hub = {
    registrar = registrar,
    desligar  = desligar,
    getEstado = function(nome)
        for _, cat in ipairs(cats) do
            for _, m in ipairs(cat.modulos) do
                if m.nome == nome then return m.ativo end
            end
        end
        return false
    end,
}

-- Processa fila de módulos registrados antes do hub
if _G.HubFila then
    for _, item in ipairs(_G.HubFila) do
        registrar(item.nome, item.toggleFn, item.categoria, item.jaAtivo)
    end
    _G.HubFila = nil
end

print(">>> HUB ATIVO")
