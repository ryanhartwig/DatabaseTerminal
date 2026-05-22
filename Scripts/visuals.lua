-- DatabaseTerminal: Visual customization
-- Applies custom materials and scale to tagged terminals

local visuals = {}

local ACTOR_CLASS = "BP_ComputerTextInterface_Terminal_PlayerBuilt_C"
local SCALE = { X = 0.75, Y = 0.75, Z = 0.75 }

-- Material names to apply
local BODY_MAT = "MI_Alterra_PosterKitty_01a"
local EMISSIVE_MAT = "MI_HardSurface_Emissive_Offset"
local ORB_MAT = "MI_Hologram_BlockingVolume"

-- Cache found materials
local matCache = {}

function visuals.clearCache()
    matCache = {}
end

local function findMat(name)
    if matCache[name] then
        local cacheOk, cacheValid = pcall(function() return matCache[name]:IsValid() end)
        if not cacheOk or not cacheValid then matCache[name] = nil end
    end
    if matCache[name] then return matCache[name] end
    local allMats = FindAllOf("MaterialInstanceConstant")
    if not allMats then return nil end
    for _, mat in ipairs(allMats) do
        if mat:GetFName():ToString() == name then
            matCache[name] = mat
            return mat
        end
    end
    return nil
end

--- Apply the Database Terminal look to an actor
function visuals.apply(actor)
    if not actor then return end
    local validOk, isValid = pcall(function() return actor:IsValid() end)
    if not validOk or not isValid then return end

    -- Scale
    pcall(function() actor:SetActorScale3D(SCALE) end)

    -- Body material (Mesh slot 0)
    local bodyMat = findMat(BODY_MAT)
    if bodyMat then
        pcall(function() actor.Mesh:SetMaterial(0, bodyMat) end)
        print("[DBTerminal] Applied body material\n")
    else
        print("[DBTerminal] Body material '" .. BODY_MAT .. "' not found in memory\n")
    end

    -- Emissive material (Mesh slot 1 + emissive overlay)
    local emisMat = findMat(EMISSIVE_MAT)
    if emisMat then
        pcall(function() actor.Mesh:SetMaterial(1, emisMat) end)
        pcall(function() actor.SM_Cicada_NOA_01_Emissive:SetMaterial(0, emisMat) end)
        print("[DBTerminal] Applied emissive material\n")
    else
        print("[DBTerminal] Emissive material '" .. EMISSIVE_MAT .. "' not found in memory\n")
    end

    -- Orb/head material
    local orbMat = findMat(ORB_MAT)
    if orbMat then
        local meshComps = FindAllOf("StaticMeshComponent")
        if meshComps then
            local actorFName = actor:GetFName():ToString()
            for _, mc in ipairs(meshComps) do
                if mc:IsValid() then
                    local fullName = mc:GetFullName()
                    if fullName:find(actorFName) then
                        local mcName = mc:GetFName():ToString()
                        if mcName ~= "Mesh" and mcName ~= "SM_Cicada_NOA_01_Emissive" then
                            for i = 0, mc:GetNumMaterials() - 1 do
                                pcall(function() mc:SetMaterial(i, orbMat) end)
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Apply visuals to all currently tagged terminals
function visuals.applyAll(terminalActors)
    local ok, actors = pcall(function() return FindAllOf(ACTOR_CLASS) end)
    if not ok or not actors then return end
    for _, actor in ipairs(actors) do
        local validOk, isValid = pcall(function() return actor:IsValid() end)
        if validOk and isValid then
            local fnameOk, fname = pcall(function() return actor:GetFName():ToString() end)
            if fnameOk and terminalActors[fname] then
                visuals.apply(actor)
            end
        end
    end
end

return visuals
