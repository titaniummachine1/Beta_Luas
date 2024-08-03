local pLocal = entities.GetLocalPlayer()
local players = entities.FindByClass("CTFPlayer")
local playerData = {}

local function doDraw()
    pLocal = entities.GetLocalPlayer()
    players = entities.FindByClass("CTFPlayer")

    for idx, player in pairs(players) do
        if not pLocal or not player:IsAlive() or player:IsDormant() or player:GetTeamNumber() == pLocal:GetTeamNumber() then
            goto continue
        end

        local playerIndex = player:GetIndex()
        local cloaked = player:InCond(TFCond_Cloaked)

        -- Initialize player data if not already present
        if playerData[playerIndex] == nil then
            playerData[playerIndex] = { cloaked = false } -- Assume initially not cloaked
        end

        -- Check if the player just decloaked
        if playerData[playerIndex].cloaked and not cloaked then
            engine.PlaySound("player/spy_uncloak_feigndeath.wav")
            playerData[playerIndex].cloaked = false
        elseif not playerData[playerIndex].cloaked and cloaked then
            -- Update the cloaked state
            playerData[playerIndex].cloaked = true
        end

        ::continue::
    end
end

callbacks.Unregister("Draw", "lc_Draw")
callbacks.Register("Draw", "lc_Draw", doDraw)

-- Play sound when loaded
engine.PlaySound("hl1/fvox/activated.wav")
