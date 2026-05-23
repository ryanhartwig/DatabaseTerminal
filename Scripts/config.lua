-- DatabaseTerminal: Config module

local config = {}
config.ModDir = debug.getinfo(1, "S").source:match("@(.*/)")  .. "../"
config.ScanRadius = 25              -- meters
config.RefreshInterval = 5          -- seconds
config.Notify = true
config.SkipLoadingScreen = false    -- skip boot animation, go straight to terminal

-- Dev tools (loaded from dev.txt, not config.txt — not shipped to users)
config.DevNudge = false
config.NudgeStartX = 0.5
config.NudgeStartY = 0.5
config.PanelCenterX = 0.5  -- horizontal center of the panel (viewport fraction)

local function loadConfig()
    local file = io.open(config.ModDir .. "config.txt", "r")
    if not file then return end
    for line in file:lines() do
        local key, val = line:match("^(%w+)%s*=%s*(.+)$")
        if key and val then
            val = val:match("^%s*(.-)%s*$")
            if key == "radius" then
                config.ScanRadius = tonumber(val) or config.ScanRadius
            elseif key == "refresh_interval" then
                config.RefreshInterval = tonumber(val) or config.RefreshInterval
            elseif key == "notify" then
                config.Notify = val ~= "false" and val ~= "0"
            elseif key == "skip_loading" then
                config.SkipLoadingScreen = val == "true" or val == "1"
            end
        end
    end
    file:close()
end

loadConfig()

-- Dev tools config (gitignored, not shipped)
local function loadDevConfig()
    local file = io.open(config.ModDir .. "dev.txt", "r")
    if not file then return end
    for line in file:lines() do
        local key, val = line:match("^(%w+)%s*=%s*(.+)$")
        if key and val then
            val = val:match("^%s*(.-)%s*$")
            if key == "nudge" then
                config.DevNudge = val == "true" or val == "1"
            elseif key == "nudge_x" then
                config.NudgeStartX = tonumber(val) or config.NudgeStartX
            elseif key == "nudge_y" then
                config.NudgeStartY = tonumber(val) or config.NudgeStartY
            elseif key == "panel_center_x" then
                config.PanelCenterX = tonumber(val) or config.PanelCenterX
            end
        end
    end
    file:close()
end

loadDevConfig()

----------------------------------------------------------------------
-- SN2ModSettings integration (optional — graceful if not installed)
----------------------------------------------------------------------
local settingsMap = {
    { key = "radius",       field = "ScanRadius",        type = "number" },
    { key = "skip_loading", field = "SkipLoadingScreen",  type = "boolean" },
}

function config.refreshModSettings()
    if not ModRef then return end
    for _, entry in ipairs(settingsMap) do
        local ok, val = pcall(function()
            return ModRef:GetSharedVariable("SN2ModSettings/DatabaseTerminal/" .. entry.key)
        end)
        if ok and val ~= nil and type(val) == entry.type then
            if entry.type == "number" then
                val = math.floor(val + 0.5)
            end
            config[entry.field] = val
        end
    end
end

config.refreshModSettings()

return config
