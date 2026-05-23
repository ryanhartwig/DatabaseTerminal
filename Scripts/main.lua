-- DatabaseTerminal v1.0.0
-- Browse and pull items from nearby containers via a buildable terminal

local config = require("config")

----------------------------------------------------------------------
-- Auto-deploy IoStore assets to ~mods/ on first install
----------------------------------------------------------------------
local function deployAssets()
    local modDir = config.ModDir
    local assetsDir = modDir .. "Assets/"
    local modsTarget = modDir .. "../../../../../Content/Paks/~mods/"

    print(string.format("[DBTerminal] Deploy: modDir=%s\n", modDir))
    print(string.format("[DBTerminal] Deploy: target=%s\n", modsTarget))

    -- Ensure ~mods/ directory exists
    pcall(function()
        os.execute('mkdir "' .. modsTarget:gsub("/", "\\") .. '" 2>nul')
    end)

    local files = { "DatabaseTerminal_P.pak", "DatabaseTerminal_P.ucas", "DatabaseTerminal_P.utoc" }
    for _, filename in ipairs(files) do
        local targetPath = modsTarget .. filename
        local exists = io.open(targetPath, "rb")
        if exists then
            exists:close()
            print(string.format("[DBTerminal] Deploy: %s already exists\n", filename))
        else
            local srcPath = assetsDir .. filename
            local src = io.open(srcPath, "rb")
            if src then
                local data = src:read("*all")
                src:close()
                local dst = io.open(targetPath, "wb")
                if dst then
                    dst:write(data)
                    dst:close()
                    print(string.format("[DBTerminal] Deployed %s to ~mods/\n", filename))
                else
                    print(string.format("[DBTerminal] Deploy FAILED: can't write %s\n", targetPath))
                end
            else
                print(string.format("[DBTerminal] Deploy FAILED: can't read %s\n", srcPath))
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
          type="slider", default=25, min=5, max=235, step=5, format="integer" },

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

----------------------------------------------------------------------
-- DEV: Live nudge tool for UI positioning
-- Enable via config.txt: dev_nudge = true
-- Set starting position: nudge_x = 0.5  nudge_y = 0.5
-- To use: set ui._nudgeSlot in ui.lua on the element you want to move,
-- open the terminal, then P=left O=right I=up U=down Y=print final values
----------------------------------------------------------------------
if config.DevNudge then
    local nudgeX = config.NudgeStartX or 0.5
    local nudgeY = config.NudgeStartY or 0.5
    local nudgeMode = config.NudgeMode or "slot"  -- "slot" or "panel"
    local function applyNudge()
        ExecuteInGameThread(function()
            if nudgeMode == "panel" then
                -- Shift the whole root widget via render translation
                local root = ui.getRoot()
                if not root then print("[Nudge] No root — open terminal first\n") return end
                local offsetPx = (nudgeX - 0.5) * 1920  -- convert fraction to pixels (approx)
                pcall(function() root:SetRenderTranslation({ X = offsetPx, Y = 0 }) end)
                print(string.format("[Nudge] PanelCenterX=%.3f (offset=%dpx)\n", nudgeX, offsetPx))
            else
                local slot = ui.getNudgeSlot()
                if not slot then print("[Nudge] No target — set ui._nudgeSlot and open terminal\n") return end
                pcall(function()
                    local x = ui.nudgePX(nudgeX)
                    local y = ui.nudgePY(nudgeY)
                    slot:SetAnchors({ Minimum = { X = x, Y = y }, Maximum = { X = x, Y = y } })
                end)
                print(string.format("[Nudge] X=%.3f Y=%.3f\n", nudgeX, nudgeY))
            end
        end)
    end
    RegisterKeyBind(Key.J, function() nudgeX = nudgeX - 0.005; applyNudge() end)
    RegisterKeyBind(Key.L, function() nudgeX = nudgeX + 0.005; applyNudge() end)
    RegisterKeyBind(Key.K, function() nudgeY = nudgeY - 0.003; applyNudge() end)
    RegisterKeyBind(Key.M, function() nudgeY = nudgeY + 0.003; applyNudge() end)
    RegisterKeyBind(Key.N, function()
        print(string.format("[Nudge] === FINAL: pX(%.3f), pY(%.3f) ===\n", nudgeX, nudgeY))
    end)
    print(string.format("[DBTerminal] Nudge tool active. Start: X=%.3f Y=%.3f\n", nudgeX, nudgeY))
end
