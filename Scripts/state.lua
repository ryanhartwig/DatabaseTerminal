-- DatabaseTerminal: State persistence
-- Saves terminal locations to disk, re-tags on mod reload by position matching

local state = {}

local STATE_FILE = debug.getinfo(1, "S").source:match("@(.*/)")  .. "../state.json"
local MATCH_DISTANCE = 50  -- units (0.5 meters) — tolerance for position matching

--- Save terminal positions to disk
function state.save(terminalActors)
    local entries = {}
    for fname, data in pairs(terminalActors) do
        if data.pos then
            table.insert(entries, string.format('{"fname":"%s","x":%.0f,"y":%.0f,"z":%.0f}',
                fname, data.pos.X, data.pos.Y, data.pos.Z))
        end
    end
    local json = "[\n  " .. table.concat(entries, ",\n  ") .. "\n]"
    local f = io.open(STATE_FILE, "w")
    if f then
        f:write(json)
        f:close()
    end
end

--- Load saved positions and re-tag matching BioBeds
--- Returns terminalActors table
function state.load()
    local terminalActors = {}

    local f = io.open(STATE_FILE, "r")
    if not f then return terminalActors end
    local content = f:read("*all")
    f:close()

    -- Parse saved positions
    local savedPositions = {}
    for fname, x, y, z in content:gmatch('"fname":"([^"]+)","x":([%-%.%d]+),"y":([%-%.%d]+),"z":([%-%.%d]+)') do
        table.insert(savedPositions, {
            fname = fname,
            x = tonumber(x),
            y = tonumber(y),
            z = tonumber(z),
        })
    end

    if #savedPositions == 0 then return terminalActors end
    print(string.format("[DBTerminal] State file has %d saved position(s)\n", #savedPositions))

    -- Find terminals and match by position
    local beds = FindAllOf("BP_ComputerTextInterface_Terminal_PlayerBuilt_C")
    if not beds then
        print("[DBTerminal] FindAllOf returned nil — actors not loaded yet\n")
        return terminalActors
    end
    print(string.format("[DBTerminal] Found %d CTI terminals in world\n", #beds))

    for _, bed in ipairs(beds) do
        if bed:IsValid() then
            local loc = bed:K2_GetActorLocation()
            for _, saved in ipairs(savedPositions) do
                local dx = loc.X - saved.x
                local dy = loc.Y - saved.y
                local dz = loc.Z - saved.z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist < MATCH_DISTANCE then
                    local fname = bed:GetFName():ToString()
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
