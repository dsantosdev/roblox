-- ============================================
-- MÓDULO: SOUND & EFFECT SUPPRESSOR
-- Remove sons e efeitos de mobs (Cervo, Gato)
-- com interface toggle + persistência local
-- ============================================

local VERSION   = "1.0"
local CATEGORIA = "World"

if not _G.Hub and not _G.HubFila then
    print('>>> sound_suppressor: hub não encontrado, abortando')
    return
end

local Players    = game:GetService("Players")
local RS         = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local TS         = game:GetService("TweenService")
local HS         = game:GetService("HttpService")
local player     = Players.LocalPlayer
local wsConn      = nil
local scratchConn = nil

-- ============================================
-- PERSISTÊNCIA
-- ============================================
local CFG_KEY = "suppressor_cfg.json"
local defaults = {
    cervoSons    = true,
    cervoEfeito  = true,
    gatoSons     = true,
    gatoEfeito   = true,
}
local cfg = {}

local function salvarCfg()
    if writefile then
        local ok, e = pcall(writefile, CFG_KEY, HS:JSONEncode(cfg))
        if not ok then warn("suppressor salvarCfg:", e) end
    end
end

local function carregarCfg()
    if isfile and readfile and isfile(CFG_KEY) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(CFG_KEY)) end)
        if ok and d then
            for k, v in pairs(defaults) do
                cfg[k] = (d[k] ~= nil) and d[k] or v
            end
            return
        end
    end
    for k, v in pairs(defaults) do cfg[k] = v end
end

carregarCfg()

-- ============================================
-- LÓGICA DE SUPRESSÃO
-- ============================================

-- Nomes conhecidos dos mobs no workspace
local CERVO_NAMES = { "Deer", "Stag", "Cervo", "Elk" }
local GATO_NAMES  = { "Cat", "Gato", "Wildcat", "Lynx" }

-- Efeitos de partícula/hit conhecidos
local EFEITO_CLASSES = { "ParticleEmitter", "Trail", "SelectionBox", "Highlight" }

local silenciados  = {}  -- [Sound] = volumeOriginal
local efeitosOff   = {}  -- [obj] = true

local function nomeBate(nome, lista)
    local low = nome:lower()
    for _, n in ipairs(lista) do
        if low:find(n:lower()) then return true end
    end
    return false
end

local function silenciarSons(model)
    for _, s in ipairs(model:GetDescendants()) do
        if s:IsA("Sound") and not silenciados[s] then
            silenciados[s] = s.Volume
            s.Volume = 0
        end
    end
end

local function restaurarSons(model)
    for _, s in ipairs(model:GetDescendants()) do
        if s:IsA("Sound") and silenciados[s] then
            s.Volume = silenciados[s]
            silenciados[s] = nil
        end
    end
end

local function desativarEfeitos(model)
    for _, obj in ipairs(model:GetDescendants()) do
        for _, cls in ipairs(EFEITO_CLASSES) do
            if obj:IsA(cls) and not efeitosOff[obj] then
                efeitosOff[obj] = true
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                    obj.Enabled = false
                elseif obj:IsA("Highlight") or obj:IsA("SelectionBox") then
                    obj.Enabled = false
                end
            end
        end
    end
end

local function restaurarEfeitos(model)
    for _, obj in ipairs(model:GetDescendants()) do
        if efeitosOff[obj] then
            efeitosOff[obj] = nil
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                obj.Enabled = true
            elseif obj:IsA("Highlight") or obj:IsA("SelectionBox") then
                obj.Enabled = true
            end
        end
    end
end

local function aplicarModel(model)
    local nome = model.Name
    local eCervo = nomeBate(nome, CERVO_NAMES)
    local eGato  = nomeBate(nome, GATO_NAMES)
    if not eCervo and not eGato then return end

    if eCervo then
        if cfg.cervoSons   then silenciarSons(model)    end
        if cfg.cervoEfeito then desativarEfeitos(model) end
    end
    if eGato then
        if cfg.gatoSons    then silenciarSons(model)    end
        if cfg.gatoEfeito  then desativarEfeitos(model) end
    end
end

local function varrerWorkspace()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            aplicarModel(obj)
        end
    end
end

local function iniciarSupressao()
    local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

    scratchConn = pg.DescendantAdded:Connect(function(obj)  -- sem "local"
        if obj.Name == "ScratchFrame" and obj:IsA("Frame") then
            obj.Visible = false
            for _, child in ipairs(obj:GetDescendants()) do
                if child:IsA("GuiObject") then
                    child.Visible = false
                end
            end
        end
    end)

    varrerWorkspace()
    wsConn = workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Model") then
            task.wait(0.1)
            aplicarModel(obj)
        end
    end)
end

local function pararSupressao()
    if wsConn then wsConn:Disconnect(); wsConn = nil end
    -- Restaura tudo
    for s, vol in pairs(silenciados) do
        pcall(function() s.Volume = vol end)
    end
    silenciados = {}
    for obj in pairs(efeitosOff) do
        pcall(function()
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                obj.Enabled = true
            elseif obj:IsA("Highlight") or obj:IsA("SelectionBox") then
                obj.Enabled = true
            end
        end)
    end
    efeitosOff = {}
	if scratchConn then scratchConn:Disconnect(); scratchConn = nil end
end

local function reaplicar()
    pararSupressao()
    iniciarSupressao()
end

-- ============================================
-- CORES / FONTES
-- ============================================
local C = {
    bg       = Color3.fromRGB(10, 11, 15),
    header   = Color3.fromRGB(12, 14, 20),
    border   = Color3.fromRGB(28, 32, 48),
    green    = Color3.fromRGB(50, 220, 100),
    greenDim = Color3.fromRGB(15, 55, 25),
    red      = Color3.fromRGB(220, 50, 70),
    redDim   = Color3.fromRGB(55, 12, 18),
    yellow   = Color3.fromRGB(255, 200, 50),
    accent   = Color3.fromRGB(0, 200, 255),
    text     = Color3.fromRGB(210, 218, 235),
    muted    = Color3.fromRGB(72, 82, 108),
    rowBg    = Color3.fromRGB(15, 17, 25),
}
local FB = Enum.Font.GothamBold
local FM = Enum.Font.GothamMedium

local W       = 230
local H_HDR   = 34
local PAD     = 6

-- ============================================
-- GUI
-- ============================================
local pg = player:WaitForChild("PlayerGui")
do local a = pg:FindFirstChild("Suppressor_hud"); if a then a:Destroy() end end

local gui = Instance.new("ScreenGui")
gui.Name = "Suppressor_hud"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true; gui.Parent = pg

local CONTENT_H = 4 * 36 + PAD * 2 + 22 + 4  -- 4 linhas + status
local frame = Instance.new("Frame")
frame.Name = "SuppFrame"
frame.Size = UDim2.new(0, W, 0, H_HDR + CONTENT_H)
frame.Position = UDim2.new(0, 260, 0, 400)
frame.BackgroundColor3 = C.bg; frame.BorderSizePixel = 0; frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", frame).Color = C.border

local topLine = Instance.new("Frame")
topLine.Size = UDim2.new(1, 0, 0, 2); topLine.BackgroundColor3 = C.yellow
topLine.BorderSizePixel = 0; topLine.ZIndex = 6; topLine.Parent = frame
Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 4)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, H_HDR); header.BackgroundColor3 = C.header
header.BorderSizePixel = 0; header.ZIndex = 4; header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 6)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 1, 0); titleLbl.Position = UDim2.new(0, 10, 0, 0)
titleLbl.Text = "[SUPP] SUPRESSOR"; titleLbl.TextColor3 = C.red
titleLbl.Font = FB; titleLbl.TextSize = 12; titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.ZIndex = 5; titleLbl.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 22, 0, 22); minBtn.Position = UDim2.new(1, -48, 0.5, -11)
minBtn.Text = "—"; minBtn.BackgroundColor3 = Color3.fromRGB(22, 25, 35)
minBtn.TextColor3 = C.muted; minBtn.Font = FB; minBtn.TextSize = 11
minBtn.BorderSizePixel = 0; minBtn.ZIndex = 5; minBtn.Parent = header
Instance.new("UIStroke", minBtn).Color = C.border
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22); closeBtn.Position = UDim2.new(1, -22, 0.5, -11)
closeBtn.Text = "✕"; closeBtn.BackgroundColor3 = C.redDim; closeBtn.TextColor3 = C.red
closeBtn.Font = FB; closeBtn.TextSize = 11; closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 5; closeBtn.Parent = header
Instance.new("UIStroke", closeBtn).Color = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

-- Conteúdo
local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 0, CONTENT_H)
content.Position = UDim2.new(0, 0, 0, H_HDR)
content.BackgroundTransparency = 1; content.ZIndex = 3; content.Parent = frame

-- Status
local statusBg = Instance.new("Frame")
statusBg.Size = UDim2.new(1, -PAD*2, 0, 20)
statusBg.Position = UDim2.new(0, PAD, 0, PAD)
statusBg.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
statusBg.BorderSizePixel = 0; statusBg.ZIndex = 4; statusBg.Parent = content
Instance.new("UICorner", statusBg).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", statusBg).Color = C.border

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -10, 1, 0); statusLbl.Position = UDim2.new(0, 6, 0, 0)
statusLbl.Text = "// DESATIVADO"; statusLbl.TextColor3 = C.muted
statusLbl.Font = FM; statusLbl.TextSize = 10; statusLbl.BackgroundTransparency = 1
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.ZIndex = 5; statusLbl.Parent = statusBg

-- ============================================
-- FACTORY: LINHA TOGGLE
-- ============================================
local toggleRows = {}

local function criarToggleRow(icon, label, cfgKey, yPos)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -PAD*2, 0, 32)
    row.Position = UDim2.new(0, PAD, 0, PAD + 22 + 4 + yPos)
    row.BackgroundColor3 = C.rowBg; row.BorderSizePixel = 0
    row.ZIndex = 4; row.Parent = content
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
    Instance.new("UIStroke", row).Color = C.border

    local iconLbl = Instance.new("TextLabel")
    iconLbl.Size = UDim2.new(0, 28, 1, 0); iconLbl.Position = UDim2.new(0, 4, 0, 0)
    iconLbl.Text = icon; iconLbl.TextSize = 14; iconLbl.Font = FB
    iconLbl.BackgroundTransparency = 1; iconLbl.ZIndex = 5; iconLbl.Parent = row
    iconLbl.TextColor3 = C.muted

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, -80, 1, 0); nameLbl.Position = UDim2.new(0, 32, 0, 0)
    nameLbl.Text = label; nameLbl.TextColor3 = C.text
    nameLbl.Font = FM; nameLbl.TextSize = 10; nameLbl.BackgroundTransparency = 1
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.ZIndex = 5; nameLbl.Parent = row

    -- Pill toggle
    local pillBg = Instance.new("Frame")
    pillBg.Size = UDim2.new(0, 40, 0, 18); pillBg.Position = UDim2.new(1, -48, 0.5, -9)
    pillBg.BorderSizePixel = 0; pillBg.ZIndex = 5; pillBg.Parent = row
    pillBg.BackgroundColor3 = C.redDim
    Instance.new("UICorner", pillBg).CornerRadius = UDim.new(0, 9)
    Instance.new("UIStroke", pillBg).Color = Color3.fromRGB(100, 20, 35)

    local pillDot = Instance.new("Frame")
    pillDot.Size = UDim2.new(0, 12, 0, 12); pillDot.Position = UDim2.new(0, 3, 0.5, -6)
    pillDot.BackgroundColor3 = C.red; pillDot.BorderSizePixel = 0
    pillDot.ZIndex = 6; pillDot.Parent = pillBg
    Instance.new("UICorner", pillDot).CornerRadius = UDim.new(0, 6)

    local pillTxt = Instance.new("TextLabel")
    pillTxt.Size = UDim2.new(1, 0, 1, 0); pillTxt.Text = "OFF"
    pillTxt.TextColor3 = C.red; pillTxt.Font = FB; pillTxt.TextSize = 8
    pillTxt.BackgroundTransparency = 1; pillTxt.ZIndex = 7; pillTxt.Parent = pillBg
    pillTxt.TextXAlignment = Enum.TextXAlignment.Right
    pillTxt.Position = UDim2.new(0, 0, 0, 0)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1
    btn.Text = ""; btn.ZIndex = 8; btn.Parent = row

    local ativo = cfg[cfgKey]

    local function atualizar(animado)
        ativo = cfg[cfgKey]
        if ativo then
            if animado then
                TS:Create(pillBg,  TweenInfo.new(0.15), { BackgroundColor3 = C.greenDim }):Play()
                TS:Create(pillDot, TweenInfo.new(0.15), { BackgroundColor3 = C.green, Position = UDim2.new(1, -15, 0.5, -6) }):Play()
            else
                pillBg.BackgroundColor3  = C.greenDim
                pillDot.BackgroundColor3 = C.green
                pillDot.Position = UDim2.new(1, -15, 0.5, -6)
            end
            pillTxt.Text = "ON "; pillTxt.TextColor3 = C.green
            pillTxt.TextXAlignment = Enum.TextXAlignment.Left
            iconLbl.TextColor3 = C.green
            Instance.new("UIStroke", pillBg) -- recria stroke verde
            local s = pillBg:FindFirstChildOfClass("UIStroke")
            if s then s.Color = Color3.fromRGB(20, 100, 35) end
        else
            if animado then
                TS:Create(pillBg,  TweenInfo.new(0.15), { BackgroundColor3 = C.redDim }):Play()
                TS:Create(pillDot, TweenInfo.new(0.15), { BackgroundColor3 = C.red, Position = UDim2.new(0, 3, 0.5, -6) }):Play()
            else
                pillBg.BackgroundColor3  = C.redDim
                pillDot.BackgroundColor3 = C.red
                pillDot.Position = UDim2.new(0, 3, 0.5, -6)
            end
            pillTxt.Text = "OFF"; pillTxt.TextColor3 = C.red
            pillTxt.TextXAlignment = Enum.TextXAlignment.Right
            iconLbl.TextColor3 = C.muted
            local s = pillBg:FindFirstChildOfClass("UIStroke")
            if s then s.Color = Color3.fromRGB(100, 20, 35) end
        end
    end

    atualizar(false)

    btn.MouseButton1Click:Connect(function()
        cfg[cfgKey] = not cfg[cfgKey]
        atualizar(true)
        salvarCfg()
        reaplicar()
    end)

    toggleRows[cfgKey] = { atualizar = atualizar }
    return row
end

-- Cria as 4 linhas
criarToggleRow("[C]", "Sons do Cervo",        "cervoSons",   0 * 36)
criarToggleRow("[C]", "Efeito Ataque Cervo",  "cervoEfeito", 1 * 36)
criarToggleRow("[G]", "Sons do Gato",         "gatoSons",    2 * 36 + 4)
criarToggleRow("[G]", "Efeito Ataque Gato",   "gatoEfeito",  3 * 36 + 4)

-- Separador visual entre cervo/gato
local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, -PAD*2, 0, 1)
sep.Position = UDim2.new(0, PAD, 0, PAD + 22 + 4 + 2 * 36 + 2)
sep.BackgroundColor3 = C.border; sep.BorderSizePixel = 0
sep.ZIndex = 4; sep.Parent = content

-- ============================================
-- ATIVO GLOBAL (hub toggle)
-- ============================================
local moduloAtivo = false

local function ligar()
    moduloAtivo = true
    titleLbl.TextColor3 = C.green
    statusLbl.Text = "// ATIVO"; statusLbl.TextColor3 = C.green
    iniciarSupressao()
end

local function desligar()
    moduloAtivo = false
    titleLbl.TextColor3 = C.red
    statusLbl.Text = "// DESATIVADO"; statusLbl.TextColor3 = C.muted
    pararSupressao()
end

-- ============================================
-- DRAG
-- ============================================
local POS_KEY_SUPP = "suppressor_pos.json"
local function salvarPos()
    if writefile then
        local ok, e = pcall(writefile, POS_KEY_SUPP, HS:JSONEncode({
            x = frame.Position.X.Offset, y = frame.Position.Y.Offset
        }))
        if not ok then warn("suppressor salvarPos:", e) end
    end
end
local function carregarPos()
    if isfile and readfile and isfile(POS_KEY_SUPP) then
        local ok, d = pcall(function() return HS:JSONDecode(readfile(POS_KEY_SUPP)) end)
        if ok and d then frame.Position = UDim2.new(0, d.x, 0, d.y) end
    end
end
carregarPos()

local dragInput, dragStartPos, dragStartMouse
header.InputBegan:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    dragInput = i; dragStartPos = frame.Position; dragStartMouse = i.Position
end)
UIS.InputChanged:Connect(function(i)
    if dragInput and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStartMouse
        frame.Position = UDim2.new(dragStartPos.X.Scale, dragStartPos.X.Offset + d.X,
                                   dragStartPos.Y.Scale, dragStartPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i == dragInput then dragInput = nil; salvarPos() end
end)

-- ============================================
-- MINIMIZAR
-- ============================================
local minimizado = false
local hCache = nil

-- Inicia minimizado
minimizado = true
hCache = H_HDR + CONTENT_H
frame.Size = UDim2.new(0, W, 0, H_HDR)
content.Visible = false
minBtn.Text = "▲"

minBtn.MouseButton1Click:Connect(function()
    minimizado = not minimizado
    salvarPos()
    if minimizado then
        hCache = frame.Size.Y.Offset
        TS:Create(frame, TweenInfo.new(0.18), { Size = UDim2.new(0, W, 0, H_HDR) }):Play()
        content.Visible = false; minBtn.Text = "▲"
    else
        content.Visible = true
        TS:Create(frame, TweenInfo.new(0.18), { Size = UDim2.new(0, W, 0, hCache or H_HDR + CONTENT_H) }):Play()
        minBtn.Text = "—"
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    salvarPos()
    desligar()
    gui.Enabled = false
    if _G.Hub then pcall(function() _G.Hub.desligar("Suppressor") end) end
end)

-- ============================================
-- HUB
-- ============================================
local function onToggle(ativo)
    if gui and gui.Parent then gui.Enabled = ativo end
    if ativo then ligar() else desligar() end
end

if _G.Hub then
    _G.Hub.registrar("Suppressor", onToggle, CATEGORIA, true)
else
    _G.HubFila = _G.HubFila or {}
    table.insert(_G.HubFila, { nome = "Suppressor", toggleFn = onToggle, categoria = CATEGORIA, jaAtivo = true })
end

-- ============================================
-- INIT
-- ============================================
ligar()
print(">>> SUPPRESSOR ATIVO")