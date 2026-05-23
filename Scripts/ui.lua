-- DatabaseTerminal: UI module
-- ScrollBox inventory browser with polished background and PULL buttons

local UEHelpers = require("UEHelpers")
local textures = require("textures")
local styles = require("styles")
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
    classes.editText = StaticFindObject("/Script/UMG.EditableTextBox")
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

local function makeText(outer, str, styleName)
    local tb = StaticConstructObject(classes.text, outer, newName("Txt"))
    if str then tb:SetText(FText(str)) end
    if styleName then styles.apply(tb, styleName) end
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
    -- Use the slim blue button from PDA Signal Manager (same as "EDIT" buttons)
    cachedButtonClass = StaticFindObject(
        "/Game/Blueprints/UI/GenericUIElements/GenericUI_WBP/WBP_ButtonGenericBlueSmall.WBP_ButtonGenericBlueSmall_C")
    -- Fallback: grab any CommonButtonBase instance class
    if not cachedButtonClass then
        local candidates = FindAllOf("CommonButtonBase")
        if candidates then
            for _, btn in ipairs(candidates) do
                if btn:IsValid() then
                    cachedButtonClass = btn:GetClass()
                    return cachedButtonClass
                end
            end
        end
    end
    return cachedButtonClass
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
    -- Specific locker types (actual Blueprint class names from actor:GetClass())
    BP_Locker_Floor_C                   = "DA_FloorLocker_ItemType",
    BP_LifepodWallLocker_C              = "DA_WallLocker_ItemType",
    -- Floating/portable lockers
    BP_FloatingLocker_Carryable_C       = "DA_FloatingLocker_Carryable_ItemType",
    -- Chargers
    BP_BasicBatteryTerminal_C           = "DA_BasicBatteryTerminal_ItemType",
    BP_PowerCellTerminal_C              = "DA_PowerCellTerminal_ItemType",
    -- Other containers
    BP_Tailing_Chest_C                  = "DA_Tailing_Chest_ItemType",
    BP_Tailing_Jar_C                    = "DA_Tailing_Jar_ItemType",
    BP_Tailing_Jar_Hanging_C            = "DA_Tailing_Jar_Hanging_ItemType",
    BP_Tailing_Jar_Coral_C              = "DA_Tailing_Jar_Coral_ItemType",
    BP_Tailing_Jar_Coral_Small_C        = "DA_Tailing_Jar_Coral_Small_ItemType",
    SN2Bioreactor                       = "DA_Bioreactor_ItemType",
    SN2ProcessorStation                 = "DA_Processor_ItemType",
    SN2BoxOfHolding                     = "DA_StorageCache_ItemType",
    BP_PlayerDied_Blackbox_Proto_C      = "DA_FloorLocker_ItemType",
    -- Fallback for any SN2Locker subclass not listed above
    SN2Locker                           = "DA_WallLocker_ItemType",
}

local containerItemTypeCache = {}

--- Look up container icon item type, trying actor class first then source class
local function getContainerItemType(containerClass, sourceClass)
    local cacheKey = containerClass or sourceClass or ""
    if containerItemTypeCache[cacheKey] ~= nil then return containerItemTypeCache[cacheKey] end

    -- Try actor class first (e.g. BP_Locker_Floor_C), then source class (e.g. SN2Locker)
    local targetName = CONTAINER_ITEM_TYPES[containerClass]
    if not targetName and sourceClass then
        targetName = CONTAINER_ITEM_TYPES[sourceClass]
    end
    if not targetName then
        containerItemTypeCache[cacheKey] = false
        return nil
    end
    -- Find the UWEItemType by name from all loaded instances
    local allTypes = FindAllOf("UWEItemType")
    if allTypes then
        for _, itemType in ipairs(allTypes) do
            local ok, name = pcall(function() return itemType:GetFName():ToString() end)
            if ok and name == targetName then
                containerItemTypeCache[cacheKey] = itemType
                return itemType
            end
        end
    end
    containerItemTypeCache[containerClass] = false
    return nil
end

----------------------------------------------------------------------
-- Panel layout — height-driven, aspect-locked
----------------------------------------------------------------------
local DESIGN_W, DESIGN_H = 1536, 972  -- PNG design dimensions
local DESIGN_RATIO = DESIGN_W / DESIGN_H  -- ~1.58
local PANEL_HEIGHT = 0.80  -- fraction of viewport height (0.0–1.0, tune this)

local PANEL = {
    L = 0.10, R = 0.90, T = 0.10, B = 0.90,  -- defaults (overwritten by computeBounds)
    GLOW = 0.008,
    HEADER_H = 0.065,
    CONTENT_PAD = 0.02,
}

--- Recalculate panel anchors based on viewport dimensions.
--- Panel always fills 90% of viewport height, width derived from design ratio.
--- Centered horizontally. Falls back to defaults if viewport can't be read.
local function computeBounds()
    local vpW, vpH = 0, 0

    -- Try multiple approaches to get viewport size
    pcall(function()
        local pc = UEHelpers:GetPlayerController()

        -- Approach 1: GameViewportClient:GetViewportSize (out param)
        pcall(function()
            local vp = pc:GetLocalPlayer():GetViewportClient()
            local size = { X = 0, Y = 0 }
            vp:GetViewportSize(size)
            vpW, vpH = size.X, size.Y
        end)

        -- Approach 2: WidgetLayoutLibrary if approach 1 failed
        if vpW <= 0 or vpH <= 0 then
            pcall(function()
                local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
                local size = wll:GetViewportSize(pc)
                vpW, vpH = size.X, size.Y
            end)
        end
    end)

    print(string.format("[DBTerminal] Viewport: %dx%d\n", vpW, vpH))

    if vpW <= 0 or vpH <= 0 then return end  -- keep defaults

    local halfH = PANEL_HEIGHT / 2
    local T, B = 0.5 - halfH, 0.5 + halfH
    local panelH = PANEL_HEIGHT * vpH
    local panelW = panelH * DESIGN_RATIO
    local maxW = 0.92 * vpW
    if panelW > maxW then panelW = maxW end

    local halfW = (panelW / vpW) / 2
    PANEL.L = 0.5 - halfW
    PANEL.R = 0.5 + halfW
    PANEL.T = T
    PANEL.B = B

    print(string.format("[DBTerminal] Panel bounds: L=%.3f R=%.3f (width=%.1f%%)\n",
        PANEL.L, PANEL.R, (PANEL.R - PANEL.L) * 100))
end

----------------------------------------------------------------------
-- Animated material overlays
----------------------------------------------------------------------

--- Try to apply a game material to an Image widget.
--- Materials may not be loaded until the relevant game screen is opened.
--- Returns the Image widget if successful, nil otherwise.
local function applyMaterial(root, canvas, name, matPath, x1, y1, x2, y2, opacity)
    local mat = StaticFindObject(matPath)
    if not mat then return nil end

    local img = StaticConstructObject(classes.img, root, newName(name))
    local ok = pcall(function() img:SetBrushFromMaterial(mat) end)
    if not ok then return nil end

    if opacity then
        pcall(function() img:SetRenderOpacity(opacity) end)
    end

    local slot = canvas:AddChildToCanvas(img)
    slot:SetAnchors({ Minimum = { X = x1, Y = y1 }, Maximum = { X = x2, Y = y2 } })
    slot:SetAutoSize(false)
    return img
end

----------------------------------------------------------------------
-- Background rendering
----------------------------------------------------------------------
local NUM_HEX_BANDS = 8

local function buildBackground(root, canvas)
    local L, R, T, B = PANEL.L, PANEL.R, PANEL.T, PANEL.B
    local G = PANEL.GLOW

    -- Background with hex grid baked in
    local bgTex = textures.get("Background")
    if bgTex then
        local bg = StaticConstructObject(classes.img, root, newName("BG"))
        pcall(function() bg:SetBrushFromTexture(bgTex, false) end)
        local bgSlot = canvas:AddChildToCanvas(bg)
        bgSlot:SetAnchors({ Minimum = { X = L, Y = T }, Maximum = { X = R, Y = B } })
        bgSlot:SetAutoSize(false)
    else
        -- Fallback: rectangle-based background
        makeRect(root, canvas, "OuterGlow",
            { R=0.04, G=0.12, B=0.22, A=0.6 },
            L-G, T-G, R+G, B+G)

        makeRect(root, canvas, "MainBG",
            { R=0.015, G=0.025, B=0.05, A=0.94 },
            L, T, R, B)

        makeRect(root, canvas, "GradTop",
            { R=0.05, G=0.10, B=0.18, A=0.35 },
            L, T, R, T+0.12)

        makeRect(root, canvas, "GradBot",
            { R=0.005, G=0.01, B=0.02, A=0.4 },
            L, B-0.08, R, B)

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
end

----------------------------------------------------------------------
-- Content area (ScrollBox with item groups)
----------------------------------------------------------------------

-- Widget references for live updates
local groupWidgets = {}  -- { groupBox, countText, subRows: { subRow, countText, container, group } }

----------------------------------------------------------------------
-- Header bar
----------------------------------------------------------------------
local function buildHeader(root, canvas, groups, closeCb)
    local L, R, T = PANEL.L, PANEL.R, PANEL.T

    -- Title
    local title = makeText(root, "DATABASE TERMINAL", "title")
    local titleSlot = canvas:AddChildToCanvas(title)
    local panelW = R - L
    local titleMidX = (L + R) / 2 - 0.034 * panelW  -- same nudge as loading screen
    titleSlot:SetAnchors({ Minimum = { X = titleMidX, Y = T+0.05 }, Maximum = { X = titleMidX, Y = T+0.05 } })
    pcall(function() titleSlot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
    titleSlot:SetAutoSize(true)

    -- Footer version
    local ver = makeText(root, "Database Terminal v0.1.0", "footer")
    local verSlot = canvas:AddChildToCanvas(ver)
    verSlot:SetAnchors({ Minimum = { X = L+0.05, Y = PANEL.B-0.066 }, Maximum = { X = L+0.05, Y = PANEL.B-0.066 } })
    verSlot:SetAutoSize(true)

    -- Alterra glitch logo — top-right, fixed pixel size to prevent stretch
    pcall(function()
        local mat = StaticFindObject("/Game/UI/Materials_test/Glitch/M_Glitch.M_Glitch")
        if mat then
            local logoImg = makeImage(root)
            pcall(function() logoImg:SetBrushFromMaterial(mat) end)
            pcall(function() logoImg:SetRenderOpacity(0.8) end)
            local logoBox = makeSizeBox(root, 80, 50)
            logoBox:SetContent(logoImg)
            local logoSlot = canvas:AddChildToCanvas(logoBox)
            logoSlot:SetAnchors({ Minimum = { X = R - 0.10, Y = T + 0.055 }, Maximum = { X = R - 0.10, Y = T + 0.055 } })
            logoSlot:SetAutoSize(true)
            pcall(function() logoSlot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
        end
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

            -- Hide entire group + its divider if total is 0
            if group.totalCount <= 0 then
                pcall(function() gw.groupBox:SetVisibility(1) end)
                if gw.divider then
                    pcall(function() gw.divider:SetVisibility(1) end)
                end
            end
        end
    end

end

local function buildContent(root, canvas, scrollBox, groups, pullCallback)
    groupWidgets = {}

    -- Position scrollbox
    local contentTop = PANEL.T + PANEL.HEADER_H + 0.055  -- extra space for search box
    local contentBot = PANEL.B - 0.055
    local scrollSlot = canvas:AddChildToCanvas(scrollBox)
    scrollSlot:SetAnchors({
        Minimum = { X = PANEL.L + PANEL.CONTENT_PAD + 0.01, Y = contentTop },
        Maximum = { X = PANEL.R - PANEL.CONTENT_PAD - 0.01, Y = contentBot }
    })
    scrollSlot:SetAutoSize(false)

    -- Empty state
    if #groups == 0 then
        local emptyText = makeText(root, "No items found in nearby containers.", "empty")
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
        local iconSize = makeSizeBox(root, 48, 48)
        iconSize:SetContent(icon)
        itemHeader:AddChildToHorizontalBox(iconSize)

        -- Small gap between icon and name
        local iconGap = makeSizeBox(root, 8, 1)
        itemHeader:AddChildToHorizontalBox(iconGap)

        local nameText = makeText(root, group.displayName, "itemName")
        local nameSlot = itemHeader:AddChildToHorizontalBox(nameText)
        pcall(function() nameSlot:SetPadding({ Top = 12, Bottom = 0, Left = 0, Right = 0 }) end)

        -- Fill spacer pushes count to the right
        local headerSpacer = StaticConstructObject(classes.sizeBox, root, newName("Spacer"))
        pcall(function() headerSpacer:SetMinDesiredWidth(20) end)
        local headerSpacerSlot = itemHeader:AddChildToHorizontalBox(headerSpacer)
        pcall(function() headerSpacerSlot:SetSize({ SizeRule = 1, Value = 1.0 }) end)

        local countText = makeText(root, "x" .. group.totalCount, "count")
        local countSlot = itemHeader:AddChildToHorizontalBox(countText)
        pcall(function() countSlot:SetPadding({ Top = 14, Bottom = 0, Left = 0, Right = 0 }) end)
        gw.countText = countText

        groupBox:AddChildToVerticalBox(itemHeader)

        -- Sub-rows per container
        for _, container in ipairs(group.containerList) do
            local subRow = makeHBox(root)

            -- Indentation (increased for visual hierarchy)
            local indent = makeSizeBox(root, 56, 1)
            subRow:AddChildToHorizontalBox(indent)

            -- Container type icon (dimmed to let material icons stand out)
            local containerIcon = makeImage(root)
            local containerType = getContainerItemType(container.containerClass, container.sourceClass)
            if containerType then
                pcall(function()
                    containerIcon:SetBrushFromSoftTexture(containerType.Thumbnail, false)
                    containerIcon:SetDesiredSizeOverride({ X = 28, Y = 28 })
                    containerIcon:SetRenderOpacity(0.5)
                end)
            end
            local cIconSize = StaticConstructObject(classes.sizeBox, root, newName("CISize"))
            pcall(function() cIconSize:SetWidthOverride(36) end)
            pcall(function() cIconSize:SetContent(containerIcon) end)
            subRow:AddChildToHorizontalBox(cIconSize)

            -- Small gap after icon
            local iconGap = makeSizeBox(root, 6, 1)
            subRow:AddChildToHorizontalBox(iconGap)

            local labelText = makeText(root, container.label, "container")
            local labelSlot = subRow:AddChildToHorizontalBox(labelText)
            pcall(function() labelSlot:SetPadding({ Top = 8, Bottom = 0, Left = 0, Right = 0 }) end)

            -- Fill spacer pushes count + button to the right
            local spacer = StaticConstructObject(classes.sizeBox, root, newName("Spacer"))
            pcall(function() spacer:SetMinDesiredWidth(20) end)
            local spacerSlot = subRow:AddChildToHorizontalBox(spacer)
            pcall(function() spacerSlot:SetSize({ SizeRule = 1, Value = 1.0 }) end)

            local subCount = makeText(root, "x" .. container.count .. "  ", "countSub")
            local subCountSlot = subRow:AddChildToHorizontalBox(subCount)
            pcall(function() subCountSlot:SetPadding({ Top = 6, Bottom = 0, Left = 0, Right = 0 }) end)

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
            gw.divider = divSize
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

--- Flash a temporary message at the bottom of the panel (auto-fades after 2s)
local messageWidget = nil
function ui.showMessage(text)
    if not root or not canvas then return end
    -- Remove existing message
    if messageWidget then
        pcall(function() messageWidget:SetVisibility(1) end)
    end
    -- Create or reuse
    if not messageWidget then
        messageWidget = makeText(root, text, "loading")
        local msgSlot = canvas:AddChildToCanvas(messageWidget)
        local midX = (PANEL.L + PANEL.R) / 2
        msgSlot:SetAnchors({ Minimum = { X = midX, Y = PANEL.B - 0.08 }, Maximum = { X = midX, Y = PANEL.B - 0.08 } })
        msgSlot:SetAutoSize(true)
        pcall(function() msgSlot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
    else
        pcall(function() messageWidget:SetText(FText(text)) end)
    end
    pcall(function() messageWidget:SetVisibility(0) end)
    -- Auto-hide after 2 seconds
    ExecuteWithDelay(2000, function()
        ExecuteInGameThread(function()
            if messageWidget then
                pcall(function() messageWidget:SetVisibility(1) end)
            end
        end)
    end)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function ui.open(groups, closeCb, onPull, refreshCb)
    if not initClasses() then
        print("[DBTerminal] Failed to init widget classes\n")
        return
    end

    -- Textures are reimported fresh by interaction.lua before each open
    -- (UE GC can free unrooted UTexture2Ds between interactions)

    computeBounds()   -- recalculate PANEL anchors for current viewport size
    styles.captureGameFont()  -- grab game font asset for styled text
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
    buildHeader(root, canvas, groups, closeCb)

    -- Search box + refresh button
    local searchY = PANEL.T + PANEL.HEADER_H + 0.015
    local searchL = PANEL.L + PANEL.CONTENT_PAD + 0.01
    local searchR = PANEL.R - PANEL.CONTENT_PAD - 0.01

    if refreshCb then
        -- Place refresh button at the right edge, shrink search box to fit
        searchR = PANEL.R - PANEL.CONTENT_PAD - 0.08
        local refreshBtn = makeButton(root, "REFRESH", function()
            refreshCb()
        end)
        local refreshSlot = canvas:AddChildToCanvas(refreshBtn)
        refreshSlot:SetAnchors({
            Minimum = { X = searchR + 0.005, Y = searchY },
            Maximum = { X = searchR + 0.005, Y = searchY }
        })
        refreshSlot:SetAutoSize(true)
    end

    local searchBox = StaticConstructObject(classes.editText, root, FName("SearchBox"))
    pcall(function() searchBox:SetText(FText("")) end)
    pcall(function() searchBox:SetHintText(FText("Search items...")) end)
    pcall(function() searchBox:SetForegroundColor({ R=0.8, G=0.9, B=1.0, A=1.0 }) end)
    -- Make the default gray background transparent
    pcall(function() searchBox:SetRenderOpacity(0.8) end)
    pcall(function()
        local style = searchBox.WidgetStyle
        style.BackgroundImageNormal.TintColor = { SpecifiedColor = { R=0, G=0, B=0, A=0 } }
        style.BackgroundImageHovered.TintColor = { SpecifiedColor = { R=0.1, G=0.3, B=0.5, A=0.3 } }
        style.BackgroundImageFocused.TintColor = { SpecifiedColor = { R=0.1, G=0.4, B=0.6, A=0.4 } }
    end)
    local searchSlot = canvas:AddChildToCanvas(searchBox)
    searchSlot:SetAnchors({
        Minimum = { X = searchL, Y = searchY },
        Maximum = { X = searchR, Y = searchY }
    })
    searchSlot:SetAutoSize(true)

    -- Poll search text and filter groups
    local lastSearchText = ""
    LoopAsync(200, function()
        if not root then return true end
        local ok, searchText = pcall(function()
            local ft = searchBox:GetText()
            local resolveOk, str = pcall(function() return ft:ToString() end)
            return resolveOk and str or ""
        end)
        if not ok then return true end
        if searchText == lastSearchText then return false end
        lastSearchText = searchText

        local filter = searchText:lower()
        for _, gw in ipairs(groupWidgets) do
            local match = (filter == "") or gw.group.displayName:lower():find(filter, 1, true)
            pcall(function()
                gw.groupBox:SetVisibility(match and 0 or 1)
            end)
        end
        return false
    end)

    -- ScrollBox
    scrollBox = StaticConstructObject(classes.scroll, root, FName("ScrollArea"))
    buildContent(root, canvas, scrollBox, groups, pullCallback)

    -- Show at high z-order
    root:AddToViewport(500)
end

function ui.close()
    buttonActions = {}
    groupWidgets = {}
    messageWidget = nil

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
