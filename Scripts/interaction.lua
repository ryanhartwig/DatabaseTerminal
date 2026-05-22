-- DatabaseTerminal: Interaction handler
-- Hooks InteractClient, manages UI open/close lifecycle

local UEHelpers = require("UEHelpers")
local interaction = {}

local ACTOR_CLASS = "BP_ComputerTextInterface_Terminal_PlayerBuilt_C"

local tracker = nil
local ui = nil
local scanner = nil
local config = nil

local isOpen = false
local currentTerminal = nil

function interaction.isOpen()
    return isOpen
end

function interaction.getCurrentTerminal()
    return currentTerminal
end

function interaction.close()
    if not isOpen then return end
    if ui then ui.close() end
    isOpen = false
    currentTerminal = nil

    local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local pc = UEHelpers:GetPlayerController()
    if pc and wbLib then
        pcall(function() wbLib:SetInputMode_GameOnly(pc, true) end)
    end
    print("[DBTerminal] UI closed.\n")
end

local function open(actor)
    if isOpen then interaction.close() end

    currentTerminal = actor
    isOpen = true

    -- Scan nearby containers
    local termPos = actor:K2_GetActorLocation()
    local items, containerCount = scanner.scan(termPos, config.ScanRadius)
    local groups = scanner.group(items)

    local totalItems = 0
    for _, group in ipairs(groups) do totalItems = totalItems + group.totalCount end
    print(string.format("[DBTerminal] Scan: %d items, %d containers, %d types\n",
        totalItems, containerCount, #groups))

    -- Open the UI
    ui.open(groups, function()
        interaction.close()
    end)

    -- Capture input
    local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local pc = UEHelpers:GetPlayerController()
    if pc and wbLib and ui.getRoot() then
        pcall(function() wbLib:SetInputMode_UIOnlyEx(pc, ui.getRoot(), 0, true) end)
    end

    print("[DBTerminal] UI opened.\n")
end

function interaction.init(deps)
    tracker = deps.tracker
    ui = deps.ui
    scanner = deps.scanner
    config = deps.config

    -- Hook InteractClient
    RegisterCustomEvent("InteractClient", function(self, ...)
        local actor = self:get()
        local className = actor:GetClass():GetFName():ToString()
        if className ~= ACTOR_CLASS then return end

        local fname = actor:GetFName():ToString()
        if not tracker.isTerminal(fname) then return end

        print("[DBTerminal] Terminal interaction detected\n")
        ExecuteInGameThread(function()
            open(actor)
        end)
    end)

    -- Override hover text: when GetInteractionInfo fires for our terminal,
    -- find the HUD TextBlock showing "NoA" and replace with our name
    local hoveringOurTerminal = false

    RegisterCustomEvent("GetInteractionInfo", function(self, ...)
        local actor = self:get()
        local cls = actor:GetClass():GetFName():ToString()
        if cls ~= ACTOR_CLASS then
            hoveringOurTerminal = false
            return
        end
        local fname = actor:GetFName():ToString()
        hoveringOurTerminal = tracker.isTerminal(fname)
    end)

    LoopAsync(100, function()
        if not hoveringOurTerminal then return false end
        local textBlocks = FindAllOf("TextBlock")
        if textBlocks then
            for _, tb in ipairs(textBlocks) do
                if tb:IsValid() then
                    local ok, text = pcall(function() return tb:GetText():ToString() end)
                    if ok and text and text:find("NoA") then
                        pcall(function() tb:SetText(FText("Use Database Terminal")) end)
                    end
                end
            end
        end
        return false
    end)

    -- ESC to close
    RegisterKeyBind(Key.ESCAPE, function()
        if not isOpen then return end
        ExecuteInGameThread(function()
            interaction.close()
        end)
    end)
end

return interaction
