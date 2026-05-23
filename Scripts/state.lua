-- DatabaseTerminal: State persistence
-- Saves terminal locations to disk, re-tags on mod reload by position matching.
-- State is keyed by save slot name (e.g. "Slot1") so terminals from different
-- saves don't interfere with each other.

local state = {}

-- State stored outside mod folder so it survives mod updates
local MOD_DIR = debug.getinfo(1, "S").source:match("@(.*/)")  .. "../"
local DATA_DIR = MOD_DIR .. "../DatabaseTerminal_data/"
local STATE_FILE = DATA_DIR .. "state.json"

-- Ensure data directory exists
pcall(function() os.execute('mkdir "' .. DATA_DIR:gsub("/", "\\") .. '" 2>nul') end)
local MATCH_DISTANCE = 50  -- units (0.5 meters) — tolerance for position matching

----------------------------------------------------------------------
-- Save slot identification
----------------------------------------------------------------------

--- Get the current save slot name (e.g. "Slot1", "Slot2").
--- Stable across loads of the same save. Returns "default" if unavailable.
local function getSlotName()
    local slot = nil
    pcall(function()
        local save = FindFirstOf("UWESaveGame")
        if save and save:IsValid() then
            -- Try MetaData.SlotName property directly
            pcall(function()
                slot = save.MetaData.SlotName:ToString()
            end)
            -- Fallback: GetSlotName() method
            if not slot or slot == "" or slot:find("^FString:") then
                pcall(function()
                    local name = save:GetSlotName()
                    slot = type(name) == "string" and name or name:ToString()
                end)
            end
        end
    end)
    print(string.format("[DBTerminal] Save slot: %s\n", tostring(slot)))
    if not slot or slot == "" or slot:find("^FString:") then slot = "default" end
    return slot
end

----------------------------------------------------------------------
-- File I/O helpers
----------------------------------------------------------------------

--- Read the full state file (all slots). Format: { "Slot1": [...], "Slot2": [...] }
local function readAllState()
    local f = io.open(STATE_FILE, "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()

    local allState = {}
    for slotId, block in content:gmatch('"([^"]+)"%s*:%s*(%b[])') do
        local positions = {}
        for fname, x, y, z in block:gmatch('"fname":"([^"]+)","x":([%-%.%d]+),"y":([%-%.%d]+),"z":([%-%.%d]+)') do
            table.insert(positions, {
                fname = fname,
                x = tonumber(x),
                y = tonumber(y),
                z = tonumber(z),
            })
        end
        allState[slotId] = positions
    end
    return allState
end

--- Write the full state table back to disk.
local function writeAllState(allState)
    local slotBlocks = {}
    for slotId, positions in pairs(allState) do
        local entries = {}
        for _, p in ipairs(positions) do
            table.insert(entries, string.format('{"fname":"%s","x":%.0f,"y":%.0f,"z":%.0f}',
                p.fname, p.x, p.y, p.z))
        end
        table.insert(slotBlocks, string.format('  "%s": [\n    %s\n  ]',
            slotId, table.concat(entries, ",\n    ")))
    end
    local json = "{\n" .. table.concat(slotBlocks, ",\n") .. "\n}"
    local f = io.open(STATE_FILE, "w")
    if f then
        f:write(json)
        f:close()
    end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Save terminal positions for the current save slot
function state.save(terminalActors)
    local slotName = getSlotName()
    local allState = readAllState()

    local positions = {}
    for fname, data in pairs(terminalActors) do
        if data.pos then
            table.insert(positions, {
                fname = fname,
                x = data.pos.X,
                y = data.pos.Y,
                z = data.pos.Z,
            })
        end
    end

    -- Update only this slot's entry, preserve other slots
    allState[slotName] = positions
    writeAllState(allState)
end

--- Load saved positions for the current save slot and re-tag matching terminals
function state.load()
    local terminalActors = {}
    local slotName = getSlotName()
    local allState = readAllState()
    local savedPositions = allState[slotName]

    if not savedPositions or #savedPositions == 0 then
        print(string.format("[DBTerminal] No terminals saved for slot %s\n", slotName))
        return terminalActors
    end
    print(string.format("[DBTerminal] State file has %d saved position(s) for slot %s\n",
        #savedPositions, slotName))

    local terminals = FindAllOf("BP_ComputerTextInterface_Terminal_PlayerBuilt_C")
    if not terminals then
        print("[DBTerminal] FindAllOf returned nil — actors not loaded yet\n")
        return terminalActors
    end
    print(string.format("[DBTerminal] Found %d CTI terminals in world\n", #terminals))

    for _, terminal in ipairs(terminals) do
        if terminal:IsValid() then
            local loc = terminal:K2_GetActorLocation()
            for _, saved in ipairs(savedPositions) do
                local dx = loc.X - saved.x
                local dy = loc.Y - saved.y
                local dz = loc.Z - saved.z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist < MATCH_DISTANCE then
                    local fname = terminal:GetFName():ToString()
                    terminalActors[fname] = { pos = { X = loc.X, Y = loc.Y, Z = loc.Z } }
                    print("[DBTerminal] Re-tagged terminal from save: " .. fname .. "\n")
                    break
                end
            end
        end
    end

    return terminalActors
end

return state
