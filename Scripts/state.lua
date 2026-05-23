-- DatabaseTerminal: Multiplayer-safe state via hidden locker UGC label
-- A tiny invisible locker is spawned underground. Its label stores terminal
-- positions as a serialized string. The game's save system persists it and
-- ServerSetPlayerText replicates it to all clients automatically.
--
-- Label format: "DBT|x1,y1,z1|x2,y2,z2|..."
-- Each segment is a terminal position (rounded to integers).

local UEHelpers = require("UEHelpers")
local config = require("config")
local state = {}

local MATCH_DISTANCE = 50    -- units (0.5m) for position matching
local DBT_PREFIX = "DBT"     -- label prefix to identify our hidden locker
local POLL_INTERVAL = 3000   -- ms between sync polls
local ACTOR_CLASS = "BP_ComputerTextInterface_Terminal_PlayerBuilt_C"
local STATE_FILE = config.ModDir .. "state.json"

local cachedUGC = nil         -- cached UWEUGCComponent on the hidden locker
local lastLabelString = ""    -- last known label for change detection
local onSyncCallback = nil    -- called when label changes (set by tracker)

----------------------------------------------------------------------
-- Label serialization
----------------------------------------------------------------------

--- Encode terminal positions into a label string
local function encodePositions(positions)
    local parts = { DBT_PREFIX }
    for _, p in ipairs(positions) do
        table.insert(parts, string.format("%.0f,%.0f,%.0f", p.x, p.y, p.z))
    end
    return table.concat(parts, "|")
end

--- Decode a label string into position table
local function decodePositions(label)
    local positions = {}
    if not label or not label:find("^" .. DBT_PREFIX) then return positions end
    local first = true
    for segment in label:gmatch("[^|]+") do
        if first then
            first = false  -- skip "DBT" prefix
        else
            local x, y, z = segment:match("([%-%.%d]+),([%-%.%d]+),([%-%.%d]+)")
            if x then
                table.insert(positions, {
                    x = tonumber(x),
                    y = tonumber(y),
                    z = tonumber(z),
                })
            end
        end
    end
    return positions
end

----------------------------------------------------------------------
-- Hidden locker management
----------------------------------------------------------------------

--- Find the hidden locker by scanning UGC labels for DBT prefix.
--- Caches the result for future reads.
local function findHiddenLocker()
    if cachedUGC then
        local valid = false
        pcall(function() valid = cachedUGC:IsValid() end)
        if valid then return cachedUGC end
        print("[DBTerminal] [sync] Cached locker invalid, re-scanning\n")
        cachedUGC = nil
    end

    local allUGC = FindAllOf("UWEUGCComponent")
    if not allUGC then return nil end

    local scanned = 0
    for _, ugc in ipairs(allUGC) do
        scanned = scanned + 1
        pcall(function()
            if ugc:IsValid() and ugc:HasUserGeneratedContent() then
                local texts = ugc.PlayerTexts
                if texts and #texts > 0 then
                    local val = texts[1].Value:ToString()
                    if val and val:find("^" .. DBT_PREFIX) then
                        cachedUGC = ugc
                        print(string.format("[DBTerminal] [sync] Found hidden locker (scanned %d UGC components)\n", scanned))
                    end
                end
            end
        end)
        if cachedUGC then break end
    end

    return cachedUGC
end

--- Spawn the hidden locker underground. Only when in a valid world.
local function spawnHiddenLocker()
    local pc = UEHelpers:GetPlayerController()
    if not pc then return nil end
    local hasPawn = false
    pcall(function() hasPawn = pc.Pawn and pc.Pawn:IsValid() end)
    if not hasPawn then return nil end
    local pos = pc.Pawn:K2_GetActorLocation()

    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local lockers = FindAllOf("BP_Locker_Floor_C")
    if not gs or not lockers or #lockers == 0 then return nil end

    local lockerClass = lockers[1]:GetClass()
    local spawnTransform = {
        Translation = { X = pos.X, Y = pos.Y, Z = pos.Z - 500 },
        Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
        Scale3D = { X = 0.01, Y = 0.01, Z = 0.01 },
    }

    local actor = nil
    pcall(function()
        actor = gs:BeginDeferredActorSpawnFromClass(pc, lockerClass, spawnTransform, 1, nil, 0)
        if actor then
            actor = gs:FinishSpawningActor(actor, spawnTransform, 0)
        end
    end)

    if not actor then
        print("[DBTerminal] Failed to spawn hidden locker\n")
        return nil
    end

    print("[DBTerminal] Hidden locker spawned\n")

    -- Write initial empty label after component init
    ExecuteWithDelay(1000, function()
        ExecuteInGameThread(function()
            local ugc = nil
            local actorFName = nil
            pcall(function() actorFName = actor:GetFName():ToString() end)

            local allUGC = FindAllOf("UWEUGCComponent")
            if allUGC and actorFName then
                for _, u in ipairs(allUGC) do
                    pcall(function()
                        if u:IsValid() then
                            local owner = u:GetOwner()
                            if owner and owner:GetFName():ToString() == actorFName then
                                ugc = u
                            end
                        end
                    end)
                    if ugc then break end
                end
            end

            if ugc then
                pcall(function()
                    ugc:ServerSetPlayerText({ TagName = FName("None") }, DBT_PREFIX)
                end)
                cachedUGC = ugc
                lastLabelString = DBT_PREFIX
                print("[DBTerminal] Hidden locker initialized with DBT label\n")
            else
                print("[DBTerminal] Could not find UGC on spawned locker\n")
            end
        end)
    end)

    return actor
end

----------------------------------------------------------------------
-- Read/write label
----------------------------------------------------------------------

--- Read the current label from the hidden locker
local function readLabel()
    local ugc = findHiddenLocker()
    if not ugc then return nil end
    local label = nil
    pcall(function()
        local texts = ugc.PlayerTexts
        if texts and #texts > 0 then
            label = texts[1].Value:ToString()
        end
    end)
    return label
end

--- Write a new label to the hidden locker (server RPC — replicates to all clients)
local function writeLabel(label)
    local ugc = findHiddenLocker()
    if not ugc then return false end
    local ok = pcall(function()
        ugc:ServerSetPlayerText({ TagName = FName("None") }, label)
    end)
    if ok then
        lastLabelString = label
        print(string.format("[DBTerminal] [sync] Wrote label: %s\n", label))
    else
        print("[DBTerminal] [sync] Label write FAILED\n")
    end
    return ok
end

----------------------------------------------------------------------
-- Position matching
----------------------------------------------------------------------

--- Match saved positions against world terminals, return terminalActors table
local function matchTerminals(positions)
    local terminalActors = {}
    if #positions == 0 then return terminalActors end

    local terminals = FindAllOf(ACTOR_CLASS)
    if not terminals then return terminalActors end

    for _, terminal in ipairs(terminals) do
        if terminal:IsValid() then
            local loc = terminal:K2_GetActorLocation()
            for _, saved in ipairs(positions) do
                local dx = loc.X - saved.x
                local dy = loc.Y - saved.y
                local dz = loc.Z - saved.z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist < MATCH_DISTANCE then
                    local fname = terminal:GetFName():ToString()
                    terminalActors[fname] = { pos = { X = loc.X, Y = loc.Y, Z = loc.Z } }
                    break
                end
            end
        end
    end

    return terminalActors
end

----------------------------------------------------------------------
-- Local state.json persistence (host-side, survives across sessions)
----------------------------------------------------------------------

--- Read positions from state.json (flat array of positions)
local function readStateFile()
    local f = io.open(STATE_FILE, "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()
    local positions = {}
    for x, y, z in content:gmatch('"x":([%-%.%d]+),"y":([%-%.%d]+),"z":([%-%.%d]+)') do
        table.insert(positions, { x = tonumber(x), y = tonumber(y), z = tonumber(z) })
    end
    return positions
end

--- Write positions to state.json
local function writeStateFile(positions)
    local entries = {}
    for _, p in ipairs(positions) do
        table.insert(entries, string.format('{"x":%.0f,"y":%.0f,"z":%.0f}', p.x, p.y, p.z))
    end
    local json = "[\n  " .. table.concat(entries, ",\n  ") .. "\n]"
    local f = io.open(STATE_FILE, "w")
    if f then f:write(json); f:close() end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Clear cached locker reference (call on world change)
function state.clearCache()
    cachedUGC = nil
    lastLabelString = ""
end

--- Set callback for when synced state changes (called by tracker)
function state.onSync(callback)
    onSyncCallback = callback
end

--- Initialize: find or spawn hidden locker, populate from state.json, start sync poll
function state.init()
    -- Try to find existing hidden locker (client joining host's game)
    local ugc = findHiddenLocker()
    if ugc then
        print("[DBTerminal] Found existing hidden locker\n")
    else
        -- No hidden locker — spawn one and populate from state.json
        print("[DBTerminal] No hidden locker found — spawning\n")
        spawnHiddenLocker()

        -- After locker initializes, write state.json positions to it
        ExecuteWithDelay(2000, function()
            ExecuteInGameThread(function()
                local positions = readStateFile()
                if #positions > 0 then
                    local label = encodePositions(positions)
                    if writeLabel(label) then
                        print(string.format("[DBTerminal] Populated locker from state.json: %d terminal(s)\n", #positions))
                    end
                end
            end)
        end)
    end

    -- Start sync poll
    print("[DBTerminal] [sync] Starting poll loop (every " .. POLL_INTERVAL .. "ms)\n")
    LoopAsync(POLL_INTERVAL, function()
        local label = readLabel()
        if not label then return false end  -- locker not found yet, keep trying

        if label ~= lastLabelString then
            print(string.format("[DBTerminal] [sync] Label changed: '%s' -> '%s'\n",
                lastLabelString, label))
            lastLabelString = label
            local positions = decodePositions(label)
            print(string.format("[DBTerminal] [sync] Parsed %d terminal position(s)\n", #positions))
            if onSyncCallback then
                pcall(function() onSyncCallback(positions) end)
            end
        end
        return false
    end)
end

--- Load current state: try hidden locker first, fallback to state.json
function state.load()
    local positions = {}

    -- Try hidden locker (multiplayer: client reads host's locker)
    local label = readLabel()
    if label and label ~= DBT_PREFIX then
        lastLabelString = label
        positions = decodePositions(label)
        print(string.format("[DBTerminal] Loaded %d terminal(s) from hidden locker\n", #positions))
    end

    -- Fallback to state.json (singleplayer or host before locker init)
    if #positions == 0 then
        positions = readStateFile()
        if #positions > 0 then
            print(string.format("[DBTerminal] Loaded %d terminal(s) from state.json\n", #positions))
        else
            print("[DBTerminal] No terminal positions found\n")
        end
    end

    return matchTerminals(positions)
end

--- Save terminal positions to both hidden locker and state.json
function state.save(terminalActors)
    local positions = {}
    for _, data in pairs(terminalActors) do
        if data.pos then
            table.insert(positions, { x = data.pos.X, y = data.pos.Y, z = data.pos.Z })
        end
    end
    local label = encodePositions(positions)
    writeLabel(label)
    writeStateFile(positions)
    print(string.format("[DBTerminal] Saved %d terminal(s)\n", #positions))
end

--- Add a single terminal position (read-modify-write, writes to both)
function state.addTerminal(pos)
    print(string.format("[DBTerminal] [sync] Adding terminal at %.0f,%.0f,%.0f\n", pos.X, pos.Y, pos.Z))
    local positions = readStateFile()
    table.insert(positions, { x = pos.X, y = pos.Y, z = pos.Z })
    writeStateFile(positions)
    print(string.format("[DBTerminal] [sync] state.json now has %d position(s)\n", #positions))
    local label = encodePositions(positions)
    writeLabel(label)
end

--- Remove a terminal position by matching (writes to both)
function state.removeTerminal(pos)
    print(string.format("[DBTerminal] [sync] Removing terminal near %.0f,%.0f,%.0f\n", pos.X, pos.Y, pos.Z))
    local label = readLabel() or DBT_PREFIX
    local positions = decodePositions(label)
    local newPositions = {}
    for _, p in ipairs(positions) do
        local dx = p.x - pos.X
        local dy = p.y - pos.Y
        local dz = p.z - pos.Z
        if math.sqrt(dx*dx + dy*dy + dz*dz) >= MATCH_DISTANCE then
            table.insert(newPositions, p)
        end
    end
    print(string.format("[DBTerminal] [sync] Removed, %d -> %d positions\n", #positions, #newPositions))
    writeLabel(encodePositions(newPositions))
    writeStateFile(newPositions)
end

return state
