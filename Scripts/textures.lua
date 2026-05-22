-- DatabaseTerminal: Texture loader
-- Loads custom PNG textures from disk via ImportFileAsTexture2D

local UEHelpers = require("UEHelpers")
local config = require("config")

local textures = {}
local cache = {}  -- name → UTexture2D
local krl = nil   -- KismetRenderingLibrary CDO

local TEXTURE_DIR = config.ModDir .. "Textures/"

local TEXTURE_FILES = {
    Background = "T_DBTerminal_Background.png",
    Header     = "T_DBTerminal_Header.png",
    Divider    = "T_DBTerminal_Divider.png",
    Button     = "T_DBTerminal_Button.png",
    ButtonHov  = "T_DBTerminal_Button_Hover.png",
    Loading    = "T_DBTerminal_Loading.png",
}

--- Import all textures fresh from disk.
--- Always clears cache first — never touches old UObject pointers
--- (UE GC can free unrooted UTexture2Ds, making old pointers dangling).
function textures.loadAll()
    cache = {}  -- drop all old refs without touching them

    if not krl then
        krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    end
    if not krl then
        print("[DBTerminal] KismetRenderingLibrary not found — custom textures unavailable\n")
        return
    end

    local pc = UEHelpers:GetPlayerController()
    if not pc then return end

    for name, filename in pairs(TEXTURE_FILES) do
        local filepath = TEXTURE_DIR .. filename
        local ok, tex = pcall(function()
            return krl:ImportFileAsTexture2D(pc, filepath)
        end)
        if ok and tex then
            cache[name] = tex
        end
    end

    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    print(string.format("[DBTerminal] Loaded %d/%d custom textures\n", count, 6))
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
    cache = {}
end

return textures
