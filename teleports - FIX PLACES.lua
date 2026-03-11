local player = game:GetService("Players").LocalPlayer

local tpLocations = {
    ["Campfire"]   = "Map.Campground.MainFire.InnerTouchZone",
    ["AlienShip"]  = "Map.Landmarks.AlienMothership.StartRoom.Teleporter.Meshes/teleporteralien_Cylinder.001",
    ["Stronghold"] = "Map.Landmarks.Stronghold.Building.Sign.Main",
    ["Anvil"]      = "Map.Landmarks.ToolWorkshop.Main",
}

local function doTeleport(path)
    pcall(function()
        local target = workspace
        for part in path:gmatch("[^.]+") do 
            target = target[part] 
        end
        
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            char.HumanoidRootPart.CFrame = target.CFrame + Vector3.new(0, 5, 0)
        end
    end)
end

-- Exemplo de como chamar (você pode vincular a botões no seu HUB futuramente):
-- doTeleport(tpLocations["Campfire"])

-- Exporta a tabela globalmente caso seu HUB precise acessar
_G.TeleportTo = doTeleport
_G.TpLocations = tpLocations