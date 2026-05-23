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
-- SN2ModSettings manifest (optional — no-op if not installed)
----------------------------------------------------------------------
do
    local SN2_DIR = "./ue4ss/Mods/SN2ModSettings/"
    local REG_DIR = SN2_DIR .. "registrations/"
    local MANIFEST = [=[return {
    name     = "DatabaseTerminal",
    display  = "Database Terminal",
    version  = "1.0.0",
    nexus_id = "",
    settings = {
        { key="radius", title="Scan Radius (meters)",
          description="How far the terminal scans for nearby containers.",
          type="slider", default=25, min=5, max=100, step=5, format="integer" },

        { key="skip_loading", title="Skip Loading Screen",
          description="Skip the boot animation and go straight to the item browser.",
          type="toggle", default=false },
    },
}
]=]

    local enabledFile = io.open(SN2_DIR .. "enabled.txt", "r")
    if enabledFile then
        enabledFile:close()
        local attempts = 0
        local MAX_ATTEMPTS = 10
        local function tryWriteManifest()
            attempts = attempts + 1
            local selfManifest = io.open(REG_DIR .. "SN2ModSettings.lua", "r")
            local initialized = selfManifest ~= nil
            if selfManifest then selfManifest:close() end

            if initialized or attempts >= MAX_ATTEMPTS then
                if not initialized then
                    os.execute('mkdir "' .. REG_DIR:gsub("/", "\\") .. '" 2>nul')
                end
                local f = io.open(REG_DIR .. "DatabaseTerminal.lua", "w")
                if f then
                    f:write(MANIFEST)
                    f:close()
                    print(string.format("[DBTerminal] SN2ModSettings manifest written (attempt %d/%d)\n",
                        attempts, MAX_ATTEMPTS))
                end
            else
                ExecuteWithDelay(1000, function()
                    ExecuteInGameThread(tryWriteManifest)
                end)
            end
        end
        ExecuteWithDelay(1000, function()
            ExecuteInGameThread(tryWriteManifest)
        end)
    end
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
