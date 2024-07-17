--[[type in console:
sv_vote_issue_kick_allowed 1
cl_vote_ui_active_after_voting 1
cl_vote_ui_show_notification 1
sv_vote_creation_timer 1
sv_vote_failure_timer 1
]]
--[[for debug purpspoe
client.Command("sv_vote_issue_kick_allowed 1", true) -- enable cheats"sv_cheats 1"
client.Command("cl_vote_ui_active_after_voting 1", true) -- enable cheats"sv_cheats 1"
client.Command("sv_vote_creation_timer 1", true) -- enable cheats"sv_cheats 1"
client.Command("sv_vote_creation_timer 1", true) -- enable cheats"sv_cheats 1"
client.Command("sv_vote_failure_timer 1", true) -- enable cheats"sv_cheats 1"
]]

pcall(UnloadLib) -- if it fails then forget about it it means it wasnt loaded in first place and were clean

local libLoaded, Lib = pcall(require, "LNXlib")
assert(libLoaded, "LNXlib not found, please install it!")
assert(Lib.GetVersion() >= 1.0, "LNXlib version is too old, please update it!")

Notify = Lib.UI.Notify
TF2 = Lib.TF2

local t = {
    ['option yes'] = 1,
    ['option no'] = 2,
    ['off'] = nil
}

_G.vote = t[gui.GetValue( 'Auto Voting' )]

if not _G.vote then
    Notify.Simple("autovote.lua _G.vote is nil", "consider reading src or enable Auto Voting and reload script", 5)
    printc( 255, 0, 0, 255, 'autovote.lua _G.vote is nil, consider reading src or enable Auto Voting and reload script' )
end

-- Global variables
local options = { 'Yes', 'No', }

-- Function to handle vote options
local function onVoteOptions(event)
    for i = 1, event:GetInt('count') do
        options[i] = event:GetString('option' .. i)
    end
end

-- Function to handle vote casting
local function onVoteCast(event)
    local voteOption = event:GetInt('vote_option') + 1
    local team = event:GetInt('team')
    local entityID = event:GetInt('entityid')
    local voteIdx = event:GetInt('voteidx')
    local entity = entities.GetByIndex(entityID)
    if not entity then return end
    local name = entity:GetName()
    local me = entities.GetLocalPlayer()

    if not me then return end
    local myTeam = me:GetTeamNumber()
    local enemyPrefix = "Enemy"

    -- Use the player's team color for their name in the chat message
    local teamColorCode = '\x03' -- Default to Player name color; adjust based on team if necessary
    if team == 2 then
        teamColorCode = '\x07FF0000' -- Red team color in HEX
    elseif team == 3 then
        teamColorCode = '\x070000FF' -- Blue team color in HEX
    end

    -- Check if the entity is on the opposing team
    if team ~= myTeam then
        name = string.format('%s%s \x03%s', teamColorCode, enemyPrefix, name)
    end

    if entity == me then
        client.ChatPrintf(string.format('\x03(Vote Reveal) \x03(Auto) \x01Voted %s', options[voteOption]))
    else
        client.ChatPrintf(string.format('\x03(Vote Reveal) \x01Voted %s (\x05%s\x01)', options[voteOption], name))
    end
end

-- hangle votes reveal and events
local function handleFireGameEvent(event)
    local eventName = event:GetName()

    if _G.vote == 0 then return end
    if eventName == 'vote_options' then
        --onVoteOptions(event) -- for advanced users
    elseif eventName == 'vote_cast' then
        onVoteCast(event)
    end
end

-- Function to handle user message vote starts
local function handleUserMessageVoteStart(msg)
    local team = msg:ReadByte()
    local voteIdx = msg:ReadInt(32)
    local entIdx = msg:ReadByte()
    local dispStr = msg:ReadString(64)
    local detailsStr = msg:ReadString(64)
    local target = msg:ReadByte() >> 1 --index
    local playerInfo = client.GetPlayerInfo(target)  -- Retrieve player information

    _G.vote = t[gui.GetValue( 'Auto Voting' )] --auto update
    local voteInt = _G.vote

    if voteInt == 0 or type(voteInt) ~= 'number' then return end

    --ent0 is caster ent1 is victim
    local ent0, ent1 = entities.GetByIndex(entIdx), entities.GetByIndex(target)
    local me = entities.GetLocalPlayer()

    -- Format the player name more clearly
    local playerName = playerInfo and playerInfo.Name or "[unknown]"

 
    if ent0 == me and voteInt == 1 then -- Check if the local player initiated the vote
        if voteInt == 1 then  -- Voting yes
            --client.ChatPrintf(string.format('\x01Initiated vote against %s (%s) "vote option%d" (%s)', playerName, playerInfo.SteamID, voteInt, dispStr))
            client.Command('say "Attention: ' .. playerName .. ' is suspected of Cheating. Vote F1."', true)
        end
    elseif ent0 ~= me and ent1 ~= me then --respodn to vote field
        -- Auto vote logic for other players' votes
        if TF2.IsFriend(target, true) then
            voteInt = 2  -- Always vote no if the target is a friend
        end
        client.Command(string.format('vote %d option%d', voteIdx, voteInt), true)
    end
end

Notify.Simple("Autovote.Lua is active", "In case of erros downlado lnxlib", 5)
-- Register and unregister callbacks for clean setup
callbacks.Unregister('FireGameEvent', 'lboxfixwhen_1')
callbacks.Register('FireGameEvent', 'lboxfixwhen_1', handleFireGameEvent)

callbacks.Unregister('DispatchUserMessage', 'AutoVote_DispatchUserMessage')
callbacks.Register('DispatchUserMessage', 'AutoVote_DispatchUserMessage', handleUserMessageVoteStart)

client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound

