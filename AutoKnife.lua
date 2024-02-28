--[[
    Description: AutoKnife.lua is a script that will automatically switch to knife
    --within range and within the backstab angle.
--]]

---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib");
assert(libLoaded, "lnxLib not found, please install it!");
assert(lnxLib.GetVersion() >= 0.996, "lnxLib version is too old, please update it!");

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local Fonts = lnxLib.UI.FontslnxLib

--optins
local MaxFov = 90

local pLocal = entities.GetLocalPlayer()
local pLocalPos = Vector3(0,0,0)
local pLocalViewPos = pLocalPos + Vector3(0,0,75) 
local pLocalViewOffset = Vector3(0,0,75)
local vHitbox = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
local TargetPlayer
local Latency = 0
local lerp = 0

-- Constants
local BACKSTAB_RANGE = 66  -- Hammer units
local BACKSTAB_ANGLE = 160  -- Degrees in radians for dot product calculation
local tickRate = (1 / globals.TickInterval())

local lastAngles = {}
local strafeAngles = {}

local function CalcStrafe()
    local players = entities.FindByClass("CTFPlayer")

    for idx, entity in ipairs(players) do
        local entityIndex = entity:GetIndex()

        if entity:IsDormant() or not entity:IsAlive() then
            lastAngles[entityIndex] = nil
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        local angle = v:Angles()

        if lastAngles[entityIndex] == nil then
            lastAngles[entityIndex] = angle.y
            goto continue
        end

        local delta = angle.y - lastAngles[entityIndex]
        lastAngles[entityIndex] = angle.y

        strafeAngles[entityIndex] = delta

        ::continue::
    end
end

-- Calculates the angle between two vectors
---@param source Vector3
---@param dest Vector3
---@return EulerAngles angles
local function PositionAngles(source, dest)
    local delta = source - dest

    local pitch = math.atan(delta.z / delta:Length2D()) * M_RADPI
    local yaw = math.atan(delta.y / delta.x) * M_RADPI

    if delta.x >= 0 then
        yaw = yaw + 180
    end

    if isNaN(pitch) then pitch = 0 end
    if isNaN(yaw) then yaw = 0 end

    return EulerAngles(pitch, yaw, 0)
end

local function CalculateBackwardVector(player)
    local forwardAngle = player:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]")
    local pitch = math.rad(forwardAngle.x)
    local yaw = math.rad(forwardAngle.y)
    local forwardVector = Vector3(math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), 0)
    return -forwardVector
end

local function UpdateTarget()
    local allPlayers = entities.FindByClass("CTFPlayer")
    local bestTargetDetails = nil
    local maxAttackDistance = 225  -- Attack range plus warp distance
    --local maxBacktrackDistance = 670 -- Max backtrack distance
    local bestDistance = maxAttackDistance + 1  -- Initialize to a large number

    for _, player in ipairs(allPlayers) do
        if player:IsAlive() and not player:IsDormant() and player:GetTeamNumber() ~= pLocal:GetTeamNumber() and player ~= pLocal then
            if gui.GetValue("ignore cloaked") == 1 and not player:InCond(4)
            or gui.GetValue("ignore clacked") == 0 then
                local playerIndex = player:GetIndex()
                local playerPos = player:GetAbsOrigin()
                local distance = (pLocalPos - playerPos):Length()

                -- Check if the player is within the attack range
                if distance < bestDistance then
                    local angles = Math.PositionAngles(pLocalViewPos, playerPos + Vector3(0, 0, 75))
                    local fov = Math.AngleFov(engine.GetViewAngles(), angles)

                    if fov <= MaxFov then
                        bestDistance = distance
                        bestTargetDetails = {
                            idx = playerIndex,
                            entity = player,
                            Pos = playerPos,
                            FPos = playerPos + player:EstimateAbsVelocity() * 0.015,
                            viewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]"),
                            hitboxPos = (player:GetHitboxes()[4][1] + player:GetHitboxes()[4][2]) * 0.5,
                            hitboxForward = CalculateBackwardVector(player),
                            --backPoint = CalculateBackPoint(player)
                        }
                    end
                end
            end
        end
    end
    return bestTargetDetails
end

-- Normalize a yaw angle to the range [-180, 180]
local function NormalizeYaw(yaw)
    yaw = yaw % 360
    if yaw > 180 then
        yaw = yaw - 360
    elseif yaw < -180 then
        yaw = yaw + 360
    end
    return yaw
end

-- Normalizes a vector to a unit vector
local function NormalizeVector(vec)
    if vec == nil then return Vector3(0, 0, 0) end
    local length = math.sqrt(vec.x^2 + vec.y^2 + vec.z^2)
    if length == 0 then return Vector3(0, 0, 0) end
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

-- Function to calculate yaw angle between two points using math.atan2
local function CalculateYawAngle(point1, direction)
    -- Determine a point along the forward direction
    local forwardPoint = point1 + direction * 104  -- 'someDistance' is an arbitrary distance

    -- Calculate the difference in the x and y coordinates
    local dx = forwardPoint.x - point1.x
    local dy = forwardPoint.y - point1.y

    -- Calculate the yaw angle using math.atan
    local yaw = math.atan(dy, dx)

    return math.deg(yaw)  -- Convert radians to degrees
end


local M_RADPI = 180 / math.pi

local function isNaN(x) return x ~= x end

local function PositionYaw(source, dest)
    local delta = source - dest

    local yaw = math.atan(delta.y / delta.x) * M_RADPI

    if delta.x >= 0 then
        yaw = yaw + 180
    end

    if isNaN(yaw) then yaw = 0 end

    return yaw
end


local function CheckYawDelta(angle1, angle2)
    local difference = angle1 - angle2

    local normalizedDifference = NormalizeYaw(difference)
    --print(normalizedDifference)
    -- Assuming you want to check if within a 120-degree arc to the right and a 40-degree arc to the left of the back
    local withinRightArc = normalizedDifference > -70 and normalizedDifference <= 0
    local withinLeftArc = normalizedDifference < 70 and normalizedDifference >= 0

    return withinRightArc or withinLeftArc
end

-- Assuming TargetPlayer is a global or accessible object with Pos and hitbox details
-- Also assuming Vector3 is a properly defined class with necessary methods

local function checkInRange(spherePos, sphereRadius)
    -- Validate inputs
    if not (spherePos and sphereRadius) then
        error("Invalid input to checkInRange function")
    end

    -- Ensure sphereRadius is positive
    if sphereRadius < 0 then
        error("Sphere radius must be positive")
    end

    -- Retrieve target player's position and hitbox
    local targetPos = TargetPlayer.FPos
    local hitbox_min = (targetPos + vHitbox[1]) -- Replace with actual way to get 
    local hitbox_max = (targetPos + vHitbox[2]) -- Replace with actual way to get hitbox max

    -- Calculate the closest point on the hitbox to the sphere
    local closestPoint = Vector3(
        math.max(spherePos.x, hitbox_min.x, math.min(spherePos.x, hitbox_max.x)),
        math.max(spherePos.y, hitbox_min.y, math.min(spherePos.y, hitbox_max.y)),
        math.max(spherePos.z, hitbox_min.z, math.min(spherePos.z, hitbox_max.z))
    )

    -- Calculate the vector from the closest point to the sphere center
    local distanceVector = (spherePos - closestPoint)
    local distance = math.abs(distanceVector:Length()) -- Assuming a Length method in Vector3

    -- Check if the sphere is in range (including intersecting)
    local inRange = distance <= sphereRadius

    -- Compare the distance along the vector to the sum of the radius
    if inRange then
       -- InRange detected (including intersecting)
        return true, closestPoint
    else
        -- No InRange
        return false, nil
    end
end

local function CheckBackstab(testPoint)
    -- Check if testPoint is valid
    if not testPoint then
        print("Invalid testPoint")
        return nil
    end

    if TargetPlayer and TargetPlayer.FPos and TargetPlayer.hitboxForward then
        local InRange = checkInRange(testPoint, BACKSTAB_RANGE) -- Assuming checkInRange is defined correctly
        if InRange and TargetPlayer.hitboxForward then
            local enemyYaw = CalculateYawAngle(TargetPlayer.hitboxPos, TargetPlayer.hitboxForward)
            enemyYaw = NormalizeYaw(enemyYaw) -- Normalize

            local spyYaw = PositionYaw(TargetPlayer.FPos, testPoint)
            --local Delta = math.abs(NormalizeYaw(spyYaw - enemyYaw))

            local canBackstab = CheckYawDelta(spyYaw, enemyYaw) -- Assuming CheckYawDelta is defined correctly
            return canBackstab
        end
    else
        print("TargetPlayer is nil")
    end

    return false
end

local killed = false
local function damageLogger(event)
    if (event:GetName() == 'player_hurt' ) then
        local victim = entities.GetByUserID(event:GetInt("userid"))
        local attacker = entities.GetByUserID(event:GetInt("attacker"))
        if (attacker == nil or pLocal:GetName() ~= attacker:GetName()) then
            return
        end
        local damage = event:GetInt("damageamount")
        --[[if damage < 450 then -- if not backstab
            return
        end]]
        killed = true --raprot kill now safely can recharge
    end
end

-- Function to update the cache for the local player and loadout slot
local function UpdateLocalPlayerCache()
    pLocal = entities.GetLocalPlayer()
    if not pLocal
    or not pLocal:IsAlive()
    or pLocal:GetPropInt("m_iClass") ~= 8 -- if not spy return
    or pLocal:InCond(4) or pLocal:InCond(9)
    or pLocal:GetPropInt("m_bFeignDeathReady") == 1
    then return false end

    --cachedLoadoutSlot2 = pLocal and pLocal:GetEntityForLoadoutSlot(2) or nil
    pLocalViewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]") or Vector3(0,0,75)
    pLocalViewPos = (pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")) or pLocalPos + Vector3(0,0,75) or pLocalPos
    pLocalPos = pLocal:GetAbsOrigin()
    return pLocal
end

local pLocalFuture = Vector3(0,0,0)
local time = Conversion.Time_to_Ticks(0.67) --switch to knife speed or 44 - 45 ticks
local lastslot = "slot1"
local tick_count = 0
local switchbackdealy = 66

local function knifetimer()
    --if we dont need knife we need to switch
    tick_count = tick_count + 1
    print(tick_count)
    if tick_count > switchbackdealy then
        client.Command("slot1", true)
        tick_count = 0 
        return
    end
end

local function OnCreateMove(cmd)
    if UpdateLocalPlayerCache() == false then return end  -- Update local player data every tick or return
    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon then return end  -- Return if the local player doesn't have an active weaponend

    if pWeapon:IsMeleeWeapon() == true then
        if killed then
            client.Command("slot1", true)
            killed = false
        else
            switchbackdealy = 66
            knifetimer()
        end
        return 
    end -- Return if the local player's active weapon is not a melee weapon

    TargetPlayer = TargetPlayer1 or UpdateTarget()
    if not TargetPlayer then
        return
    end

    CalcStrafe()

    -- Calculate latency in seconds
    local latOut = clientstate.GetLatencyOut()
    local latIn = clientstate.GetLatencyIn()
    lerp = client.GetConVar("cl_interp") or 0
    Latency = Conversion.Time_to_Ticks(latOut + latIn + lerp)

    --if true then return end

    -- Local player prediction
    if pLocal:EstimateAbsVelocity() == 0 then
        -- If the local player is not accelerating, set the predicted position to the current position
        pLocalFuture = pLocalPos
    else
        local player = WPlayer.FromEntity(pLocal)

        local strafeAngle = strafeAngles[pLocal:GetIndex()]
        local shouldHitEntity = function(entity) return entity:GetName() ~= pLocal:GetName() end --trace ignore simulated player

        local predData = Prediction.Player(player, time, strafeAngle, shouldHitEntity)
        if not predData then print("no local") return end

        pLocalFuture = predData.pos[time] + pLocalViewOffset
    end

    --if true then return end

    -- Target player prediction
    if TargetPlayer.entity:EstimateAbsVelocity() == 0 then
        -- If the target player is not accelerating, set the predicted position to their current position
        TargetPlayer.future = TargetPlayer.entity:GetAbsOrigin()
    else
        local player = WPlayer.FromEntity(TargetPlayer.entity)

        local strafeAngle = strafeAngles[TargetPlayer.entity:GetIndex()] or 0
        local shouldHitEntity = function(entity) return entity:GetName() ~= player:GetName() end --trace ignore simulated player

        local predData = Prediction.Player(player, time, strafeAngle, shouldHitEntity)
        if not predData then print("notarget") return end

        TargetPlayer.future = predData.pos[time]
    end
    --if true then return end 

    local canBackstab = CheckBackstab(pLocalFuture)
    if canBackstab then
        tick_count = 0
        client.Command("slot3", true)
    end
end

--[[ Remove the menu when unloaded ]]--
local function OnUnload()                                -- Called when the script is unloaded
    UnloadLib() --unloading lualib
    --CreateCFG([[LBOX Auto trickstab lua]], Menu) --saving the config
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

callbacks.Unregister("FireGameEvent", "adaamaXDgeLogger")
callbacks.Register("FireGameEvent", "adaamaXDgeLogger", damageLogger)

callbacks.Unregister("CreateMove", "jumpbughanddd")
callbacks.Register("CreateMove", "jumpbughanddd", OnCreateMove)

callbacks.Unregister("Unload", "AtSM_Unload")                    -- Unregister the "Unload" callback
callbacks.Register("Unload", "AtSM_Unload", OnUnload)                         -- Register the "Unload" callback

--[[ Play sound when loaded ]]--
client.Command('play "ui/buttonclick"', true) -- Play the "buttonclick" sound when the script is loaded
