-- Load lnxLib library
---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() <= 0.995, "lnxLib version is too old, please update it!")


-- Import required modules from lnxLib
local WPlayer = lnxLib.TF2.WPlayer
local Prediction = lnxLib.TF2.Prediction


local pLocalPath = {}
local hitChance = 0

local function calculateHitChancePercentage(lastPredictedPos, currentPos)
    local horizontalDistance = math.sqrt((currentPos.x - lastPredictedPos.x)^2 + (currentPos.y - lastPredictedPos.y)^2)
    local verticalDistanceUp = currentPos.z - lastPredictedPos.z
    local verticalDistanceDown = lastPredictedPos.z - currentPos.z
    
    -- You can adjust these values based on your game's mechanics
    local maxHorizontalDistance = 16
    local maxVerticalDistanceUp = 45
    local maxVerticalDistanceDown = 0
    
    if horizontalDistance > maxHorizontalDistance or verticalDistanceUp > maxVerticalDistanceUp or verticalDistanceDown > maxVerticalDistanceDown then
        return 0 -- No chance to hit
    else
        local horizontalHitChance = 100 - (horizontalDistance / maxHorizontalDistance) * 100
        local verticalHitChance = 100 - (verticalDistanceUp / maxVerticalDistanceUp) * 100
        local overallHitChance = (horizontalHitChance + verticalHitChance) / 2
        return overallHitChance
    end
end
local probabilities = {0, 0, 0, 0, 0}

local function calculateAverageProbability()
    if #probabilities == 0 then
        return 0
    else
        local sum = 0
        for i = 1, #probabilities do
            sum = sum + probabilities[i]
        end
        return sum / #probabilities
    end
end

local lastAngles = {} ---@type table<number, EulerAngles>
local strafeAngles = {} ---@type table<number, number>

---@param me WPlayer
local function CalcStrafe(me)
    local players = entities.FindByClass("CTFPlayer")
    for idx, entity in ipairs(players) do
        if entity:IsDormant() or not entity:IsAlive() then
            lastAngles[entity:GetIndex()] = nil
            strafeAngles[entity:GetIndex()] = nil
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        local angle = v:Angles()

        -- Play doesn't have a last angle
        if lastAngles[entity:GetIndex()] == nil then
            lastAngles[entity:GetIndex()] = angle
            goto continue
        end

        -- Calculate the delta angle
        if angle.y ~= lastAngles[entity:GetIndex()].y then
            strafeAngles[entity:GetIndex()] = angle.y - lastAngles[entity:GetIndex()].y
        end
        lastAngles[entity:GetIndex()] = angle

        ::continue::
    end
end

local lastPosition = Vector3()
-- Callback function for CreateMove event
local function OnCreateMove()
    local pLocal = entities.GetLocalPlayer()
    local WpLocal = WPlayer.FromEntity(pLocal) -- Convert pLocal to lualib WPlayer

    CalcStrafe(me)
    local strafeAngle = strafeAngles[pLocal:GetIndex()] or 0
    local predData = Prediction.Player(WpLocal, 15, strafeAngle) -- Time (ticks), strafe angle (0 or nil = disabled)
    pLocalPath = predData.pos

    -- Example usage
    local currentPosition = pLocal:GetAbsOrigin()

    if lastPosition then
        hitChance = calculateHitChancePercentage(lastPosition, currentPosition)
        table.insert(probabilities, hitChance)
        if #probabilities > 3 then
            table.remove(probabilities, 1)
        end
        hitChance = calculateAverageProbability(probabilities)
        
    end

    lastPosition = predData.pos[1]
end

local function convertPercentageToRGB(percentage)
    local value = math.floor(percentage / 100 * 255)
    return math.max(0, math.min(255, value))
end

-- Draw predicted path
local function doDraw()
local greenValue = convertPercentageToRGB(hitChance)
local blueValue = convertPercentageToRGB(hitChance)
draw.Color(255, greenValue, blueValue, 255)
draw.Text(0, 0, tostring(hitChance))
    -- Draw lines between the predicted positions
    if pLocalPath == nil then return end

    for i = 1, #pLocalPath - 1 do
        local pos1 = pLocalPath[i]
        local pos2 = pLocalPath[i + 1]

        local screenPos1 = client.WorldToScreen(pos1)
        local screenPos2 = client.WorldToScreen(pos2)

        if screenPos1 ~= nil and screenPos2 ~= nil then
            draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
        end
    end
end

-- Unregister previous callbacks
callbacks.Unregister("CreateMove", "MCT_CreateMove") -- Unregister the "CreateMove" callback
callbacks.Unregister("Draw", "MCT_Draw1") -- Unregister the "Draw" callback

-- Register callbacks
callbacks.Register("CreateMove", "MCT_CreateMove", OnCreateMove) -- Register the "CreateMove" callback
callbacks.Register("Draw", "MCT_Draw1", doDraw) -- Register the "Draw" callback
