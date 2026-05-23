-- DatabaseTerminal: Build action tracker
-- Tracks which CTI terminals are Database Terminals via builder menu hooks
-- and hidden locker UGC sync (multiplayer-safe).

local state = require("state")
local visuals = require("visuals")
local tracker = {}

local BUILD_ACTION_NAME = "DA_AxumTrashcanData"
local ACTOR_CLASS = "BP_ComputerTextInterface_Terminal_PlayerBuilt_C"

local lastBuildAction = nil
local terminalActors = {}  -- FName → { pos = {X, Y, Z} }

function tracker.isTerminal(actorFName)
    return terminalActors[actorFName] ~= nil
end

function tracker.getTerminals()
    return terminalActors
end

--- Re-tag terminals from a list of positions (called by sync poll)
local function syncFromPositions(positions)
    local MATCH_DISTANCE = 50
    local terminals = FindAllOf(ACTOR_CLASS)
    if not terminals then return end

    local newActors = {}
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
                    newActors[fname] = { pos = { X = loc.X, Y = loc.Y, Z = loc.Z } }

                    -- Apply visuals if this is a newly discovered terminal
                    if not terminalActors[fname] then
                        print("[DBTerminal] Sync: new terminal " .. fname .. "\n")
                        pcall(function() visuals.apply(terminal) end)
                    end
                    break
                end
            end
        end
    end

    terminalActors = newActors
end

--- Load saved state
function tracker.loadState()
    visuals.clearCache()
    terminalActors = {}

    local loaded = state.load()
    local count = 0
    for k, v in pairs(loaded) do
        terminalActors[k] = v
        count = count + 1
    end

    if count > 0 then
        print(string.format("[DBTerminal] Restored %d terminal(s)\n", count))
        ExecuteWithDelay(2000, function()
            ExecuteInGameThread(function()
                visuals.applyAll(terminalActors)
                print("[DBTerminal] Applied visuals to restored terminals\n")
            end)
        end)
    else
        print("[DBTerminal] No terminals found in save (or actors not loaded yet)\n")
    end
end

--- Initialize hooks
function tracker.init()
    -- Track which recipe the player selected in the builder menu
    RegisterCustomEvent("RecipeClicked", function(self, ...)
        local args = {...}
        if #args > 0 then
            local ok, vm = pcall(function() return args[1]:get() end)
            if ok and vm then
                local actionOk, action = pcall(function() return vm.BuilderAction end)
                if actionOk and action and action:IsValid() then
                    lastBuildAction = action:GetFName():ToString()
                else
                    lastBuildAction = nil
                end
            end
        end
    end)

    -- When construction starts with our build action, tag the new actor
    pcall(function()
        RegisterHook("/Script/Subnautica2.SN2BuilderTool:BeginConstruction", function(self, actorParam)
            if lastBuildAction ~= BUILD_ACTION_NAME then return end

            ExecuteInGameThread(function()
                local existing = {}
                local beds = FindAllOf(ACTOR_CLASS)
                if beds then
                    for _, bed in ipairs(beds) do
                        existing[bed:GetFName():ToString()] = true
                    end
                end

                local attempts = 0
                LoopAsync(500, function()
                    attempts = attempts + 1
                    if attempts > 20 then return true end

                    local ok, found = pcall(function()
                        local currentBeds = FindAllOf(ACTOR_CLASS)
                        if currentBeds then
                            for _, bed in ipairs(currentBeds) do
                                local fname = bed:GetFName():ToString()
                                if not existing[fname] and not terminalActors[fname] then
                                    local loc = bed:K2_GetActorLocation()
                                    terminalActors[fname] = { pos = { X = loc.X, Y = loc.Y, Z = loc.Z } }
                                    -- Write to hidden locker (replicates to all clients)
                                    state.addTerminal(loc)
                                    visuals.apply(bed)
                                    print("[DBTerminal] Tagged terminal: " .. fname .. "\n")
                                    return true
                                end
                            end
                        end
                        return false
                    end)
                    if not ok then return true end
                    return found
                end)
            end)
        end)
    end)

    -- Register sync callback — when hidden locker label changes, re-tag terminals
    state.onSync(function(positions)
        print(string.format("[DBTerminal] [sync] Sync callback fired with %d position(s)\n", #positions))
        ExecuteInGameThread(function()
            syncFromPositions(positions)
        end)
    end)

    -- Initialize hidden locker + sync poll
    ExecuteWithDelay(2000, function()
        ExecuteInGameThread(function()
            pcall(function() state.init() end)
        end)
    end)

    -- Load state on mod reload
    ExecuteWithDelay(3000, function()
        ExecuteInGameThread(function()
            pcall(tracker.loadState)
        end)
    end)

    -- Load state on game start / world change
    RegisterHook("/Script/Subnautica2.SN2PlayerController:OnPossessedPawnChangedFunction", function()
        ExecuteWithDelay(3000, function()
            ExecuteInGameThread(function()
                -- Clear stale cache from previous world
                state.clearCache()

                -- Load from state.json immediately (reliable, always available)
                pcall(tracker.loadState)

                -- Then init hidden locker for multiplayer sync (async, may take a few seconds)
                ExecuteWithDelay(1000, function()
                    ExecuteInGameThread(function()
                        pcall(function() state.init() end)
                    end)
                end)
            end)
        end)
    end)
end

return tracker
