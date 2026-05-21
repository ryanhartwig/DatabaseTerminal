-- Temporary debug: log ALL InteractClient events
RegisterCustomEvent("InteractClient", function(self, ...)
    local actor = self:get()
    local className = actor:GetClass():GetFName():ToString()
    print("[DBTerminal:debug] InteractClient: " .. className .. "\n")
end)
print("[DBTerminal:debug] Broad interaction logging active\n")
