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

--- Hide the NoA terminal widget visually (keep it active for input management)
local function hideCTIWidget()
    local widgets = FindAllOf("WBP_ComputerTextInterface_C")
    if not widgets then return end
    for _, widget in ipairs(widgets) do
        if widget:IsValid() then
            pcall(function()
                -- SetVisibility: 0=Visible, 1=Hidden, 2=Collapsed
                widget:SetVisibility(1)
                print("[DBTerminal] Hid NoA widget\n")
            end)
        end
    end
end


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

    -- Restore CTI widget visibility and deactivate it properly
    local widgets = FindAllOf("WBP_ComputerTextInterface_C")
    if widgets then
        for _, widget in ipairs(widgets) do
            if widget:IsValid() then
                pcall(function() widget:SetVisibility(0) end)
                pcall(function() widget:DeactivateWidget() end)
            end
        end
    end

    -- Restore game input
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

    -- Pull callback — move one item from container to player inventory
    local function onPull(container, itemEntry)
        local pawn = UEHelpers:GetPlayerController().Pawn
        if not pawn or not pawn:IsValid() then return end
        local playerInv = pawn.InventoryComponent
        if not playerInv or not playerInv:IsValid() then return end

        if playerInv:IsFull() then
            print("[DBTerminal] Inventory full!\n")
            return
        end

        local ok, err = pcall(function()
            playerInv:MoveItemBetweenInventories(
                itemEntry.itemId,
                itemEntry.inventoryId,
                playerInv.InventoryId
            )
        end)
        if ok then
            print(string.format("[DBTerminal] Pulled %s from %s\n",
                itemEntry.displayName, container.label))
        else
            print(string.format("[DBTerminal] Pull failed: %s\n", tostring(err)))
        end
    end

    -- Open the UI (stacks on top of NoA widget which handles input mode)
    ui.open(groups, function()
        interaction.close()
    end, onPull)

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
        local isOurs = tracker.isTerminal(fname)
        print(string.format("[DBTerminal] InteractClient: %s | isTerminal=%s\n", fname, tostring(isOurs)))

        -- Debug: print all tracked terminals
        local tracked = tracker.getTerminals()
        for k, _ in pairs(tracked) do
            print("[DBTerminal]   tracked: " .. k .. "\n")
        end

        if not isOurs then return end

        print("[DBTerminal] Terminal interaction detected\n")

        ExecuteInGameThread(function()
            -- Let the NoA widget fully activate (sets up cursor/input), then hide it
            ExecuteWithDelay(80, function()
                ExecuteInGameThread(function()
                    hideCTIWidget()
                    open(actor)
                end)
            end)
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

    -- ESC to close (may not fire during UI mode)
    RegisterKeyBind(Key.ESCAPE, function()
        if not isOpen then return end
        ExecuteInGameThread(function()
            interaction.close()
        end)
    end)

    -- Backup close key (F6) in case ESC doesn't fire
    RegisterKeyBind(Key.F6, function()
        if not isOpen then return end
        ExecuteInGameThread(function()
            interaction.close()
        end)
    end)

    -- Also hook the NoA widget's own back/close buttons
    RegisterCustomEvent("BP_OnDeactivated", function(self, ...)
        if not isOpen then return end
        local widget = self:get()
        local cls = widget:GetClass():GetFName():ToString()
        if cls == "WBP_ComputerTextInterface_C" then
            ExecuteInGameThread(function()
                interaction.close()
            end)
        end
    end)
end

return interaction
