-- DatabaseTerminal: Text styling
-- Centralized color palette, font configuration, and text styling helpers.
-- All text in the UI flows through applyStyle() for visual consistency.

local styles = {}

----------------------------------------------------------------------
-- Style definitions
-- Each entry maps to a visual role in the UI. Fields:
--   size     : font size in pt
--   spacing  : letter spacing (0 = default)
--   opacity  : 0.0–1.0 (nil = full opacity)
--   shadow   : { offset={X,Y}, color={R,G,B,A} } — also acts as text tint
--   outline  : outline size in px, or nil
--
-- NOTE: TextBlock:SetColorAndOpacity takes FSlateColor (not FLinearColor),
-- and UE4SS misinterprets raw RGBA tables, making text invisible.
-- We use SetOpacity for dimming and SetShadowColorAndOpacity for tinting.
-- Shadow at offset {0,0} effectively tints the text without displacement.
----------------------------------------------------------------------
styles.defs = {
    title = {
        size = 18, spacing = 400,
        shadow = { offset = { X=0, Y=0 }, color = { R=0.55, G=0.88, B=1.0, A=1.0 } },
    },
    stats = {
        size = 12, spacing = 100, opacity = 0.55,
    },
    itemName = {
        size = 14, spacing = 50,
    },
    count = {
        size = 13,
        shadow = { offset = { X=0, Y=0 }, color = { R=0.55, G=0.78, B=0.95, A=0.9 } },
    },
    countSub = {
        size = 12, opacity = 0.5,
    },
    container = {
        size = 12, opacity = 0.55,
    },
    footer = {
        size = 10, spacing = 100, opacity = 0.35,
    },
    empty = {
        size = 14, opacity = 0.45,
    },
    loading = {
        size = 20, spacing = 300,
        shadow = { offset = { X=1, Y=1 }, color = { R=0.35, G=0.80, B=1.0, A=1.0 } },
    },
    loadingSub = {
        size = 12, spacing = 100, opacity = 0.4,
    },
}

----------------------------------------------------------------------
-- Game font capture
----------------------------------------------------------------------
local gameFont = nil

--- Grab the font asset from an existing game TextBlock (call once after world loads).
function styles.captureGameFont()
    if gameFont then return true end
    local ok = pcall(function()
        local allTb = FindAllOf("TextBlock")
        if allTb then
            for _, tb in ipairs(allTb) do
                if tb:IsValid() then
                    gameFont = tb.Font
                    return
                end
            end
        end
    end)
    return gameFont ~= nil
end

----------------------------------------------------------------------
-- Apply a named style to a TextBlock
----------------------------------------------------------------------

--- Apply a predefined style to a TextBlock widget.
--- @param tb      UTextBlock widget
--- @param name    string key from styles.defs (e.g. "title", "itemName")
function styles.apply(tb, name)
    local def = styles.defs[name]
    if not def then return end

    -- Opacity (dimming)
    if def.opacity then
        pcall(function() tb:SetOpacity(def.opacity) end)
    end

    -- Font (size, spacing, outline)
    if gameFont and (def.size or def.spacing) then
        pcall(function()
            local f = tb.Font
            f.FontObject = gameFont.FontObject
            if def.size then f.Size = def.size end
            if def.spacing then f.LetterSpacing = def.spacing end
            if def.outline then
                f.OutlineSettings.OutlineSize = def.outline
            end
            tb:SetFont(f)
        end)
    end

    -- Shadow — used for both glow effects and text tinting.
    -- Offset {0,0} with a color tints without displacement.
    if def.shadow then
        pcall(function()
            tb:SetShadowOffset(def.shadow.offset)
            tb:SetShadowColorAndOpacity(def.shadow.color)
        end)
    end
end

return styles
