-- DatabaseTerminal: Interaction handler
-- Hooks InteractClient, manages UI open/close lifecycle

local UEHelpers = require("UEHelpers")
local textures = require("textures")
local styles = require("styles")
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
local modalBlocker = nil  -- ModalActivatableWidget on WindowManager layer 3
                          -- blocks escape menu while our UI is open

----------------------------------------------------------------------
-- Loading screen
----------------------------------------------------------------------
-- Design aspect ratio for loading/background PNGs (1536x972)
local DESIGN_RATIO = 1536 / 972
local PANEL_HEIGHT = 0.80  -- must match ui.lua's PANEL_HEIGHT

--- Compute panel anchors matching the design aspect ratio for current viewport.
local function getPanelBounds(pc)
    local halfH = PANEL_HEIGHT / 2
    local L, R, T, B = 0.10, 0.90, 0.5 - halfH, 0.5 + halfH  -- defaults
    local vpW, vpH = 0, 0
    pcall(function()
        local vp = pc:GetLocalPlayer():GetViewportClient()
        local size = { X = 0, Y = 0 }
        vp:GetViewportSize(size)
        vpW, vpH = size.X, size.Y
    end)
    -- Fallback: WidgetLayoutLibrary (returns FVector2D directly)
    if vpW <= 0 or vpH <= 0 then
        pcall(function()
            local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
            local size = wll:GetViewportSize(pc)
            vpW, vpH = size.X, size.Y
        end)
    end
    if vpW > 0 and vpH > 0 then
        local panelH = (B - T) * vpH
        local panelW = panelH * DESIGN_RATIO
        local maxW = 0.92 * vpW
        if panelW > maxW then panelW = maxW end
        local halfW = (panelW / vpW) / 2
        L = 0.5 - halfW
        R = 0.5 + halfW
    end
    return L, R, T, B
end

local loadingAlive = false  -- flag for LoopAsync animation teardown

-- Visual center correction as fraction of panel dimensions (not viewport).
-- Scales correctly across resolutions. Tuned at 1920x1080.
local CENTER_NUDGE_X = -0.034  -- fraction of panel width
local CENTER_NUDGE_Y = -0.030  -- fraction of panel height

--- Try to apply a game material to an Image widget (graceful no-op if not loaded)
local function applyMaterial(root, canvas, name, matPath, x1, y1, x2, y2, opacity)
    local mat = StaticFindObject(matPath)
    if not mat then return nil end
    local imgCls = StaticFindObject("/Script/UMG.Image")
    local img = StaticConstructObject(imgCls, root, FName(name))
    local ok = pcall(function() img:SetBrushFromMaterial(mat) end)
    if not ok then return nil end
    if opacity then pcall(function() img:SetRenderOpacity(opacity) end) end
    local slot = canvas:AddChildToCanvas(img)
    slot:SetAnchors({ Minimum = { X = x1, Y = y1 }, Maximum = { X = x2, Y = y2 } })
    slot:SetAutoSize(false)
    return img
end
local NUM_RINGS = 7
local NUM_HEX_BANDS = 8
local HEX_STAGGER = 80  -- ms between each hex band appearing

local function showLoadingScreen()
    if loadingWidget then
        pcall(function() loadingWidget:RemoveFromViewport() end)
        loadingWidget = nil
    end
    loadingAlive = false

    -- Reimport textures fresh (UE GC can free unrooted UTexture2Ds)
    pcall(function() textures.loadAll() end)
    styles.captureGameFont()

    local wbLib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local uwClass = StaticFindObject("/Script/UMG.UserWidget")
    local canvasCls = StaticFindObject("/Script/UMG.CanvasPanel")
    local imgCls = StaticFindObject("/Script/UMG.Image")
    local textCls = StaticFindObject("/Script/UMG.TextBlock")
    local pc = UEHelpers:GetPlayerController()
    if not pc or not wbLib then return end

    local root = wbLib:Create(pc, uwClass, pc)
    if not root then return end

    local canvas = StaticConstructObject(canvasCls, root, FName("LoadCanvas"))
    root.WidgetTree.RootWidget = canvas

    local L, R, T, B = getPanelBounds(pc)
    local panelW = R - L
    local panelH = B - T
    local midX = (L + R) / 2 + CENTER_NUDGE_X * panelW
    local midY = (T + B) / 2 + CENTER_NUDGE_Y * panelH

    -- Background (with hex grid baked in)
    local bgTex = textures.get("Background")
    if bgTex then
        local bg = StaticConstructObject(imgCls, root, FName("LoadBG"))
        pcall(function() bg:SetBrushFromTexture(bgTex, false) end)
        local bgSlot = canvas:AddChildToCanvas(bg)
        bgSlot:SetAnchors({ Minimum = { X = L, Y = T }, Maximum = { X = R, Y = B } })
        bgSlot:SetAutoSize(false)
    end

    ----------------------------------------------------------------
    -- Hex glow bands — sweep outward across the panel
    ----------------------------------------------------------------
    local hexWidgets = {}
    for i = 1, NUM_HEX_BANDS do
        local hexTex = textures.get("Hex" .. i)
        if hexTex then
            local hex = StaticConstructObject(imgCls, root, FName("Hex" .. i))
            pcall(function() hex:SetBrushFromTexture(hexTex, false) end)
            pcall(function() hex:SetRenderOpacity(0) end)
            local hexSlot = canvas:AddChildToCanvas(hex)
            hexSlot:SetAnchors({ Minimum = { X = L, Y = T }, Maximum = { X = R, Y = B } })
            hexSlot:SetAutoSize(false)
            hexWidgets[i] = hex
        end
    end

    ----------------------------------------------------------------
    -- Radar pulse: orb + 7 rings, stacked at center
    ----------------------------------------------------------------
    local ringWidgets = {}

    local function addRadarLayer(name, texName, startAlpha)
        local tex = textures.get(texName)
        if not tex then return nil end
        local img = StaticConstructObject(imgCls, root, FName(name))
        pcall(function() img:SetBrushFromTexture(tex, true) end)
        pcall(function() img:SetColorAndOpacity({ R=1, G=1, B=1, A=startAlpha or 0 }) end)
        local slot = canvas:AddChildToCanvas(img)
        slot:SetAnchors({ Minimum = { X = midX, Y = midY }, Maximum = { X = midX, Y = midY } })
        slot:SetAutoSize(true)
        pcall(function() slot:SetAlignment({ X = 0.5, Y = 0.5 }) end)
        return img
    end

    local orbImg = addRadarLayer("Orb", "Orb", 0)  -- start invisible
    for i = 1, NUM_RINGS do
        ringWidgets[i] = addRadarLayer("Ring" .. i, "Ring" .. i, 0)
    end

    ----------------------------------------------------------------
    -- Shared chrome (same positions as main UI)
    ----------------------------------------------------------------
    local sizeBoxCls = StaticFindObject("/Script/UMG.SizeBox")

    -- Title header (disabled — only shown in terminal view)
    -- local title = StaticConstructObject(textCls, root, FName("LoadTitle"))
    -- title:SetText(FText("DATABASE TERMINAL"))
    -- styles.apply(title, "title")
    -- local titleSlot = canvas:AddChildToCanvas(title)
    -- local loadTitleX = (L + R) / 2 + CENTER_NUDGE_X * panelW
    -- titleSlot:SetAnchors({ Minimum = { X = loadTitleX, Y = T+0.044 }, Maximum = { X = loadTitleX, Y = T+0.044 } })
    -- titleSlot:SetAutoSize(true)
    -- pcall(function() titleSlot:SetAlignment({ X = 0.5, Y = 0.5 }) end)

    -- Footer version
    local ver = StaticConstructObject(textCls, root, FName("LoadVer"))
    ver:SetText(FText("Database Terminal v0.1.0"))
    styles.apply(ver, "footer")
    local verSlot = canvas:AddChildToCanvas(ver)
    verSlot:SetAnchors({ Minimum = { X = L+0.05, Y = B-0.065 }, Maximum = { X = L+0.05, Y = B-0.065 } })
    verSlot:SetAutoSize(true)

    ----------------------------------------------------------------
    -- "Scanning containers..." — single centered text, terminal flicker
    ----------------------------------------------------------------
    local label = StaticConstructObject(textCls, root, FName("LoadLabel"))
    label:SetText(FText("Scanning containers..."))
    styles.apply(label, "loadingSub")
    local labelSlot = canvas:AddChildToCanvas(label)
    labelSlot:SetAnchors({ Minimum = { X = midX, Y = midY + 0.16 }, Maximum = { X = midX, Y = midY + 0.16 } })
    labelSlot:SetAutoSize(true)
    pcall(function() labelSlot:SetAlignment({ X = 0.5, Y = 0.5 }) end)

    -- Alterra logo — centered below text, fixed pixel size to prevent stretch
    pcall(function()
        local sizeBoxCls = StaticFindObject("/Script/UMG.SizeBox")
        local mat = StaticFindObject("/Game/UI/Materials_test/Glitch/M_Glitch.M_Glitch")
        if mat and sizeBoxCls then
            local logoImg = StaticConstructObject(imgCls, root, FName("AlterraLogo"))
            logoImg:SetBrushFromMaterial(mat)
            logoImg:SetRenderOpacity(0.8)
            local logoBox = StaticConstructObject(sizeBoxCls, root, FName("LogoBox"))
            logoBox:SetWidthOverride(80)
            logoBox:SetHeightOverride(50)
            logoBox:SetContent(logoImg)
            local logoSlot = canvas:AddChildToCanvas(logoBox)
            logoSlot:SetAnchors({ Minimum = { X = midX, Y = midY + 0.22 }, Maximum = { X = midX, Y = midY + 0.22 } })
            logoSlot:SetAutoSize(true)
            logoSlot:SetAlignment({ X = 0.5, Y = 0.5 })
        end
    end)

    -- Subtle terminal-style opacity jitter on the scanning text
    LoopAsync(120, function()
        if not loadingAlive then return true end
        -- Base opacity is 0.4 (from style). Jitter mostly near base with occasional dips.
        local jitter = 0.30 + math.random() * 0.10
        pcall(function() label:SetOpacity(jitter) end)
        return false
    end)

    ----------------------------------------------------------------
    -- Animation sequence:
    -- 1. Hex glow sweep starts immediately
    -- 2. Orb + ring pulse starts 200ms later
    ----------------------------------------------------------------
    loadingAlive = true

    -- Hex sweep (single pass)
    local HEX_TICK = 100
    local HEX_FADE = 3
    local HEX_CYCLE = NUM_HEX_BANDS + HEX_FADE + 1
    local hexPhase = 0

    LoopAsync(HEX_TICK, function()
        if not loadingAlive then return true end
        hexPhase = hexPhase + 1
        if hexPhase > HEX_CYCLE then return true end

        for i = 1, NUM_HEX_BANDS do
            local age = hexPhase - i
            local opacity = 0
            if age >= 0 and age < HEX_FADE then
                opacity = 1.0 * (1 - age / HEX_FADE)
            end
            if hexWidgets[i] then
                pcall(function() hexWidgets[i]:SetRenderOpacity(opacity) end)
            end
        end
        return false
    end)

    -- Orb + ring pulse (delayed so hex sweep completes first)
    ExecuteWithDelay(700, function()
        ExecuteInGameThread(function()
            if not loadingAlive then return end

            -- Flash orb on
            if orbImg then
                pcall(function() orbImg:SetColorAndOpacity({ R=1, G=1, B=1, A=0.7 }) end)
            end

            local RING_TICK = 100
            local RING_FADE = 3
            local RING_CYCLE = NUM_RINGS + RING_FADE + 1
            local ringPhase = 0

            LoopAsync(RING_TICK, function()
                if not loadingAlive then return true end
                ringPhase = ringPhase + 1

                -- Fade orb out
                if orbImg and ringPhase <= 4 then
                    local orbAlpha = 0.7 * (1 - ringPhase / 4)
                    pcall(function() orbImg:SetColorAndOpacity({ R=1, G=1, B=1, A=orbAlpha }) end)
                end

                if ringPhase > RING_CYCLE then return true end

                for i = 1, NUM_RINGS do
                    local age = ringPhase - i
                    local alpha = 0
                    if age >= 0 and age < RING_FADE then
                        alpha = 0.7 * (1 - age / RING_FADE)
                    end
                    if ringWidgets[i] then
                        pcall(function()
                            ringWidgets[i]:SetColorAndOpacity({ R=1, G=1, B=1, A=alpha })
                        end)
                    end
                end
                return false
            end)
        end)
    end)

    root:AddToViewport(501)
    loadingWidget = root

    -- Push modal blocker to layer 3 — prevents ESC from opening settings menu
    pcall(function()
        local modalCls = StaticFindObject("/Script/UWECommonUI.ModalActivatableWidget")
        local wm = FindFirstOf("WindowManager")
        if wm and modalCls then
            modalBlocker = wm:PushToLayer(3, modalCls)
        end
    end)

    -- Lock input so player can't move during load
    pcall(function() wbLib:SetInputMode_UIOnlyEx(pc, root, 0, true) end)
    pcall(function() pc.bShowMouseCursor = false end)
end

local function hideLoadingScreen()
    loadingAlive = false  -- stops the LoopAsync pulse animation
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

    -- Pop modal blocker from WindowManager layer 3
    if modalBlocker then
        pcall(function()
            local wm = FindFirstOf("WindowManager")
            if wm then wm:Pop(modalBlocker) end
        end)
        modalBlocker = nil
    end

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
            ExecuteWithDelay(1800, function()
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

    -- ESC to close — modal blocker on WindowManager layer 3 prevents the
    -- game from opening the settings menu when ESC is pressed (same pattern
    -- as inventory/fabricator). See docs/probes/esc-close-results.md.
    RegisterKeyBind(Key.ESCAPE, function()
        if not isOpen then return end
        ExecuteInGameThread(function()
            interaction.close()
        end)
    end)

    -- Backup close key (F6)
    RegisterKeyBind(Key.F6, function()
        if not isOpen then return end
        ExecuteInGameThread(function()
            interaction.close()
        end)
    end)

end

return interaction
