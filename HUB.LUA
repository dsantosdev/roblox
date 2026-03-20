-- ============================================
-- HUB CENTRAL Ã¢â‚¬â€ ABAS MULTI-LINHA
-- ============================================

local VERSION   = "1.0.5"
local Players = game:GetService('Players')
local UIS     = game:GetService('UserInputService')
local HS      = game:GetService('HttpService')
local TS      = game:GetService('TweenService')
local player  = Players.LocalPlayer

local function cleanupReloadModuleStates()
    local toCleanup = {}
    for key, value in pairs(_G) do
        if type(key) == "string"
            and key ~= "Hub"
            and type(value) == "table"
            and type(value.cleanup) == "function" then
            table.insert(toCleanup, { key = key, cleanup = value.cleanup })
        end
    end
    for _, entry in ipairs(toCleanup) do
        pcall(entry.cleanup)
    end
end

-- Destroi hub anterior
do
    local oldHub = _G.Hub
    if type(oldHub) == "table" and type(oldHub.cleanup) == "function" then
        pcall(oldHub.cleanup, "hub_reload")
    end
    cleanupReloadModuleStates()

    local pg = player:WaitForChild("PlayerGui")
    local ant = pg:FindFirstChild("HubCentral_hud")
    if ant then ant:Destroy() end
    _G.Hub = nil
    _G.HubFila = nil
end

-- ============================================
-- ICON + MOBILE PATCH GLOBAL
-- Troca simbolos quebrados por icones de imagem
-- e aplica escala proporcional no celular.
-- ============================================
do
    local ICON_PATCH_STATE_KEY = "__kah_hub_icon_patch_state"
    local oldPatch = _G[ICON_PATCH_STATE_KEY]
    if type(oldPatch) == "table" and type(oldPatch.cleanup) == "function" then
        pcall(oldPatch.cleanup)
    end
    _G[ICON_PATCH_STATE_KEY] = nil

    local patchConns = {}
    local function bindConn(conn)
        if conn then
            table.insert(patchConns, conn)
        end
        return conn
    end

    local ICONS = {
        close = "rbxassetid://6031094678",
        min   = "rbxassetid://6035067836",
        up    = "rbxassetid://6031090990",
        edit  = "rbxassetid://6031280882",
    }

    local TEXT_TO_KIND = {
        ["X"] = "close", ["x"] = "close",
        ["-"] = "min",
        ["^"] = "up",
        ["E"] = "edit", ["e"] = "edit",
    }

    local function iconSize(kind)
        if kind == "up" then return UDim2.new(0, 10, 0, 10) end
        return UDim2.new(0, 12, 0, 12)
    end

    local function applyIcon(btn)
        if not btn or not btn:IsA("TextButton") then return end
        local txt = tostring(btn.Text or ""):gsub("%s+", "")
        local kind = TEXT_TO_KIND[txt]
        local icon = btn:FindFirstChild("__KAHIcon")

        if not kind then
            if icon then icon.Visible = false end
            if btn:GetAttribute("__KAHIconApplied") then
                btn.TextTransparency = 0
                btn:SetAttribute("__KAHIconApplied", false)
            end
            return
        end

        if not icon then
            icon = Instance.new("ImageLabel")
            icon.Name = "__KAHIcon"
            icon.BackgroundTransparency = 1
            icon.AnchorPoint = Vector2.new(0.5, 0.5)
            icon.Position = UDim2.new(0.5, 0, 0.5, 0)
            icon.ZIndex = btn.ZIndex + 1
            icon.Parent = btn
        end

        icon.Image = ICONS[kind]
        icon.ImageColor3 = btn.TextColor3
        icon.Size = iconSize(kind)
        icon.Visible = true
        btn.TextTransparency = 1
        btn:SetAttribute("__KAHIconApplied", true)
    end

    local function watchButton(btn)
        if not btn or not btn:IsA("TextButton") then return end
        if btn:GetAttribute("__KAHIconWatch") then
            applyIcon(btn)
            return
        end
        btn:SetAttribute("__KAHIconWatch", true)
        bindConn(btn:GetPropertyChangedSignal("Text"):Connect(function()
            applyIcon(btn)
        end))
        bindConn(btn:GetPropertyChangedSignal("TextColor3"):Connect(function()
            local icon = btn:FindFirstChild("__KAHIcon")
            if icon then icon.ImageColor3 = btn.TextColor3 end
        end))
        applyIcon(btn)
    end

    local function isHudGui(gui)
        if not gui or not gui:IsA("ScreenGui") then return false end
        return gui.Name:sub(-4) == "_hud"
    end

    local function getMobileScale()
        if not UIS.TouchEnabled then
            return 1
        end
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
        local shortest = math.min(vp.X, vp.Y)
        return math.clamp(shortest / 500, 0.72, 1)
    end

    local function applyMobileScale(gui)
        if not isHudGui(gui) then return end
        local s = gui:FindFirstChild("__KAHMobileScale")
        if not s then
            s = Instance.new("UIScale")
            s.Name = "__KAHMobileScale"
            s.Parent = gui
        end
        s.Scale = getMobileScale()
    end

    local function refreshMobileScale(pg)
        for _, g in ipairs(pg:GetChildren()) do
            if g:IsA("ScreenGui") then
                applyMobileScale(g)
            end
        end
    end

    local function scan(root)
        if not root then return end
        if root:IsA("TextButton") then watchButton(root) end
        if root:IsA("ScreenGui") then applyMobileScale(root) end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("TextButton") then
                watchButton(d)
            elseif d:IsA("ScreenGui") then
                applyMobileScale(d)
            end
        end
    end

    local pg = player:WaitForChild("PlayerGui")
    scan(pg)
    refreshMobileScale(pg)
    bindConn(pg.DescendantAdded:Connect(function(d)
        if d:IsA("TextButton") then
            watchButton(d)
        elseif d:IsA("ScreenGui") then
            applyMobileScale(d)
        end
    end))

    local vpConn
    local function hookCamera()
        if vpConn then
            vpConn:Disconnect()
            vpConn = nil
        end
        local cam = workspace.CurrentCamera
        if not cam then return end
        vpConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            refreshMobileScale(pg)
        end)
        bindConn(vpConn)
    end

    hookCamera()
    bindConn(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        hookCamera()
        refreshMobileScale(pg)
    end))

    _G.KAH_RescanIcons = function()
        scan(pg)
        refreshMobileScale(pg)
    end

    _G[ICON_PATCH_STATE_KEY] = {
        cleanup = function()
            if vpConn then
                pcall(function() vpConn:Disconnect() end)
                vpConn = nil
            end
            for i = #patchConns, 1, -1 do
                local conn = patchConns[i]
                pcall(function() conn:Disconnect() end)
                patchConns[i] = nil
            end
            if _G.KAH_RescanIcons then
                _G.KAH_RescanIcons = nil
            end
            _G[ICON_PATCH_STATE_KEY] = nil
        end
    }
end

-- ============================================
-- CONFIG
-- ============================================
local CONFIG_PATH  = "hub_config.json"
local cfgPadrao    = { posX = 10, posY = -320, extraH = 0 }

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

local UI_DEFAULTS_PATH = "kah_ui_defaults.json"
local function carregarUiDefaults()
    if isfile and readfile and isfile(UI_DEFAULTS_PATH) then
        local ok, data = pcall(function()
            return HS:JSONDecode(readfile(UI_DEFAULTS_PATH))
        end)
        if ok and type(data) == "table" then
            return data
        end
    end
    return { minimizedWidth = 260, language = "pt-BR" }
end
local uiDefaults = carregarUiDefaults()
local function salvarUiDefaults()
    if not writefile then return end
    pcall(writefile, UI_DEFAULTS_PATH, HS:JSONEncode(uiDefaults))
end
local function getMinimizedWidthDefault()
    local v = math.floor(tonumber(uiDefaults.minimizedWidth) or 260)
    return math.clamp(v, 240, 480)
end
local function setMinimizedWidthDefault(v)
    uiDefaults.minimizedWidth = math.clamp(math.floor(tonumber(v) or 260), 240, 480)
    salvarUiDefaults()
end
local function normalizeLang(lang)
    local l = string.lower(tostring(lang or "pt-BR"))
    if l == "en" then return "en" end
    if l == "es" then return "es" end
    return "pt-BR"
end
local function getLanguageDefault()
    return normalizeLang(uiDefaults.language)
end
local function setLanguageDefault(lang)
    uiDefaults.language = normalizeLang(lang)
    salvarUiDefaults()
end
_G.KAHUiDefaults = {
    getMinWidth = getMinimizedWidthDefault,
    setMinWidth = setMinimizedWidthDefault,
    getLanguage = getLanguageDefault,
    setLanguage = setLanguageDefault,
}

-- Persistencia global do estado das janelas dos modulos.
-- Estados validos: "maximizado" | "minimizado" | "fechado"
local WIN_STATE_PATH = "kah_window_state.json"
local function carregarEstadoJanelas()
    if isfile and readfile and isfile(WIN_STATE_PATH) then
        local ok, data = pcall(function()
            return HS:JSONDecode(readfile(WIN_STATE_PATH))
        end)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}
end

local _winStates = carregarEstadoJanelas()

local function salvarEstadoJanelas()
    if not writefile then return end
    pcall(writefile, WIN_STATE_PATH, HS:JSONEncode(_winStates))
end

_G.KAHWindowState = {
    get = function(modName, defaultState)
        local v = _winStates[modName]
        if v == "maximizado" or v == "minimizado" or v == "fechado" then
            return v
        end
        return defaultState
    end,
    set = function(modName, state)
        if state ~= "maximizado" and state ~= "minimizado" and state ~= "fechado" then
            return
        end
        _winStates[modName] = state
        salvarEstadoJanelas()
    end,
}

-- Funcao para calcular posicao segura dentro da tela
-- Converte de qualquer sistema (scale+offset) para offset puro
local function posSegura(px, py, scaleX, scaleY, fw, fh)
    -- Converte para offset absoluto considerando o scale
    local vp = workspace.CurrentCamera.ViewportSize
    local ax  = scaleX * vp.X + px
    local ay  = scaleY * vp.Y + py
    -- Clamp para dentro da tela com margem
    ax = math.clamp(ax, 4, vp.X - fw - 4)
    ay = math.clamp(ay, 4, vp.Y - fh - 4)
    return ax, ay
end

-- ============================================
-- CONSTANTES
-- ============================================
local BASE_W       = 260
local MIN_W        = 240
local MAX_W        = 480
local W            = math.clamp(tonumber(cfg.width) or BASE_W, MIN_W, MAX_W)
local MIN_EXTRA_H  = 0
local MAX_EXTRA_H  = 420
local EXTRA_H      = math.clamp(tonumber(cfg.extraH) or 0, MIN_EXTRA_H, MAX_EXTRA_H)
local H_HDR        = 38
local H_TAB        = 26
local H_SUBTAB     = 24
local H_ROW        = 38
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
local rowStatusUpdaters = {}
local activeInlineDropdownClose = nil
local refreshCatSubtabs = function() end
local currentLanguage = getLanguageDefault()
local adminPreferredTab = true

local LANG_ORDER = { "pt-BR", "en", "es" }
local CATEGORY_I18N = {
    Admin = { ["pt-BR"] = "Admin", en = "Admin", es = "Admin" },
    Utility = { ["pt-BR"] = "Utilidade", en = "Utility", es = "Utilidad" },
    World = { ["pt-BR"] = "Mundo", en = "World", es = "Mundo" },
    Player = { ["pt-BR"] = "Jogador", en = "Player", es = "Jugador" },
    Combat = { ["pt-BR"] = "Combate", en = "Combat", es = "Combate" },
    Farm = { ["pt-BR"] = "Farm", en = "Farm", es = "Farm" },
    Settings = { ["pt-BR"] = "Settings", en = "Settings", es = "Settings" },
}

local MODULE_I18N = {
    ["Teleporte"] = { ["pt-BR"] = "Teleporte", en = "Teleport", es = "Teleporte" },
    ["Pet Chats"] = { ["pt-BR"] = "Pet Chats", en = "Pet Chats", es = "Chats de Mascotas" },
    ["Player Actions"] = { ["pt-BR"] = "Acoes de Jogador", en = "Player Actions", es = "Acciones de Jugador" },
    ["Game Settings"] = { ["pt-BR"] = "Config. do Jogo", en = "Game Settings", es = "Ajustes del Juego" },
    ["Sound Mixer"] = { ["pt-BR"] = "Config. do Jogo", en = "Game Settings", es = "Ajustes del Juego" },
    ["Sound"] = { ["pt-BR"] = "Sound", en = "Sound", es = "Sound" },
    ["FX"] = { ["pt-BR"] = "FX", en = "FX", es = "FX" },
    ["Ping"] = { ["pt-BR"] = "Ping", en = "Ping", es = "Ping" },
    ["Stronghold"] = { ["pt-BR"] = "Fortaleza Auto", en = "Stronghold Auto", es = "Fortaleza Auto" },
    ["Diamond"] = { ["pt-BR"] = "Diamond Farm", en = "Diamond Farm", es = "Diamond Farm" },
    ["Night Skip"] = { ["pt-BR"] = "Pular Noite", en = "Skip Night", es = "Saltar Noche" },
    ["Skip Night"] = { ["pt-BR"] = "Pular Noite", en = "Skip Night", es = "Saltar Noche" },
    ["Mob Killer"] = { ["pt-BR"] = "Mob Killer", en = "Mob Killer", es = "Mob Killer" },
    ["Chest Farm"] = { ["pt-BR"] = "Chest Farm", en = "Chest Farm", es = "Chest Farm" },
    ["Language"] = { ["pt-BR"] = "Idioma", en = "Language", es = "Idioma" },
    ["God Mode"] = { ["pt-BR"] = "God Mode", en = "God Mode", es = "God Mode" },
    ["Instant Prompt"] = { ["pt-BR"] = "Instant Prompt", en = "Instant Prompt", es = "Instant Prompt" },
    ["No Damage Blink"] = { ["pt-BR"] = "No Damage Blink", en = "No Damage Blink", es = "No Damage Blink" },
}

local function translateCategory(raw)
    if raw == "Developer" then return "Developer" end
    local t = CATEGORY_I18N[raw]
    return (t and (t[currentLanguage] or t["pt-BR"])) or raw
end

local function translateModule(raw)
    if raw == "Developer" then return "Developer" end
    local t = MODULE_I18N[raw]
    return (t and (t[currentLanguage] or t["pt-BR"])) or raw
end

local CATEGORY_ORDER = {
    Admin = 1,
    Utility = 2,
    World = 3,
    Player = 4,
    Combat = 5,
    Farm = 6,
    Developer = 98,
    Settings = 99,
}

local function categoryRank(raw)
    return CATEGORY_ORDER[raw] or 50
end

local function sortCategories()
    table.sort(cats, function(a, b)
        local ra = categoryRank(a.nomeRaw)
        local rb = categoryRank(b.nomeRaw)
        if ra ~= rb then
            return ra < rb
        end
        return tostring(a.nomeRaw or "") < tostring(b.nomeRaw or "")
    end)
end

local function getDefaultCategory()
    for _, cat in ipairs(cats) do
        if cat.nomeRaw == "Farm" then
            return cat
        end
    end
    return cats[1]
end

local function cycleLanguage()
    local idx = 1
    for i = 1, #LANG_ORDER do
        if LANG_ORDER[i] == currentLanguage then
            idx = i
            break
        end
    end
    idx = idx + 1
    if idx > #LANG_ORDER then idx = 1 end
    currentLanguage = LANG_ORDER[idx]
    setLanguageDefault(currentLanguage)
end

-- Retorna quantas linhas de tab existem dado N categorias
local function numLinhas(n)
    return math.max(1, math.ceil(n / TABS_LINHA))
end

-- Altura total da barra de tabs
local function hTabBar()
    return numLinhas(#cats) * H_TAB
end

local function getModuleSubtabName(modulo)
    local opts = modulo and modulo.opts or nil
    local raw = opts and opts.subtab or nil
    local name = tostring(raw or ""):match("^%s*(.-)%s*$")
    if name == "" then
        return "Main"
    end
    return name
end

local function isModulePinnedAboveSubtabs(modulo)
    local opts = modulo and modulo.opts or nil
    return opts and opts.pinAboveSubtabs == true
end

local function collectCatSubtabNames(cat)
    local names, seen = {}, {}
    if not cat then
        return names
    end
    for _, modulo in ipairs(cat.modulos or {}) do
        if not isModulePinnedAboveSubtabs(modulo) then
            local name = getModuleSubtabName(modulo)
            if not seen[name] then
                seen[name] = true
                table.insert(names, name)
            end
        end
    end
    if #names == 0 then
        table.insert(names, "Main")
    end
    return names
end

local function orderCategorySubtabs(cat, names)
    local ordered = {}
    for i, name in ipairs(names or {}) do
        ordered[i] = name
    end

    if cat and cat.nomeRaw == "Admin" then
        local rank = {
            Spells = 1,
            Impero = 2,
            Access = 3,
            Fun = 4,
            Main = 99,
        }
        table.sort(ordered, function(a, b)
            local ra = rank[a] or 50
            local rb = rank[b] or 50
            if ra ~= rb then
                return ra < rb
            end
            return tostring(a) < tostring(b)
        end)
    end

    return ordered
end

local function catHasMultipleSubtabs(cat)
    return cat and cat.subtabOrder and #cat.subtabOrder > 1
end

local function getCatPinnedRowCount(cat)
    if not cat then
        return 0
    end
    local count = 0
    for _, modulo in ipairs(cat.modulos or {}) do
        if isModulePinnedAboveSubtabs(modulo) then
            count += 1
        end
    end
    return count
end

local function getCatVisibleRowCount(cat)
    if not cat then
        return 0
    end
    if not catHasMultipleSubtabs(cat) then
        return #cat.modulos
    end
    local active = cat.activeSubtab or (cat.subtabOrder and cat.subtabOrder[1]) or "Main"
    local count = 0
    for _, modulo in ipairs(cat.modulos or {}) do
        if isModulePinnedAboveSubtabs(modulo) or getModuleSubtabName(modulo) == active then
            count += 1
        end
    end
    return count
end

-- Altura total do frame para uma categoria
local function hFrame(cat)
    local rows = getCatVisibleRowCount(cat)
    local subtabH = catHasMultipleSubtabs(cat) and (H_SUBTAB + PAD) or 0
    return H_HDR + hTabBar() + PAD + subtabH + rows * (H_ROW + 2) + PAD
end
local function hFrameExpandido(cat)
    if not cat then return H_HDR end
    return hFrame(cat) + EXTRA_H
end

-- ============================================
-- GUI
-- ============================================
local gui = Instance.new("ScreenGui")
gui.Name          = "HubCentral_hud"
gui.ResetOnSpawn  = false
gui.IgnoreGuiInset = true
gui.DisplayOrder  = 2000
gui.Parent        = player:WaitForChild("PlayerGui")

-- Converte posicao salva para offset absoluto e clamp na tela
-- O cfg antigo salvava (posX, posY) com scale Y=1, novo salva scale=0
local _hubSX = cfg.scaleX or 0
local _hubSY = cfg.scaleY or (cfg.posY and cfg.posY < 0 and 1 or 0)
local _hubPX = cfg.posX or 10
local _hubPY = cfg.posY or -320

local frame = Instance.new("Frame")
frame.Name            = "HubFrame"
frame.Size            = UDim2.new(0, W, 0, H_HDR)
frame.Position        = UDim2.new(_hubSX, _hubPX, _hubSY, _hubPY)  -- posicao inicial (corrigida no defer)
frame.BackgroundColor3 = C.panel
frame.BorderSizePixel = 0
frame.ClipsDescendants = false
frame.Parent          = gui

local hubScale = Instance.new("UIScale")
hubScale.Name = "__HubResizeScale"
hubScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.9, 1.35)
hubScale.Parent = frame

task.defer(function()
    -- Roda depois do primeiro frame para ViewportSize estar disponivel
    local ax, ay = posSegura(_hubPX, _hubPY, _hubSX, _hubSY, W, H_HDR)
    frame.Position = UDim2.new(0, ax, 0, ay)
    -- Salva no novo formato (offset puro, scale=0)
    cfg.posX   = ax; cfg.posY = ay
    cfg.scaleX = 0;  cfg.scaleY = 0
    cfg.width  = W
    cfg.extraH = EXTRA_H
    salvarCfg(cfg)
end)
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
dot.Size             = UDim2.new(0, 3, 0, 14)
dot.Position         = UDim2.new(0, 12, 0.5, -7)
dot.BackgroundColor3 = C.accent
dot.BorderSizePixel  = 0
dot.ZIndex           = 4
dot.Parent           = header
Instance.new("UICorner", dot).CornerRadius = UDim.new(0, 2)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size               = UDim2.new(1, -72, 1, 0)
titleLbl.Position           = UDim2.new(0, 22, 0, 0)
titleLbl.Text               = "KAH HUB"
titleLbl.TextColor3         = C.text
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 14
titleLbl.BackgroundTransparency = 1
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.ZIndex             = 4
titleLbl.Parent             = header

local langBtn = Instance.new("TextButton")
langBtn.Size = UDim2.new(0, 28, 0, 20)
langBtn.Position = UDim2.new(1, -154, 0.5, -10)
langBtn.Text = "PT"
langBtn.BackgroundColor3 = C.tabBg
langBtn.TextColor3 = C.text
langBtn.Font = Enum.Font.GothamBold
langBtn.TextSize = 11
langBtn.BorderSizePixel = 0
langBtn.ZIndex = 4
langBtn.Parent = header
Instance.new("UICorner", langBtn).CornerRadius = UDim.new(0, 2)
Instance.new("UIStroke", langBtn).Color = C.border

local minWidthBtn = Instance.new("TextButton")
minWidthBtn.Size = UDim2.new(0, 36, 0, 20)
minWidthBtn.Position = UDim2.new(1, -122, 0.5, -10)
minWidthBtn.Text = ""
minWidthBtn.BackgroundColor3 = C.tabBg
minWidthBtn.TextColor3 = C.text
minWidthBtn.Font = Enum.Font.GothamBold
minWidthBtn.TextSize = 11
minWidthBtn.BorderSizePixel = 0
minWidthBtn.ZIndex = 4
minWidthBtn.Parent = header
Instance.new("UICorner", minWidthBtn).CornerRadius = UDim.new(0, 2)
Instance.new("UIStroke", minWidthBtn).Color = C.border

local organizeBtn = Instance.new("TextButton")
organizeBtn.Size = UDim2.new(0, 36, 0, 20)
organizeBtn.Position = UDim2.new(1, -82, 0.5, -10)
organizeBtn.Text = "GRID"
organizeBtn.BackgroundColor3 = Color3.fromRGB(12, 36, 50)
organizeBtn.TextColor3 = C.accent
organizeBtn.Font = Enum.Font.GothamBold
organizeBtn.TextSize = 10
organizeBtn.BorderSizePixel = 0
organizeBtn.ZIndex = 4
organizeBtn.Parent = header
Instance.new("UICorner", organizeBtn).CornerRadius = UDim.new(0, 2)
Instance.new("UIStroke", organizeBtn).Color = C.border

local organizeConfirmArmed = false
local organizeConfirmToken = 0

local function refreshOrganizeBtn()
    if UIS.TouchEnabled and organizeConfirmArmed then
        organizeBtn.Text = "OK?"
        organizeBtn.BackgroundColor3 = Color3.fromRGB(68, 44, 12)
        organizeBtn.TextColor3 = C.yellow
        return
    end
    organizeBtn.Text = "GRID"
    organizeBtn.BackgroundColor3 = Color3.fromRGB(12, 36, 50)
    organizeBtn.TextColor3 = C.accent
end

local function clearOrganizeConfirm()
    organizeConfirmArmed = false
    organizeConfirmToken = 0
    refreshOrganizeBtn()
end

local function armOrganizeConfirm()
    organizeConfirmArmed = true
    organizeConfirmToken = tick()
    refreshOrganizeBtn()
    local token = organizeConfirmToken
    task.delay(2.8, function()
        if organizeConfirmToken == token then
            clearOrganizeConfirm()
        end
    end)
end

local minBtn = Instance.new("TextButton")
minBtn.Size             = UDim2.new(0, 18, 0, 18)
minBtn.Position         = UDim2.new(1, -42, 0.5, -9)
minBtn.Text             = "-"
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
closeBtn.Size             = UDim2.new(0, 18, 0, 18)
closeBtn.Position         = UDim2.new(1, -20, 0.5, -9)
closeBtn.Text             = "x"
closeBtn.BackgroundColor3 = C.redDim
closeBtn.TextColor3       = C.red
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 11
closeBtn.BorderSizePixel  = 0
closeBtn.ZIndex           = 4
closeBtn.Parent           = header
Instance.new("UIStroke", closeBtn).Color        = Color3.fromRGB(100, 20, 35)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 2)

local miniIcon = Instance.new("TextButton")
miniIcon.Name = "HubMiniIcon"
miniIcon.Size = UDim2.new(0, 42, 0, 42)
miniIcon.Position = UDim2.new(0, frame.Position.X.Offset + math.max(frame.Size.X.Offset - 42, 0), 0, frame.Position.Y.Offset)
miniIcon.BackgroundColor3 = C.header
miniIcon.TextColor3 = C.accent
miniIcon.Font = Enum.Font.GothamBold
miniIcon.TextSize = 14
miniIcon.Text = "KAH"
miniIcon.BorderSizePixel = 0
miniIcon.AutoButtonColor = false
miniIcon.ZIndex = 12
miniIcon.Visible = false
miniIcon.Parent = gui
Instance.new("UICorner", miniIcon).CornerRadius = UDim.new(0, 8)
local miniIconStroke = Instance.new("UIStroke", miniIcon)
miniIconStroke.Color = C.border
miniIconStroke.Thickness = 1

local resizeHandle = Instance.new("TextButton")
resizeHandle.Name             = "ResizeHandle"
resizeHandle.Size             = UDim2.new(0, 14, 0, 14)
resizeHandle.Position         = UDim2.new(1, -14, 1, -14)
resizeHandle.Text             = ""
resizeHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHandle.BorderSizePixel  = 0
resizeHandle.AutoButtonColor  = true
resizeHandle.ZIndex           = 8
resizeHandle.Parent           = frame
Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 2)
local rsStroke = Instance.new("UIStroke", resizeHandle)
rsStroke.Color = C.border
rsStroke.Thickness = 1

local resizeDot = Instance.new("Frame")
resizeDot.Size = UDim2.new(0, 3, 0, 3)
resizeDot.Position = UDim2.new(1, -5, 1, -5)
resizeDot.BackgroundColor3 = C.muted
resizeDot.BorderSizePixel = 0
resizeDot.Parent = resizeHandle
Instance.new("UICorner", resizeDot).CornerRadius = UDim.new(1, 0)

local resizeHHandle = Instance.new("TextButton")
resizeHHandle.Name             = "ResizeHeightHandle"
resizeHHandle.Size             = UDim2.new(0, 24, 0, 8)
resizeHHandle.Position         = UDim2.new(0.5, -12, 1, -8)
resizeHHandle.Text             = ""
resizeHHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeHHandle.BorderSizePixel  = 0
resizeHHandle.AutoButtonColor  = true
resizeHHandle.ZIndex           = 8
resizeHHandle.Parent           = frame
Instance.new("UICorner", resizeHHandle).CornerRadius = UDim.new(1, 0)
local rsHStroke = Instance.new("UIStroke", resizeHHandle)
rsHStroke.Color = C.border
rsHStroke.Thickness = 1

local resizeLHandle = Instance.new("TextButton")
resizeLHandle.Name             = "ResizeLeftHandle"
resizeLHandle.Size             = UDim2.new(0, 8, 0, 36)
resizeLHandle.Position         = UDim2.new(0, 0, 0.5, -18)
resizeLHandle.Text             = ""
resizeLHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeLHandle.BorderSizePixel  = 0
resizeLHandle.AutoButtonColor  = true
resizeLHandle.ZIndex           = 8
resizeLHandle.Parent           = frame
Instance.new("UICorner", resizeLHandle).CornerRadius = UDim.new(1, 0)
local rsLStroke = Instance.new("UIStroke", resizeLHandle)
rsLStroke.Color = C.border
rsLStroke.Thickness = 1

local resizeRHandle = Instance.new("TextButton")
resizeRHandle.Name             = "ResizeRightHandle"
resizeRHandle.Size             = UDim2.new(0, 8, 0, 36)
resizeRHandle.Position         = UDim2.new(1, -8, 0.5, -18)
resizeRHandle.Text             = ""
resizeRHandle.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
resizeRHandle.BorderSizePixel  = 0
resizeRHandle.AutoButtonColor  = true
resizeRHandle.ZIndex           = 8
resizeRHandle.Parent           = frame
Instance.new("UICorner", resizeRHandle).CornerRadius = UDim.new(1, 0)
local rsRStroke = Instance.new("UIStroke", resizeRHandle)
rsRStroke.Color = C.border
rsRStroke.Thickness = 1

local function setResizeHandlesVisible(v)
    resizeHandle.Visible = false
    resizeHHandle.Visible = false
    resizeLHandle.Visible = false
    resizeRHandle.Visible = false
end

local function refreshMinWidthBtn()
    if minWidthBtn then
        minWidthBtn.Text = tostring(getMinimizedWidthDefault())
    end
end
refreshMinWidthBtn()

local function refreshLangBtn()
    if not langBtn then return end
    if currentLanguage == "en" then
        langBtn.Text = "EN"
    elseif currentLanguage == "es" then
        langBtn.Text = "ES"
    else
        langBtn.Text = "PT"
    end
end
refreshLangBtn()
langBtn.Visible = false
minWidthBtn.Visible = false
organizeBtn.Visible = false
setResizeHandlesVisible(false)

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
-- ATUALIZAR LAYOUT (chame apÃƒÂ³s qualquer mudanÃƒÂ§a estrutural)
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

        -- largura: ÃƒÂºltima da linha (ou ÃƒÂºltima geral) pega o restante
        local isUltima = (coluna == TABS_LINHA - 1) or (i == #cats)
        local w = isUltima and (W - tabW * coluna) or tabW

        cat.tabBtn.Parent   = linhaFrame
        cat.tabBtn.Position = UDim2.new(0, coluna * tabW, 0, 0)
        cat.tabBtn.Size     = UDim2.new(0, w, 1, 0)
    end

    -- 4. Reposiciona todos os containers de mÃƒÂ³dulos abaixo da tabBar
    local containerY = H_HDR + tabH
    for _, cat in ipairs(cats) do
        cat.container.Position = UDim2.new(0, 0, 0, containerY)
        refreshCatSubtabs(cat)
    end

    -- 5. Redimensiona frame para a aba ativa
    if not minimizado and catAtiva then
        local h = hFrameExpandido(catAtiva)
        frame.Size = UDim2.new(0, W, 0, h)
    end
end

local function aplicarLarguraHub(novaW, novaExtraH, salvar)
    W = math.clamp(math.floor((tonumber(novaW) or W) + 0.5), MIN_W, MAX_W)
    if tonumber(novaExtraH) ~= nil then
        EXTRA_H = math.floor(tonumber(novaExtraH) + 0.5)
    end
    EXTRA_H = math.clamp(EXTRA_H, MIN_EXTRA_H, MAX_EXTRA_H)
    hubScale.Scale = math.clamp((W / BASE_W) ^ 0.55, 0.9, 1.35)

    atualizarLayout()
    if catAtiva then
        local sh = workspace.CurrentCamera.ViewportSize.Y
        local baseH = hFrame(catAtiva)
        local maxExtraView = math.max(0, sh - baseH - 8)
        EXTRA_H = math.clamp(EXTRA_H, MIN_EXTRA_H, math.min(MAX_EXTRA_H, maxExtraView))
    end
    if minimizado then
        frame.Size = UDim2.new(0, getMinimizedWidthDefault(), 0, H_HDR)
    elseif catAtiva then
        frame.Size = UDim2.new(0, W, 0, hFrameExpandido(catAtiva))
    else
        frame.Size = UDim2.new(0, W, 0, H_HDR)
    end
    setResizeHandlesVisible(not minimizado)

    local sw = workspace.CurrentCamera.ViewportSize.X
    local sh = workspace.CurrentCamera.ViewportSize.Y
    local nx = math.clamp(frame.Position.X.Offset, 4, sw - frame.Size.X.Offset - 4)
    local ny = math.clamp(frame.Position.Y.Offset, 4, sh - frame.Size.Y.Offset - 4)
    frame.Position = UDim2.new(0, nx, 0, ny)

    if salvar then
        cfg.posX = nx
        cfg.posY = ny
        cfg.scaleX = 0
        cfg.scaleY = 0
        cfg.width = W
        cfg.extraH = EXTRA_H
        salvarCfg(cfg)
    end

    if _G.Snap and _G.Snap.atualizarTamanho then
        pcall(function() _G.Snap.atualizarTamanho(frame) end)
    end
end

local function aplicarEstadoVisualRow(row, ativo)
    if not row then return end
    local lb = row:FindFirstChild("LeftBar")
    local tr = row:FindFirstChild("Track")
    local kn = tr and tr:FindFirstChild("Knob")
    local nl = row:FindFirstChild("NomeLabel")
    local ts = tr and tr:FindFirstChildOfClass("UIStroke")

    if ativo then
        row.BackgroundColor3 = C.rowActive
        if lb then lb.BackgroundColor3 = C.green end
        if nl then nl.TextColor3 = C.green end
        if tr then tr.BackgroundColor3 = C.greenDim end
        if kn then
            kn.Position = UDim2.new(1, -14, 0.5, -6)
            kn.BackgroundColor3 = C.green
        end
        if ts then ts.Color = Color3.fromRGB(30, 100, 50) end
    else
        row.BackgroundColor3 = C.rowBg
        if lb then lb.BackgroundColor3 = C.border end
        if nl then nl.TextColor3 = C.text end
        if tr then tr.BackgroundColor3 = Color3.fromRGB(25, 28, 40) end
        if kn then
            kn.Position = UDim2.new(0, 2, 0.5, -6)
            kn.BackgroundColor3 = C.muted
        end
        if ts then ts.Color = C.border end
    end
end

local function setCatActiveSubtab(cat, subtabName, fromUser)
    if not cat or not cat.subtabs then return end
    if fromUser and cat.nomeRaw == "Admin" then
        cat.adminSubtabManual = true
    end
    cat.activeSubtab = subtabName
    for name, entry in pairs(cat.subtabs) do
        if entry.container then
            entry.container.Visible = (name == subtabName)
        end
        if entry.btn then
            entry.btn.BackgroundColor3 = (name == subtabName) and C.tabActive or C.tabBg
            entry.btn.TextColor3 = (name == subtabName) and C.accent or C.muted
        end
    end
    if catAtiva == cat and not minimizado then
        frame.Size = UDim2.new(0, W, 0, hFrameExpandido(cat))
    end
end

local function ensureCatSubtabEntry(cat, subtabName)
    cat.subtabs = cat.subtabs or {}
    if cat.subtabs[subtabName] then
        return cat.subtabs[subtabName]
    end

    local btn = Instance.new("TextButton")
    btn.Name = "SubTab_" .. subtabName
    btn.Text = string.upper(subtabName)
    btn.BackgroundColor3 = C.tabBg
    btn.TextColor3 = C.muted
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.BorderSizePixel = 0
    btn.ZIndex = 4
    btn.Parent = cat.subtabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)

    local container = Instance.new("Frame")
    container.Name = "SubCont_" .. subtabName
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(1, 0, 1, 0)
    container.Position = UDim2.new(0, 0, 0, 0)
    container.Visible = false
    container.ZIndex = 2
    container.Parent = cat.contentFrame

    btn.MouseButton1Click:Connect(function()
        setCatActiveSubtab(cat, subtabName, true)
    end)

    cat.subtabs[subtabName] = {
        name = subtabName,
        btn = btn,
        container = container,
    }
    return cat.subtabs[subtabName]
end

refreshCatSubtabs = function(cat)
    if not cat or not cat.subtabBar or not cat.contentFrame or not cat.pinnedFrame then return end

    local wanted = orderCategorySubtabs(cat, collectCatSubtabNames(cat))
    local wantedSet = {}
    for _, name in ipairs(wanted) do
        wantedSet[name] = true
        ensureCatSubtabEntry(cat, name)
    end

    for name, entry in pairs(cat.subtabs or {}) do
        if not wantedSet[name] then
            if entry.btn and entry.btn.Parent then entry.btn:Destroy() end
            if entry.container and entry.container.Parent then entry.container:Destroy() end
            cat.subtabs[name] = nil
        end
    end

    cat.subtabOrder = wanted
    local count = #wanted
    local visible = count > 1
    cat.subtabBar.Visible = visible

    local pinnedCount = getCatPinnedRowCount(cat)
    local pinnedHeight = pinnedCount > 0 and (PAD + pinnedCount * (H_ROW + 2)) or 0
    cat.pinnedFrame.Visible = pinnedCount > 0
    cat.pinnedFrame.Position = UDim2.new(0, 0, 0, 0)
    cat.pinnedFrame.Size = UDim2.new(1, 0, 0, pinnedHeight)

    cat.subtabBar.Position = UDim2.new(0, 6, 0, pinnedHeight)
    local contentY = pinnedHeight + (visible and (H_SUBTAB + PAD) or 0)
    cat.contentFrame.Position = UDim2.new(0, 0, 0, contentY)
    cat.contentFrame.Size = UDim2.new(1, 0, 1, -contentY)

    local widthBase = math.max(1, math.floor((W - 12) / math.max(count, 1)))
    local posX = 0
    for idx, name in ipairs(wanted) do
        local entry = cat.subtabs[name]
        if entry and entry.btn then
            local isLast = idx == count
            local width = isLast and math.max(1, (W - 12) - posX) or widthBase
            entry.btn.Size = UDim2.new(0, width, 1, 0)
            entry.btn.Position = UDim2.new(0, posX, 0, 0)
            posX += width
        end
    end

    local active = cat.activeSubtab
    if cat.nomeRaw == "Admin" and wantedSet["Spells"] then
        active = "Spells"
    elseif not active or not wantedSet[active] then
        if cat.nomeRaw == "Admin" and wantedSet["Spells"] then
            active = "Spells"
        else
            active = wanted[1]
        end
    end
    setCatActiveSubtab(cat, active)
end

-- ============================================
-- CRIAR ROW
-- ============================================
local function criarRow(modulo, container, index)
    local posY = PAD + (index - 1) * (H_ROW + 2)
    local opts = modulo.opts or {}
    local hasInlineNumber = opts.inlineNumber ~= nil
    local hasInlineText = opts.inlineText ~= nil
    local hasInlineDropdown = opts.inlineDropdown ~= nil
    local dropdownOnly = hasInlineDropdown and opts.inlineDropdown.toggle ~= true
    local hasRightEditor = hasInlineNumber or hasInlineText or hasInlineDropdown
    local labelRightPad
    if hasInlineNumber then
        labelRightPad = -126
    elseif hasInlineText then
        labelRightPad = -150
    elseif hasInlineDropdown then
        labelRightPad = -196
    else
        labelRightPad = -60
    end
    local buttonRightPad
    if hasInlineNumber then
        buttonRightPad = -110
    elseif hasInlineText then
        buttonRightPad = -134
    elseif hasInlineDropdown then
        buttonRightPad = -162
    else
        buttonRightPad = 0
    end

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
    nomeLbl.Size               = UDim2.new(1, labelRightPad, 1, 0)
    nomeLbl.Position           = UDim2.new(0, 12, 0, 0)
    nomeLbl.Text               = translateModule(modulo.nomeRaw or modulo.nome)
    nomeLbl.TextColor3         = C.text
    nomeLbl.Font               = Enum.Font.GothamBold
    nomeLbl.TextSize           = 12
    nomeLbl.BackgroundTransparency = 1
    nomeLbl.TextXAlignment     = Enum.TextXAlignment.Left
    nomeLbl.ZIndex             = 5
    nomeLbl.Parent             = row

    local track
    local trackStroke
    local knob
    if not dropdownOnly then
        track = Instance.new("Frame")
        track.Name             = "Track"
        track.Size             = UDim2.new(0, 34, 0, 16)
        track.Position         = UDim2.new(1, -44, 0.5, -8)
        track.BackgroundColor3 = Color3.fromRGB(25, 28, 40)
        track.BorderSizePixel  = 0
        track.ZIndex           = 5
        track.Parent           = row
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
        trackStroke = Instance.new("UIStroke", track)
        trackStroke.Color     = C.border
        trackStroke.Thickness = 1

        knob = Instance.new("Frame")
        knob.Name             = "Knob"
        knob.Size             = UDim2.new(0, 12, 0, 12)
        knob.Position         = UDim2.new(0, 2, 0.5, -6)
        knob.BackgroundColor3 = C.muted
        knob.BorderSizePixel  = 0
        knob.ZIndex           = 6
        knob.Parent           = track
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    end

    local inlineNumberBox
    if hasInlineNumber then
        inlineNumberBox = Instance.new("TextBox")
        inlineNumberBox.Name = "InlineNumber"
        inlineNumberBox.Size = UDim2.new(0, 54, 0, 20)
        inlineNumberBox.Position = UDim2.new(1, -102, 0.5, -10)
        inlineNumberBox.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
        inlineNumberBox.TextColor3 = C.text
        inlineNumberBox.PlaceholderColor3 = C.muted
        inlineNumberBox.Font = Enum.Font.GothamBold
        inlineNumberBox.TextSize = 11
        inlineNumberBox.BorderSizePixel = 0
        inlineNumberBox.ClearTextOnFocus = false
        inlineNumberBox.ZIndex = 6
        inlineNumberBox.Parent = row
        Instance.new("UICorner", inlineNumberBox).CornerRadius = UDim.new(0, 3)
        Instance.new("UIStroke", inlineNumberBox).Color = C.border

        local function refreshInlineValue()
            local getFn = opts.inlineNumber.get
            if type(getFn) ~= "function" then return end
            local ok, v = pcall(getFn)
            if ok and tonumber(v) then
                inlineNumberBox.Text = tostring(math.floor(tonumber(v) + 0.5))
            end
        end
        refreshInlineValue()

        inlineNumberBox.FocusLost:Connect(function(enterPressed)
            if not enterPressed then
                refreshInlineValue()
                return
            end
            local raw = tonumber(inlineNumberBox.Text)
            if not raw then
                refreshInlineValue()
                return
            end
            local minV = tonumber(opts.inlineNumber.min)
            local maxV = tonumber(opts.inlineNumber.max)
            if minV then raw = math.max(minV, raw) end
            if maxV then raw = math.min(maxV, raw) end
            local setFn = opts.inlineNumber.set
            if type(setFn) == "function" then
                pcall(setFn, raw)
            end
            refreshInlineValue()
        end)

        modulo._refreshInlineValue = refreshInlineValue
    end

    local inlineTextBox
    if hasInlineText then
        inlineTextBox = Instance.new("TextBox")
        inlineTextBox.Name = "InlineText"
        inlineTextBox.Size = UDim2.new(0, 82, 0, 20)
        inlineTextBox.Position = UDim2.new(1, -130, 0.5, -10)
        inlineTextBox.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
        inlineTextBox.TextColor3 = C.text
        inlineTextBox.PlaceholderColor3 = C.muted
        inlineTextBox.Font = Enum.Font.GothamBold
        inlineTextBox.TextSize = 11
        inlineTextBox.BorderSizePixel = 0
        inlineTextBox.ClearTextOnFocus = false
        inlineTextBox.TextTruncate = Enum.TextTruncate.AtEnd
        inlineTextBox.PlaceholderText = tostring(opts.inlineText.placeholder or "")
        inlineTextBox.ZIndex = 6
        inlineTextBox.Parent = row
        Instance.new("UICorner", inlineTextBox).CornerRadius = UDim.new(0, 3)
        Instance.new("UIStroke", inlineTextBox).Color = C.border

        local function refreshInlineText()
            local getFn = opts.inlineText.get
            if type(getFn) ~= "function" then return end
            local ok, v = pcall(getFn)
            if ok then
                inlineTextBox.Text = tostring(v or "")
            end
        end
        refreshInlineText()

        inlineTextBox.FocusLost:Connect(function(enterPressed)
            if not enterPressed then
                refreshInlineText()
                return
            end
            local setFn = opts.inlineText.set
            if type(setFn) == "function" then
                pcall(setFn, tostring(inlineTextBox.Text or ""))
            end
            refreshInlineText()
        end)

        modulo._refreshInlineValue = refreshInlineText
    end

    local inlineDropdownButton
    local toggleInlineDropdown = nil
    if hasInlineDropdown then
        inlineDropdownButton = Instance.new("TextButton")
        inlineDropdownButton.Name = "InlineDropdown"
        inlineDropdownButton.Size = UDim2.new(0, 126, 0, 22)
        inlineDropdownButton.Position = UDim2.new(1, -176, 0.5, -11)
        inlineDropdownButton.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
        inlineDropdownButton.TextColor3 = C.text
        inlineDropdownButton.Font = Enum.Font.GothamBold
        inlineDropdownButton.TextSize = 12
        inlineDropdownButton.BorderSizePixel = 0
        inlineDropdownButton.TextTruncate = Enum.TextTruncate.AtEnd
        inlineDropdownButton.TextXAlignment = Enum.TextXAlignment.Left
        inlineDropdownButton.ZIndex = 6
        inlineDropdownButton.Parent = row
        Instance.new("UICorner", inlineDropdownButton).CornerRadius = UDim.new(0, 3)
        Instance.new("UIStroke", inlineDropdownButton).Color = C.border
        local dropdownPadding = Instance.new("UIPadding")
        dropdownPadding.PaddingLeft = UDim.new(0, 8)
        dropdownPadding.PaddingRight = UDim.new(0, 20)
        dropdownPadding.Parent = inlineDropdownButton

        local dropdownArrow = Instance.new("TextLabel")
        dropdownArrow.Name = "Arrow"
        dropdownArrow.Size = UDim2.new(0, 16, 1, 0)
        dropdownArrow.Position = UDim2.new(1, -18, 0, 0)
        dropdownArrow.BackgroundTransparency = 1
        dropdownArrow.Text = "v"
        dropdownArrow.TextColor3 = C.muted
        dropdownArrow.Font = Enum.Font.GothamBold
        dropdownArrow.TextSize = 12
        dropdownArrow.ZIndex = 7
        dropdownArrow.Parent = inlineDropdownButton

        local function getDropdownOptionsSnapshot()
            local getOptionsFn = opts.inlineDropdown.getOptions
            if type(getOptionsFn) ~= "function" then
                return {}
            end
            local ok, raw = pcall(getOptionsFn)
            if not ok or type(raw) ~= "table" then
                return {}
            end
            local snapshot = {}
            for _, item in ipairs(raw) do
                local value, label
                if type(item) == "table" then
                    value = tostring(item.value or item.name or item.id or item.label or "")
                    label = tostring(item.label or item.text or item.displayName or value)
                else
                    value = tostring(item or "")
                    label = value
                end
                table.insert(snapshot, {
                    value = value,
                    label = label ~= "" and label or value,
                })
            end
            return snapshot
        end

        local function getCurrentDropdownValue()
            local getFn = opts.inlineDropdown.get
            if type(getFn) ~= "function" then
                return ""
            end
            local ok, value = pcall(getFn)
            if not ok then
                return ""
            end
            return tostring(value or "")
        end

        local function refreshInlineDropdown(snapshot)
            local currentValue = getCurrentDropdownValue()
            local displayText = tostring(opts.inlineDropdown.placeholder or "Selecionar")
            for _, option in ipairs(snapshot or getDropdownOptionsSnapshot()) do
                if tostring(option.value) == currentValue then
                    displayText = tostring(option.label)
                    break
                end
            end
            if currentValue ~= "" and displayText == tostring(opts.inlineDropdown.placeholder or "Selecionar") then
                displayText = currentValue
            end
            inlineDropdownButton.Text = displayText
        end

        local dropdownPopup = nil
        local function closeDropdown()
            if dropdownPopup and dropdownPopup.Parent then
                dropdownPopup:Destroy()
            end
            dropdownPopup = nil
            dropdownArrow.Text = "v"
            if activeInlineDropdownClose == closeDropdown then
                activeInlineDropdownClose = nil
            end
        end

        local function openDropdown()
            if activeInlineDropdownClose and activeInlineDropdownClose ~= closeDropdown then
                pcall(activeInlineDropdownClose)
            end
            if dropdownPopup and dropdownPopup.Parent then
                closeDropdown()
                return
            end

            local snapshot = getDropdownOptionsSnapshot()
            local visibleCount = math.max(1, math.min(#snapshot, 6))
            local popupHeight = visibleCount * 22 + 4

            dropdownPopup = Instance.new("Frame")
            dropdownPopup.Name = "InlineDropdownPopup"
            dropdownPopup.Size = UDim2.new(0, 126, 0, popupHeight)
            dropdownPopup.Position = UDim2.new(1, -176, 1, 2)
            dropdownPopup.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
            dropdownPopup.BorderSizePixel = 0
            dropdownPopup.ZIndex = 20
            dropdownPopup.Parent = row
            Instance.new("UICorner", dropdownPopup).CornerRadius = UDim.new(0, 4)
            Instance.new("UIStroke", dropdownPopup).Color = C.border

            local popupScroll = Instance.new("ScrollingFrame")
            popupScroll.Size = UDim2.new(1, -4, 1, -4)
            popupScroll.Position = UDim2.new(0, 2, 0, 2)
            popupScroll.BackgroundTransparency = 1
            popupScroll.BorderSizePixel = 0
            popupScroll.ScrollBarThickness = 2
            popupScroll.ScrollBarImageColor3 = C.accent
            popupScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            popupScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            popupScroll.ZIndex = 21
            popupScroll.Parent = dropdownPopup

            local popupLayout = Instance.new("UIListLayout")
            popupLayout.Padding = UDim.new(0, 2)
            popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
            popupLayout.Parent = popupScroll

            if #snapshot == 0 then
                local emptyLabel = Instance.new("TextLabel")
                emptyLabel.Size = UDim2.new(1, -8, 0, 20)
                emptyLabel.Position = UDim2.new(0, 4, 0, 0)
                emptyLabel.BackgroundTransparency = 1
                emptyLabel.Text = tostring(opts.inlineDropdown.emptyText or "Sem opcoes")
                emptyLabel.TextColor3 = C.muted
                emptyLabel.Font = Enum.Font.GothamBold
                emptyLabel.TextSize = 11
                emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
                emptyLabel.ZIndex = 22
                emptyLabel.Parent = popupScroll
            else
                local currentValue = getCurrentDropdownValue()
                for i, option in ipairs(snapshot) do
                    local optionBtn = Instance.new("TextButton")
                    optionBtn.Name = "Option_" .. i
                    optionBtn.Size = UDim2.new(1, 0, 0, 20)
                    optionBtn.BackgroundColor3 = tostring(option.value) == currentValue and C.rowActive or C.rowBg
                    optionBtn.Text = tostring(option.label)
                    optionBtn.TextColor3 = tostring(option.value) == currentValue and C.green or C.text
                    optionBtn.Font = Enum.Font.GothamBold
                    optionBtn.TextSize = 11
                    optionBtn.BorderSizePixel = 0
                    optionBtn.TextTruncate = Enum.TextTruncate.AtEnd
                    optionBtn.TextXAlignment = Enum.TextXAlignment.Left
                    optionBtn.ZIndex = 22
                    optionBtn.Parent = popupScroll
                    Instance.new("UICorner", optionBtn).CornerRadius = UDim.new(0, 3)
                    local optionPadding = Instance.new("UIPadding")
                    optionPadding.PaddingLeft = UDim.new(0, 8)
                    optionPadding.PaddingRight = UDim.new(0, 8)
                    optionPadding.Parent = optionBtn

                    optionBtn.MouseButton1Click:Connect(function()
                        local setFn = opts.inlineDropdown.set
                        if type(setFn) == "function" then
                            pcall(setFn, tostring(option.value))
                        end
                        refreshInlineDropdown(snapshot)
                        closeDropdown()
                    end)
                end
            end

            dropdownArrow.Text = "^"
            activeInlineDropdownClose = closeDropdown
        end

        toggleInlineDropdown = openDropdown

        refreshInlineDropdown()
        inlineDropdownButton.MouseButton1Click:Connect(openDropdown)
        row.Destroying:Connect(closeDropdown)
        modulo._refreshInlineValue = refreshInlineDropdown
    end

    local function refreshRowText()
        local base = translateModule(modulo.displayName or modulo.nomeRaw or modulo.nome)
        local suffix = ""
        if type(opts.statusProvider) == "function" then
            local ok, txt = pcall(opts.statusProvider)
            if ok and type(txt) == "string" and txt ~= "" then
                suffix = " | " .. txt
            end
        end
        nomeLbl.Text = base .. suffix
    end
    modulo._refreshRowText = refreshRowText
    refreshRowText()
    if type(opts.statusProvider) == "function" then
        table.insert(rowStatusUpdaters, modulo)
    end

    local function handleToggle()
        if dropdownOnly then
            if toggleInlineDropdown then
                toggleInlineDropdown()
            end
            return
        end
        modulo.ativo = not modulo.ativo
        aplicarEstadoVisualRow(row, modulo.ativo)

        local ok, err = pcall(modulo.toggleFn, modulo.ativo)
        if not ok then warn(">>> HUB toggle [" .. modulo.nome .. "]: " .. tostring(err)) end
    end

    local btn = Instance.new("TextButton")
    btn.Size               = UDim2.new(1, hasRightEditor and buttonRightPad or 0, 1, 0)
    btn.Position           = UDim2.new(0, 0, 0, 0)
    btn.BackgroundTransparency = 1
    btn.Text               = ""
    btn.ZIndex             = 7
    btn.Parent             = row
    btn.MouseButton1Click:Connect(handleToggle)

    if not dropdownOnly then
        local trackBtn = Instance.new("TextButton")
        trackBtn.Size = UDim2.new(0, 38, 0, 20)
        trackBtn.Position = UDim2.new(1, -46, 0.5, -10)
        trackBtn.BackgroundTransparency = 1
        trackBtn.Text = ""
        trackBtn.ZIndex = 7
        trackBtn.Parent = row
        trackBtn.MouseButton1Click:Connect(handleToggle)
    end

    aplicarEstadoVisualRow(row, modulo.ativo == true)

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
    refreshCatSubtabs(cat)

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
        frame.Size = UDim2.new(0, W, 0, hFrameExpandido(cat))
    end
end

-- ============================================
-- REGISTRAR MÃƒâ€œDULO
-- ============================================
local function reflowCategoryRows(cat)
    if not cat then return end
    refreshCatSubtabs(cat)
    local offsets = {}
    for _, name in ipairs(cat.subtabOrder or { "Main" }) do
        offsets[name] = 0
    end
    local pinnedOffset = 0
    for i, row in ipairs(cat.rows) do
        local modulo = cat.modulos[i]
        if row and row.Parent and modulo then
            if isModulePinnedAboveSubtabs(modulo) and cat.pinnedFrame then
                row.Parent = cat.pinnedFrame
                local posY = PAD + pinnedOffset * (H_ROW + 2)
                row.Position = UDim2.new(0, 6, 0, posY)
                pinnedOffset += 1
            else
                local subtabName = getModuleSubtabName(modulo)
                local entry = ensureCatSubtabEntry(cat, subtabName)
                if entry and entry.container then
                    row.Parent = entry.container
                    local posY = PAD + offsets[subtabName] * (H_ROW + 2)
                    row.Position = UDim2.new(0, 6, 0, posY)
                    offsets[subtabName] += 1
                end
            end
        end
    end
end

local function removeStatusUpdater(modulo)
    for i = #rowStatusUpdaters, 1, -1 do
        if rowStatusUpdaters[i] == modulo then
            table.remove(rowStatusUpdaters, i)
        end
    end
end

local function moduleNameKey(name)
    local s = tostring(name or ""):match("^%s*(.-)%s*$")
    return string.lower(s)
end

local function rowNeedsRebuild(row, opts)
    if not row then return false end
    opts = opts or {}
    local wantsInlineNumber = opts.inlineNumber ~= nil
    local wantsInlineText = opts.inlineText ~= nil
    local wantsInlineDropdown = opts.inlineDropdown ~= nil
    local hasInlineNumber = row:FindFirstChild("InlineNumber") ~= nil
    local hasInlineText = row:FindFirstChild("InlineText") ~= nil
    local hasInlineDropdown = row:FindFirstChild("InlineDropdown") ~= nil
    return wantsInlineNumber ~= hasInlineNumber
        or wantsInlineText ~= hasInlineText
        or wantsInlineDropdown ~= hasInlineDropdown
end

local function remover(nome)
    local wanted = moduleNameKey(nome)
    for _, cat in ipairs(cats) do
        for i, m in ipairs(cat.modulos) do
            local mk = moduleNameKey(m.nomeRaw or m.nome)
            if mk == wanted then
                local row = cat.rows[i]
                if row and row.Parent then
                    row:Destroy()
                end
                removeStatusUpdater(m)
                table.remove(cat.modulos, i)
                table.remove(cat.rows, i)
                reflowCategoryRows(cat)
                if catAtiva == cat and not minimizado then
                    frame.Size = UDim2.new(0, W, 0, hFrameExpandido(cat))
                end
                return true
            end
        end
    end
    return false
end

local function registrar(nome, toggleFn, categoria, jaAtivo, opts)
    categoria = categoria or "Geral"
    opts = opts or {}
    local wantedNameKey = moduleNameKey(nome)

    -- Se ja existe, atualiza callback/opts em vez de ignorar.
    -- Isso permite hot-reload do modulo sem quebrar o toggle da linha existente.
    for _, c in ipairs(cats) do
        for i, m in ipairs(c.modulos) do
            local mk = moduleNameKey(m.nomeRaw or m.nome)
            if mk == wantedNameKey then
                if c.nomeRaw ~= categoria then
                    local wasActive = m.ativo == true
                    local row = c.rows[i]
                    if row and row.Parent then
                        row:Destroy()
                    end
                    table.remove(c.modulos, i)
                    table.remove(c.rows, i)
                    reflowCategoryRows(c)
                    jaAtivo = wasActive
                    break
                end
                local row = c.rows[i]
                if rowNeedsRebuild(row, opts) then
                    local wasActive = m.ativo == true
                    if row and row.Parent then
                        row:Destroy()
                    end
                    removeStatusUpdater(m)
                    m.toggleFn = toggleFn
                    m.opts = opts
                    m.ativo = wasActive
                    local rebuilt = criarRow(m, c.contentFrame or c.container, i)
                    c.rows[i] = rebuilt
                    reflowCategoryRows(c)
                    if m.ativo then
                        aplicarEstadoVisualRow(rebuilt, true)
                    end
                    if m._refreshRowText then
                        pcall(m._refreshRowText)
                    end
                    if m._refreshInlineValue then
                        pcall(m._refreshInlineValue)
                    end
                    pcall(toggleFn, m.ativo == true)
                    return
                end
                m.toggleFn = toggleFn
                m.opts = opts
                reflowCategoryRows(c)
                if row then
                    aplicarEstadoVisualRow(row, m.ativo == true)
                end
                if m._refreshRowText then
                    pcall(m._refreshRowText)
                end
                if m._refreshInlineValue then
                    pcall(m._refreshInlineValue)
                end
                pcall(toggleFn, m.ativo == true)
                return
            end
        end
    end

    -- ObtÃƒÂ©m ou cria categoria
    local cat
    for _, c in ipairs(cats) do
        if c.nomeRaw == categoria then cat = c; break end
    end

    if not cat then
        -- Cria tabBtn e container
        local tabBtn = Instance.new("TextButton")
        tabBtn.Name             = "Tab_" .. categoria
        tabBtn.Text             = translateCategory(categoria):upper()
        tabBtn.BackgroundColor3 = C.tabBg
        tabBtn.TextColor3       = C.muted
        tabBtn.Font             = Enum.Font.GothamBold
        tabBtn.TextSize         = 10
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

        local subtabBar = Instance.new("Frame")
        subtabBar.Name = "SubTabBar"
        subtabBar.Size = UDim2.new(1, -12, 0, H_SUBTAB)
        subtabBar.Position = UDim2.new(0, 6, 0, 0)
        subtabBar.BackgroundColor3 = C.tabBg
        subtabBar.BorderSizePixel = 0
        subtabBar.ZIndex = 3
        subtabBar.Visible = false
        subtabBar.Parent = container
        Instance.new("UICorner", subtabBar).CornerRadius = UDim.new(0, 4)
        Instance.new("UIStroke", subtabBar).Color = C.border

        local contentFrame = Instance.new("Frame")
        contentFrame.Name = "SubTabContent"
        contentFrame.BackgroundTransparency = 1
        contentFrame.Size = UDim2.new(1, 0, 1, 0)
        contentFrame.Position = UDim2.new(0, 0, 0, 0)
        contentFrame.ZIndex = 2
        contentFrame.Parent = container

        local pinnedFrame = Instance.new("Frame")
        pinnedFrame.Name = "PinnedRows"
        pinnedFrame.BackgroundTransparency = 1
        pinnedFrame.Size = UDim2.new(1, 0, 0, 0)
        pinnedFrame.Position = UDim2.new(0, 0, 0, 0)
        pinnedFrame.ZIndex = 2
        pinnedFrame.Visible = false
        pinnedFrame.Parent = container

        cat = {
            nomeRaw = categoria,
            tabBtn = tabBtn,
            container = container,
            contentFrame = contentFrame,
            pinnedFrame = pinnedFrame,
            subtabBar = subtabBar,
            subtabs = {},
            subtabOrder = { "Main" },
            activeSubtab = "Main",
            adminSubtabManual = false,
            modulos = {},
            rows = {},
        }
        table.insert(cats, cat)
        sortCategories()

        tabBtn.MouseButton1Click:Connect(function()
            adminPreferredTab = false
            ativarAba(cat)
        end)

        tabBar.Visible = true
        atualizarLayout()
    end

    -- Adiciona mÃƒÂ³dulo Ã¢â‚¬â€ comeÃƒÂ§a ativo se jaAtivo=true
    local modulo = { nomeRaw = nome, nome = nome, toggleFn = toggleFn, ativo = jaAtivo == true, opts = opts }
    table.insert(cat.modulos, modulo)
    local row = criarRow(modulo, cat.contentFrame or cat.container, #cat.modulos)
    table.insert(cat.rows, row)
    reflowCategoryRows(cat)

    -- Se jÃƒÂ¡ ativo, atualiza visual do toggle para ON e notifica o mÃƒÂ³dulo
    if modulo.ativo then
        aplicarEstadoVisualRow(row, true)
        -- Avisa o mÃƒÂ³dulo que estÃƒÂ¡ ativo (necessÃƒÂ¡rio quando vem da HubFila)
        pcall(toggleFn, true)
    end

    -- Primeira aba ou aba ativa crescendo
    if adminPreferredTab then
        local defaultCat = getDefaultCategory()
        if defaultCat then
            ativarAba(defaultCat)
        end
    elseif not catAtiva then
        ativarAba(cat)
    elseif catAtiva == cat and not minimizado then
        frame.Size = UDim2.new(0, W, 0, hFrameExpandido(cat))
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
                aplicarEstadoVisualRow(row, false)
                return
            end
        end
    end
end

-- ============================================
-- SET ESTADO (liga/desliga por nome)
-- ============================================
local function setEstado(nome, ativo)
    for _, cat in ipairs(cats) do
        for i, m in ipairs(cat.modulos) do
            if m.nome == nome then
                if m.ativo == ativo then return true end
                m.ativo = ativo

                local row = cat.rows[i]
                if row then
                    aplicarEstadoVisualRow(row, ativo == true)
                end

                local ok, err = pcall(m.toggleFn, ativo)
                if not ok then warn(">>> HUB setEstado [" .. tostring(nome) .. "]: " .. tostring(err)) end
                return true
            end
        end
    end
    return false
end

local function setNomeVisual(nome, novoNome)
    for _, cat in ipairs(cats) do
        for i, m in ipairs(cat.modulos) do
            if m.nome == nome or m.nomeRaw == nome then
                m.displayName = tostring(novoNome or "")
                if m._refreshRowText then
                    pcall(m._refreshRowText)
                elseif cat.rows[i] then
                    local lbl = cat.rows[i]:FindFirstChild("NomeLabel")
                    if lbl then
                        lbl.Text = tostring(novoNome or "")
                    end
                end
                return true
            end
        end
    end
    return false
end

local function refreshLanguageUi()
    for _, cat in ipairs(cats) do
        if cat.tabBtn then
            cat.tabBtn.Text = translateCategory(cat.nomeRaw or "Geral"):upper()
        end
        for _, m in ipairs(cat.modulos) do
            if m._refreshRowText then
                pcall(m._refreshRowText)
            end
            if m._refreshInlineValue then
                pcall(m._refreshInlineValue)
            end
        end
    end
    refreshOrganizeBtn()
    refreshLangBtn()
end

task.spawn(function()
    while gui and gui.Parent do
        task.wait(1)
        for _, m in ipairs(rowStatusUpdaters) do
            if m and m._refreshRowText then
                pcall(m._refreshRowText)
            end
        end
    end
end)

-- ============================================
-- MINIMIZAR
-- ============================================
local minimizedRestorePos = nil

local function getViewportSizeSafe()
    local cam = workspace.CurrentCamera
    if cam then
        return cam.ViewportSize
    end
    return Vector2.new(1920, 1080)
end

local function clampIconPos(x, y)
    local vp = getViewportSizeSafe()
    local maxX = math.max(4, vp.X - miniIcon.Size.X.Offset - 4)
    local maxY = math.max(4, vp.Y - miniIcon.Size.Y.Offset - 4)
    return math.clamp(x, 4, maxX), math.clamp(y, 4, maxY)
end

local function snapIconPos(x, y)
    local vp = getViewportSizeSafe()
    local minX, minY = 4, 4
    local maxX = math.max(minX, vp.X - miniIcon.Size.X.Offset - 4)
    local maxY = math.max(minY, vp.Y - miniIcon.Size.Y.Offset - 4)

    local leftDist = math.abs(x - minX)
    local rightDist = math.abs(maxX - x)
    local topDist = math.abs(y - minY)
    local bottomDist = math.abs(maxY - y)
    local minDist = math.min(leftDist, rightDist, topDist, bottomDist)

    if minDist == leftDist then
        x = minX
    elseif minDist == rightDist then
        x = maxX
    elseif minDist == topDist then
        y = minY
    else
        y = maxY
    end

    return clampIconPos(x, y)
end

local function placeMiniIconNearFrame()
    local basePos = frame.Position
    if minimizedRestorePos then
        basePos = minimizedRestorePos
    end
    local x = basePos.X.Offset + math.max(frame.Size.X.Offset - miniIcon.Size.X.Offset, 0)
    local y = basePos.Y.Offset
    x, y = clampIconPos(x, y)
    miniIcon.Position = UDim2.new(0, x, 0, y)
end

local function saveFramePos()
    cfg.posX = frame.Position.X.Offset
    cfg.posY = frame.Position.Y.Offset
    cfg.scaleX = 0
    cfg.scaleY = 0
    cfg.width = W
    cfg.extraH = EXTRA_H
    salvarCfg(cfg)
end

local function restoreFrameFromSavedPos()
    local vp = getViewportSizeSafe()
    local restorePos = minimizedRestorePos or frame.Position
    local nx = math.clamp(restorePos.X.Offset, 4, vp.X - frame.Size.X.Offset - 4)
    local ny = math.clamp(restorePos.Y.Offset, 4, vp.Y - frame.Size.Y.Offset - 4)
    frame.Position = UDim2.new(0, nx, 0, ny)
    minimizedRestorePos = frame.Position
    saveFramePos()
end

local function toggleMinimizar()
    minimizado = not minimizado
    if minimizado then
        minimizedRestorePos = frame.Position
        tabBar.Visible = false
        if catAtiva then catAtiva.container.Visible = false end
        placeMiniIconNearFrame()
        frame.Visible = false
        miniIcon.Visible = true
        minBtn.Text = "^"
    else
        miniIcon.Visible = false
        restoreFrameFromSavedPos()
        frame.Visible = true
        tabBar.Visible = true
        if catAtiva then catAtiva.container.Visible = true end
        frame.Size = UDim2.new(0, W, 0, catAtiva and hFrameExpandido(catAtiva) or H_HDR)
        minBtn.Text = "-"
    end
    setResizeHandlesVisible(false)
end

-- ============================================
-- DRAG
-- ============================================
local dragging, dragStart, startPos
local iconDragging, iconDragStart, iconStartPos
local iconDragMoved = false
local ICON_DRAG_THRESHOLD = 6

header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        if minimizado then return end
        dragging = true; dragStart = i.Position; startPos = frame.Position
    end
end)
miniIcon.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        iconDragging = true
        iconDragStart = i.Position
        iconStartPos = miniIcon.Position
        iconDragMoved = false
    end
end)
UIS.InputChanged:Connect(function(i)
    if iconDragging and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - iconDragStart
        if not iconDragMoved and d.Magnitude >= ICON_DRAG_THRESHOLD then
            iconDragMoved = true
        end
        local nx = iconStartPos.X.Offset + d.X
        local ny = iconStartPos.Y.Offset + d.Y
        nx, ny = clampIconPos(nx, ny)
        miniIcon.Position = UDim2.new(0, nx, 0, ny)
        return
    end

    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d  = i.Position - dragStart
        local vp = getViewportSizeSafe()
        local nx = startPos.X.Scale * vp.X + startPos.X.Offset + d.X
        local ny = startPos.Y.Scale * vp.Y + startPos.Y.Offset + d.Y
        nx = math.clamp(nx, 4, vp.X - frame.Size.X.Offset - 4)
        ny = math.clamp(ny, 4, vp.Y - frame.Size.Y.Offset - 4)
        local snap = _G.Snap
        if snap and snap.mover then
            pcall(function()
                snap.mover(frame, nx, ny)
            end)
        else
            frame.Position = UDim2.new(0, nx, 0, ny)
        end
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        if dragging then
            local snap = _G.Snap
            if snap and snap.soltar then
                pcall(function()
                    snap.soltar(frame)
                end)
            end
            saveFramePos()
        end
        dragging = false

        if iconDragging then
            if iconDragMoved then
                local sx, sy = snapIconPos(miniIcon.Position.X.Offset, miniIcon.Position.Y.Offset)
                miniIcon.Position = UDim2.new(0, sx, 0, sy)
                minimizedRestorePos = UDim2.new(0, sx, 0, sy)
            else
                toggleMinimizar()
            end
        end
        iconDragging = false
        iconDragMoved = false
    end
end)

-- ============================================
-- EVENTOS
-- ============================================
local function arrumarJanelasAgora()
    clearOrganizeConfirm()
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    local ny = math.max(4, vp.Y - frame.Size.Y.Offset - 8)
    frame.Position = UDim2.new(0, 8, 0, ny)
    cfg.posX = 8
    cfg.posY = ny
    cfg.scaleX = 0
    cfg.scaleY = 0
    salvarCfg(cfg)

    local snap = _G.Snap
    if snap and snap.organizarPadrao then
        pcall(function()
            snap.organizarPadrao(getMinimizedWidthDefault(), {
                mode = "minimize",
                managerFrame = frame,
            })
        end)
    end
end

local function confirmarOuArrumarJanelas()
    if UIS.TouchEnabled and not organizeConfirmArmed then
        armOrganizeConfirm()
        return
    end
    arrumarJanelasAgora()
end

local MIN_W_CYCLE = { 220, 240, 260, 280, 300, 320 }
local function cycleMinWidth()
    local cur = getMinimizedWidthDefault()
    local idx = 1
    for i = 1, #MIN_W_CYCLE do
        if MIN_W_CYCLE[i] == cur then
            idx = i
            break
        end
    end
    idx = idx + 1
    if idx > #MIN_W_CYCLE then idx = 1 end
    setMinimizedWidthDefault(MIN_W_CYCLE[idx])
    refreshMinWidthBtn()
    if minimizado then
        frame.Size = UDim2.new(0, getMinimizedWidthDefault(), 0, H_HDR)
    end
end

local function cycleLanguageAndRefresh()
    cycleLanguage()
    refreshLangBtn()
    refreshLanguageUi()
end

local hubCleaned = false
local function cleanupHub(reason)
    if hubCleaned then
        return false
    end
    hubCleaned = true

    if activeInlineDropdownClose then
        pcall(activeInlineDropdownClose)
        activeInlineDropdownClose = nil
    end

    local iconPatchState = _G.__kah_hub_icon_patch_state
    if type(iconPatchState) == "table" and type(iconPatchState.cleanup) == "function" then
        pcall(iconPatchState.cleanup)
    end

    _G.Hub = nil
    _G.KAHLocale = nil

    if gui and gui.Parent then
        pcall(function() gui:Destroy() end)
    end

    if reason == "hub_reload" then
        _G.Snap = nil
    end

    return true
end

minBtn.MouseButton1Click:Connect(toggleMinimizar)
closeBtn.MouseButton1Click:Connect(function()
    cleanupHub("close_button")
end)

-- ============================================
-- API GLOBAL
-- ============================================
_G.Hub = {
    registrar = registrar,
    remover   = remover,
    setNomeVisual = setNomeVisual,
    desligar  = desligar,
    setEstado = setEstado,
    arrumarJanelas = arrumarJanelasAgora,
    getLanguage = function()
        return currentLanguage
    end,
    setLanguage = function(lang)
        currentLanguage = normalizeLang(lang)
        setLanguageDefault(currentLanguage)
        refreshLangBtn()
        refreshLanguageUi()
    end,
    getEstado = function(nome)
        for _, cat in ipairs(cats) do
            for _, m in ipairs(cat.modulos) do
                if m.nome == nome then return m.ativo end
            end
        end
        return false
    end,
    cleanup = cleanupHub,
}

_G.KAHLocale = _G.KAHLocale or {}
_G.KAHLocale.get = function()
    return currentLanguage
end
_G.KAHLocale.set = function(lang)
    currentLanguage = normalizeLang(lang)
    setLanguageDefault(currentLanguage)
    refreshLangBtn()
    refreshLanguageUi()
end

local function registerInternalSettingsRows()
    if not _G.Hub then
        return
    end

    if _G.Hub.remover then
        pcall(function()
            _G.Hub.remover("Language")
        end)
    end

    _G.Hub.registrar("Language", function() end, "Settings", false, {
        inlineDropdown = {
            toggle = false,
            get = function()
                return currentLanguage
            end,
            set = function(v)
                currentLanguage = normalizeLang(v)
                setLanguageDefault(currentLanguage)
                refreshLangBtn()
                refreshLanguageUi()
            end,
            getOptions = function()
                return {
                    { value = "pt-BR", label = "Português (BR)" },
                    { value = "en", label = "English" },
                    { value = "es", label = "Español" },
                }
            end,
            placeholder = "Idioma",
            emptyText = "Sem opcoes",
        },
    })
end

registerInternalSettingsRows()

-- ============================================
-- SNAP SYSTEM
-- Janelas grudam nas bordas umas das outras
-- USA Position.Offset (nao AbsolutePosition)
-- para evitar leituras antes do primeiro render
-- ============================================
do
    local SNAP_DIST = 14    -- pixels para ativar snap
    local janelas   = {}    -- { frame, w, h, salvarPos }

    local function getViewport()
        local cam = workspace.CurrentCamera
        if cam then
            return cam.ViewportSize.X, cam.ViewportSize.Y
        end
        return 1920, 1080
    end

    local function getMenuSafeRect()
        local top = UIS.TouchEnabled and 58 or 42
        local left = UIS.TouchEnabled and 176 or 156
        return {
            l = 0,
            t = 0,
            r = left,
            b = top,
        }
    end

    local function overlapsRect(nx, ny, fw, fh, rect)
        return nx < rect.r and (nx + fw) > rect.l and ny < rect.b and (ny + fh) > rect.t
    end

    local function avoidMenuArea(nx, ny, fw, fh)
        local sw, sh = getViewport()
        local rect = getMenuSafeRect()
        local minX = 4
        local minY = 4
        local maxX = math.max(minX, sw - fw - 4)
        local maxY = math.max(minY, sh - fh - 4)

        nx = math.clamp(nx, minX, maxX)
        ny = math.clamp(ny, minY, maxY)

        if not overlapsRect(nx, ny, fw, fh, rect) then
            return nx, ny
        end

        local rightX = math.clamp(rect.r + 8, minX, maxX)
        local belowY = math.clamp(rect.b + 8, minY, maxY)
        local canMoveRight = rightX <= maxX
        local canMoveDown = belowY <= maxY

        if canMoveRight and not canMoveDown then
            return rightX, ny
        end
        if canMoveDown and not canMoveRight then
            return nx, belowY
        end
        if canMoveRight and canMoveDown then
            if math.abs(rightX - nx) <= math.abs(belowY - ny) then
                return rightX, ny
            end
            return nx, belowY
        end

        return nx, ny
    end

    -- Retorna bounds usando Position.Offset + Size.Offset
    -- (confiaveis antes do primeiro render)
    local function getBounds(entry)
        local f  = entry.frame
        local px = f.Position.X.Offset
        local py = f.Position.Y.Offset
        local sw = f.Size.X.Offset
        local sh = f.Size.Y.Offset
        return { l=px, t=py, r=px+sw, b=py+sh, w=sw, h=sh }
    end

    -- Clamp para manter dentro da tela (margem de 4px)
    local function clampTela(nx, ny, fw, fh)
        return avoidMenuArea(nx, ny, fw, fh)
    end

    local function frameEfetivamenteVisivel(f)
        if not f or not f.Parent then return false end
        local cur = f
        while cur and cur ~= game do
            if cur:IsA("ScreenGui") then
                return cur.Enabled == true and cur.Parent ~= nil
            end
            if cur:IsA("GuiObject") and cur.Visible == false then
                return false
            end
            cur = cur.Parent
        end
        return false
    end

    local function ret(nx, ny, fw, fh)
        return { l = nx, t = ny, r = nx + fw, b = ny + fh, w = fw, h = fh }
    end

    local function sobrepoe(a, b)
        local gap = 8
        return a.l < (b.r + gap) and (a.r + gap) > b.l and a.t < (b.b + gap) and (a.b + gap) > b.t
    end

    local function sobrepoeComLista(r, placed)
        for _, p in ipairs(placed) do
            if sobrepoe(r, p) then
                return true
            end
        end
        return false
    end

    local function acharPosLivre(startX, startY, fw, fh, placed)
        local baseX, baseY = clampTela(startX, startY, fw, fh)
        local baseR = ret(baseX, baseY, fw, fh)
        if not sobrepoeComLista(baseR, placed) then
            return baseX, baseY
        end

        local STEP = 26
        local MAX_RING = 24
        for ring = 1, MAX_RING do
            for dy = -ring, ring do
                for dx = -ring, ring do
                    if math.abs(dx) ~= ring and math.abs(dy) ~= ring then
                        continue
                    end
                    local nx, ny = clampTela(startX + dx * STEP, startY + dy * STEP, fw, fh)
                    local r = ret(nx, ny, fw, fh)
                    if not sobrepoeComLista(r, placed) then
                        return nx, ny
                    end
                end
            end
        end

        local sw, sh = getViewport()
        local maxX = math.max(4, sw - fw - 4)
        local maxY = math.max(4, sh - fh - 4)
        for y = 4, maxY, STEP do
            for x = 4, maxX, STEP do
                local r = ret(x, y, fw, fh)
                if not sobrepoeComLista(r, placed) then
                    return x, y
                end
            end
        end
        return baseX, baseY
    end

    local function organizarSemSobreposicao(salvar)
        local entries = {}
        for _, e in ipairs(janelas) do
            if e.frame and e.frame.Parent and frameEfetivamenteVisivel(e.frame) then
                table.insert(entries, e)
            end
        end
        table.sort(entries, function(a, b)
            local ay = a.frame.Position.Y.Offset
            local by = b.frame.Position.Y.Offset
            if ay == by then
                return a.frame.Position.X.Offset < b.frame.Position.X.Offset
            end
            return ay < by
        end)

        local placed = {}
        for _, e in ipairs(entries) do
            local f = e.frame
            local fw = f.Size.X.Offset
            local fh = f.Size.Y.Offset
            local sx, sy = clampTela(f.Position.X.Offset, f.Position.Y.Offset, fw, fh)
            local nx, ny = acharPosLivre(sx, sy, fw, fh, placed)
            local moved = nx ~= f.Position.X.Offset or ny ~= f.Position.Y.Offset
            if moved then
                f.Position = UDim2.new(0, nx, 0, ny)
                if salvar and e.salvarPos then
                    pcall(e.salvarPos)
                end
            end
            table.insert(placed, ret(nx, ny, fw, fh))
        end
    end

    local function organizarGradePadrao(targetWidth, opts)
        opts = opts or {}
        local mode = opts.mode
        local managerFrame = opts.managerFrame
        targetWidth = math.clamp(math.floor(tonumber(targetWidth) or getMinimizedWidthDefault()), 220, 420)
        local entries = {}
        for _, e in ipairs(janelas) do
            if e.frame and e.frame.Parent and frameEfetivamenteVisivel(e.frame) then
                if managerFrame and e.frame == managerFrame then
                    continue
                end
                if e.normalizar then
                    pcall(e.normalizar, targetWidth, mode)
                end
                table.insert(entries, e)
            end
        end

        table.sort(entries, function(a, b)
            local ay = a.frame.Position.Y.Offset
            local by = b.frame.Position.Y.Offset
            if ay == by then
                return a.frame.Position.X.Offset < b.frame.Position.X.Offset
            end
            return ay < by
        end)

        local sw, sh = getViewport()
        local menuRect = getMenuSafeRect()
        local x = 8
        local y = 8
        local rowH = 0
        local gap = 8

        for _, e in ipairs(entries) do
            local f = e.frame
            local fw = f.Size.X.Offset
            local fh = f.Size.Y.Offset
            if y < (menuRect.b + gap) and x < (menuRect.r + gap) then
                x = menuRect.r + gap
            end
            if x + fw > (sw - 8) then
                x = 8
                y = y + rowH + gap
                rowH = 0
            end

            local nx, ny = clampTela(x, y, fw, fh)
            f.Position = UDim2.new(0, nx, 0, ny)
            if e.salvarPos then
                pcall(e.salvarPos)
            end

            x = nx + fw + gap
            rowH = math.max(rowH, fh)
            if y + rowH > (sh - 8) then
                y = 8
                x = 8
                rowH = 0
            end
        end
    end

    local function snapPos(movingFrame, nx, ny)
        local fw = movingFrame.Size.X.Offset
        local fh = movingFrame.Size.Y.Offset
        local bx, by = nx, ny
        local snappedX, snappedY = false, false

        for _, entry in ipairs(janelas) do
            local f = entry.frame
            if f == movingFrame then continue end
            if not frameEfetivamenteVisivel(f) then continue end
            local b = getBounds(entry)

            -- Snap X
            if not snappedX then
                if math.abs(nx - b.r) < SNAP_DIST then         bx = b.r;      snappedX = true
                elseif math.abs(nx + fw - b.l) < SNAP_DIST then bx = b.l - fw; snappedX = true
                elseif math.abs(nx - b.l) < SNAP_DIST then     bx = b.l;      snappedX = true
                elseif math.abs(nx + fw - b.r) < SNAP_DIST then bx = b.r - fw; snappedX = true end
            end
            -- Snap Y
            if not snappedY then
                if math.abs(ny - b.b) < SNAP_DIST then         by = b.b;      snappedY = true
                elseif math.abs(ny + fh - b.t) < SNAP_DIST then by = b.t - fh; snappedY = true
                elseif math.abs(ny - b.t) < SNAP_DIST then     by = b.t;      snappedY = true
                elseif math.abs(ny + fh - b.b) < SNAP_DIST then by = b.b - fh; snappedY = true end
            end
        end

        return clampTela(bx, by, fw, fh)
    end

    _G.Snap = {
        -- Registra uma janela no sistema de snap
        -- Chame logo apos carregarPos()
        registrar = function(frameRef, salvarPosFn, normalizarFn)
            for _, e in ipairs(janelas) do
                if e.frame == frameRef then
                    e.salvarPos = salvarPosFn
                    e.normalizar = normalizarFn
                    return
                end
            end
            table.insert(janelas, { frame = frameRef, salvarPos = salvarPosFn, normalizar = normalizarFn })
            -- Garante que a janela inicia dentro da tela
            task.defer(function()
                local f  = frameRef
                if not f or not f.Parent then return end
                local fw = f.Size.X.Offset
                local fh = f.Size.Y.Offset
                local nx, ny = clampTela(f.Position.X.Offset, f.Position.Y.Offset, fw, fh)
                if nx ~= f.Position.X.Offset or ny ~= f.Position.Y.Offset then
                    f.Position = UDim2.new(0, nx, 0, ny)
                    if salvarPosFn then salvarPosFn() end
                end
            end)
        end,

        -- Chame a cada frame durante o drag
        mover = function(frameRef, nx, ny)
            local bx, by = snapPos(frameRef, nx, ny)
            frameRef.Position = UDim2.new(0, bx, 0, by)
        end,

        -- Chame ao soltar: aplica snap, clamp e salva
        soltar = function(frameRef)
            local nx = frameRef.Position.X.Offset
            local ny = frameRef.Position.Y.Offset
            local bx, by = snapPos(frameRef, nx, ny)
            frameRef.Position = UDim2.new(0, bx, 0, by)
            for _, e in ipairs(janelas) do
                if e.frame == frameRef and e.salvarPos then
                    e.salvarPos(); break
                end
            end
        end,

        -- Atualiza posicao com base no tamanho atual do frame.
        atualizarTamanho = function(frameRef)
            if not frameRef or not frameRef.Parent then return end
            local fw = frameRef.Size.X.Offset
            local fh = frameRef.Size.Y.Offset
            local nx, ny = clampTela(frameRef.Position.X.Offset, frameRef.Position.Y.Offset, fw, fh)
            if nx ~= frameRef.Position.X.Offset or ny ~= frameRef.Position.Y.Offset then
                frameRef.Position = UDim2.new(0, nx, 0, ny)
                for _, e in ipairs(janelas) do
                    if e.frame == frameRef and e.salvarPos then
                        pcall(e.salvarPos)
                        break
                    end
                end
            end
        end,
        organizarVisiveis = function()
            organizarSemSobreposicao(true)
        end,
        organizarPadrao = function(targetWidth, opts)
            organizarGradePadrao(targetWidth, opts)
        end,
    }
end

-- Processa fila de mÃƒÂ³dulos registrados antes do hub
if _G.HubFila then
    local deduped = {}
    local indexByKey = {}
    for _, item in ipairs(_G.HubFila) do
        local key = moduleNameKey(item and item.nome or "")
        if key == "" then
            key = "__unnamed_" .. tostring(#deduped + 1)
        end
        if indexByKey[key] then
            deduped[indexByKey[key]] = item
        else
            indexByKey[key] = #deduped + 1
            table.insert(deduped, item)
        end
    end
    for _, item in ipairs(deduped) do
        local ok, err = pcall(registrar, item.nome, item.toggleFn, item.categoria, item.jaAtivo, item.opts)
        if not ok then
            warn(">>> HUB: erro ao registrar [" .. tostring(item.nome) .. "]: " .. tostring(err))
        end
    end
    _G.HubFila = nil
end

aplicarLarguraHub(W, EXTRA_H, false)
refreshLanguageUi()


