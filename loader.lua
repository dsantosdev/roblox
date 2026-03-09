
local VERSION   = "1.0"
local baseUrl = "https://raw.githubusercontent.com/dsantosdev/roblox/refs/heads/main/"

local function loadScript(fileName)
    local url = baseUrl .. fileName
    local success, content = pcall(game.HttpGet, game, url, true)
    
    if success and content and #content > 0 then
        loadstring(content)()
    else
        warn("Erro: Arquivo " .. fileName .. " nao encontrado ou falha no download.")
    end
end

loadScript("HUB.LUA")
loadScript("invencible.lua")
loadScript("player.lua")
loadScript("teleporter.lua")
loadScript("nightSkipMachine.lua")
loadScript("instantOpen.lua")
loadScript("chestOpen.lua")
loadScript("diamonds.lua")
loadScript("chatMode.lua")
loadScript("killAura.lua")
loadScript("suppressor.lua")
loadScript("noDmgBlink.lua")