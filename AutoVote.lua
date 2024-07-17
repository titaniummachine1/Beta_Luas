-- type in console : ``lua vote = 1`` means auto vote yes, ``lua vote = 2`` means auto vote no
--[[type in console:
sv_vote_issue_kick_allowed 1
cl_vote_ui_active_after_voting 1
cl_vote_ui_show_notification 1
sv_vote_creation_timer 1
sv_vote_failure_timer 1
]]
--fopr debug purpspoe

pcall(UnloadLib) -- if it fails then forget about it it means it wasnt loaded in first place and were clean

local libLoaded, Lib = pcall(require, "LNXlib")
assert(libLoaded, "LNXlib not found, please install it!")
assert(Lib.GetVersion() >= 1.0, "LNXlib version is too old, please update it!")

Notify = Lib.UI.Notify
TF2 = Lib.TF2

client.Command("sv_vote_issue_kick_allowed 1", true) -- enable cheats"sv_cheats 1"
client.Command("cl_vote_ui_active_after_voting 1", true) -- enable cheats"sv_cheats 1"
client.Command("sv_vote_creation_timer 1", true) -- enable cheats"sv_cheats 1"
client.Command("sv_vote_creation_timer 1", true) -- enable cheats"sv_cheats 1"
client.Command("sv_vote_failure_timer 1", true) -- enable cheats"sv_cheats 1"

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
local g_voteidx = nil
local options = { 'Yes', 'No' }

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
    g_voteidx = voteIdx
end

-- General function to handle game events
local function handleFireGameEvent(event)
    local eventName = event:GetName()
    --[[ for advanced users
    if _G.vote == 2 or _G.vote == 0 then return end
    if eventName == 'vote_options' then
        onVoteOptions(event)
    elseif eventName == 'vote_cast' then
        onVoteCast(event)
    end
    ]]
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

    if _G.vote == 2 or _G.vote == 0 then return end

    --ent0 is caster ent1 is victim
    local ent0, ent1 = entities.GetByIndex(entIdx), entities.GetByIndex(target)
    local me = entities.GetLocalPlayer()

    _G.vote = t[gui.GetValue( 'Auto Voting' )] --auto update
    local voteInt = _G.vote

    -- Format the player name more clearly
    local playerName = playerInfo and playerInfo.Name or "[unknown]"

    -- Check if the local player initiated the vote
    if ent0 == me then
        print(voteInt)
        if voteInt == 1 then  -- Voting yes
            --client.ChatPrintf(string.format('\x01Initiated vote against %s (%s) "vote option%d" (%s)', playerName, playerInfo.SteamID, voteInt, dispStr))
            client.Command('say "Attention: ' .. playerName .. ' is suspected of Cheating. Vote F1."', true)
        end
    elseif ent0 ~= me and ent1 ~= me and type(voteInt) == 'number' then
        -- Auto vote logic for other players' votes
        if TF2.IsFriend(target, true) then
            voteInt = 2  -- Always vote no if the target is a friend
        end
        client.ChatPrintf(string.format('\x01Voted %s "option%d" (\x05%s\x01)', options[_G.vote], voteInt, detailsStr))
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

