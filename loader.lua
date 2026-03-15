print('[KAH][LOAD] loader.lua')
local VERSION   = "1.0"
local baseUrl = "https://raw.githubusercontent.com/dsantosdev/roblox/refs/heads/main/"

local function loadScript(fileName)
    local url = baseUrl .. fileName
    local success, content = pcall(game.HttpGet, game, url)
    
    if not success or not content or #content == 0 then
        warn("[KAH][WARN][LOADER] falha ao baixar '" .. fileName .. "'")
        return
    end
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

loadScript("HUB.LUA")
_G.KAHtpFila = _G.KAHtpFila or {}
table.insert(_G.KAHtpFila, function()
    if _G.KAHtp and _G.KAHtp.teleportar then
        _G.KAHtp.teleportar(CFrame.new(-90, 3, 10))
    end
end)
loadScript("teleporter.lua")
loadScript("developer.lua")
loadScript("invencible.lua")
loadScript("player.lua")
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
