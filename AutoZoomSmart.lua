
---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local TF2 = lnxLib.TF2
local Fonts = lnxLib.UI.Fonts
local Input = lnxLib.Utils.Input
local Notify = lnxLib.UI.Notify

local pLocal = entities.GetLocalPlayer()
local Target
local pLocalClass
local TargetDistance = 10000
local MaxDistance = 2000
local IsInRange = false

local stopScope = false;
local countUp = 0;
local countUpMax = 14
local UnZoomDelay = 28

--consts
local friend = -1

-- Runs a function n times with given arguments and returns the elapsed time in seconds
---@return number
function Run(n, func, args)
    local startTime = os.clock()
    for _ = 1, n do
        func(table.unpack(args))
    end
    local endTime = os.clock()
    local elapsedTime = endTime - startTime
    return elapsedTime
end

function Normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

---The Manhattan distance between two entities
--takes 0.006 seconds to run 10000 times
--takes 0.002 seconds to run 10000 tiems, when using valeua already preset but its irreleant cuz this onl moves the vlaue gathering to other code waht makes code take 10000 lines
function DistanceFrom(vec1, vec2)
    local dx = math.abs(vec2.x - vec1.x)
    local dy = math.abs(vec2.y - vec1.y)
    return dx + dy
end

--print(Run(10000, DistanceFrom, {Vector3(50,30,20), Vector3(10, -10, 100)}) .. "lengh()")

local function GetSentryLocations()
    local sentrys = entities.FindByClass("CObjectSentrygun")

    if (localp == nil or not localp:IsAlive()) then
        return;
    end

    local x = 0

    for i, sentry in pairs(sentrys) do

        local localpOrigin = localp:GetAbsOrigin();
        local localX = localpOrigin.x
        local localY = localpOrigin.y

        local Vector3Sentrys = sentry:GetAbsOrigin();
        local X = Vector3Sentrys.x
        local Y = Vector3Sentrys.y


        if sentry:GetTeamNumber() == localp:GetTeamNumber() then
            --donothing
        else
            x = x + 1
        end    
        if x > 0 and DistanceFrom(localX, localY, X, Y) < Distance then
            yes = true
            countUp = 0;
        else
           yes = false
        end   
        if x == 0 then
            yes = false    
        end
    end

    if x == 0 then
        yes = false    
    end

    --print("There are " .. tostring(x) .. " sentries")
   --print(yes)

end
local function isVisibleHitbox(localPlayerPos, targetEntity, targetPos)
    -- Normalized direction vector from the local player position to the target
    local direction = Normalize(targetPos - localPlayerPos)

    -- Calculation of the left and right vector by rotating the direction vector by 90 degrees (in radians)
    -- This is an approximation that works well on the X-Y plane, but may require adjustment for three-dimensional space
    local leftVector = Normalize(Vector3(-direction.y, direction.x, direction.z))
    local rightVector = Normalize(Vector3(direction.y, -direction.x, direction.z))

    -- Offset by about 14 units to the sides
    local offsetDistance = 14
    local leftPosition = targetPos + leftVector * offsetDistance
    local rightPosition = targetPos + rightVector * offsetDistance

    -- Check visibility for offset positions
    local futureVisibleLeft = Helpers.VisPos(targetEntity, leftPosition + Vector3(0, 0, 72), targetPos + Vector3(0, 0, 72))
    local futureVisibleRight = Helpers.VisPos(targetEntity, rightPosition + Vector3(0, 0, 72), targetPos + Vector3(0, 0, 72))
    
    local currentVisibleLeft = Helpers.VisPos(targetEntity, leftPosition + Vector3(0, 0, 72), targetEntity:GetAbsOrigin() + Vector3(0, 0, 72))
    local currentVisibleRight = Helpers.VisPos(targetEntity, rightPosition + Vector3(0, 0, 72), targetEntity:GetAbsOrigin() + Vector3(0, 0, 72))
    
    -- Return true if any of the positions are visible
    return futureVisibleLeft or currentVisibleLeft or futureVisibleRight or currentVisibleRight
end


local function GetPlayerLocations()
    if pLocal == nil then
        return
    end

    local players = entities.FindByClass("CTFPlayer")
    Target = nil
    TargetDistance = MaxDistance

    local pLocalOrigin = pLocal:GetAbsOrigin()
    local LocalVelocity = pLocal:EstimateAbsVelocity()
    local TickInterval = globals.TickInterval()
    local LocalVelocityPerTick = LocalVelocity * TickInterval
    local LocalPredPos = (LocalVelocityPerTick * countUpMax) + pLocalOrigin


    for i, player in pairs(players) do
        -- Skip players based on certain conditions
        local isPlayerAlive = player:IsAlive()
        local isPlayerDormant = player:IsDormant()
        local isPlayerLocal = player == pLocal
        local isSameTeam = player:GetTeamNumber() == pLocal:GetTeamNumber()
        local isFriend = TF2.IsFriend(player:GetIndex(), true)
        local Velocity = player:EstimateAbsVelocity()
        local VelocityPerTick = Velocity * TickInterval
        local PredPos = (VelocityPerTick * countUpMax) + player:GetAbsOrigin()

        if not isPlayerAlive or isPlayerDormant or isPlayerLocal or isSameTeam or isFriend then
            goto continue
        end

        local futureVisible = Helpers.VisPos(player, LocalPredPos + Vector3(0, 0, 72), PredPos + Vector3(0, 0, 72))
        local currentVisible = Helpers.VisPos(player, pLocalOrigin + Vector3(0, 0, 72), player:GetAbsOrigin() + Vector3(0, 0, 72))

        -- Check visibility for offset positions
        --local futureVisibleSides = isVisibleHitbox(LocalPredPos, player, PredPos)
        --local currentVisibleSides = isVisibleHitbox(pLocalOrigin, player, player:GetAbsOrigin())

        if not futureVisible and not currentVisible and not futureVisibleSides and not currentVisibleSides then
            goto continue
        end

        -- Get the current enumerated player's vector2 from their vector3
        local PlayerOrigin = player:GetAbsOrigin()
        local currentDistance = DistanceFrom(pLocalOrigin, PlayerOrigin)

        if not IsInRange or currentDistance < MaxDistance then
            IsInRange = true
            Target = player
            TargetDistance = currentDistance
        end

        ::continue::
    end

    -- Check conditions after all players have been processed
    if Target == nil then
        IsInRange = false
        return
    end

    local isLocalPlayerValid = pLocal and pLocal:IsAlive()
    local isTargetValid = Target:IsAlive() and not Target:IsDormant()
    local isTargetFriend = playerlist.GetPriority(Target) == friend

    if IsInRange and (not isLocalPlayerValid or not isTargetValid or isTargetFriend) then
        IsInRange = false
    end
end

local function ZoomDistanceScoping(cmd)
    pLocal = entities.GetLocalPlayer()
    if (pLocal == nil or not pLocal:IsAlive()) then
        return;
    end

    pLocalClass = pLocal:GetPropInt("m_iClass")
    if pLocalClass ~= 2 then return end

    local Weapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not Weapon then return end

    local primary = pLocal:GetEntityForLoadoutSlot(0)
    local WeaponID = primary:GetWeaponID()

  
    if not Weapon:IsShootingWeapon() or Weapon ~= primary then return end
    local WeaponID = Weapon:GetWeaponID()
    if Target and Target:GetHealth() <= 50 then --finisher
        gui.SetValue("sniper: auto zoom", 0);
        gui.SetValue("sniper: zoomed only", 0);
    else
        gui.SetValue("sniper: auto zoom", 1)
        gui.SetValue("sniper: zoomed only", 1)
    end

    if IsInRange and Target then
        if not pLocal:InCond(TFCond_Zoomed) then
            cmd.buttons = cmd.buttons | IN_ATTACK2
        end
        countUp = 0
    end

    if not inRange and countUp < UnZoomDelay then
        countUp = countUp + 1
    else
        if pLocal:InCond(TFCond_Zoomed) then
            cmd.buttons = cmd.buttons | IN_ATTACK2
        end
        countUp = 0
    end
end

callbacks.Register("CreateMove", "ScopeinOrNot", ZoomDistanceScoping)
callbacks.Register("CreateMove", "GetPlayerLocations", GetPlayerLocations)