-- DatabaseTerminal: UI module
-- ScrollBox inventory browser with PULL buttons

local UEHelpers = require("UEHelpers")
local ui = {}

----------------------------------------------------------------------
-- Widget class cache (lazy-init)
----------------------------------------------------------------------
local classes = {}

local function initClasses()
    if classes.wbLib then return true end
    classes.wbLib    = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    classes.uwClass  = StaticFindObject("/Script/UMG.UserWidget")
    classes.canvas   = StaticFindObject("/Script/UMG.CanvasPanel")
    classes.vbox     = StaticFindObject("/Script/UMG.VerticalBox")
    classes.hbox     = StaticFindObject("/Script/UMG.HorizontalBox")
    classes.text     = StaticFindObject("/Script/UMG.TextBlock")
    classes.scroll   = StaticFindObject("/Script/UMG.ScrollBox")
    classes.img      = StaticFindObject("/Script/UMG.Image")
    classes.sizeBox  = StaticFindObject("/Script/UMG.SizeBox")
    return classes.wbLib ~= nil
end

----------------------------------------------------------------------
-- Widget factory helpers
----------------------------------------------------------------------
local widgetCounter = 0

local function newName(prefix)
    widgetCounter = widgetCounter + 1
    return FName(prefix .. "_" .. widgetCounter)
end

local function makeText(outer, str, size)
    local tb = StaticConstructObject(classes.text, outer, newName("Txt"))
    if str then tb:SetText(FText(str)) end
    return tb
end

local function makeImage(outer)
    return StaticConstructObject(classes.img, outer, newName("Img"))
end

local function makeHBox(outer)
    return StaticConstructObject(classes.hbox, outer, newName("HBox"))
end

local function makeVBox(outer)
    return StaticConstructObject(classes.vbox, outer, newName("VBox"))
end

local function makeSizeBox(outer, width, height)
    local sb = StaticConstructObject(classes.sizeBox, outer, newName("Size"))
    if width then pcall(function() sb:SetWidthOverride(width) end) end
    if height then pcall(function() sb:SetHeightOverride(height) end) end
    return sb
end

----------------------------------------------------------------------
-- Button system — uses game's CommonButtonBase via wbLib:Create
----------------------------------------------------------------------
local buttonActions = {}  -- address string → callback function
local buttonHookRegistered = false

local function registerButtonHook()
    if buttonHookRegistered then return end
    pcall(function()
        RegisterHook("/Script/CommonUI.CommonButtonBase:HandleButtonClicked", function(self)
            local widget = self:get()
            if not widget or not widget:IsValid() then return end
            local addr = tostring(widget:GetAddress())
            local action = buttonActions[addr]
            if action then
                ExecuteInGameThread(function()
                    action()
                end)
            end
        end)
    end)
    buttonHookRegistered = true
end

--- Find a game button class to use as template
local cachedButtonClass = nil

local function getButtonClass()
    if cachedButtonClass then return cachedButtonClass end
    -- Try to find WBP_GenericButtonBig from loaded widgets
    local candidates = FindAllOf("CommonButtonBase")
    if candidates then
        for _, btn in ipairs(candidates) do
            if btn:IsValid() then
                cachedButtonClass = btn:GetClass()
                return cachedButtonClass
            end
        end
    end
    return nil
end

--- Create a clickable button with text and callback
local function makeButton(outer, text, onClick)
    local btnClass = getButtonClass()
    if not btnClass then
        -- Fallback: return a text label (no click)
        local label = makeText(outer, "[" .. text .. "]")
        return label
    end

    local pc = UEHelpers:GetPlayerController()
    local btn = classes.wbLib:Create(pc, btnClass, pc)
    if not btn then
        return makeText(outer, "[" .. text .. "]")
    end

    -- Try to set the button text
    pcall(function() btn:SetText(FText(text)) end)

    -- Register click handler
    if onClick then
        buttonActions[tostring(btn:GetAddress())] = onClick
    end

    return btn
end

----------------------------------------------------------------------
-- UI State
----------------------------------------------------------------------
local root = nil
local canvas = nil
local scrollBox = nil
local scanGroups = nil
local onCloseCb = nil
local pullCallback = nil  -- function(container, itemEntry)

function ui.getRoot()
    return root
end

----------------------------------------------------------------------
-- Build the widget tree from scan data
----------------------------------------------------------------------
local function buildContent()
    if not scrollBox or not scanGroups then return end

    -- Header bar
    local header = makeHBox(root)
    local titleText = makeText(root, "DATABASE TERMINAL")
    header:AddChildToHorizontalBox(titleText)

    -- Stats
    local totalItems = 0
    local totalContainers = 0
    for _, group in ipairs(scanGroups) do
        totalItems = totalItems + group.totalCount
        totalContainers = totalContainers + #group.containerList
    end
    local statsText = makeText(root, string.format("    %d items | %d containers    [ESC] Close", totalItems, totalContainers))
    header:AddChildToHorizontalBox(statsText)

    local headerSlot = canvas:AddChildToCanvas(header)
    headerSlot:SetAnchors({ Minimum = { X = 0.15, Y = 0.08 }, Maximum = { X = 0.85, Y = 0.08 } })
    headerSlot:SetAutoSize(true)

    -- ScrollBox positioned below header
    local scrollSlot = canvas:AddChildToCanvas(scrollBox)
    scrollSlot:SetAnchors({ Minimum = { X = 0.15, Y = 0.13 }, Maximum = { X = 0.85, Y = 0.88 } })
    scrollSlot:SetAutoSize(false)

    -- Empty state
    if #scanGroups == 0 then
        local emptyText = makeText(root, "No items found in nearby containers.")
        scrollBox:AddChild(emptyText)
        return
    end

    -- Item groups
    for _, group in ipairs(scanGroups) do
        local groupBox = makeVBox(root)

        -- Item header row: icon + name + total count
        local itemHeader = makeHBox(root)

        -- Thumbnail icon
        local icon = makeImage(root)
        pcall(function()
            icon:SetBrushFromSoftTexture(group.itemType.Thumbnail, true)
        end)
        local iconSize = makeSizeBox(root, 32, 32)
        iconSize:SetContent(icon)
        itemHeader:AddChildToHorizontalBox(iconSize)

        -- Item name + total count
        local nameText = makeText(root, string.format("  %s", group.displayName))
        itemHeader:AddChildToHorizontalBox(nameText)

        local countText = makeText(root, string.format("  x%d", group.totalCount))
        itemHeader:AddChildToHorizontalBox(countText)

        groupBox:AddChildToVerticalBox(itemHeader)

        -- Sub-rows: one per container holding this item
        for _, container in ipairs(group.containerList) do
            local subRow = makeHBox(root)

            -- Indented label + count
            local labelText = makeText(root, string.format("        %s", container.label))
            subRow:AddChildToHorizontalBox(labelText)

            local subCount = makeText(root, string.format("  x%d  ", container.count))
            subRow:AddChildToHorizontalBox(subCount)

            -- PULL button
            local pullBtn = makeButton(root, "PULL", function()
                if pullCallback and #container.items > 0 then
                    pullCallback(container, container.items[1])
                end
            end)
            subRow:AddChildToHorizontalBox(pullBtn)

            groupBox:AddChildToVerticalBox(subRow)
        end

        scrollBox:AddChild(groupBox)
    end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function ui.open(groups, closeCb, onPull)
    if not initClasses() then
        print("[DBTerminal] Failed to init widget classes\n")
        return
    end

    registerButtonHook()

    scanGroups = groups
    onCloseCb = closeCb
    pullCallback = onPull

    local pc = UEHelpers:GetPlayerController()
    if not pc then return end

    -- Create root widget
    root = classes.wbLib:Create(pc, classes.uwClass, pc)
    if not root then
        print("[DBTerminal] Failed to create root widget\n")
        return
    end

    canvas = StaticConstructObject(classes.canvas, root, FName("Canvas"))
    root.WidgetTree.RootWidget = canvas

    -- Create scroll box
    scrollBox = StaticConstructObject(classes.scroll, root, FName("ScrollArea"))

    -- Build content
    buildContent()

    -- Show at high z-order (above the NoA widget)
    root:AddToViewport(500)

    -- Poll: if the NoA widget closes (player pressed ESC), close our UI too
    LoopAsync(200, function()
        if not root then return true end  -- we're already closed
        local ctiWidgets = FindAllOf("WBP_ComputerTextInterface_C")
        local anyActive = false
        if ctiWidgets then
            for _, w in ipairs(ctiWidgets) do
                if w:IsValid() then
                    local ok, active = pcall(function() return w:IsActivated() end)
                    if ok and active then anyActive = true; break end
                end
            end
        end
        if not anyActive and onCloseCb then
            ExecuteInGameThread(function()
                onCloseCb()
            end)
            return true
        end
        return false
    end)
end

function ui.close()
    -- Clear button actions for our widgets
    buttonActions = {}

    if root then
        pcall(function() root:RemoveFromViewport() end)
        root = nil
    end
    canvas = nil
    scrollBox = nil
    scanGroups = nil
    onCloseCb = nil
    pullCallback = nil
    widgetCounter = 0
end

return ui
