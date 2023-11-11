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
            cachedPlayers[player:GetIndex()] = {
                entity = player,
                isAlive = player:IsAlive(),
                isDormant = player:IsDormant(),
                teamNumber = player:GetTeamNumber(),
                absOrigin = player:GetAbsOrigin(),
                viewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]"),
                hitboxPos = GetHitboxPos(player, 4)
            }
        end
    end
end


-- Initialize cache
UpdateLocalPlayerCache()
UpdatePlayersCache()

local hitboxpos = Vector3(0, 0, 0)
local function CanBackstabFromPosition(cmd, viewPos)
    for _, targetPlayer in pairs(cachedPlayers) do
        if targetPlayer.isAlive and not targetPlayer.isDormant and targetPlayer.teamNumber ~= cachedLocalPlayer:GetTeamNumber() then
            local distance = vector.Distance(viewPos, targetPlayer.hitboxPos)
            hitboxpos = targetPlayer.hitboxPos
            if distance < 105 then  -- Assuming 105 is the backstab range
                local ang = PositionAngles(viewPos, targetPlayer.hitboxPos)
                cmd:SetViewAngles(ang:Unpack())  -- Set view angles

                if cachedLoadoutSlot2 and cachedLoadoutSlot2:GetPropInt("m_bReadyToBackstab") == 257 then
                    return true
                end
            end
        end
    end

    return false
end

local function OnCreateMove(cmd)
    UpdateLocalPlayerCache()  -- Update local player data every tick
    UpdatePlayersCache()  -- Update player data every tick

    if CanBackstabFromPosition(cmd, pLocalViewPos) then
        cmd:SetButtons(cmd.buttons | IN_ATTACK)  -- Perform backstab
    end
end

local function doDraw()

end

callbacks.Unregister("CreateMove", "OnCreateMove123313")
callbacks.Register("CreateMove", "OnCreateMove12313", OnCreateMove)

callbacks.Unregister("Draw", "AMsadaAT_Draw")                        -- Unregister the "Draw" callback
callbacks.Register("Draw", "AMsadaAT_Draw", doDraw)                               -- Register the "Draw" callback


