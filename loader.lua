print('[KAH][LOAD] loader.lua')
local VERSION   = "1.0"
local baseUrl = "https://raw.githubusercontent.com/dsantosdev/roblox/refs/heads/main/"
_G.KAH_BASE_URL = baseUrl
local Players = game:GetService("Players")

local INITIAL_TP_CFRAME = CFrame.new(-90, 3, 10)
local INITIAL_TP_CONFIRM_GUI = "KAH_InitialTeleportConfirm"

-- substitua a função loadScript por essa versão com fix de BOM:
local function loadScript(fileName)
    local url = baseUrl .. fileName
    local success, content = pcall(game.HttpGet, game, url)
    
    if not success or not content or #content == 0 then
        warn("[KAH][WARN][LOADER] falha ao baixar '" .. fileName .. "'")
        return
    end
    content = content:gsub("^\xEF\xBB\xBF", "") -- remove BOM UTF-8
    local fn, err = loadstring(content)
    if not fn then
        warn("[KAH][WARN][LOADER] sintaxe em '" .. fileName .. "': " .. tostring(err))
        return
    end
    local ok, runErr = pcall(fn)
    if not ok then
        warn("[KAH][WARN][LOADER] erro ao executar '" .. fileName .. "': " .. tostring(runErr))
    end
end

local function getPlayerGui()
    local lp = Players.LocalPlayer
    if not lp then return nil end

    local pg = lp:FindFirstChildOfClass("PlayerGui")
    if pg then return pg end

    local ok, waited = pcall(function()
        return lp:WaitForChild("PlayerGui", 5)
    end)
    if ok then
        return waited
    end
    return nil
end

local function askInitialTeleportConfirmation(onConfirm)
    local pg = getPlayerGui()
    if not pg then
        warn("[KAH][WARN][LOADER] sem PlayerGui; teleporte inicial ficou manual")
        return
    end

    local oldGui = pg:FindFirstChild(INITIAL_TP_CONFIRM_GUI)
    if oldGui then
        oldGui:Destroy()
    end

    local resolved = false

    local gui = Instance.new("ScreenGui")
    gui.Name = INITIAL_TP_CONFIRM_GUI
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = pg

    local dim = Instance.new("Frame")
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dim.BackgroundTransparency = 0.4
    dim.BorderSizePixel = 0
    dim.Parent = gui

    local card = Instance.new("Frame")
    card.Size = UDim2.new(0, 340, 0, 170)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.BackgroundColor3 = Color3.fromRGB(23, 25, 31)
    card.BorderSizePixel = 0
    card.Parent = dim

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 12)
    cardCorner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(82, 173, 255)
    stroke.Thickness = 1
    stroke.Transparency = 0.2
    stroke.Parent = card

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 16, 0, 14)
    title.Size = UDim2.new(1, -32, 0, 26)
    title.Font = Enum.Font.GothamBold
    title.Text = "Confirmar teleporte inicial"
    title.TextColor3 = Color3.fromRGB(245, 247, 250)
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local body = Instance.new("TextLabel")
    body.BackgroundTransparency = 1
    body.Position = UDim2.new(0, 16, 0, 48)
    body.Size = UDim2.new(1, -32, 0, 56)
    body.Font = Enum.Font.Gotham
    body.Text = "Deseja executar o teleporte inicial agora?"
    body.TextColor3 = Color3.fromRGB(210, 216, 224)
    body.TextSize = 15
    body.TextWrapped = true
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.Parent = card

    local function makeButton(text, bgColor)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.5, -22, 0, 40)
        btn.BackgroundColor3 = bgColor
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = true
        btn.Font = Enum.Font.GothamBold
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 15

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = btn

        return btn
    end

    local noBtn = makeButton("Nao", Color3.fromRGB(84, 89, 99))
    noBtn.Position = UDim2.new(0, 16, 1, -56)
    noBtn.Parent = card

    local yesBtn = makeButton("Sim", Color3.fromRGB(37, 140, 255))
    yesBtn.Position = UDim2.new(0.5, 6, 1, -56)
    yesBtn.Parent = card

    local function finish(confirmed)
        if resolved then return end
        resolved = true
        pcall(function()
            gui:Destroy()
        end)
        if confirmed and type(onConfirm) == "function" then
            task.defer(function()
                local ok, err = pcall(onConfirm)
                if not ok then
                    warn("[KAH][WARN][LOADER] falha no teleporte inicial confirmado: " .. tostring(err))
                end
            end)
        end
    end

    noBtn.MouseButton1Click:Connect(function()
        finish(false)
    end)

    yesBtn.MouseButton1Click:Connect(function()
        finish(true)
    end)
end

loadScript("HUB.LUA")
_G.KAHtpFila = _G.KAHtpFila or {}
table.insert(_G.KAHtpFila, function()
    if _G.KAHtp and _G.KAHtp.teleportar then
        askInitialTeleportConfirmation(function()
            _G.KAHtp.teleportar(INITIAL_TP_CFRAME)
        end)
    end
end)
loadScript("teleporter.lua")
loadScript("claustrum.lua")
loadScript("developer.lua")
loadScript("invencible.lua")
loadScript("player.lua")
loadScript("antiFling.lua")
loadScript("nightSkipMachine.lua")
loadScript("instantOpen.lua")
loadScript("chestOpen.lua")
loadScript("diamonds.lua")
loadScript("chatMode.lua")
loadScript("sendMessage.lua")
loadScript("noDmgBlink.lua")
loadScript("bright.obf.lua")
loadScript("Stronghold.lua")
loadScript("gemCollector.lua")
loadScript("jungleTemple.lua")
loadScript("soundDisable.lua")
