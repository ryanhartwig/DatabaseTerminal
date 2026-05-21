-- DatabaseTerminal: Config module

local config = {}
config.ModDir = debug.getinfo(1, "S").source:match("@(.*/)")  .. "../"
config.ScanRadius = 25       -- meters
config.RefreshInterval = 5   -- seconds
config.Notify = true

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
            end
        end
    end
    file:close()
end

loadConfig()
return config
