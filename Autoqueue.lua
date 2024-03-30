--[[
    Auto Queue for Lmaobox
    Author: LNX (github.com/lnx00)
    Fixed by titaniummachine1 (github.com/titaniummachine1)
]]

AutoQueue = true
local lastTime = 0
local delay = 4  -- Delay in seconds
local casualQueue = party.GetAllMatchGroups()["Casual"]

local function AutoQueue()
    -- Check if the function is called before the delay has passed
    if globals.RealTime() - lastTime < delay then
        return
    end

    -- Update the last time the function was called
    lastTime = globals.RealTime()

    if not AutoQueue or gamecoordinator.HasLiveMatch() or gamecoordinator.IsConnectedToMatchServer() or gamecoordinator.GetNumMatchInvites() > 0 then
        return
    end

    if #party.GetQueuedMatchGroups() == 0 and not party.IsInStandbyQueue() and party.CanQueueForMatchGroup(casualQueue) == true then
        party.QueueUp(casualQueue)
    end
end

AutoQueue() --inicial call to start the script

--Can't use CreateMove, because it's not called in main menu
--just hooking to anything relevant to hope for any call that wil triger this code whil in main menu
callbacks.Unregister("FireGameEvent", "AutoQueue")
callbacks.Register("FireGameEvent", "AutoQueue", AutoQueue)

callbacks.Unregister("OnLobbyUpdated", "AutoQueue")
callbacks.Register("OnLobbyUpdated", "AutoQueue", AutoQueue)

callbacks.Unregister("Draw", "AutoQueue")
callbacks.Register("Draw", "AutoQueue", AutoQueue)

callbacks.Unregister("SetRichPresence", "AutoQueue")
callbacks.Register("SetRichPresence", "AutoQueue", AutoQueue)

--engine.Notification("You have just executed the AutoQueue script.\nIf you want to stop it, simply type this into the console:\nlua AutoQueue = false\n\nYou can re-enable AutoQueue again by running the script again or by typing:\nlua AutoQueue = true")
client.Command('play "ui/buttonclick"', true)
