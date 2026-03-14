print('[KAH][LOAD] jungle_chests_probe.lua')

local STATE_KEY = "__kah_jungle_chests_probe"

do
    local old = _G[STATE_KEY]
    if old and old.cleanup then
        pcall(old.cleanup)
    end
    _G[STATE_KEY] = nil
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local lp = Players.LocalPlayer
local PLACE_ID = game.PlaceId
local JOB_ID = (type(game.JobId) == "string" and game.JobId ~= "" and game.JobId) or "single"
local SCAN_INTERVAL = 1.5

local running = true
local hb = nil
local acc = 0
local lastDump = nil

local TARGETS = {
    "JungleChest1",
    "JungleChest2",
    "JungleChest3",
    "JungleChest4",
}

local function copyClipboard(text)
    if setclipboard then
        pcall(setclipboard, text)
    elseif toclipboard then
        pcall(toclipboard, text)
    end
end

local function pathOf(inst)
    if not inst then return "nil" end
    local parts = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
end

local function getWorldPosition(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then
        return obj.Position
    end
    if obj:IsA("Model") then
        local ok, pivot = pcall(function()
            return obj:GetPivot()
        end)
        if ok and pivot then
            return pivot.Position
        end
        local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.Position
        end
    end
    local part = obj:FindFirstChildWhichIsA("BasePart", true)
    if part then
        return part.Position
    end
    return nil
end

local function scanPodiumCenter()
    local sum = Vector3.new(0, 0, 0)
    local count = 0
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst.Name == "JungleGemPodium" then
            local pos = getWorldPosition(inst)
            if pos then
                sum += pos
                count += 1
            end
        end
    end
    if count <= 0 then
        return nil, 0
    end
    return (sum / count), count
end

local function fmtVec3(v)
    if not v then return "nil" end
    return string.format("(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
end

local function luaVec3(v)
    if not v then return "nil" end
    return string.format("Vector3.new(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
end

local function findExact(name)
    local obj = workspace:FindFirstChild(name, true)
    if obj then
        return obj
    end
    local items = workspace:FindFirstChild("Items")
    if items then
        return items:FindFirstChild(name, true)
    end
    return nil
end

local function buildDump()
    local center, podiumCount = scanPodiumCenter()
    local payload = {
        placeId = PLACE_ID,
        jobId = JOB_ID,
        user = {
            name = lp.Name,
            userId = lp.UserId,
        },
        podiumCount = podiumCount,
        templeCenter = center and { x = center.X, y = center.Y, z = center.Z } or nil,
        chests = {},
    }

    local lines = {
        "JUNGLE_CHESTS_PROBE",
        string.format("place=%s | job=%s | user=%s(%s)", tostring(PLACE_ID), tostring(JOB_ID), lp.Name, tostring(lp.UserId)),
        string.format("podiums=%d", podiumCount),
        "temple_center=" .. fmtVec3(center),
        "lua_temple_center=" .. luaVec3(center),
    }

    for _, name in ipairs(TARGETS) do
        local obj = findExact(name)
        local pos = getWorldPosition(obj)
        local item = {
            found = obj ~= nil,
            path = pathOf(obj),
        }
        if pos then
            item.pos = { x = pos.X, y = pos.Y, z = pos.Z }
            if center then
                item.delta = {
                    x = pos.X - center.X,
                    y = pos.Y - center.Y,
                    z = pos.Z - center.Z,
                    distance = (pos - center).Magnitude,
                }
            end
        end
        payload.chests[name] = item

        table.insert(lines, string.format("%s=%s", name, fmtVec3(pos)))
        table.insert(lines, string.format("lua_%s=%s", name, luaVec3(pos)))
        table.insert(lines, string.format("path_%s=%s", name, pathOf(obj)))
        if pos and center then
            table.insert(lines, string.format(
                "delta_%s=(%.3f, %.3f, %.3f) dist=%.3f",
                name,
                pos.X - center.X,
                pos.Y - center.Y,
                pos.Z - center.Z,
                (pos - center).Magnitude
            ))
        end
    end

    table.insert(lines, "json=" .. HttpService:JSONEncode(payload))
    return table.concat(lines, "\n")
end

local function scanAndCopy()
    local dump = buildDump()
    if dump ~= lastDump then
        lastDump = dump
        _G.__kah_jungle_chests_probe_dump = dump
        copyClipboard(dump)
    end
end

local function cleanup()
    running = false
    if hb then
        pcall(function()
            hb:Disconnect()
        end)
        hb = nil
    end
end

_G.KAH_StopJungleChestsProbe = cleanup
_G[STATE_KEY] = {
    cleanup = cleanup,
}

scanAndCopy()

hb = RunService.Heartbeat:Connect(function(dt)
    if not running then return end
    acc += dt
    if acc < SCAN_INTERVAL then return end
    acc = 0
    scanAndCopy()
end)

