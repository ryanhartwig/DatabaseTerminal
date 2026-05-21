-- DatabaseTerminal: Scanner module
-- Discovers nearby containers and collects all item data

local UEHelpers = require("UEHelpers")
local scanner = {}

--- Get distance between a position and an actor
local function getDistanceFromPos(pos, actor)
    local loc = actor:K2_GetActorLocation()
    local dx = pos.X - loc.X
    local dy = pos.Y - loc.Y
    local dz = pos.Z - loc.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Read locker label from UGCComponent
local function getLockerLabel(actor)
    local ugc = actor.UGCComponent
    if not ugc or not ugc:IsValid() then return nil end
    local ok, hasContent = pcall(function() return ugc:HasUserGeneratedContent() end)
    if not ok or not hasContent then return nil end

    local texts = ugc.PlayerTexts
    if not texts then return nil end

    for i = 1, #texts do
        local val = texts[i].Value:ToString()
        if val and not val:match("^FString: 0x") then
            local trimmed = val:match("^%s*(.-)%s*$")
            if trimmed ~= "" then return trimmed end
        end
    end
    return nil
end

--- Scan all nearby containers and return a flat table of item entries
--- @param terminalPos table {X, Y, Z} position of the terminal actor
--- @param radiusMeters number scan radius in meters
--- @return table items, number containerCount
function scanner.scan(terminalPos, radiusMeters)
    local radiusUnits = radiusMeters * 100  -- UE uses centimeters

    local containerSources = {
        { class = "SN2Locker",                  getInv = function(a) return a.Inventory end,            labelFn = getLockerLabel },
        { class = "BP_Tailing_Chest_C",         getInv = function(a) return a.InventoryComponent end,   labelFn = function() return "Tailing Chest" end },
        { class = "BP_BasicBatteryTerminal_C",   getInv = function(a) return a.InventoryComponent end,  labelFn = function() return "Battery Charger" end },
        { class = "BP_PowerCellTerminal_C",      getInv = function(a) return a.InventoryComponent end,  labelFn = function() return "Power Cell Charger" end },
    }

    local items = {}
    local containerCount = 0

    for _, source in ipairs(containerSources) do
        local actors = FindAllOf(source.class)
        if actors then
            for _, actor in ipairs(actors) do
                if actor:IsValid() then
                    local dist = getDistanceFromPos(terminalPos, actor)
                    if dist <= radiusUnits then
                        local invOk, inv = pcall(function() return source.getInv(actor) end)
                        if invOk and inv and inv:IsValid() then
                            local isEmpty = inv:IsEmpty()
                            if not isEmpty then
                                containerCount = containerCount + 1
                                local label = nil
                                pcall(function() label = source.labelFn(actor) end)
                                if not label then label = source.class end

                                local invId = inv.InventoryId
                                local invItems = inv:GetItems()
                                if invItems then
                                    for _, item in ipairs(invItems) do
                                        local s = item:get()
                                        local typeName = s.ItemType:GetFName():ToString()
                                        local displayName = s.ItemType.Name:ToString()
                                        table.insert(items, {
                                            displayName = displayName,
                                            typeName = typeName,
                                            itemId = s.ItemId,
                                            inventoryId = invId,
                                            count = s.Count,
                                            lockerLabel = label,
                                            lockerInv = inv,
                                            itemType = s.ItemType,
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return items, containerCount
end

--- Group raw item entries by typeName, then by inventoryId
--- Returns sorted groups for UI display
function scanner.group(items)
    -- Group by typeName
    local byType = {}
    local typeOrder = {}
    for _, item in ipairs(items) do
        if not byType[item.typeName] then
            byType[item.typeName] = {
                displayName = item.displayName,
                typeName = item.typeName,
                itemType = item.itemType,
                totalCount = 0,
                containers = {},
            }
            table.insert(typeOrder, item.typeName)
        end
        local group = byType[item.typeName]
        group.totalCount = group.totalCount + item.count

        -- Group within by inventoryId
        local invKey = tostring(item.inventoryId)
        if not group.containers[invKey] then
            group.containers[invKey] = {
                label = item.lockerLabel,
                count = 0,
                inventoryId = item.inventoryId,
                lockerInv = item.lockerInv,
                items = {},
            }
        end
        local container = group.containers[invKey]
        container.count = container.count + item.count
        table.insert(container.items, item)
    end

    -- Sort type groups alphabetically by display name
    table.sort(typeOrder, function(a, b)
        return byType[a].displayName:lower() < byType[b].displayName:lower()
    end)

    -- Convert container maps to sorted arrays (highest count first)
    local result = {}
    for _, typeName in ipairs(typeOrder) do
        local group = byType[typeName]
        local containerList = {}
        for _, container in pairs(group.containers) do
            table.insert(containerList, container)
        end
        table.sort(containerList, function(a, b) return a.count > b.count end)
        group.containerList = containerList
        group.containers = nil  -- drop the map
        table.insert(result, group)
    end

    return result
end

return scanner
