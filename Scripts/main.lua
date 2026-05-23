-- DatabaseTerminal v1.0.0
-- Browse and pull items from nearby containers via a buildable terminal

local config = require("config")

----------------------------------------------------------------------
-- Auto-deploy IoStore assets to ~mods/ on first install
----------------------------------------------------------------------
local function deployAssets()
    local modDir = config.ModDir
    local assetsDir = modDir .. "Assets/"
    -- Navigate from ue4ss/Mods/DatabaseTerminal/ up to game Content/Paks/~mods/
    -- Path: DatabaseTerminal → Mods → ue4ss → Win64 → Binaries → Subnautica2 → Content/Paks/~mods/
    local modsTarget = modDir .. "../../../../../Content/Paks/~mods/"

    local files = { "DatabaseTerminal_P.pak", "DatabaseTerminal_P.ucas", "DatabaseTerminal_P.utoc" }
    for _, filename in ipairs(files) do
        local targetPath = modsTarget .. filename
        -- Check if already deployed
        local exists = io.open(targetPath, "rb")
        if exists then
            exists:close()
        else
            -- Copy from Assets/ to ~mods/
            local src = io.open(assetsDir .. filename, "rb")
            if src then
                local data = src:read("*all")
                src:close()
                local dst = io.open(targetPath, "wb")
                if dst then
                    dst:write(data)
                    dst:close()
                    print(string.format("[DBTerminal] Deployed %s to ~mods/\n", filename))
                end
            end
        end
    end
end

local deployOk, deployErr = pcall(deployAssets)
if not deployOk then
    print(string.format("[DBTerminal] Asset deploy error: %s\n", tostring(deployErr)))
end

----------------------------------------------------------------------
-- Module init
----------------------------------------------------------------------
local scanner = require("scanner")
local tracker = require("tracker")
local interaction = require("interaction")
local ui = require("ui")

local VERSION = "1.0.0"
print(string.format("[DBTerminal] v%s loaded\n", VERSION))

-- Initialize modules
tracker.init()
interaction.init({
    tracker = tracker,
    ui = ui,
    scanner = scanner,
    config = config,
})

print("[DBTerminal] Ready.\n")
