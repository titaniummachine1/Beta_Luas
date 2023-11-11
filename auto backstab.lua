-- Calculate angle between two points
local function PositionAngles(source, dest)
    local M_RADPI = 180 / math.pi
    local delta = source - dest
    local pitch = math.atan(delta.z / delta:Length2D()) * M_RADPI
    local yaw = math.atan(delta.y / delta.x) * M_RADPI
    yaw = delta.x >= 0 and yaw + 180 or yaw
    return EulerAngles(pitch, yaw, 0)
end

-- Get the center position of a player's hitbox
local function GetHitboxPos(player, hitboxID)
    local hitbox = player:GetHitboxes()[hitboxID]
    return hitbox and (hitbox[1] + hitbox[2]) * 0.5 or nil
end

local cachedLocalPlayer
local cachedPlayers = {}
local cachedLoadoutSlot2
local pLocalViewPos
local tickCount = 0

-- Function to update the cache for the local player and loadout slot
local function UpdateLocalPlayerCache()
    cachedLocalPlayer = entities.GetLocalPlayer()
    cachedLoadoutSlot2 = cachedLocalPlayer and cachedLocalPlayer:GetEntityForLoadoutSlot(2) or nil
    pLocalViewPos = cachedLocalPlayer and (cachedLocalPlayer:GetAbsOrigin() + cachedLocalPlayer:GetPropVector("localdata", "m_vecViewOffset[0]")) or nil
end

-- Function to update the cache for all players
local function UpdatePlayersCache()
    local allPlayers = entities.FindByClass("CTFPlayer")
    for i, player in pairs(allPlayers) do
        if player:GetIndex() ~= cachedLocalPlayer:GetIndex() then
            local hitboxPos = GetHitboxPos(player, 4)  -- Assuming hitbox ID 4 is relevant
            cachedPlayers[player:GetIndex()] = {
                entity = player,
                isAlive = player:IsAlive(),
                isDormant = player:IsDormant(),
                teamNumber = player:GetTeamNumber(),
                absOrigin = player:GetAbsOrigin(),
                viewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]"),
                hitboxPos = hitboxPos
            }
        end
    end
end


-- Initialize cache
UpdateLocalPlayerCache()
UpdatePlayersCache()

-- Function to check if a backstab can be performed on a specific player from a position
local function CanBackstabFromPosition(viewPos, targetPlayer)
    if not cachedLoadoutSlot2 or cachedLoadoutSlot2:GetPropInt("m_bReadyToBackstab") ~= 257 then
        return false
    end

    if targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
        local distance = vector.Distance(viewPos, targetPlayer.absOrigin + targetPlayer.viewOffset)
        if distance < 105 then  -- Assuming 105 is the backstab range
            return true
        end
    end

    return false
end

-- Main function for player targeting and action execution
local function OnCreateMove(cmd)
    UpdateLocalPlayerCache()  -- Update local player data every tick
    UpdatePlayersCache()  -- Update player data every tick

    for _, cachedPlayer in pairs(cachedPlayers) do
        if CanBackstabFromPosition(pLocalViewPos, cachedPlayer) then
            local ang = PositionAngles(pLocalViewPos, cachedPlayer.hitboxPos)
            cmd:SetViewAngles(ang:Unpack())
            local weapon = cachedLocalPlayer:GetPropEntity("m_hActiveWeapon")
            if weapon == cachedLoadoutSlot2 and weapon:GetPropInt("m_bReadyToBackstab") == 257 then
                cmd:SetButtons(cmd.buttons | IN_ATTACK)
            end
        end
    end
end

callbacks.Unregister("CreateMove", "OnCreateMove123313")
callbacks.Register("CreateMove", "OnCreateMove12313", OnCreateMove)

