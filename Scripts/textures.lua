-- DatabaseTerminal: Texture loader
-- Loads custom PNG textures from disk via ImportFileAsTexture2D.
-- Textures are rooted in a persistent hidden widget to prevent UE GC
-- from collecting them (Lua-only references are invisible to UE GC).

local UEHelpers = require("UEHelpers")
local config = require("config")

local textures = {}
local cache = {}    -- name → UTexture2D
local krl = nil     -- KismetRenderingLibrary CDO
local anchor = nil  -- hidden widget that roots textures in UE object graph

local TEXTURE_DIR = config.ModDir .. "Textures/"

local TEXTURE_FILES = {
    -- Backgrounds
    Background     = "T_DBTerminal_Background.png",
    Backgroundbare = "T_DBTerminal_Background_No_Hex.png",
    -- UI chrome
    Header     = "T_DBTerminal_Header.png",
    Divider    = "T_DBTerminal_Divider.png",
    Button     = "T_DBTerminal_Button.png",
    ButtonHov  = "T_DBTerminal_Button_Hover.png",
    Loading    = "T_DBTerminal_Loading.png",
    -- Hex bands
    Hex1 = "T_DBTerminal_HexBand_1.png",
    Hex2 = "T_DBTerminal_HexBand_2.png",
    Hex3 = "T_DBTerminal_HexBand_3.png",
    Hex4 = "T_DBTerminal_HexBand_4.png",
    Hex5 = "T_DBTerminal_HexBand_5.png",
    Hex6 = "T_DBTerminal_HexBand_6.png",
    Hex7 = "T_DBTerminal_HexBand_7.png",
    Hex8 = "T_DBTerminal_HexBand_8.png",
    -- Radar pulse
    Orb   = "T_DBTerminal_Orb.png",
    Ring1 = "T_DBTerminal_Ring_1.png",
    Ring2 = "T_DBTerminal_Ring_2.png",
    Ring3 = "T_DBTerminal_Ring_3.png",
    Ring4 = "T_DBTerminal_Ring_4.png",
    Ring5 = "T_DBTerminal_Ring_5.png",
    Ring6 = "T_DBTerminal_Ring_6.png",
    Ring7 = "T_DBTerminal_Ring_7.png",
}

--- Create a hidden widget with Image children that hold brush refs to each
--- texture. This roots the textures in UE's object graph so GC won't
--- collect them while the anchor widget is alive.
local function rootTextures()
    -- Remove old anchor if re-importing
    if anchor then
        pcall(function() anchor:RemoveFromViewport() end)
        anchor = nil
    end

    local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local uwClass = StaticFindObject("/Script/UMG.UserWidget")
    local canvasCls = StaticFindObject("/Script/UMG.CanvasPanel")
    local imgCls = StaticFindObject("/Script/UMG.Image")
    local pc = UEHelpers:GetPlayerController()
    if not pc or not wbLib then return end

    local root = wbLib:Create(pc, uwClass, pc)
    if not root then return end

    local canvas = StaticConstructObject(canvasCls, root, FName("AnchorCanvas"))
    root.WidgetTree.RootWidget = canvas

    -- Create one Image per texture, set brush to hold the reference
    local i = 0
    for name, tex in pairs(cache) do
        i = i + 1
        local img = StaticConstructObject(imgCls, root, FName("Anchor_" .. i))
        pcall(function() img:SetBrushFromTexture(tex, false) end)
        -- Don't add to canvas viewport — just needs to exist in the widget tree
        canvas:AddChildToCanvas(img)
    end

    -- Add at z-order -1 so it's invisible behind everything
    -- Opacity 0 ensures nothing renders
    pcall(function() root:SetRenderOpacity(0) end)
    root:AddToViewport(-1)
    anchor = root
end

--- Import all textures from disk. Only imports missing entries.
--- If the anchor widget was destroyed (e.g. save switch), clears cache
--- and reimports everything to avoid dangling texture pointers.
function textures.loadAll()
    -- Check if anchor is still alive — save switches destroy viewport widgets
    if anchor then
        local anchorValid = false
        pcall(function() anchorValid = anchor:IsValid() end)
        if not anchorValid then
            print("[DBTerminal] Texture anchor lost (save switch?) — reimporting\n")
            cache = {}
            anchor = nil
        end
    end

    if not krl then
        krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    end
    if not krl then
        print("[DBTerminal] KismetRenderingLibrary not found — custom textures unavailable\n")
        return
    end

    local pc = UEHelpers:GetPlayerController()
    if not pc then return end

    local imported = 0
    for name, filename in pairs(TEXTURE_FILES) do
        if not cache[name] then
            local filepath = TEXTURE_DIR .. filename
            local ok, tex = pcall(function()
                return krl:ImportFileAsTexture2D(pc, filepath)
            end)
            if ok and tex then
                cache[name] = tex
                imported = imported + 1
            end
        end
    end

    -- Root newly imported textures in UE object graph
    if imported > 0 then
        rootTextures()
    end

    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    local total = 0
    for _ in pairs(TEXTURE_FILES) do total = total + 1 end
    print(string.format("[DBTerminal] Loaded %d/%d custom textures (%d new)\n", count, total, imported))
end

--- Get a loaded texture by name. Returns UTexture2D or nil.
function textures.get(name)
    return cache[name]
end

--- Check if textures are available
function textures.isLoaded()
    return cache.Background ~= nil
end

--- Clear cache (for reload safety)
function textures.clear()
    if anchor then
        pcall(function() anchor:RemoveFromViewport() end)
        anchor = nil
    end
    cache = {}
end

return textures
