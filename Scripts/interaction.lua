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
local loadingWidget = nil

--- Show a loading screen that covers the NoA widget flash
local function showLoadingScreen()
    local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local uwClass = StaticFindObject("/Script/UMG.UserWidget")
    local canvasCls = StaticFindObject("/Script/UMG.CanvasPanel")
    local imgCls = StaticFindObject("/Script/UMG.Image")
    local textCls = StaticFindObject("/Script/UMG.TextBlock")

    local pc = UEHelpers:GetPlayerController()
    if not pc or not wbLib then return end

    loadingWidget = wbLib:Create(pc, uwClass, pc)
    if not loadingWidget then return end

    local canvas = StaticConstructObject(canvasCls, loadingWidget, FName("LoadCanvas"))
    loadingWidget.WidgetTree.RootWidget = canvas

    -- Match the main UI panel size — fully opaque to cover NoA
    local bg = StaticConstructObject(imgCls, loadingWidget, FName("LoadBG"))
    pcall(function() bg:SetColorAndOpacity({ R=0.015, G=0.025, B=0.05, A=1.0 }) end)
    local bgSlot = canvas:AddChildToCanvas(bg)
    bgSlot:SetAnchors({ Minimum = { X=0.10, Y=0.05 }, Maximum = { X=0.90, Y=0.95 } })
    bgSlot:SetAutoSize(false)

    -- Top accent line (matches main UI)
    local accent = StaticConstructObject(imgCls, loadingWidget, FName("LoadAccent"))
    pcall(function() accent:SetColorAndOpacity({ R=0.1, G=0.65, B=0.95, A=0.85 }) end)
    local accentSlot = canvas:AddChildToCanvas(accent)
    accentSlot:SetAnchors({ Minimum = { X=0.10, Y=0.05 }, Maximum = { X=0.90, Y=0.054 } })
    accentSlot:SetAutoSize(false)

    -- Loading text centered
    local txt = StaticConstructObject(textCls, loadingWidget, FName("LoadTxt"))
    txt:SetText(FText("Scanning containers..."))
    local txtSlot = canvas:AddChildToCanvas(txt)
    txtSlot:SetAnchors({ Minimum = { X=0.42, Y=0.48 }, Maximum = { X=0.42, Y=0.48 } })
    txtSlot:SetAutoSize(true)

    loadingWidget:AddToViewport(499)
end

local function removeLoadingScreen()
    if loadingWidget then
        pcall(function() loadingWidget:RemoveFromViewport() end)
        loadingWidget = nil
    end
end

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
        if not tracker.isTerminal(fname) then return end

        print("[DBTerminal] Terminal interaction detected\n")

        ExecuteInGameThread(function()
            -- Show loading screen immediately (masks the NoA widget)
            showLoadingScreen()

            -- Let the NoA widget activate (sets up cursor), then hide + open ours
            ExecuteWithDelay(100, function()
                ExecuteInGameThread(function()
                    hideCTIWidget()
                    removeLoadingScreen()
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
