-- Cloak helper by V01D

local function ShouldThink(localPlayer)
    local playerResources = entities.GetPlayerResources();
    local allPlayerClasses = playerResources:GetPropDataTableInt("m_iPlayerClass");
    
    local currentPlayerClass = allPlayerClasses[localPlayer:GetIndex() + 1];
    local playingSpy = currentPlayerClass == TF2_Spy;

    return playingSpy;
end

local shouldThink = false;

local function CreateMoveHook(cmd)
    local localPlayer = entities.GetLocalPlayer();

    if not localPlayer:IsAlive() then
        return false
    end    

    -- Updating player info each 1/2th of second
    if cmd.tick_count % 33 == 0 then
        shouldThink = ShouldThink(localPlayer);
    end

    if not shouldThink then
        return;
    end

    local isDisguised = localPlayer:InCond(TFCond_Cloaked);

    if not isDisguised then
        return;
    end

    local cloakMeter = localPlayer:GetPropFloat("m_flCloakMeter");

    -- Exit early if the cloak meter is above a certain threshold
    if cloakMeter > 10.0 then
        return;
    end

    local moveModifier
    local time = globals.RealTime()

    -- Parameters for the stopping behavior
    local stopDuration = 0.2 -- Duration of each stop in seconds
    local rechargeThreshold = 0.05 -- Cloak meter value under which to initiate a recharge stop
    local waveFrequency = 4 * math.pi -- Frequency of the wave motion

    -- Calculate the current phase of the wave
    local wavePhase = waveFrequency * time
    local waveMotion = 0.5 * (1 + math.sin(wavePhase))

    -- Determine the need for a short stop based on the cloak meter reaching the recharge threshold
    if cloakMeter <= rechargeThreshold then
        -- Calculate whether the current time falls within a stop period based on stop duration
        if (time % (1 / waveFrequency)) < stopDuration then
            moveModifier = 0 -- Stop moving entirely to simulate recharging
        else
            -- Resume normal movement after the stop, with moveModifier based on wave motion and cloakMeter
            moveModifier = waveMotion * (0.0044 * cloakMeter * cloakMeter)
        end
    else
        -- Normal movement modification based on the cloak meter, without the need for stopping
        moveModifier = waveMotion * (0.0044 * cloakMeter * cloakMeter)
    end

    cmd:SetForwardMove(cmd:GetForwardMove() * moveModifier);
    cmd:SetSideMove(cmd:GetSideMove() * moveModifier);
    cmd:SetUpMove(cmd:GetUpMove() * moveModifier);
    cmd:SetButtons(cmd:GetButtons() & ~IN_JUMP);
end

callbacks.Register("CreateMove", "createmove_cloak_stop", CreateMoveHook);