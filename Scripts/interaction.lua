-- DatabaseTerminal: Interaction handler
-- Hooks InteractClient, manages UI open/close lifecycle

local UEHelpers = require("UEHelpers")
local textures = require("textures")
local interaction = {}

local ACTOR_CLASS = "BP_ComputerTextInterface_Terminal_PlayerBuilt_C"

local tracker = nil
local ui = nil
local scanner = nil
local config = nil

local isOpen = false
local currentTerminal = nil
local loadingWidget = nil
local interactionGen = 0  -- generation counter — stale callbacks bail out

----------------------------------------------------------------------
-- Loading screen
----------------------------------------------------------------------
local function showLoadingScreen()
    if loadingWidget then
        pcall(function() loadingWidget:RemoveFromViewport() end)
        loadingWidget = nil
    end

    -- Always reimport textures fresh — UE GC can free unrooted UTexture2Ds
    -- between interactions, and touching a freed pointer = segfault
    pcall(function() textures.loadAll() end)
    local loadingTex = textures.get("Loading")
    if not loadingTex then return false end

    local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local uwClass = StaticFindObject("/Script/UMG.UserWidget")
    local canvasCls = StaticFindObject("/Script/UMG.CanvasPanel")
    local imgCls = StaticFindObject("/Script/UMG.Image")
    local pc = UEHelpers:GetPlayerController()
    if not pc or not wbLib then return end

    local root = wbLib:Create(pc, uwClass, pc)
    if not root then return end

    local canvas = StaticConstructObject(canvasCls, root, FName("LoadCanvas"))
    root.WidgetTree.RootWidget = canvas

    -- Loading image — same bounds as the main UI panel
    local img = StaticConstructObject(imgCls, root, FName("LoadImg"))
    pcall(function() img:SetBrushFromTexture(loadingTex, false) end)
    local slot = canvas:AddChildToCanvas(img)
    slot:SetAnchors({ Minimum = { X = 0.10, Y = 0.05 }, Maximum = { X = 0.90, Y = 0.95 } })
    slot:SetAutoSize(false)

    root:AddToViewport(501)  -- above main UI z-order (500)
    loadingWidget = root

    -- Lock input so player can't move during load
    pcall(function() wbLib:SetInputMode_UIOnlyEx(pc, root, 0, true) end)
    pcall(function() pc.bShowMouseCursor = false end)
end

local function hideLoadingScreen()
    if loadingWidget then
        pcall(function() loadingWidget:RemoveFromViewport() end)
        loadingWidget = nil
    end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
function interaction.isOpen()
    return isOpen
end

function interaction.getCurrentTerminal()
    return currentTerminal
end

function interaction.close()
    if not isOpen then return end
    interactionGen = interactionGen + 1  -- invalidate any pending delayed callback
    hideLoadingScreen()
    if ui then ui.close() end
    isOpen = false
    currentTerminal = nil

    -- Restore game input and hide cursor
    local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local pc = UEHelpers:GetPlayerController()
    if pc and wbLib then
        pcall(function() wbLib:SetInputMode_GameOnly(pc, true) end)
        pcall(function() pc.bShowMouseCursor = false end)
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
        local ok, actor = pcall(function() return self:get() end)
        if not ok or not actor then return end
        local classOk, className = pcall(function() return actor:GetClass():GetFName():ToString() end)
        if not classOk or className ~= ACTOR_CLASS then return end

        local fnameOk, fname = pcall(function() return actor:GetFName():ToString() end)
        if not fnameOk or not tracker.isTerminal(fname) then return end

        print("[DBTerminal] Terminal interaction detected\n")

        -- Suppress the NoA widget BEFORE it opens by calling CloseUI
        -- on the CTI component. This prevents the widget push entirely.
        -- Wrapped in pcall — if the component is in a bad state, we skip
        -- suppression and our UI still opens (NoA may flash briefly).
        local suppressOk = pcall(function()
            local comp = actor.BPC_ComputerTextInterface_Component
            if comp and comp:IsValid() then
                comp:CloseUI()
            end
        end)
        if not suppressOk then
            print("[DBTerminal] CloseUI failed — NoA popup may flash\n")
        end

        -- Mark open immediately so ESC/F6 work during loading phase
        isOpen = true
        currentTerminal = actor
        interactionGen = interactionGen + 1
        local myGen = interactionGen

        ExecuteInGameThread(function()
            if interactionGen ~= myGen then return end
            -- Show loading screen instantly
            pcall(function() showLoadingScreen() end)

            -- After delay, transition to the main UI
            ExecuteWithDelay(1200, function()
                ExecuteInGameThread(function()
                    -- Bail if this interaction was cancelled (user hit ESC/F6)
                    if interactionGen ~= myGen then return end

                    pcall(function()
                        -- Verify actor is still valid before using it
                        if not actor or not actor:IsValid() then
                            print("[DBTerminal] Actor no longer valid — aborting\n")
                            interaction.close()
                            return
                        end

                        hideLoadingScreen()
                        -- Reset isOpen so open() doesn't double-close
                        isOpen = false
                        open(actor)
                        -- Set up input mode and show cursor
                        local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
                        local pc = UEHelpers:GetPlayerController()
                        if pc and wbLib and ui.getRoot() then
                            wbLib:SetInputMode_UIOnlyEx(pc, ui.getRoot(), 0, true)
                            pc.bShowMouseCursor = true
                            -- Center cursor on screen
                            pcall(function()
                                local vpSize = { X = 0, Y = 0 }
                                pcall(function()
                                    local vp = pc:GetLocalPlayer():GetViewportClient()
                                    vp:GetViewportSize(vpSize)
                                end)
                                if vpSize.X > 0 then
                                    pc:SetMouseLocation(vpSize.X / 2, vpSize.Y / 2)
                                end
                            end)
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
        local ok = pcall(function()
            local actor = self:get()
            local cls = actor:GetClass():GetFName():ToString()
            if cls ~= ACTOR_CLASS then
                hoveringOurTerminal = false
                return
            end
            local fname = actor:GetFName():ToString()
            hoveringOurTerminal = tracker.isTerminal(fname)
        end)
        if not ok then hoveringOurTerminal = false end
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

    -- Close via F6 — ESC can't be used because RegisterKeyBind doesn't
    -- consume input, so the game also processes it (opens settings menu).
    -- The UI has a close button [X] for mouse users.
    RegisterKeyBind(Key.F6, function()
        if not isOpen then return end
        ExecuteInGameThread(function()
            interaction.close()
        end)
    end)

end

return interaction
