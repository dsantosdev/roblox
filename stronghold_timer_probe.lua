-- Stronghold timer probe (isolated diagnostic)
-- Goal: find GUI texts like "07m 50s", log to clipboard, and keep live updates.

local STATE_KEY = "__kah_stronghold_timer_probe"

do
    local old = _G[STATE_KEY]
    if old and old.cleanup then
        pcall(old.cleanup)
    end
    _G[STATE_KEY] = nil
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local lp = Players.LocalPlayer
local MAX_LINES = 220
local SCAN_INTERVAL = 1.5

local lines = {}
local watched = {}
local conns = {}
local lastTimerText = {}
local running = true

local function copyClipboard(text)
    if setclipboard then
        pcall(setclipboard, text)
    elseif toclipboard then
        pcall(toclipboard, text)
    end
end

local function push(msg)
    local line = os.date("%H:%M:%S") .. " | " .. tostring(msg)
    print(">>> timer-probe: " .. line)
    table.insert(lines, line)
    if #lines > MAX_LINES then
        table.remove(lines, 1)
    end
    local dump = table.concat(lines, "\n")
    _G.__kah_stronghold_timer_probe_log = dump
    copyClipboard(dump)
end

local function pathOf(inst)
    if not inst then return "nil" end
    local names = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(names, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(names, ".")
end

local function parseTimer(text)
    if type(text) ~= "string" then return nil end
    local m, s = string.match(text, "(%d+)%s*[mM]%s*(%d+)%s*[sS]")
    if m and s then
        return tonumber(m), tonumber(s)
    end
    local mm, ss = string.match(text, "(%d+)%s*:%s*(%d+)")
    if mm and ss then
        return tonumber(mm), tonumber(ss)
    end
    return nil
end

local function nearestStrongholdRoot()
    local root
    pcall(function()
        root = workspace.Map.Landmarks.Stronghold
    end)
    if root then return root end
    return workspace
end

local function logTimer(inst, origin)
    local txt = inst and inst.Text
    local m, s = parseTimer(txt)
    if not m or not s then return false end
    if lastTimerText[inst] == txt and origin ~= "changed" then
        return false
    end
    lastTimerText[inst] = txt
    local secs = (m * 60) + s
    push(string.format(
        "timer[%s] %02dm %02ds (%ds) path=%s class=%s",
        origin,
        m, s, secs,
        pathOf(inst),
        inst.ClassName
    ))
    return true
end

local function watchTextInstance(inst)
    if watched[inst] then return end
    watched[inst] = true

    logTimer(inst, "initial")

    local c1 = inst:GetPropertyChangedSignal("Text"):Connect(function()
        logTimer(inst, "changed")
    end)
    local c2 = inst.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            if conns[inst] then
                for _, c in ipairs(conns[inst]) do
                    pcall(function() c:Disconnect() end)
                end
            end
            conns[inst] = nil
            watched[inst] = nil
        end
    end)
    conns[inst] = { c1, c2 }
end

local function scanOnce()
    local root = nearestStrongholdRoot()
    local total = 0
    local timersNow = 0
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
            total = total + 1
            watchTextInstance(d)
            local m, s = parseTimer(d.Text)
            if m and s then
                timersNow = timersNow + 1
                logTimer(d, "scan")
            end
        end
    end
    push(string.format("scan done root=%s textNodes=%d timers=%d", pathOf(root), total, timersNow))
end

local function cleanup()
    running = false
    for _, list in pairs(conns) do
        for _, c in ipairs(list) do
            pcall(function() c:Disconnect() end)
        end
    end
    conns = {}
    watched = {}
    lastTimerText = {}
    push("probe stopped")
end

_G[STATE_KEY] = {
    cleanup = cleanup
}

push("probe started; clipboard logging active")
scanOnce()

task.spawn(function()
    while running do
        task.wait(SCAN_INTERVAL)
        if not running then break end
        scanOnce()
    end
end)
