-- DatabaseTerminal: UI module
-- Builds the UMG widget tree, handles keyboard navigation, pull actions

local UEHelpers = require("UEHelpers")
local ui = {}

-- Widget class references (lazy-init)
local wbLib, uwClass, canvasCls, vboxCls, hboxCls, textCls, scrollCls, imgCls

local root = nil       -- UUserWidget
local onClose = nil    -- callback to close interaction

local scanGroups = nil
local subRows = {}     -- flat list for keyboard nav: { group, container }
local selectedIdx = 1

local function initClasses()
    if wbLib then return end
    wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    uwClass = StaticFindObject("/Script/UMG.UserWidget")
    canvasCls = StaticFindObject("/Script/UMG.CanvasPanel")
    vboxCls = StaticFindObject("/Script/UMG.VerticalBox")
    hboxCls = StaticFindObject("/Script/UMG.HorizontalBox")
    textCls = StaticFindObject("/Script/UMG.TextBlock")
    scrollCls = StaticFindObject("/Script/UMG.ScrollBox")
    imgCls = StaticFindObject("/Script/UMG.Image")
end

local function buildSubRows(groups)
    subRows = {}
    for _, group in ipairs(groups) do
        for _, container in ipairs(group.containerList) do
            table.insert(subRows, { group = group, container = container })
        end
    end
end

function ui.getRoot()
    return root
end

function ui.close()
    if root then
        root:RemoveFromViewport()
        root = nil
    end
    scanGroups = nil
    subRows = {}
    selectedIdx = 1
    onClose = nil
end

function ui.open(groups, closeCb)
    initClasses()
    local pc = UEHelpers:GetPlayerController()
    if not pc then return end

    scanGroups = groups
    onClose = closeCb
    buildSubRows(groups)
    selectedIdx = 1

    -- Create root widget
    root = wbLib:Create(pc, uwClass, pc)
    if not root then
        print("[DBTerminal] Failed to create root widget\n")
        return
    end

    local canvas = StaticConstructObject(canvasCls, root, FName("Canvas"))
    root.WidgetTree.RootWidget = canvas

    -- Build the visual layout
    ui.rebuild(canvas)

    root:AddToViewport(200)
end

function ui.rebuild(canvas)
    -- TODO: Full visual implementation
    -- For now, console output as placeholder
    if not scanGroups then return end
    for _, group in ipairs(scanGroups) do
        print(string.format("[DBTerminal]   %s x%d\n", group.displayName, group.totalCount))
        for _, container in ipairs(group.containerList) do
            print(string.format("[DBTerminal]     %s: %d\n", container.label, container.count))
        end
    end
end

return ui
