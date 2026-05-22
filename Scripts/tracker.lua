-- DatabaseTerminal: Build action tracker
-- Tracks which BioBeds are our Database Terminals via builder menu hooks

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

--- Load saved state from disk
function tracker.loadState()
    visuals.clearCache()
    terminalActors = {}  -- clear stale entries from previous world
    local loaded = state.load()
    local count = 0
    for k, v in pairs(loaded) do
        terminalActors[k] = v
        count = count + 1
    end
    if count > 0 then
        print(string.format("[DBTerminal] Restored %d terminal(s) from save\n", count))
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

--- Initialize hooks for build action tracking
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
                -- Snapshot existing BioBeds
                local existing = {}
                local beds = FindAllOf(ACTOR_CLASS)
                if beds then
                    for _, bed in ipairs(beds) do
                        existing[bed:GetFName():ToString()] = true
                    end
                end

                -- Poll for new BioBed
                local attempts = 0
                LoopAsync(500, function()
                    attempts = attempts + 1
                    if attempts > 20 then return true end

                    local currentBeds = FindAllOf(ACTOR_CLASS)
                    if currentBeds then
                        for _, bed in ipairs(currentBeds) do
                            local fname = bed:GetFName():ToString()
                            if not existing[fname] and not terminalActors[fname] then
                                local loc = bed:K2_GetActorLocation()
                                terminalActors[fname] = { pos = { X = loc.X, Y = loc.Y, Z = loc.Z } }
                                state.save(terminalActors)
                                visuals.apply(bed)
                                print("[DBTerminal] Tagged terminal: " .. fname .. "\n")
                                return true
                            end
                        end
                    end
                    return false
                end)
            end)
        end)
    end)

    -- Load state on mod reload (immediate, with delay for world to be ready)
    ExecuteWithDelay(2000, function()
        ExecuteInGameThread(tracker.loadState)
    end)

    -- Load state on fresh game start (OnPossessedPawn fires when player spawns)
    RegisterHook("/Script/Subnautica2.SN2PlayerController:OnPossessedPawnChangedFunction", function()
        ExecuteWithDelay(3000, function()
            ExecuteInGameThread(tracker.loadState)
        end)
    end)
end

return tracker
