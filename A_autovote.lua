-- type in console : ``lua vote = 1`` means auto vote yes, ``lua vote = 2`` means auto vote no
local t = {
    ['option yes'] = 1,
    ['option no'] = 2,
    ['off'] = nil
 }

 _G.vote = 1 -- Set to 1 to automatically vote "Yes"
-- _G.vote = t[gui.GetValue( 'Auto Voting' )] -- ONCE

if not _G.vote then
    printc( 255, 0, 0, 255, 'autovote.lua _G.vote is nil, consider reading src or enable Auto Voting and reload script' )
end

local g_voteidx = nil

local options = { 'Yes', 'No' }

callbacks.Register( 'FireGameEvent', 'lboxfixwhen_1', function( event )
    if event:GetName() == 'vote_options' then
        for i = 1, event:GetInt( 'count' ) do
            options[i] = event:GetString( 'option' .. i )
        end
    end

    if event:GetName() == 'vote_cast' then
        local vote_option, team, entityid, voteidx
        vote_option = event:GetInt( 'vote_option' ) + 1 -- ??? consistency
        team = event:GetInt( 'team' )
        entityid = event:GetInt( 'entityid' )
        voteidx = event:GetInt( 'voteidx' )
        g_voteidx = voteidx
    end
end )

callbacks.Register( 'SendStringCmd', 'lboxfixwhen_2', function( cmd )
    local input = cmd:Get()
    if input:find( 'vote option' ) then
        cmd:Set( input:gsub( 'vote', '%1 ' .. g_voteidx ) )
    end
end )

callbacks.Register('DispatchUserMessage', 'lboxfixwhen_3', function(msg)
    if msg:GetID() == VoteStart then
        local team, voteidx, entidx, disp_str, details_str, target
        team = msg:ReadByte()
        voteidx = msg:ReadInt(32)
        entidx = msg:ReadByte()
        disp_str = msg:ReadString(64)
        details_str = msg:ReadString(64)
        target = msg:ReadByte() >> 1

        local ent0, ent1 = entities.GetByIndex(entidx), entities.GetByIndex(target)
        local me = entities.GetLocalPlayer()
        local voteint = _G.vote

        if ent0 ~= me and ent1 ~= me and type(voteint) == 'number' then
            -- Debug: Print entity and vote information
            print("Entities: ", ent0:GetName(), ent1:GetName())
            print("Current voteint: ", voteint)
            
            -- Vote no if target is a friend
            voteint = (function()
                local playerinfo = client.GetPlayerInfo(target)
                
                -- Debug: Check if playerinfo is nil
                if not playerinfo then
                    print("playerinfo is nil")
                    return voteint
                end
                
                if steam.IsFriend(playerinfo.SteamID) then
                    print("Target is a friend, voting No")  -- Debug
                    return 2
                end
                
                local members = party.GetMembers()
                for i, steamid in ipairs(members) do
                    if steamid == playerinfo.SteamID then
                        print("Target is in party, voting No")  -- Debug
                        return 2
                    end
                end

                print("Target is neither a friend nor in party, voting based on _G.vote")  -- Debug
                return voteint
            end)()

            -- Debug: Final vote decision
            print("Final voteint: ", voteint)

            client.ChatPrintf(string.format('\x01Voted %s "vote option%d" (\x05%s\x01)', options[voteint], voteint, disp_str))
            client.Command(string.format('vote %d option%d', voteidx, voteint), true)
        else
            -- Debug: Conditions not met for voting
            print("Conditions not met for auto-voting")
        end
    end
end)
