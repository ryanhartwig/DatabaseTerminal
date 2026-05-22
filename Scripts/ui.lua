-- DatabaseTerminal: UI module
-- ScrollBox inventory browser with polished background and PULL buttons

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

local function makeText(outer, str)
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

--- Create a colored rectangle (Image with tint) anchored to the canvas
local function makeRect(root, canvas, name, color, x1, y1, x2, y2)
    local i = StaticConstructObject(classes.img, root, newName(name))
    pcall(function() i:SetColorAndOpacity(color) end)
    local s = canvas:AddChildToCanvas(i)
    s:SetAnchors({ Minimum = { X = x1, Y = y1 }, Maximum = { X = x2, Y = y2 } })
    s:SetAutoSize(false)
    return i
end

----------------------------------------------------------------------
-- Button system
----------------------------------------------------------------------
local buttonActions = {}
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
                ExecuteInGameThread(function() action() end)
            end
        end)
    end)
    buttonHookRegistered = true
end

local cachedButtonClass = nil

local function getButtonClass()
    if cachedButtonClass then return cachedButtonClass end
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

local function makeButton(root, text, onClick)
    local btnClass = getButtonClass()
    if not btnClass then
        return makeText(root, "[" .. text .. "]")
    end

    local pc = UEHelpers:GetPlayerController()
    local btn = classes.wbLib:Create(pc, btnClass, pc)
    if not btn then
        return makeText(root, "[" .. text .. "]")
    end

    pcall(function() btn:SetText(FText(text)) end)

    if onClick then
        buttonActions[tostring(btn:GetAddress())] = onClick
    end

    return btn
end

----------------------------------------------------------------------
-- Container type icons via UWEItemType Thumbnails (auto-loading TSoftObjectPtr)
----------------------------------------------------------------------
local CONTAINER_ITEM_TYPES = {
    SN2Locker                           = "DA_WallLocker_ItemType",
    BP_FloatingLocker_Carryable_C       = "DA_FloatingLocker_Carryable_ItemType",
    BP_Tailing_Chest_C                  = "DA_FloorLocker_ItemType",  -- closest match
    BP_BasicBatteryTerminal_C           = "DA_BasicBatteryTerminal_ItemType",
    BP_PowerCellTerminal_C              = "DA_PowerCellTerminal_ItemType",
    SN2Bioreactor                       = "DA_Bioreactor_ItemType",
    SN2ProcessorStation                 = "DA_Processor_ItemType",
    SN2BoxOfHolding                     = "DA_StorageCache_ItemType",
    BP_PlayerDied_Blackbox_Proto_C      = "DA_FloorLocker_ItemType",  -- fallback
}

local containerItemTypeCache = {}

local function getContainerItemType(containerClass)
    if containerItemTypeCache[containerClass] ~= nil then return containerItemTypeCache[containerClass] end
    local targetName = CONTAINER_ITEM_TYPES[containerClass]
    if not targetName then
        containerItemTypeCache[containerClass] = false
        return nil
    end
    -- Find the UWEItemType by name from all loaded instances
    local allTypes = FindAllOf("UWEItemType")
    if allTypes then
        for _, itemType in ipairs(allTypes) do
            local ok, name = pcall(function() return itemType:GetFName():ToString() end)
            if ok and name == targetName then
                containerItemTypeCache[containerClass] = itemType
                return itemType
            end
        end
    end
    containerItemTypeCache[containerClass] = false
    return nil
end

----------------------------------------------------------------------
-- Panel layout constants
----------------------------------------------------------------------
local PANEL = {
    L = 0.10, R = 0.90, T = 0.05, B = 0.95,  -- panel bounds
    GLOW = 0.008,                                -- outer glow size
    HEADER_H = 0.065,                            -- header height from top
    CONTENT_PAD = 0.02,                          -- content inset from panel edges
}

----------------------------------------------------------------------
-- Background rendering
----------------------------------------------------------------------
local function buildBackground(root, canvas)
    local L, R, T, B = PANEL.L, PANEL.R, PANEL.T, PANEL.B
    local G = PANEL.GLOW

    -- Outer glow
    makeRect(root, canvas, "OuterGlow",
        { R=0.04, G=0.12, B=0.22, A=0.6 },
        L-G, T-G, R+G, B+G)

    -- Main background
    makeRect(root, canvas, "MainBG",
        { R=0.015, G=0.025, B=0.05, A=0.94 },
        L, T, R, B)

    -- Top gradient
    makeRect(root, canvas, "GradTop",
        { R=0.05, G=0.10, B=0.18, A=0.35 },
        L, T, R, T+0.12)

    -- Bottom gradient
    makeRect(root, canvas, "GradBot",
        { R=0.005, G=0.01, B=0.02, A=0.4 },
        L, B-0.08, R, B)

    -- Accent lines
    makeRect(root, canvas, "AccentTop",
        { R=0.1, G=0.65, B=0.95, A=0.85 },
        L, T, R, T+0.004)

    makeRect(root, canvas, "AccentBot",
        { R=0.06, G=0.35, B=0.6, A=0.5 },
        L, B-0.003, R, B)

    makeRect(root, canvas, "AccentLeft",
        { R=0.06, G=0.35, B=0.6, A=0.3 },
        L, T, L+0.002, B)

    makeRect(root, canvas, "AccentRight",
        { R=0.06, G=0.35, B=0.6, A=0.3 },
        R-0.002, T, R, B)

    -- Header separator
    makeRect(root, canvas, "SepHeader",
        { R=0.08, G=0.4, B=0.65, A=0.45 },
        L+PANEL.CONTENT_PAD, T+PANEL.HEADER_H, R-PANEL.CONTENT_PAD, T+PANEL.HEADER_H+0.003)

    -- Content area inner border
    makeRect(root, canvas, "InnerBorder",
        { R=0.03, G=0.08, B=0.15, A=0.3 },
        L+0.015, T+PANEL.HEADER_H+0.01, R-0.015, B-0.015)

    -- Footer separator
    makeRect(root, canvas, "FooterSep",
        { R=0.08, G=0.4, B=0.65, A=0.25 },
        L+PANEL.CONTENT_PAD, B-0.045, R-PANEL.CONTENT_PAD, B-0.042)
end

----------------------------------------------------------------------
-- Header bar
----------------------------------------------------------------------
local function buildHeader(root, canvas, groups)
    local L, T = PANEL.L, PANEL.T

    -- Title
    local title = makeText(root, "DATABASE TERMINAL")
    local titleSlot = canvas:AddChildToCanvas(title)
    titleSlot:SetAnchors({ Minimum = { X = L+0.025, Y = T+0.018 }, Maximum = { X = L+0.025, Y = T+0.018 } })
    titleSlot:SetAutoSize(true)

    -- Stats
    local totalItems = 0
    local totalContainers = 0
    for _, group in ipairs(groups) do
        totalItems = totalItems + group.totalCount
        totalContainers = totalContainers + #group.containerList
    end

    local statsStr = string.format("%d items | %d containers", totalItems, totalContainers)
    statsWidget = makeText(root, statsStr)
    local statsSlot = canvas:AddChildToCanvas(statsWidget)
    statsSlot:SetAnchors({ Minimum = { X = PANEL.R-0.22, Y = T+0.018 }, Maximum = { X = PANEL.R-0.22, Y = T+0.018 } })
    statsSlot:SetAutoSize(true)

    -- Footer version
    local ver = makeText(root, "Database Terminal v0.1.0")
    local verSlot = canvas:AddChildToCanvas(ver)
    verSlot:SetAnchors({ Minimum = { X = L+0.025, Y = PANEL.B-0.035 }, Maximum = { X = L+0.025, Y = PANEL.B-0.035 } })
    verSlot:SetAutoSize(true)
end

----------------------------------------------------------------------
-- Content area (ScrollBox with item groups)
----------------------------------------------------------------------

-- Widget references for live updates
local statsWidget = nil
local groupWidgets = {}  -- { groupBox, countText, subRows: { subRow, countText, container, group } }

local function updateStatsText()
    if not statsWidget or not scanGroups then return end
    local totalItems = 0
    local totalContainers = 0
    for _, group in ipairs(scanGroups) do
        totalItems = totalItems + group.totalCount
        totalContainers = totalContainers + #group.containerList
    end
    pcall(function()
        statsWidget:SetText(FText(string.format("%d items | %d containers", totalItems, totalContainers)))
    end)
end

--- Called after a successful pull — update counts and hide empty rows
function ui.onPullComplete(container, group)
    -- Decrement counts
    container.count = container.count - 1
    group.totalCount = group.totalCount - 1
    table.remove(container.items, 1)

    -- Update group widgets
    for _, gw in ipairs(groupWidgets) do
        if gw.group == group then
            -- Update group header count
            pcall(function()
                gw.countText:SetText(FText("x" .. group.totalCount))
            end)

            -- Update sub-row counts
            for _, sr in ipairs(gw.subRows) do
                if sr.container == container then
                    if container.count <= 0 then
                        -- Collapse the empty sub-row (1 = Collapsed in UE5)
                        pcall(function() sr.subRow:SetVisibility(1) end)
                    else
                        pcall(function()
                            sr.countText:SetText(FText("x" .. container.count .. "  "))
                        end)
                    end
                end
            end

            -- Hide entire group if total is 0
            if group.totalCount <= 0 then
                pcall(function() gw.groupBox:SetVisibility(1) end)
            end
        end
    end

    -- Update header stats
    updateStatsText()
end

local function buildContent(root, canvas, scrollBox, groups, pullCallback)
    groupWidgets = {}

    -- Position scrollbox
    local contentTop = PANEL.T + PANEL.HEADER_H + 0.015
    local contentBot = PANEL.B - 0.05
    local scrollSlot = canvas:AddChildToCanvas(scrollBox)
    scrollSlot:SetAnchors({
        Minimum = { X = PANEL.L + PANEL.CONTENT_PAD + 0.01, Y = contentTop },
        Maximum = { X = PANEL.R - PANEL.CONTENT_PAD - 0.01, Y = contentBot }
    })
    scrollSlot:SetAutoSize(false)

    -- Empty state
    if #groups == 0 then
        local emptyText = makeText(root, "No items found in nearby containers.")
        scrollBox:AddChild(emptyText)
        return
    end

    -- Item groups
    for idx, group in ipairs(groups) do
        local groupBox = makeVBox(root)
        local gw = { groupBox = groupBox, group = group, countText = nil, subRows = {} }

        -- Item header: icon + name + (spacer) + total count
        local itemHeader = makeHBox(root)

        local icon = makeImage(root)
        pcall(function()
            icon:SetBrushFromSoftTexture(group.itemType.Thumbnail, true)
        end)
        local iconSize = makeSizeBox(root, 32, 32)
        iconSize:SetContent(icon)
        itemHeader:AddChildToHorizontalBox(iconSize)

        -- Small gap between icon and name
        local iconGap = makeSizeBox(root, 8, 1)
        itemHeader:AddChildToHorizontalBox(iconGap)

        local nameText = makeText(root, group.displayName)
        itemHeader:AddChildToHorizontalBox(nameText)

        -- Fill spacer pushes count to the right
        local headerSpacer = StaticConstructObject(classes.sizeBox, root, newName("Spacer"))
        pcall(function() headerSpacer:SetMinDesiredWidth(20) end)
        local headerSpacerSlot = itemHeader:AddChildToHorizontalBox(headerSpacer)
        pcall(function() headerSpacerSlot:SetSize({ SizeRule = 1, Value = 1.0 }) end)

        local countText = makeText(root, "x" .. group.totalCount)
        itemHeader:AddChildToHorizontalBox(countText)
        gw.countText = countText

        groupBox:AddChildToVerticalBox(itemHeader)

        -- Sub-rows per container
        for _, container in ipairs(group.containerList) do
            local subRow = makeHBox(root)

            -- Indentation
            local indent = makeSizeBox(root, 28, 1)
            subRow:AddChildToHorizontalBox(indent)

            -- Container type icon (uses same TSoftObjectPtr pattern as item thumbnails)
            local containerIcon = makeImage(root)
            local containerType = getContainerItemType(container.containerClass)
            if containerType then
                pcall(function()
                    containerIcon:SetBrushFromSoftTexture(containerType.Thumbnail, false)
                end)
            end
            local cIconSize = makeSizeBox(root, 20, 20)
            cIconSize:SetContent(containerIcon)
            subRow:AddChildToHorizontalBox(cIconSize)

            -- Small gap after icon
            local iconGap = makeSizeBox(root, 6, 1)
            subRow:AddChildToHorizontalBox(iconGap)

            local labelText = makeText(root, container.label)
            subRow:AddChildToHorizontalBox(labelText)

            -- Fill spacer pushes count + button to the right
            local spacer = StaticConstructObject(classes.sizeBox, root, newName("Spacer"))
            pcall(function() spacer:SetMinDesiredWidth(20) end)
            local spacerSlot = subRow:AddChildToHorizontalBox(spacer)
            pcall(function() spacerSlot:SetSize({ SizeRule = 1, Value = 1.0 }) end)

            local subCount = makeText(root, "x" .. container.count .. "  ")
            subRow:AddChildToHorizontalBox(subCount)

            local pullBtn = makeButton(root, "PULL", function()
                if pullCallback and #container.items > 0 then
                    pullCallback(container, container.items[1], group)
                end
            end)
            subRow:AddChildToHorizontalBox(pullBtn)

            groupBox:AddChildToVerticalBox(subRow)

            table.insert(gw.subRows, {
                subRow = subRow,
                countText = subCount,
                container = container,
            })
        end

        scrollBox:AddChild(groupBox)

        -- Add subtle divider line between groups (not after the last one)
        if idx < #groups then
            local divider = StaticConstructObject(classes.img, root, newName("Div"))
            pcall(function() divider:SetColorAndOpacity({ R=0.06, G=0.2, B=0.35, A=0.3 }) end)
            local divSize = makeSizeBox(root, nil, 2)
            divSize:SetContent(divider)
            scrollBox:AddChild(divSize)
        end

        table.insert(groupWidgets, gw)
    end
end

----------------------------------------------------------------------
-- UI State
----------------------------------------------------------------------
local root = nil
local canvas = nil
local scrollBox = nil
local scanGroups = nil
local onCloseCb = nil
local pullCallback = nil

function ui.getRoot()
    return root
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

    -- Create root
    root = classes.wbLib:Create(pc, classes.uwClass, pc)
    if not root then
        print("[DBTerminal] Failed to create root widget\n")
        return
    end

    canvas = StaticConstructObject(classes.canvas, root, FName("Canvas"))
    root.WidgetTree.RootWidget = canvas

    -- Build layers
    buildBackground(root, canvas)
    buildHeader(root, canvas, groups)

    -- ScrollBox
    scrollBox = StaticConstructObject(classes.scroll, root, FName("ScrollArea"))
    buildContent(root, canvas, scrollBox, groups, pullCallback)

    -- Show at high z-order
    root:AddToViewport(500)
    -- Close via ESC/F6 keybinds in interaction.lua (no NoA widget polling needed
    -- since CloseUI() prevents the NoA widget from ever opening)
end

function ui.close()
    buttonActions = {}
    groupWidgets = {}
    statsWidget = nil

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
