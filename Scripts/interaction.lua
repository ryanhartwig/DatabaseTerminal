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

    -- Restore game input (we manage it via SetInputMode_UIOnlyEx on open)
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
    local function onPull(container, itemEntry, group)
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
            -- Update UI live
            ui.onPullComplete(container, group)
        else
            print(string.format("[DBTerminal] Pull failed: %s\n", tostring(err)))
        end
    end

    -- Open the UI
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
        if not tracker.isTerminal(fname) then return end

        print("[DBTerminal] Terminal interaction detected\n")

        -- Suppress the NoA widget BEFORE it opens by calling CloseUI
        -- on the CTI component. This prevents the widget push entirely.
        pcall(function()
            local comp = actor.BPC_ComputerTextInterface_Component
            if comp and comp:IsValid() then
                comp:CloseUI()
            end
        end)

        ExecuteInGameThread(function()
            -- Open our UI directly — no loading screen needed
            ExecuteWithDelay(50, function()
                ExecuteInGameThread(function()
                    pcall(function()
                        open(actor)
                        -- Set up our own input mode since NoA widget isn't managing it
                        local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
                        local pc = UEHelpers:GetPlayerController()
                        if pc and wbLib and ui.getRoot() then
                            wbLib:SetInputMode_UIOnlyEx(pc, ui.getRoot(), 0, true)
                        end
                    end)
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
        local ok = pcall(function()
            local textBlocks = FindAllOf("TextBlock")
            if textBlocks then
                for _, tb in ipairs(textBlocks) do
                    if tb:IsValid() then
                        local readOk, text = pcall(function() return tb:GetText():ToString() end)
                        if readOk and text and text:find("NoA") then
                            pcall(function() tb:SetText(FText("Use Database Terminal")) end)
                        end
                    end
                end
            end
        end)
        if not ok then return true end  -- error = stop polling
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

end

return interaction
