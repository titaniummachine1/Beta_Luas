local EulerAngles = EulerAngles -- fps boost
local M_RADPI = 180 / math.pi

local function isNaN(x) return x ~= x end

-- Normalizes a vector to a unit vector
-- ultimate Normalize a vector
local function Normalize(vec)
    return  vec / vec:Length()
end

-- Calculates the angle between two vectors
---@param source Vector3
---@param dest Vector3
---@return EulerAngles angles
function PositionAngles(source, dest)
    local delta = dest - source

    local pitch = math.atan(delta.z / delta:Length2D()) * M_RADPI
    local yaw = math.atan(delta.y / delta.x) * M_RADPI

    if delta.x >= 0 then
        yaw = yaw + 180
    end

    if isNaN(pitch) then pitch = 0 end
    if isNaN(yaw) then yaw = 0 end

    return EulerAngles(pitch, yaw, 0)
end

local function findClosestTarget(me, players)
    local closestTarget, closestDistance = nil, 115

    for _, Target in ipairs(players) do
        if Target:IsAlive()
        and not Target:IsDormant()
        and Target:GetTeamNumber() ~= me:GetTeamNumber()
        and not Target:InCond(TFCond_Ubercharged)
        and not Target:InCond(TFCond_Cloaked) then
            local dist = (Target:GetAbsOrigin() - me:GetAbsOrigin()):Length()
            if dist < closestDistance then
                closestTarget, closestDistance = Target, dist
            end
        end
    end

    return closestTarget
end

local function GetHitboxPos(player, hitboxID)
    local hitbox = player:GetHitboxes()[hitboxID]
    if not hitbox then return nil end

    return (hitbox[1] + hitbox[2]) * 0.5
end

local function isBehindTarget(me, target)
    local vecToTarget = target:GetAbsOrigin() - me:GetAbsOrigin()
    vecToTarget.z = 0
    Normalize(vecToTarget)

    local targetForward = target:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]"):Forward()
    targetForward.z = 0
    Normalize(targetForward)

    return vecToTarget:Dot(targetForward) > 0 -- Negative dot product to check if behind
end

local swingrange = 48
local TotalSwingRange = 48
local SwingHullSize = 38
local SwingHalfhullSize = SwingHullSize / 2

local swignhull = {
    Min = Vector3(-SwingHalfhullSize,-SwingHalfhullSize,-SwingHalfhullSize),
    Max = Vector3(SwingHalfhullSize,SwingHalfhullSize,SwingHalfhullSize)
}

local function IsInRange(targetPos, spherePos, target)
    local closestPoint = Vector3(
        math.max(targetPos.x - 24, math.min(spherePos.x, targetPos.x + 24)),
        math.max(targetPos.y - 24, math.min(spherePos.y, targetPos.y + 24)),
        math.max(targetPos.z, math.min(spherePos.z, targetPos.z + 82))
    )
    local distance = (spherePos - closestPoint):Length()
    local sphereRadius = TotalSwingRange + SwingHalfhullSize

    if sphereRadius > distance then
        local direction = Normalize(closestPoint - spherePos)
        local endpos = spherePos + direction * swingrange
        local traceEntity = engine.TraceLine(spherePos, endpos, MASK_SHOT_HULL).entity
        local traceHullEntity = engine.TraceHull(spherePos, endpos, swignhull.Min, swignhull.Max, MASK_SHOT_HULL).entity
        return (traceEntity == target or traceHullEntity == target), (traceEntity == target or traceHullEntity == target) and closestPoint or nil
    end

    return false, nil
end

local function CheckBackstab(me, target, viewpos)
    local targetPos = target:GetAbsOrigin()

    return isBehindTarget(me, target) and IsInRange(targetPos, viewpos, target)
end

local function PsilentShoot(cmd, Angle)
    cmd:SetSendPacket(false)
    cmd:SetViewAngles(Angle.pitch, Angle.yaw, 0) --engine.SetViewAngles(Angle) --
    cmd:SetButtons(cmd:GetButtons() | IN_ATTACK)
    cmd:SetSendPacket(true)
end

local function backstabAimbot(cmd)
    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() then return end

    if me:GetPropInt("m_iClass") ~= TF2_Spy or me:InCond(TFCond_Cloaked) then
        return
    end

    local weapon = me:GetPropEntity("m_hActiveWeapon")
    if not weapon or not weapon:IsMeleeWeapon() then return end

    local players = entities.FindByClass("CTFPlayer")
    local target = findClosestTarget(me, players)
    if not target then return end

    local viewoffset = me:GetPropVector("localdata", "m_vecViewOffset[0]")
    local viewpos = me:GetAbsOrigin() + viewoffset

    if CheckBackstab(me, target, viewpos) then
        if weapon:GetPropInt("m_bReadyToBackstab") == 257 then
            cmd:SetButtons(cmd:GetButtons() | IN_ATTACK)
        end

        swingrange = weapon:GetSwingRange()
        TotalSwingRange = swingrange + SwingHalfhullSize

        local targetPos = target:GetAbsOrigin()

        local closestPoint = Vector3(
            math.max(targetPos.x - 24, math.min(viewpos.x, targetPos.x + 24)),
            math.max(targetPos.y - 24, math.min(viewpos.y, targetPos.y + 24)),
            math.max(targetPos.z, math.min(viewpos.z, targetPos.z + 82))
        )

        local Angle = PositionAngles(closestPoint, viewpos)
        PsilentShoot(cmd, Angle)
    end
end

callbacks.Register("CreateMove", "backstabAimbot", backstabAimbot)
