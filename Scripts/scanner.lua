-- DatabaseTerminal: Scanner module
-- Discovers nearby containers and collects all item data

local UEHelpers = require("UEHelpers")
local scanner = {}
local categories = require("categories")

----------------------------------------------------------------------
-- Container name lookup via UWEItemType (localized)
----------------------------------------------------------------------
local CONTAINER_ITEM_TYPES = {
    BP_Locker_Floor_C              = "DA_FloorLocker_ItemType",
    BP_LifepodWallLocker_C         = "DA_WallLocker_ItemType",
    BP_FloatingLocker_Carryable_C  = "DA_FloatingLocker_Carryable_ItemType",
    BP_BasicBatteryTerminal_C      = "DA_BasicBatteryTerminal_ItemType",
    BP_PowerCellTerminal_C         = "DA_PowerCellTerminal_ItemType",
    BP_Tailing_Chest_C             = "DA_Tailing_Chest_ItemType",
    BP_Tailing_Jar_C               = "DA_Tailing_Jar_ItemType",
    BP_Tailing_Jar_Hanging_C       = "DA_Tailing_Jar_Hanging_ItemType",
    BP_Tailing_Jar_Coral_C         = "DA_Tailing_Jar_Coral_ItemType",
    BP_Tailing_Jar_Coral_Small_C   = "DA_Tailing_Jar_Coral_Small_ItemType",
    SN2Bioreactor                  = "DA_Bioreactor_ItemType",
    SN2ProcessorStation            = "DA_Processor_ItemType",
    SN2BoxOfHolding                = "DA_StorageCache_ItemType",
    SN2Locker                      = "DA_WallLocker_ItemType",
}

--- Get the localized container name from its UWEItemType.
--- Falls back to "Locker" if the ItemType can't be found.
local function getLocalizedContainerName(actorClass, sourceClass)
    local targetName = CONTAINER_ITEM_TYPES[actorClass]
    if not targetName and sourceClass then
        targetName = CONTAINER_ITEM_TYPES[sourceClass]
    end
    if not targetName then return nil end

    local allTypes = FindAllOf("UWEItemType")
    if allTypes then
        for _, itemType in ipairs(allTypes) do
            local ok, name = pcall(function() return itemType:GetFName():ToString() end)
            if ok and name == targetName then
                local nameOk, locName = pcall(function() return itemType.Name:ToString() end)
                if nameOk and locName and locName ~= "" then
                    return locName
                end
            end
        end
    end
    return nil
end

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

--- Scan nearby containers and return a flat table of item entries.
--- Uses a known-container list since the game uses multiple inventory patterns
--- (UWEInventoryComponent, UWEInventory, etc.) that can't be unified.
--- @param terminalPos table {X, Y, Z} position of the terminal actor
--- @param radiusMeters number scan radius in meters
--- @return table items, number containerCount
function scanner.scan(terminalPos, radiusMeters)
    local radiusUnits = radiusMeters * 100  -- UE uses centimeters

    local containerSources = {
        -- Tailing containers (before SN2Locker — chest is a subclass but uses UWEInventory not Inventory)
        { class = "BP_Tailing_Chest_C",              getInv = function(a) return a.UWEInventory end,            labelFn = nil },
        { class = "BP_Tailing_Jar_C",                getInv = function(a) return a.UWEInventory or a.InventoryComponent or a.Inventory end, labelFn = nil },
        -- Lockers (floor, wall, lifepod — all subclasses of SN2Locker)
        { class = "SN2Locker",                       getInv = function(a) return a.Inventory end,            labelFn = getLockerLabel },
        -- Portable/floating lockers
        { class = "BP_FloatingLocker_Carryable_C",   getInv = function(a) return a.UWEInventory end,         labelFn = nil },
        { class = "BP_Tailing_Jar_Hanging_C",        getInv = function(a) return a.UWEInventory or a.InventoryComponent or a.Inventory end, labelFn = nil },
        { class = "BP_Tailing_Jar_Coral_C",          getInv = function(a) return a.UWEInventory or a.InventoryComponent or a.Inventory end, labelFn = nil },
        { class = "BP_Tailing_Jar_Coral_Small_C",    getInv = function(a) return a.UWEInventory or a.InventoryComponent or a.Inventory end, labelFn = nil },
        -- Chargers
        { class = "BP_BasicBatteryTerminal_C",       getInv = function(a) return a.InventoryComponent end,   labelFn = nil },
        { class = "BP_PowerCellTerminal_C",          getInv = function(a) return a.InventoryComponent end,   labelFn = nil },
        -- Bioreactor
        { class = "SN2Bioreactor",                   getInv = function(a) return a.InventoryComponent end,   labelFn = nil },
        -- Processor (input + output inventories)
        { class = "SN2ProcessorStation",             getInv = function(a) return a.OutputInventory end,      labelFn = nil },
        { class = "SN2ProcessorStation",             getInv = function(a) return a.InputInventory end,       labelFn = nil },
        -- Storage cache
        { class = "SN2BoxOfHolding",                 getInv = function(a) return a.InventoryComponent end,   labelFn = nil },
        -- Blackbox
        { class = "BP_PlayerDied_Blackbox_Proto_C",  getInv = function(a) return a.InventoryComponent end,   labelFn = nil },
    }

    local items = {}
    local containerCount = 0

    -- Get player inventory ID so we can skip it
    local playerInvId = nil
    pcall(function()
        local pawn = UEHelpers:GetPlayerController().Pawn
        if pawn and pawn:IsValid() then
            playerInvId = pawn.InventoryComponent.InventoryId
        end
    end)

    -- Track scanned inventory IDs to prevent double-counting
    local scannedInventories = {}

    for _, source in ipairs(containerSources) do
        local actors = FindAllOf(source.class)
        if actors then
            for _, actor in ipairs(actors) do
                if actor:IsValid() then
                    local dist = getDistanceFromPos(terminalPos, actor)
                    if dist <= radiusUnits then
                        local invOk, inv = pcall(function() return source.getInv(actor) end)
                        if invOk and inv and inv:IsValid() then
                            local invId = inv.InventoryId

                            -- Skip player inventories
                            if invId == playerInvId then goto nextActor end
                            -- Skip already-scanned inventories (dedup)
                            if scannedInventories[invId] then goto nextActor end
                            scannedInventories[invId] = true

                            local isEmpty = inv:IsEmpty()
                            if not isEmpty then
                                containerCount = containerCount + 1

                                -- Actor class for icon differentiation
                                local actorClass = source.class
                                pcall(function() actorClass = actor:GetClass():GetFName():ToString() end)

                                -- Label: user-set name → localized container name → fallback
                                local label = nil
                                if source.labelFn then
                                    pcall(function() label = source.labelFn(actor) end)
                                end
                                if not label then
                                    label = getLocalizedContainerName(actorClass, source.class) or "Container"
                                end

                                local invItems = inv:GetItems()
                                if invItems then
                                    for _, item in ipairs(invItems) do
                                        pcall(function()
                                            local s = item:get()
                                            local typeName = s.ItemType:GetFName():ToString()
                                            table.insert(items, {
                                                displayName = s.ItemType.Name:ToString(),
                                                typeName = typeName,
                                                itemId = s.ItemId,
                                                inventoryId = invId,
                                                count = 1,
                                                lockerLabel = label,
                                                lockerInv = inv,
                                                itemType = s.ItemType,
                                                containerClass = actorClass,
                                                sourceClass = source.class,
                                                category = categories.classify(s.ItemType, typeName),
                                            })
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
                ::nextActor::
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
                category = item.category,
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
                containerClass = item.containerClass,
                sourceClass = item.sourceClass,
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
