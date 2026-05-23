-- DatabaseTerminal: Item category classification
-- Classifies items using TypeTag (primary) + name pattern fallback

local categories = {}

----------------------------------------------------------------------
-- Category definitions (order = sidebar display order)
----------------------------------------------------------------------
categories.ALL = {
    { id = "all",       label = "All" },
    { id = "minerals",  label = "Minerals" },
    { id = "flora",     label = "Flora" },
    { id = "fauna",     label = "Fauna" },
    { id = "gear",      label = "Gear" },
    { id = "power",     label = "Power" },
    { id = "food",      label = "Food" },
    { id = "medical",   label = "Medical" },
    { id = "materials", label = "Materials" },
}

----------------------------------------------------------------------
-- TypeTag prefix → category mapping
----------------------------------------------------------------------
local TAG_MAP = {
    { prefix = "ItemType.Mineral",   cat = "minerals" },
    { prefix = "ItemType.Flora",     cat = "flora" },
    { prefix = "ItemType.Fauna",     cat = "fauna" },
    { prefix = "ItemType.Equippable",cat = "gear" },
    { prefix = "ItemType.Battery",   cat = "power" },
    { prefix = "ItemType.PowerCell", cat = "power" },
    { prefix = "ItemType.Fuel",      cat = "power" },
}

----------------------------------------------------------------------
-- Name-based pattern matching (from QuickStack categories.lua)
----------------------------------------------------------------------
local FOOD_PATTERNS = {
    "pavlova", "souvlaki", "temaki", "chutney", "jerky", "salad",
    "saturn", "mash", "clump", "shavings", "cookie", "nutrient",
    "cooked", "halfmoon", "geordie", "houndgar", "sandspear",
    "quadrate", "spineytail", "pneumo", "bluemoon", "harvestmoon",
}
local DRINK_PATTERNS = { "water", "isotonic", "drink", "filtered" }
local HEAL_PATTERNS = { "firstaid", "first_aid", "medkit", "med_kit" }

local function matchesAny(lname, patterns)
    for _, p in ipairs(patterns) do
        if string.find(lname, p, 1, true) then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Classify an item
----------------------------------------------------------------------

--- Classify an item into a category.
--- @param itemType UWEItemType object (may be nil)
--- @param typeName string FName of the item type (e.g. "DA_Glass_ItemType")
--- @return string category id
function categories.classify(itemType, typeName)
    -- 1. Check TypeTag first
    if itemType then
        local tagStr = nil
        pcall(function()
            tagStr = itemType.TypeTag.TagName:ToString()
        end)
        if tagStr and tagStr ~= "" and tagStr ~= "None" then
            for _, entry in ipairs(TAG_MAP) do
                if string.find(tagStr, entry.prefix, 1, true) == 1 then
                    return entry.cat
                end
            end
        end
    end

    -- 2. Name-based fallback for TypeTag = None items
    local lname = string.lower(typeName or "")

    -- Food & drink → "food"
    if matchesAny(lname, FOOD_PATTERNS) then return "food" end
    if matchesAny(lname, DRINK_PATTERNS) then return "food" end

    -- Medical
    if matchesAny(lname, HEAL_PATTERNS) then return "medical" end

    -- Tool flag
    if itemType then
        local isTool = false
        pcall(function() isTool = itemType.bTool end)
        if isTool then return "gear" end

        -- EquipmentSlot check
        local slotStr = nil
        pcall(function() slotStr = itemType.EquipmentSlot.TagName:ToString() end)
        if slotStr and slotStr ~= "" and slotStr ~= "None" then
            return "gear"
        end
    end

    -- Fallback
    return "materials"
end

return categories
