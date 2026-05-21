-- DatabaseTerminal v0.1.0
-- Browse and pull items from nearby containers via a buildable terminal

local config = require("config")
local scanner = require("scanner")
local tracker = require("tracker")
local interaction = require("interaction")
local ui = require("ui")

local VERSION = "0.1.0"
print(string.format("[DBTerminal] v%s loaded\n", VERSION))

-- Initialize modules
tracker.init()
interaction.init({
    tracker = tracker,
    ui = ui,
    scanner = scanner,
    config = config,
})

require("debug")  -- temporary: broad interaction logging
print("[DBTerminal] Ready.\n")
