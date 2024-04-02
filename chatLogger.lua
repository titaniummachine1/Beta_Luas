-- original LUA: https://lmaobox.net/lua/Lua_Classes/UserMessage/
-- Edited By https://lmaobox.net/forum/v/profile/34545496/somefemboy5141
-- Improved by https://github.com/titaniummachine1 for more data in the chat log
-- The TXT file is in team fortress 2 folder, not in %localappdata%.
local function myCoolMessageHook(msg)
    if msg:GetID() == SayText2 then 
        local bf = msg:GetBitBuffer()
        bf:SetCurBit(8) -- skip 1 byte of not useful data
        local me = entities.GetLocalPlayer()
        local chatType = bf:ReadString(256)
        local playerName = bf:ReadString(256)
        local message = bf:ReadString(256)
        local targetIdx = bf:ReadInt(32)

        local playerInfo = client.GetPlayerInfo(targetIdx)
        local SteamID3 = playerInfo.SteamID

        local file = io.open("chat.txt", "a")
        if file then
            file:write( os.date("[%m/%d/%Y]") .. ": " .. SteamID3 .. ": " .. playerName .. ": " .. message .. "\n")
            file:close()
        else
            print("Error: Couldn't open file for writing.")
        end
    end
end

callbacks.Unregister("DispatchUserMessage", "myCoolMessageHook");
callbacks.Register("DispatchUserMessage", "myCoolMessageHook", myCoolMessageHook)
--io.close(file)