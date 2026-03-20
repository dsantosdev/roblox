print('[KAH][LOAD] loader.lua')
local VERSION   = "1.0"
local baseUrl = "https://raw.githubusercontent.com/dsantosdev/roblox/refs/heads/main/"
_G.KAH_BASE_URL = baseUrl

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

loadScript("HUB.LUA")
_G.KAHtpFila = _G.KAHtpFila or {}
loadScript("teleporter.lua")
loadScript("claustrum.lua")
loadScript("leviosaCfg.lua")
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
