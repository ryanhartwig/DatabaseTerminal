-- Visual experimentation probe v2
local UEHelpers = require("UEHelpers")
local tracker = require("tracker")

local ACTOR_CLASS = "BP_ComputerTextInterface_Terminal_PlayerBuilt_C"

local function getTerminalNearby()
    local pawn = UEHelpers:GetPlayerController().Pawn
    if not pawn or not pawn:IsValid() then return nil end
    local actors = FindAllOf(ACTOR_CLASS)
    if not actors then return nil end
    local closest, closestDist = nil, 99999
    local playerLoc = pawn:K2_GetActorLocation()
    for _, actor in ipairs(actors) do
        if actor:IsValid() and tracker.isTerminal(actor:GetFName():ToString()) then
            local loc = actor:K2_GetActorLocation()
            local dx, dy, dz = playerLoc.X-loc.X, playerLoc.Y-loc.Y, playerLoc.Z-loc.Z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist < closestDist then closestDist = dist; closest = actor end
        end
    end
    return closestDist < 500 and closest or nil
end

-- F2: Enumerate all components on the actor
RegisterKeyBind(Key.F2, function()
    ExecuteInGameThread(function()
        local actor = getTerminalNearby()
        if not actor then print("[visual] No terminal nearby\n") return end

        -- List known components from header dump
        local comps = {"Mesh", "SM_Cicada_NOA_01_Emissive", "UWESave", "ScanningOrbCollision",
                       "UWEAttachable", "UWEPoweredAppliance", "BPC_ScanningOrb",
                       "ProximityCheck", "BPC_ComputerTextInterface_Component", "DefaultSceneRoot"}
        for _, name in ipairs(comps) do
            local ok, comp = pcall(function() return actor[name] end)
            if ok and comp then
                local valid = comp:IsValid()
                local cls = ""
                pcall(function() cls = comp:GetClass():GetFName():ToString() end)
                print(string.format("[visual] %s: valid=%s class=%s\n", name, tostring(valid), cls))
            end
        end

        -- Get Mesh details
        local mesh = actor.Mesh
        print("[visual] Mesh materials: " .. tostring(mesh:GetNumMaterials()) .. "\n")
        for i = 0, mesh:GetNumMaterials() - 1 do
            local matOk, mat = pcall(function() return mesh:GetMaterial(i) end)
            if matOk and mat then
                local matName = mat:GetFName():ToString()
                local matClass = mat:GetClass():GetFName():ToString()
                print(string.format("[visual]   [%d] %s (%s)\n", i, matName, matClass))
            end
        end
    end)
end)

-- F3: Try SetVectorParameterValue on EXISTING materials (not dynamic)
RegisterKeyBind(Key.F3, function()
    ExecuteInGameThread(function()
        local actor = getTerminalNearby()
        if not actor then print("[visual] No terminal nearby\n") return end
        local mesh = actor.Mesh

        for i = 0, mesh:GetNumMaterials() - 1 do
            local mat = mesh:GetMaterial(i)
            if mat then
                -- Try color params on existing material
                local params = {"BaseColor", "EmissiveColor", "Color", "Tint",
                               "BCM Color", "Emissive", "EmissiveMultiplier"}
                for _, p in ipairs(params) do
                    local ok = pcall(function()
                        mat:SetVectorParameterValue(FName(p), {R=0.0, G=0.8, B=1.0, A=1.0})
                    end)
                    if ok then print("[visual] mat[" .. i .. "] SetVector '" .. p .. "': OK\n") end
                end
            end
        end
    end)
end)

-- F4: Try hiding the main Mesh (should make the body disappear)
RegisterKeyBind(Key.F4, function()
    ExecuteInGameThread(function()
        local actor = getTerminalNearby()
        if not actor then print("[visual] No terminal nearby\n") return end

        local mesh = actor.Mesh
        local ok, vis = pcall(function() return mesh:IsVisible() end)
        if ok then
            pcall(function() mesh:SetVisibility(not vis, true) end)
            print("[visual] Mesh visibility: " .. tostring(not vis) .. "\n")
        end
    end)
end)

-- F5: Try SetActorScale3D with non-uniform scale
RegisterKeyBind(Key.F5, function()
    ExecuteInGameThread(function()
        local actor = getTerminalNearby()
        if not actor then print("[visual] No terminal nearby\n") return end
        pcall(function() actor:SetActorScale3D({ X = 0.8, Y = 0.8, Z = 1.2 }) end)
        print("[visual] Non-uniform scale applied (0.8, 0.8, 1.2)\n")
    end)
end)

-- F6: Reset
RegisterKeyBind(Key.F6, function()
    ExecuteInGameThread(function()
        local actor = getTerminalNearby()
        if not actor then print("[visual] No terminal nearby\n") return end
        pcall(function() actor:SetActorScale3D({ X = 1.0, Y = 1.0, Z = 1.0 }) end)
        pcall(function() actor.Mesh:SetVisibility(true, true) end)
        print("[visual] Reset\n")
    end)
end)

print("[visual] F2=enumerate, F3=tint existing mats, F4=toggle mesh, F5=non-uniform scale, F6=reset\n")
