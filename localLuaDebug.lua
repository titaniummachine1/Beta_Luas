UnloadScript( GetScriptName() )
callbacks.Unregister( 'SendStringCmd', 'cli-parse')

local cvar, var = {}, {}
cvar.RegisterCommand = function( name, callback )
    if type( var[name] ) ~= 'nil' then return false end
    var[name] = callback
    return true
end
cvar.UnregisterCommand = function( name )
    if type( var[name] ) == 'nil' then return false end
    var[name] = undef
    return true
end
local VarSetInfo = function( name, val ) client.Command( string.format( 'setinfo %q %q', name, val or '' ), true ) end

callbacks.Register( 'SendStringCmd', 'cli-parse', function( cmd )
    local feed = cmd:Get()
    for name, callback in pairs( var ) do
        local i, j = string.find( feed, name, 1, true )
        if i == 1 then
            local a = {}
            for w in feed:sub( j + 1, #feed ):gmatch( '%S+' ) do a[#a + 1] = w end
            cvar.Set = function( any ) return cmd:Set( any ) end
            return callback( #a, table.unpack( a ) )
        end
    end
end )

cvar.RegisterCommand( 'info', function( argc, ... )
    cvar.Set( '' )
    local argcc = argc > 0 and argc or 1
    printc( 255 // (argc * 0.01), 255, 255 // (argc * 0.03), 255, string.format( 'current script: %s', GetScriptName() ) )
    printc( 255 // (argc * 0.01), 255, 255 // (argc * 0.03), 255, string.format( 'argument count: %d', argc ) )
    print( table.concat( { ... }, '\n' ) )
end )

cvar.RegisterCommand( 'lua_unload', function( argc, to_unload )
    cvar.Set( '' )
    local argcc = argc > 0 and argc or 1
    local dir = os.getenv('LOCALAPPDATA')
    local absolute = dir .. "//" .. to_unload
    if type( to_unload ) == 'string' and #to_unload > 0 then
        printc( 255 // (argc * 0.01), 255, 255 // (argc * 0.03), 255, string.format( 'unloading %s (result: %s)', absolute, UnloadScript( absolute ) ) )   
    end
end )

-- because unload command is used in beta version of the cheat to uninject.
cvar.RegisterCommand( 'lua_unload', function( argc, to_unload )
    cvar.Set( '' )
    local argcc = argc > 0 and argc or 1
    local dir = os.getenv('LOCALAPPDATA')
    local absolute = dir .. "//" .. to_unload
    if type( to_unload ) == 'string' and #to_unload > 0 then
        printc( 255 // (argc * 0.01), 255, 255 // (argc * 0.03), 255, string.format( 'unloading %s (result: %s)', absolute, UnloadScript( absolute ) ) )   
    end
end )

local me = entities.GetLocalPlayer()

if me then

    local ammoTable = me:GetPropDataTableInt("localdata", "m_iAmmo")
    if ammoTable then
        printc("255", "0", "0", "100", "**Ammo Table Info:**")
        for i, ammoCount in ipairs(ammoTable) do
            print("Ammo for index '" .. tostring(i) .. "': " .. tostring(ammoCount))
        end
    end

    local function printWeaponAmmoInfo(weaponEntity, weaponName)
        if weaponEntity then
            local wData = weaponEntity:GetWeaponData()

            local clip1 = weaponEntity:GetPropInt("LocalWeaponData", "m_iClip1")
            local clip2 = weaponEntity:GetPropInt("LocalWeaponData", "m_iClip2")
  
            local itemDefinitionIndex = weaponEntity:GetPropInt("m_iItemDefinitionIndex")
            local itemDefinition = itemschema.GetItemDefinitionByID(itemDefinitionIndex)
            local weaponDefName = itemDefinition:GetName()
            local weaponClass = itemDefinition:GetClass()
            local weaponLoadoutSlot = itemDefinition:GetLoadoutSlot()
            local weaponHidden = itemDefinition:IsHidden()
            local weaponIsTool = itemDefinition:IsTool()
            local weaponIsBaseItem = itemDefinition:IsBaseItem()
            local weaponIsWearable = itemDefinition:IsWearable()
            local weaponTypeName = itemDefinition:GetTypeName()
            local weaponDescription = itemDefinition:GetDescription()
            local weaponIconName = itemDefinition:GetIconName()
            local weaponBaseNumber = itemDefinition:GetBaseItemName()
            local eCanCrit = weaponEntity:CanRandomCrit()

            local wDamage = wData.damage
            local wBulletsPerShot = wData.bulletsPerShot
            local wRange = wData.range
            local wSpread = wData.spread
            local wPunchAngle = wData.punchAngle
            local wTimeFireDelay = wData.timeFireDelay
            local wTimeIdle = wData.timeIdle
            local wTimeIdleEmpty = wData.timeIdleEmpty
            local wTimeReloadStart = wData.timeReloadStart
            local wTimeReload = wData.timeReload
            local wDrawCrosshair = wData.drawCrosshair
            local wProjectile = wData.projectile
            local wAmmoPerShot = wData.ammoPerShot
            local wProjectileSpeed = wData.projectileSpeed
            local wSmackDelay = wData.smackDelay
            local wUseRapidFireCrits = wData.useRapidFireCrits

            printc("0", "255", "0", "100", "Definition Name: " .. weaponDefName)
            print("Class: " .. weaponClass)
            print("Loadout Slot: " .. weaponLoadoutSlot)
            print("Hidden: " .. tostring(weaponHidden))
            print("Is Tool: " .. tostring(weaponIsTool))
            print("Is Base Item: " .. tostring(weaponIsBaseItem))
            print("Is Wearable: " .. tostring(weaponIsWearable))
            print("Type Name: " .. weaponTypeName)
            
            if weaponDescription then
                print("Description: " .. weaponDescription)
            else
                printc("255", "255", "0", "100", "Failed to get description. 'itemDefinition:GetDescription()' may not work for this item.")
            end           

            if weaponIconName then
                print("Icon Name: " .. weaponIconName)
            else
                printc("255", "255", "0", "100", "Failed to get icon name. 'itemDefinition:GetIconName()' may not work for this item.")
            end

            print("Base Item Name: " .. weaponBaseNumber)
            print("Can Random Crit: " .. tostring(eCanCrit))

            printc("255", "0", "0", "100", "**m_iClip(1/2) for " .. weaponDefName .. ":**")
            print("Current " .. weaponName .. " weapon entity: " .. tostring(weaponEntity))
            print("Current Ammo in m_iClip1: " .. tostring(clip1))
            print("Current Ammo in m_iClip2: " .. tostring(clip2))

            printc("255", "0", "0", "100", "**Weapon Data for " .. weaponDefName .. ":**")
            print("Weapon Damage: " .. tostring(wDamage))
            print("Bullets Per Shot: " .. tostring(wBulletsPerShot))
            print("Range: " .. tostring(wRange))
            print("Spread: " .. tostring(wSpread))
            print("Punch Angle: " .. tostring(wPunchAngle))
            print("Time Fire Delay: " .. tostring(wTimeFireDelay))
            print("Time Idle: " .. tostring(wTimeIdle))
            print("Time Idle Empty: " .. tostring(wTimeIdleEmpty))
            print("Time Reload Start: " .. tostring(wTimeReloadStart))
            print("Time Reload: " .. tostring(wTimeReload))
            print("Draw Crosshair: " .. tostring(wDrawCrosshair))
            print("Projectile: " .. tostring(wProjectile))
            print("Ammo Per Shot: " .. tostring(wAmmoPerShot))
            print("Projectile Speed: " .. tostring(wProjectileSpeed))
            print("Smack Delay: " .. tostring(wSmackDelay))
            print("Use Rapid Fire Crits: " .. tostring(wUseRapidFireCrits))
            
            if weaponEntity:IsShootingWeapon() then
                
                printc("255", "0", "0", "100", "Shooting weapon info for " .. weaponDefName .. ":")

                local eType = weaponEntity:GetWeaponProjectileType()
                local eSpread = weaponEntity:GetWeaponSpread()
                local eSpeed = weaponEntity:GetProjectileSpeed()
                local eGravity = weaponEntity:GetProjectileGravity()
                local ePSpread = weaponEntity:GetProjectileSpread()
                local eLoadoutSlotID = weaponEntity:GetLoadoutSlot()
                local eWeaponID = weaponEntity:GetWeaponID()
                local eFlippedViewmodel = weaponEntity:IsViewModelFlipped()

                print("Projectile Type: " .. tostring(eType))
                print("Spread: " .. tostring(eSpread))
                print("Speed: " .. tostring(eSpeed))
                print("Gravity: " .. tostring(eGravity))
                print("Project Spread: " .. tostring(ePSpread))
                print("Loadout Slot ID: " .. tostring(eLoadoutSlotID))
                print("Weapon ID: " .. tostring(eWeaponID))
                print("Flipped Viewmodel: " .. tostring(eFlippedViewmodel))

            else
                printc("0", "255", "0", "100", weaponDefName .. " is not a shooting weapon.*********")
            end

            if weaponEntity:IsMeleeWeapon() then

                printc("255", "0", "0", "100", "Melee weapon info for " .. weaponDefName .. ":")
                local eSwingRange = weaponEntity:GetSwingRange()
                local eSwingTrace = weaponEntity:DoSwingTrace()
                    local tEntity = eSwingTrace.entity
                    local tEntityStr = tostring(tEntity)
                    local tEntityPlayer = tostring(tEntity:IsPlayer())
                    local tContents = eSwingTrace.contents
                    local tHitbox = eSwingTrace.hitbox
                    local tHitgroup = eSwingTrace.hitgroup
                    
                    if tEntityPlayer == "true" then
                        tEntityName = tEntity:GetName()
                    end

                print("Swing Range: " .. tostring(eSwingRange))

                    if tEntityStr == "InvalidEntity" then
                        print("If swung, your melee weapon would hit nothing.")

                    elseif tEntityPlayer == "false" then
                        print("If swung, your melee would not hit a player! You would hit an entity of class type: " .. tostring(tEntity))
                        
                    elseif tEntityPlayer == "true" then
                        print("If swung, your melee would hit the player: " .. tostring(tEntityName))  
                    end

                print("Melee swing contents: " .. tostring(tContents))
                print("Melee swing hitbox: " .. tostring(tHitbox))
                print("Melee swing hitgroup: " .. tostring(tHitgroup))
                
            else
                printc("0", "255", "0", "100", weaponDefName .. " is not a melee weapon.*********")
            end

            local function HealCheck(target)
                local CanHealTarget = weaponEntity:IsMedigunAllowedToHealTarget(target)
                return CanHealTarget
            end

            if weaponEntity:IsMedigun() then
                        
            -- Target Check
            local tMe = entities.GetLocalPlayer();
            local tSource = tMe:GetAbsOrigin() + tMe:GetPropVector("localdata", "m_vecViewOffset[0]")
            local tDestination = tSource + engine.GetViewAngles():Forward() * 1000
            local tTrace = engine.TraceLine(tSource, tDestination, MASK_SHOT_HULL)
            local tVisTarget = tTrace.entity
            if (tVisTarget ~= nil) then
                if tostring(HealCheck(tVisTarget)) == "false" then
                    print(tostring(tVisTarget:GetClass()) .. " is not healable.******************************")
                else
                print("Can heal visible target: " .. tostring(canHealVisTarget))
                end
                --Distance calculation if I want to add heal target distance check later: tTrace.fraction * 1000
            end

                printc("255", "0", "0", "100", "Medigun info for " .. weaponDefName .. ":")

                local eHealRate = weaponEntity:GetMedigunHealRate()
                local eHealStickRange = weaponEntity:GetMedigunHealingStickRange()
                local eHealRange = weaponEntity:GetMedigunHealingRange()
                local IsMedigunAllowedToHealTarget
                local HealSelf = HealCheck(me)
                local HealTarget = HealCheck(tVisTarget)

                print("Heal Rate: " .. tostring(eHealRate))
                print("Heal Stick Range: " .. tostring(eHealStickRange))
                print("Heal Range: " .. tostring(eHealRange))
                print("Can Heal Self: " .. tostring(HealSelf))
                print("Can Heal Target: " .. tostring(HealTarget))

            end


        else
            print("Could not retrieve " .. weaponName .. " weapon entity.")
        end
    end

    local primaryWeaponEntity = me:GetEntityForLoadoutSlot(LOADOUT_POSITION_PRIMARY)
    local secondaryWeaponEntity = me:GetEntityForLoadoutSlot(LOADOUT_POSITION_SECONDARY)
    local meleeEntity = me:GetEntityForLoadoutSlot(LOADOUT_POSITION_MELEE)

    printc("255", "0", "0", "100", "**Weapon Ammo Info:**")
    printWeaponAmmoInfo(primaryWeaponEntity, "primary")
    printWeaponAmmoInfo(secondaryWeaponEntity, "secondary")
    printWeaponAmmoInfo(meleeEntity, "melee")

else
    print("Local player entity not found.")
end

itemschema.EnumerateAttributes( function( attrDef )
    print( attrDef:GetName() .. ": " .. tostring( attrDef:GetID() ) )
end )

local consolas = draw.CreateFont("Consolas", 17, 500)
local current_fps = 0

local function watermark()
  draw.SetFont(consolas)
  draw.Color(255, 255, 255, 255)

  -- update fps every 100 frames
  if globals.FrameCount() % 100 == 0 then
    current_fps = math.floor(1 / globals.FrameTime())
  end

  draw.Text(5, 5, "[lmaobox | fps: " .. current_fps .. "]")
end

callbacks.Register("Draw", "draw", watermark)

local function damageLogger(event)

    if (event:GetName() == 'player_hurt' ) then

        local localPlayer = entities.GetLocalPlayer();
        local victim = entities.GetByUserID(event:GetInt("userid"))
        local health = event:GetInt("health")
        local attacker = entities.GetByUserID(event:GetInt("attacker"))
        local damage = event:GetInt("damageamount")

        if (attacker == nil or localPlayer:GetIndex() ~= attacker:GetIndex()) then
            return
        end

        print("You hit " ..  victim:GetName() .. " or ID " .. victim:GetIndex() .. " for " .. damage .. "HP they now have " .. health .. "HP left")
    end

end

callbacks.Register("FireGameEvent", "exampledamageLogger", damageLogger)

local myfont = draw.CreateFont( "Verdana", 16, 800 )

local function doDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end

    local players = entities.FindByClass("CTFPlayer")

    for i, p in ipairs( players ) do
        if p:IsAlive() and not p:IsDormant() then

            local screenPos = client.WorldToScreen( p:GetAbsOrigin() )
            if screenPos ~= nil then
                draw.SetFont( myfont )
                draw.Color( 255, 255, 255, 255 )
                draw.Text( screenPos[1], screenPos[2], p:GetName() )
            end
        end
    end
end

callbacks.Register("Draw", "mydraw", doDraw)

-- type in console : ``lua vote = 1`` means auto vote yes, ``lua vote = 2`` means auto vote no
local t = {
    ['option yes'] = 1,
    ['option no'] = 2,
    ['off'] = nil
 }

_G.vote = t[gui.GetValue( 'Auto Voting' )] -- ONCE

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

callbacks.Register( 'DispatchUserMessage', 'lboxfixwhen_3', function( msg )
    if msg:GetID() == VoteStart then
        local team, voteidx, entidx, disp_str, details_str, target
        team = msg:ReadByte()
        voteidx = msg:ReadInt( 32 )
        entidx = msg:ReadByte()
        disp_str = msg:ReadString( 64 )
        details_str = msg:ReadString( 64 )
        target = msg:ReadByte() >> 1

        local ent0, ent1 = entities.GetByIndex( entidx ), entities.GetByIndex( target )
        local me = entities.GetLocalPlayer()
        local voteint = _G.vote

        if ent0 ~= me and ent1 ~= me and type( voteint ) == 'number' then

            -- vote no if target is friend
            voteint = (function()
                local playerinfo = client.GetPlayerInfo( target )
                if steam.IsFriend( playerinfo.SteamID ) == true then
                    return 2
                end

                local members = party.GetMembers()
                for i, steamid in ipairs( members ) do
                    if steamid == playerinfo.SteamID then
                        return 2
                    end
                end

                return voteint
            end)()

            client.ChatPrintf( string.format( '\x01Voted %s "vote option%d" (\x05%s\x01)', options[voteint], voteint,
                disp_str ) )
            client.Command( string.format( 'vote %d option%d', voteidx, voteint ), true )
        end
    end
end )

local kv = [[
    "upgrades" {
        "itemslot" ""
        "upgrade" ""
        "count" ""
    }
]]

--region: idc
local umsg_name = {
    [0] = 'Geiger',
    'Train',
    'HudText',
    'SayText',
    'SayText2',
    'TextMsg',
    'ResetHUD',
    'GameTitle',
    'ItemPickup',
    'ShowMenu',
    'Shake',
    'Fade',
    'VGUIMenu',
    'Rumble',
    'CloseCaption',
    'SendAudio',
    'VoiceMask',
    'RequestState',
    'Damage',
    'HintText',
    'KeyHintText',
    'HudMsg',
    'AmmoDenied',
    'AchievementEvent',
    'UpdateRadar',
    'VoiceSubtitle',
    'HudNotify',
    'HudNotifyCustom',
    'PlayerStatsUpdate',
    'MapStatsUpdate',
    'PlayerIgnited',
    'PlayerIgnitedInv',
    'HudArenaNotify',
    'UpdateAchievement',
    'TrainingMsg',
    'TrainingObjective',
    'DamageDodged',
    'PlayerJarated',
    'PlayerExtinguished',
    'PlayerJaratedFade',
    'PlayerShieldBlocked',
    'BreakModel',
    'CheapBreakModel',
    'BreakModel_Pumpkin',
    'BreakModelRocketDud',
    'CallVoteFailed',
    'VoteStart',
    'VotePass',
    'VoteFailed',
    'VoteSetup',
    'PlayerBonusPoints',
    'RDTeamPointsChanged',
    'SpawnFlyingBird',
    'PlayerGodRayEffect',
    'PlayerTeleportHomeEffect',
    'MVMStatsReset',
    'MVMPlayerEvent',
    'MVMResetPlayerStats',
    'MVMWaveFailed',
    'MVMAnnouncement',
    'MVMPlayerUpgradedEvent',
    'MVMVictory',
    'MVMWaveChange',
    'MVMLocalPlayerUpgradesClear',
    'MVMLocalPlayerUpgradesValue',
    'MVMResetPlayerWaveSpendingStats',
    'MVMLocalPlayerWaveSpendingValue',
    'MVMResetPlayerUpgradeSpending',
    'MVMServerKickTimeUpdate',
    'PlayerLoadoutUpdated',
    'PlayerTauntSoundLoopStart',
    'PlayerTauntSoundLoopEnd',
    'ForcePlayerViewAngles',
    'BonusDucks',
    'EOTLDuckEvent',
    'PlayerPickupWeapon',
    'QuestObjectiveCompleted',
    'SPHapWeapEvent',
    'HapDmg',
    'HapPunch',
    'HapSetDrag',
    'HapSetConst',
    'HapMeleeContact'
 }
--endregion

callbacks.Register( 'DispatchUserMessage', function( u )
print(umsg_name[u:GetID()])
end )

callbacks.Register( 'Draw', function()
    if globals.FrameCount() % (1 // globals.TickInterval()) == 0 then
        client.Command( 'bot_command all addcond 0', '' )
        client.Command( 'bot_command all addcond 71', '' )
        client.Command( 'tf_mvm_tank_kill', '' )
    end
end )

local table_gen = require( 'table_gen' )
local json = require( 'json' )
local msgpack = require( 'msgpack' )
-- client.Command( 'exec vote', true )
local config = {}

config.Voting = {
    annouce_vote_issue = 0,
    annouce_voter = 0,
    auto_callvote = 0,
    auto_voteoption = 0,
    vote_end = 0
 }

local localizeCache = {}

local function Localize( key, ... )
    local varargs, localized = { ... }, client.Localize( key )

    if localized == nil or localized:len() < 1 then
        print( string.format( 'Cannot localize key: %q', key ) )
        return key
    end

    if not localizeCache[key] then
        local index = 0
        localizeCache[key] = localized:gsub( '%%[acdglpsuwx%[%]]%d', function( capture )
            index = index + 1
            ---@author: Moonverse#9320 2022-07-21 00:00:33
            -- So, in lbox there's an unexplainable behavior on `print`, `printc` and `ChatPrintf`
            -- the game crashes if i don't pcix string with "%%" 
            -- note it doesn't happen with `engine.Notification`
            -- so, if you know what that is, report it to bf and tell me about it.
            return varargs[index] or string.format( '%%%s', capture )
        end )
    end

    return localizeCache[key]
end

local function Announce( text, bit )
end

local vote_failed_t = {
    [0] = '#GameUI_vote_failed',
    [3] = '#GameUI_vote_failed_yesno',
    [4] = '#GameUI_vote_failed_quorum'
 }

local UNASSIGNED, SPECTATOR, TEAM_RED, TEAM_BLU = 0, 1, 2, 3
local team_color = {
    [UNASSIGNED] = 0xF6D7A7ff,
    [SPECTATOR] = 0xcfcfc4ff,
    [TEAM_RED] = 0xff6663ff,
    [TEAM_BLU] = 0x9EC1CFff
 }
local team_name = {
    [0] = 'UNASSIGNED',
    'SPECTATOR',
    'RED',
    'BLU'
 }

local options_str, options_voteidx_str, count, voted, info = {}, {}, {}, {}, {}

local finalize_vote = function( voteidx, team, text )
    printc( 0, 255, 0, 255,
        string.format( 'Vote Ended ( index: %d, server: %s, begin at: %s, map: %s )', voteidx, info[voteidx][1],
            info[voteidx][2], info[voteidx][3] ) )

    if text then
        local rgba = team_color[team]
        printc( rgba >> 24 & 0xFF, rgba >> 16 & 0xFF, rgba >> 8 & 0xFF, rgba & 0xFF,
            string.format( '[%s] %s', team_name[team], text ) )
    end

    if voted[voteidx] then
        local result, rows = {}, {}

        for t, arr in pairs( voted[voteidx] ) do
            for i, v in ipairs( arr ) do
                rows[#rows + 1] = v
            end
        end

        local sheet = table_gen( rows, { "Team", "Name", "SteamID", "Option" }, {
            style = "Markdown (Github)"
         } )
        print( sheet )

        for i, option in ipairs( count[voteidx] ) do
            if option > 0 and i <= 5 then
                result[#result + 1] = (options_voteidx_str[voteidx][i] or 'option' .. i) .. ": " .. option
            end
        end

        print( "- " .. table.concat( result, ', ' ) )
        options_voteidx_str[voteidx], count[voteidx], voted[voteidx], info[voteidx] = nil, nil, nil, nil
    end
end

callbacks.Register( 'FireGameEvent', function( event )
    local eventname = event:GetName()

    if eventname == 'vote_options' then -- server doesn't return voteidx
        for i = 1, event:GetInt( 'count' ) do
            options_str[i] = event:GetString( 'option' .. i )
        end
        return
    end

    if eventname == 'vote_changed' then
        local option, voteidx
        voteidx = event:GetInt( 'voteidx' )
        for j = 1, 5 do
            count[voteidx][j] = event:GetInt( 'vote_option' .. j )
        end
        count[voteidx][#count + 1] = event:GetInt( 'potentialVotes' )
        return
    end

    if eventname == 'vote_cast' then
        local option, team, entidx, voteidx
        option = event:GetInt( 'vote_option' ) + 1
        team = event:GetInt( 'team' )
        entidx = event:GetInt( 'entityid' )
        voteidx = event:GetInt( 'voteidx' )

        local playerinfo, teamname = client.GetPlayerInfo( entidx ), team_name[team] or team
        if not voted[voteidx] then
            options_voteidx_str[voteidx], count[voteidx], voted[voteidx] = options_str, {}, {}
            info[voteidx] = { engine.GetServerIP(), os.date( '%Y-%m-%d %H:%M:%S' ),
                              engine.GetMapName():gsub( '.bsp$', '.nav' ) }
        end
        voted[voteidx][team] = voted[voteidx][team] or {}
        table.insert( voted[voteidx][team],
            { teamname, playerinfo.Name, playerinfo.SteamID, options_voteidx_str[voteidx][option] or option } )
        return
    end

    if eventname == 'client_disconnect' then
        for i in pairs( voted ) do
            finalize_vote( i )
        end
    end

end )

callbacks.Register( 'DispatchUserMessage', function( msg )
    local id, sizeOfData, offset
    id = msg:GetID()
    sizeOfData = msg:GetDataBytes()

    if id == CallVoteFailed then
        local reason, time
        reason = msg:ReadByte()
        time = msg:ReadInt( 16 )
        
        return
    end

    if id == VoteStart then
        local team, voteidx, entidx, disp_str, details_str, target
        team = msg:ReadByte()
        voteidx = msg:ReadInt( 32 )
        entidx = msg:ReadByte()
        disp_str = msg:ReadString( 64 )
        details_str = msg:ReadString( 64 )
        target = msg:ReadByte() >> 1

        local playerinfo, teamname = client.GetPlayerInfo( entidx ), team_name[team] or team
        local rgba = team_color[team]
        local text = Localize( disp_str, '\x05' .. details_str .. '\x01' )
        printc( 0, 255, 0, 255, string.format( 'Vote Started ( index: %d, from: %s | %s )', voteidx, playerinfo.Name,
            playerinfo.SteamID ) )
        printc( rgba & 0xFF, rgba >> 24 & 0xFF, rgba >> 16 & 0xFF, rgba >> 8 & 0xFF, string.format( '[%s] %s', teamname,
            text:gsub( "\7......", "" ):gsub( "\8........", "" ):gsub( '%c', ' ' ) ) )
        Announce( string.format( '\8%d %s', team_color[team], text ), config.Voting.annouce_vote_issue )
        if config.announce_voter then

        end
        return
    end

    if id == VotePass then
        local team, voteidx, disp_str, details_str
        team = msg:ReadByte()
        voteidx = msg:ReadInt( 32 )
        disp_str = msg:ReadString( 256 )
        details_str = msg:ReadString( 256 )

        local text = Localize( disp_str, details_str )
        Announce( string.format( '\8%d %s', team_color[team], text ), config.Voting.vote_end )
        return finalize_vote( voteidx, team, text )
    end

    if id == VoteFailed then
        local team, voteidx, reason
        team = msg:ReadByte()
        voteidx = msg:ReadInt( 32 )
        reason = msg:ReadByte()

        local text = Localize( vote_failed_t[reason] )
        Announce( string.format( '\8%d %s', team_color[team], text ), config.Voting.vote_end )
        return finalize_vote( voteidx, team, text )
    end

end )

--print( msgpack.decode( msgpack.encode( "abc", config ) ) )
--print( json.decode( json.encode( "a", config ) ) )

--[[
    https://github.com/sapphyrus/table_gen.lua
-- require the file
local table_gen = require "table_gen"

local headings = {"Country", "Capital", "Population", "Language"}
local rows = {
	{"USA", "Washington, D.C.", "237 million", "English"},
	{"Sweden", "Stockholm", "10 million",	"Swedish"},
	{"Germany", "Berlin", "82 million", "German"}
}

-- generate the table. Last argument are the options, or if a string, the style option
local table_out = table_gen(rows, headings, {
	style = "Markdown (Github)"
})

-- Print it to console
print(table_out)

-- output:
-- | Country |     Capital      | Population  | Language |
-- |---------|------------------|-------------|----------|
-- | USA     | Washington, D.C. | 237 million | English  |
-- | Sweden  | Stockholm        | 10 million  | Swedish  |
-- | Germany | Berlin           | 82 million  | German   |

"Vote_RestartGame"		"Restart Game"
"Vote_Kick"				"Kick"
"Vote_ChangeLevel"		"Change Map"
"Vote_NextLevel"			"Next Map"
"Vote_ExtendLevel"			"Extend Current Map"
"Vote_ScrambleTeams"		"Scramble Teams"
"Vote_ChangeMission"		"Change Mission"
"Vote_Eternaween"			"Eternaween"
"Vote_TeamAutoBalance_Enable"		"Enable Team AutoBalance"
"Vote_TeamAutoBalance_Disable"	"Disable Team AutoBalance"
"Vote_ClassLimit_Enable"			"Enable Class Limits"
"Vote_ClassLimit_Disable"			"Disable Class Limits"
"Vote_PauseGame"			"Pause Game"

]]

-- If you see this error 
-- 50: attempt to concatenate a nil value (field 'shots_left_till_bucket_full')
-- It's safe to ignore! 
-- I was simply caching GetWeaponData() because CreateMove updates more often than Draw
local colors = {
    white = { 255, 255, 255, 255 },
    gray = { 190, 190, 190, 255 },
    red = { 255, 0, 0, 255 },
    green = { 36, 255, 122, 255 },
    blue = { 30, 139, 195, 255 }
 }

local other_weapon_info = {
    crit_chance = 0,
    observedCritChance = 0,
    damageStats = {}
 }
local cache_weapon_info = {
    [0] = {}
 }
function cache_weapon_info.get(critCheckCount)
    if cache_weapon_info[0].critCheckCount == critCheckCount then
        return cache_weapon_info[0], false
    end
end
function cache_weapon_info.update(t)
    for k, v in pairs(t) do
        cache_weapon_info[0][k] = v
    end
end

local hardcoded_weapon_ids = {}
local arr = { 441, 416, 40, 594, 595, 813, 834, 141, 1004, 142, 232, 61, 1006, 525, 132, 1082, 266, 482, 327, 307, 357,
              404, 812, 833, 237, 265, 155, 230, 460, 1178, 14, 201, 56, 230, 402, 526, 664, 752, 792, 801, 851, 881,
              890, 899, 908, 957, 966, 1005, 1092, 1098, 15000, 15007, 15019, 15023, 15033, 15059, 15070, 15071, 15072,
              15111, 15112, 15135, 15136, 15154, 30665, 194, 225, 356, 461, 574, 638, 649, 665, 727, 794, 803, 883, 892,
              901, 910, 959, 968, 15062, 15094, 15095, 15096, 15118, 15119, 15143, 15144, 131, 406, 1099, 1144, 46, 42,
              311, 863, 1002, 159, 433, 1190, 129, 226, 354, 1001, 1101, 1179, 642, 133, 444, 405, 608, 57, 231, 29,
              211, 35, 411, 663, 796, 805, 885, 894, 903, 912, 961, 970, 998, 15008, 15010, 15025, 15039, 15050, 15078,
              15097, 15121, 15122, 15123, 15145, 15146, 30, 212, 59, 60, 297, 947, 735, 736, 810, 831, 933, 1080, 1102,
              140, 1086, 30668, 25, 737, 26, 28, 222, 1121, 1180, 58, 1083, 1105 }
for i = 1, #arr do
    hardcoded_weapon_ids[arr[i]] = true
end

local function CanFireCriticalShot(me, wpn)
    if me:GetPropInt('m_iClass') == TF2_Spy and wpn:IsMeleeWeapon() then
        return false
    end
    local className = wpn:GetClass()
    if className == 'CTFSniperRifle' or className == 'CTFBuffItem' or className == 'CTFWeaponLunchBox' then
        return false
    end
    if hardcoded_weapon_ids[wpn:GetPropInt('m_iItemDefinitionIndex')] then
        return false
    end
    if wpn:GetCritChance() <= 0 then
        return false
    end
    if wpn:GetWeaponBaseDamage() <= 0 then
        return false
    end
    return true
end

local fontid = draw.CreateFont('Verdana', 16, 700, FONTFLAG_CUSTOM | FONTFLAG_OUTLINE)
callbacks.Unregister('Draw', 'Draw-F3drQ')
callbacks.Register('Draw', 'Draw-F3drQ', function()
    local me, wpn
    me = entities.GetLocalPlayer()
    if me and me:IsAlive() then
        wpn = me:GetPropEntity('m_hActiveWeapon')
        if not (wpn and wpn:IsWeapon() and CanFireCriticalShot(me, wpn)) then
            return
        end
    else
        return
    end

    local x, y = 600, 800
    draw.SetFont(fontid)

    local weaponinfo = cache_weapon_info[0]

    local sv_allow_crit = wpn:CanRandomCrit()
    if wpn:IsMeleeWeapon() then
        local tf_weapon_criticals_melee = client.GetConVar('tf_weapon_criticals_melee')
        sv_allow_crit = (sv_allow_crit and tf_weapon_criticals_melee == 1) or (tf_weapon_criticals_melee == 2)
    end

    local mult = 0
    local elements = {}
    elements[1] = { 'Crit',
                    (me:IsCritBoosted() or me:InCond(TFCond_CritCola)) and colors.blue or sv_allow_crit and colors.green or
        colors.gray }
    elements[2] = { weaponinfo.shots_left_till_bucket_full .. ' attacks left until full bar', nil,
                    weaponinfo.shots_left_till_bucket_full ~= 0 }
    elements[3] = { weaponinfo.stored_crits .. ' crits available' }
    elements[4] = { 'deal ' .. math.floor(other_weapon_info.requiredDamage) .. ' damage', nil,
                    (other_weapon_info.critChance + 0.1 < other_weapon_info.observedCritChance) }
    elements[5] = { 'streaming crit', colors.red, wpn:GetRapidFireCritTime() > wpn:GetLastRapidFireCritCheckTime() }
    for i = 1, #elements, 1 do
        local text, color, visible = elements[i][1], elements[i][2] or colors.white, elements[i][3]
        draw.Color(color[1], color[2], color[3], color[4])
        if visible ~= false then
            draw.Text(x, y + mult, text)
            mult = mult + 20
        end
    end
end)

callbacks.Unregister('CreateMove', 'CreateMove-N8bat')
callbacks.Register('CreateMove', 'CreateMove-N8bat', function()
    local me, wpn
    me = entities.GetLocalPlayer()
    if me and me:IsAlive() then
        wpn = me:GetPropEntity('m_hActiveWeapon')
        if not (wpn and wpn:IsWeapon() and CanFireCriticalShot(me, wpn)) then
            return
        end
    else
        return
    end

    local weaponinfo, needupdate = cache_weapon_info.get(wpn:GetCritCheckCount())
    if needupdate == nil or wpn:GetIndex() ~= weaponinfo.currentWeapon then
        -- printc(255, 0, 0, 255, 'updating weaponinfo...')
        weaponinfo = setmetatable({}, {
            __index = wpn:GetWeaponData()
         })
        -- LuaFormatter off
        weaponinfo.currentWeapon                  = wpn:GetIndex()   
        weaponinfo.isRapidFire                    = weaponinfo.useRapidFireCrits or wpn:GetClass() == 'CTFMinigun' 
        weaponinfo.currentCritSeed                = wpn:GetCurrentCritSeed()
        weaponinfo.bulletsPerShot                 = wpn:AttributeHookFloat('mult_bullets_per_shot', weaponinfo.bulletsPerShot)
        weaponinfo.added_per_shot                 = wpn:GetWeaponBaseDamage()
        weaponinfo.bucket                         = wpn:GetCritTokenBucket()
        weaponinfo.bucket_max                     = client.GetConVar('tf_weapon_criticals_bucket_cap')
        weaponinfo.bucket_min                     = client.GetConVar('tf_weapon_criticals_bucket_bottom')
        weaponinfo.bucket_start                   = client.GetConVar('tf_weapon_criticals_bucket_default')
        weaponinfo.critRequestCount               = wpn:GetCritSeedRequestCount()
        weaponinfo.critCheckCount                 = wpn:GetCritCheckCount()
        weaponinfo.shots_to_fill_bucket           = weaponinfo.bucket_max / weaponinfo.added_per_shot
        weaponinfo.costs                          = {}
        weaponinfo.stored_crits                   = 0
        weaponinfo.shots_left_till_bucket_full    = 0
        -- LuaFormatter on

        local temp, temp1, temp2
        temp = weaponinfo.bucket_min
        temp1 = weaponinfo.bucket
        temp2 = weaponinfo.bucket

        --- FIXME : random bullshit go
        if wpn:IsMeleeWeapon() then
            local min = wpn:GetCritCost(temp, weaponinfo.critRequestCount, weaponinfo.critCheckCount)
            while temp1 > min do
                weaponinfo.stored_crits = weaponinfo.stored_crits + 1
                min = min +
                          wpn:GetCritCost(min, weaponinfo.critRequestCount + weaponinfo.stored_crits,
                                          weaponinfo.critCheckCount)
                if temp2 < weaponinfo.bucket_max then
                    temp2 = math.min(temp2 + weaponinfo.added_per_shot, weaponinfo.bucket_max)
                    weaponinfo.shots_left_till_bucket_full = weaponinfo.shots_left_till_bucket_full + 1
                end
                local temp3 = min +
                                  wpn:GetCritCost(min, weaponinfo.critRequestCount + weaponinfo.stored_crits + 1,
                                                  weaponinfo.critCheckCount) + weaponinfo.added_per_shot -
                                  weaponinfo.shots_to_fill_bucket
                if temp3 > weaponinfo.bucket_max then
                    break
                end
            end
        else
            for i = 0, weaponinfo.shots_to_fill_bucket + 1, 1 do
                if temp < weaponinfo.bucket_max then
                    temp = math.min(temp + weaponinfo.added_per_shot, weaponinfo.bucket_max)
                    weaponinfo.costs[i] = wpn:GetCritCost(temp, weaponinfo.critRequestCount + i,
                                                          weaponinfo.critCheckCount)
                end
                if temp1 >= weaponinfo.costs[i] then
                    temp1 = temp1 - weaponinfo.costs[i]
                    weaponinfo.stored_crits = weaponinfo.stored_crits + 1
                end
                if temp2 < weaponinfo.bucket_max then
                    temp2 = math.min(temp2 + weaponinfo.added_per_shot, weaponinfo.bucket_max)
                    weaponinfo.shots_left_till_bucket_full = weaponinfo.shots_left_till_bucket_full + 1
                end
            end
        end

        cache_weapon_info.update(weaponinfo)
    end

    -- from bf : weapon state affects the crit rate and for some reason the non revved state doesnt have bIsRapidFire afaik
    -- may cause inaccurate result on custom server / when reload script (due to hardcoded value)
    local critChance = wpn:GetCritChance()
    if weaponinfo.isRapidFire then
        critChance = 0.0102
    end

    -- TODO : figure out why holding mouse 1 with heavy still allow you to crit despite cmpChance + 0.1 < observedCritChance 
    local damageStats = wpn:GetWeaponDamageStats()
    local cmpCritChance = critChance + 0.1
    local requiredTotalDamage = (damageStats['critical'] * (2.0 * cmpCritChance + 1.0)) / cmpCritChance / 3.0
    other_weapon_info.requiredDamage = requiredTotalDamage - damageStats['total']
    other_weapon_info.observedCritChance = wpn:CalcObservedCritChance()
    other_weapon_info.critChance = critChance
    other_weapon_info.damageStats = damageStats
end)

local weapon_name_cache = {}
local function get_weapon_name( any )
    if type( any ) == 'number' then
        return weapon_name_cache[any] or get_weapon_name( itemschema.GetItemDefinitionByID( any ) )
    end

    local meta = getmetatable( any )

    if meta['__name'] == 'Entity' then
        if any:IsWeapon() then
            return get_weapon_name( any:GetPropInt( 'm_iItemDefinitionIndex' ) )
        end
        return 'entity is not a weapon'
    end

    if meta['__name'] == 'ItemDefinition' then
        if weapon_name_cache[any] then
            return weapon_name_cache[any]
        end
        local special = tostring( any ):match( 'TF_WEAPON_[%a%A]*' )
        if special then
            local i1 = client.Localize( special )
            if i1:len() ~= 0 then
                weapon_name_cache[any:GetID()] = i1
                return i1
            end
            weapon_name_cache[any:GetID()] = client.Localize( any:GetTypeName():gsub( '_Type', '' ) )
            return weapon_name_cache[any:GetID()]
        end
        for attrDef, value in pairs( any:GetAttributes() ) do
            local name = attrDef:GetName()
            if name == 'paintkit_proto_def_index' or name == 'limited quantity item' then
                weapon_name_cache[any:GetID()] = client.Localize( any:GetTypeName():gsub( '_Type', '' ) )
                return weapon_name_cache[any:GetID()]
            end
        end
        weapon_name_cache[any:GetID()] = tostring( any:GetNameTranslated() )
        return weapon_name_cache[any:GetID()]
    end
end

local function is_rapid_fire_weapon( wpn )
    -- todo: Ask bf to add GetWeaponData.m_bUseRapidFireCrits
    return wpn:GetLastRapidFireCritCheckTime() > 0 or wpn:GetClass() == 'CTFMinigun'
end

local function get_crit_cap( wpn )
    local me_crit_multiplier = entities.GetLocalPlayer():GetCritMult()
    local chance = 0.02

    if wpn:IsMeleeWeapon() then
        chance = 0.15
    end
    local multiplier_crit_chance = wpn:AttributeHookFloat( "mult_crit_chance", me_crit_multiplier * chance )

    if is_rapid_fire_weapon( wpn ) then
        local total_crit_chance = math.max( math.min( 0.02 * me_crit_multiplier, 0.01 ), 0.99 )
        local crit_duration = 2.0
        local non_crit_duration = (crit_duration / total_crit_chance) - crit_duration
        local start_crit_chance = 1 / non_crit_duration
        multiplier_crit_chance = wpn:AttributeHookFloat( "mult_crit_chance", start_crit_chance )
    end

    return multiplier_crit_chance
end

--- 

local indicator = draw.CreateFont( 'Verdana', 16, 700, FONTFLAG_CUSTOM | FONTFLAG_OUTLINE )
-- draw.CreateFont( 'Verdana', 24, 700, FONTFLAG_CUSTOM | FONTFLAG_ANTIALIAS )

callbacks.Register( "Draw", function()
    local width, height = draw.GetScreenSize()
    local width_center, height_center = width // 2, height // 2
    draw.SetFont( indicator )
    draw.Color( 0, 0, 0, 255 )
    local me = entities.GetLocalPlayer()

    if not me then
        return
    end

    local wpn = me:GetPropEntity( 'm_hActiveWeapon' )

    if not wpn or not me:IsAlive() then
        return
    end

    local name = get_weapon_name( wpn )

    local rapidfire_history, rapidfire_check_time = wpn:GetRapidFireCritTime(), wpn:GetLastRapidFireCritCheckTime()

    local bucket_current, bucket_cap, bucket_bottom, bucket_start = wpn:GetCritTokenBucket(), client.GetConVar(
        'tf_weapon_criticals_bucket_cap' ), client.GetConVar( 'tf_weapon_criticals_bucket_bottom' ), client.GetConVar(
        'tf_weapon_criticals_bucket_default' )

    local crit_check, crit_request = wpn:GetCritCheckCount(), wpn:GetCritSeedRequestCount()
    local observed_crit_chance = wpn:CalcObservedCritChance()
    local wpn_critchance = wpn:GetCritChance()
    local wpn_seed = wpn:GetCurrentCritSeed()
    local wpn_can_crit = wpn:CanRandomCrit()
    local damage_base = wpn:GetWeaponBaseDamage()
    local stats = wpn:GetWeaponDamageStats()
    local cost = wpn:GetCritCost( bucket_current, crit_request, crit_check )

    local server_allow_crit = false
    local can_criticals_melee = client.GetConVar( 'tf_weapon_criticals_melee' )
    local can_weapon_criticals = client.GetConVar( 'tf_weapon_criticals' )

    if wpn:IsMeleeWeapon() then
        if can_criticals_melee == 2 or (can_weapon_criticals == 1 and can_criticals_melee == 1) then
            server_allow_crit = true
        end
    elseif wpn:IsShootingWeapon() then
        if can_weapon_criticals == 1 then
            server_allow_crit = true
        end
    end

    ---- 
    local startpos, txt_x, txt_y = 130, draw.GetTextSize( name )
    draw.FilledRect( startpos, startpos, startpos + txt_x, startpos + txt_y )
    draw.Color( 255, 255, 255, 255 )
    draw.TextShadow( startpos, startpos, name )
    local wpndebug = {
        variable = { 'server_allow_crit', 'rapidfire_history', 'rapidfire_check_time', 'bucket_current', 'bucket_cap',
                     'bucket_bottom', 'bucket_start', 'cost', 'crit_check', 'crit_request', 'observed_crit_chance',
                     'wpn_critchance', 'wpn_seed', 'damage_base', 'total', 'critical', 'melee' },
        value = { server_allow_crit, rapidfire_history, rapidfire_check_time, bucket_current, bucket_cap, bucket_bottom,
                  bucket_start, cost, crit_check, crit_request, observed_crit_chance, wpn_critchance, wpn_seed,
                  damage_base, stats.total, stats.critical, stats.melee }
     }

    local i, j, space = 0, 0, 0
    for _, name in ipairs( wpndebug.variable ) do
        local width, height = draw.GetTextSize( name )
        if width + startpos > space - 100 then
            space = width + startpos + 100
        end
        draw.Text( startpos, startpos + math.floor( height * i ) + txt_y * 2, name )
        i = i + 1.3
    end
    draw.Color( 36, 255, 122, 255 )
    for _, value in ipairs( wpndebug.value ) do
        if type( value ) == 'number' and math.floor( value ) ~= value then
            value = string.format( "%.6s", value )
        end
        local width, height = draw.GetTextSize( tostring( value ) )
        draw.Text( space - (width // 2), startpos + math.floor( height * j ) + txt_y * 2, tostring( value ) )
        j = j + 1.3
    end

    --- 
    draw.Color( 255, 255, 255, 255 )
    local data, text = {}
    local cmpCritChance = wpn_critchance + 0.1

    if not server_allow_crit then
        data[#data + 1] = 'server disabled crit'
    end

    if not wpn:CanRandomCrit() then
        data[#data + 1] = 'no random crit'
    end

    for i = 1, bucket_cap // damage_base do
        print( string.format('cost: %s, request: %d', wpn:GetCritCost( bucket_start, 1, i ), i) )
    end

    if cmpCritChance < wpn:CalcObservedCritChance() then
        local requiredTotalDamage = (stats.critical * (2.0 * cmpCritChance + 1.0)) / cmpCritChance / 3.0
        local requiredDamage = requiredTotalDamage - stats.total
        data[#data + 1] = 'deal ' .. math.floor( requiredDamage ) .. ' damage'
    end

    if bucket_current < math.floor( cost ) then
        data[#data + 1] = 'low bucket'
    end

    if bucket_current == bucket_cap then
        data[#data + 1] = 'bucket reached cap'
    end

    if is_rapid_fire_weapon( wpn ) then
        data[#data + 1] = 'rapidfire-able'
    end

    if rapidfire_history - globals.CurTime() > 0 then
        data[#data + 1] = 'rapid firing: ' .. string.format( "%.4s", rapidfire_history - globals.CurTime() )
    end

    text = table.concat( data, ', ' )
    txt_x, txt_y = draw.GetTextSize( text )
    draw.Text( width_center - math.floor( txt_x / 2 ), math.floor( height_center * 1.05 ), text )

end )

-- mult_dmg : damage bonus / penalty (modifier)

local ammoboxMaterial = materials.Find( "models/items/ammo_box2" )

local function onDrawModel( drawModelContext )
    local entity = drawModelContext:GetEntity()

    if entity:GetClass() == "CTFPlayer" then
        drawModelContext:ForcedMaterialOverride( ammoboxMaterial )
    end
end

callbacks.Register("DrawModel", "hook123", onDrawModel) 

callbacks.Register( "Draw", function ()
    local player = entities.GetLocalPlayer()
    local hitboxes = player:GetHitboxes()

    for i = 1, #hitboxes do
        local hitbox = hitboxes[i]
        local min = hitbox[1]
        local max = hitbox[2]

        -- to screen space
        min = client.WorldToScreen( min )
        max = client.WorldToScreen( max )

        if (min ~= nil and max ~= nil) then
            -- draw hitbox
            draw.Color(255, 255, 255, 255)
            draw.Line( min[1], min[2], max[1], min[2] )
            draw.Line( max[1], min[2], max[1], max[2] )
            draw.Line( max[1], max[2], min[1], max[2] )
            draw.Line( min[1], max[2], min[1], min[2] )
        end
    end
end )

local isTaunting = me:InCond( TFCond_Taunting )

local rageMeter = me:GetPropFloat( "m_flRageMeter" )

local me = entities.GetLocalPlayer()
local viewAngles = me:GetPropVector("tfnonlocaldata", "m_angEyeAngles[0]")

local myAngles = EulerAngles( 30, 60, 0 )
local pitch, yaw, roll = myAngles:Unpack()

local lobby = gamecoordinator.GetGameServerLobby()

if lobby then
    for _, player in pairs( lobby:GetMembers() ) do
        print( player:GetSteamID() )
    end
end

local nameAttr = itemschema.GetAttributeDefinitionByName( "custom name attr" )

local firstItem = inventory.GetItemByPosition( 1 )

firstItem:SetAttribute( "attach particle effect", 33 ) -- Set the unusual effect to rotating flames
firstItem:SetAttribute( nameAttr, "Dumb dumb item" ) -- Set the custom name to "Dumb dumb item"

local item = inventory.GetItemByPosition( 1 )

for def, v in pairs( item:GetAttributes() ) do
    print( def:GetName() .. " : " .. tostring( v ) )
end

callbacks.Register( "OnLobbyUpdated", "mylobby", function( lobby )
    for _, player in pairs( lobby:GetMembers() ) do
        print( player:GetSteamID(), player:GetTeam() )
    end
end )

kv = [["VertexLitGeneric"
{
    "$basetexture"  "vgui/white_additive"
    "$ignorez" "1"
}
]]

myMaterial = materials.Create( "myMaterial", kv )
myMaterial:SetMaterialVarFlag( MATERIAL_VAR_IGNOREZ, false )

local netChannel = clientstate.GetNetChannel()

if netChannel then
    local outSequenceNr, inSequenceNr, outSequenceNrAck = netChannel:GetSequenceData()
    netChannel:SetSequenceData(outSequenceNr + 1, inSequenceNr, outSequenceNrAck)
end

local ammoboxMaterial = materials.Find( "models/items/ammo_box2" )

local function onStaticProps( info )

    info:StudioSetColorModulation( 0.5, 0, 0 )
    info:StudioSetAlphaModulation( 0.7 )
    info:ForcedMaterialOverride( ammoboxMaterial )

end

callbacks.Register("DrawStaticProps", "hook123", onStaticProps) 

local function onStringCmd( stringCmd )

    if stringCmd:Get() == "status" then
        stringCmd:Set( "echo No status for you!" )
    end
end

callbacks.Register( "SendStringCmd", "hook", onStringCmd )

local me = entities.GetLocalPlayer();
local source = me:GetAbsOrigin() + me:GetPropVector( "localdata", "m_vecViewOffset[0]" );
local destination = source + engine.GetViewAngles():Forward() * 1000;

local trace = engine.TraceLine( source, destination, MASK_SHOT_HULL );

if (trace.entity ~= nil) then
    print( "I am looking at " .. trace.entity:GetClass() );
    print( "Distance to entity: " .. trace.fraction * 1000 );
end

local function doBunnyHop( cmd )
    local player = entities.GetLocalPlayer( );

    if (player ~= nil or not player:IsAlive()) then
    end

    if input.IsButtonDown( KEY_SPACE ) then

        local flags = player:GetPropInt( "m_fFlags" );

        if flags & FL_ONGROUND == 1 then
            cmd:SetButtons(cmd.buttons | IN_JUMP)
        else 
            cmd:SetButtons(cmd.buttons & (~IN_JUMP))
        end
    end
end

callbacks.Register("CreateMove", "myBhop", doBunnyHop)

local function myCoolMessageHook(msg)

    if msg:GetID() == SayText2 then 
        local bf = msg:GetBitBuffer()

        bf:SetCurBit(8)-- skip 1 byte of not useful data

        local chatType = bf:ReadString(256)
        local playerName = bf:ReadString(256)
        local message = bf:ReadString(256)

        print("Player " .. playerName .. " said " .. message)
    end

end

callbacks.Register("DispatchUserMessage", myCoolMessageHook)

local view = client.GetViewSetup()
print( "View origin: " .. view.origin )

if client.ChatPrintf( "\x06[\x07FF1122LmaoBox\x06] \x04You died!" ) then
    print( "Chat message sent" )
end

local me = entities.GetLocalPlayer()
local name = entities.GetPlayerNameByIndex(me:GetIndex())
print( name )

local me = entities.GetLocalPlayer()
local playerInfo = entities.GetPlayerInfo(me:GetIndex())
local steamID = playerInfo.SteamID
print( steamID )

local netChannel = clientstate.GetNetChannel()

if netChannel then
    print(netChannel:GetAddress())
end

local lmaoboxTexture = draw.CreateTexture( "lmaobox.png" ) -- in %localappdata% folder

callbacks.Register("Draw", function()
    local w, h = draw.GetScreenSize()
    local tw, th = draw.GetTextureSize( lmaoboxTexture )

    draw.TexturedRect( lmaoboxTexture, w/2 - tw/2, h/2 - th/2, w/2 + tw/2, h/2 + th/2 )
end)

local lmaoboxTexture = draw.CreateTexture( "lmaobox.png" ) -- in %localappdata% folder

callbacks.Register("Draw", function()
    local w, h = draw.GetScreenSize()
    local tw, th = draw.GetTextureSize( lmaoboxTexture )

    draw. TexturedPolygon( lmaoboxTexture, {
        { w/2 - tw/2, h/2 - th/2, 0.0, 0.0 },
        { w/2 + tw/2, h/2 - th/2, 1.0, 0.1 },
        { w/2 + tw/2, h/2 + th/2, 1.0, 1.0 },
        { w/2 - tw/2, h/2 + th/2, 0.0, 1.0 },
    }, true )
end)

draw.AddFontResource("Choktoff.ttf") -- In Team Fortress 2 folder
local myfont = draw.CreateFont("Choktoff", 15, 800, FONTFLAG_CUSTOM | FONTFLAG_ANTIALIAS)

local function doDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end

    draw.Color(255, 255, 255, 255)
    draw.Line(100, 100, 100, 200)
    draw.Line(100, 200, 200, 200)
    draw.Line(200, 200, 200, 100)
    draw.Line(200, 100, 100, 100)
end

callbacks.Register("Draw", "mydraw", doDraw)

local kv = [[
    "use_action_slot_item_server"
    {
    }
]]

engine.SendKeyValues( kv )

local name = me:GetName()
print( name )

local players = entities.FindByClass("CTFPlayer")

for i, player in ipairs(players) do
    print( player:GetName() )
end

for i = 1, entities.GetHighestEntityIndex() do -- index 1 is world entity
    local entity = entities.GetByIndex( i )
    if entity then
        print( i, entity:GetClass() )
    end
end

success, fullPath = filesystem.CreateDirectory( [[myContent]] )

filesystem.EnumerateDirectory( [[tf/*]] , function( filename, attributes )
    print( filename, attributes )
   end )

   gamecoordinator.EnumerateQueueMapsHealth( function( map, health )

    if map:GetName() == "cp_dustbowl" then
        party.SetCasualMapSelected( map, true )
    end

    if party.IsCasualMapSelected( map ) then
        print( "Selected: " .. map:GetName() .. ": " .. tostring(health) )
    end

end )

local function onCreateMove( cmd )
    if gamerules.IsTruceActive() then
        cmd.buttons = cmd.buttons & ~IN_ATTACK
    end
end

callbacks.Register("CreateMove", onCreateMove)

local consolas = draw.CreateFont("Consolas", 17, 500)
local current_fps = 0

local function watermark()
  draw.SetFont(consolas)
  draw.Color(255, 255, 255, 255)

  -- update fps every 100 frames
  if globals.FrameCount() % 100 == 0 then
    current_fps = math.floor(1 / globals.FrameTime())
  end

  draw.Text(5, 5, "[lmaobox | fps: " .. current_fps .. "]")
end

callbacks.Register("Draw", "draw", watermark)
-- https://github.com/x6h

gui.SetValue("aim bot", 1);
gui.SetValue("aim method", "silent");

local aim_method = gui.GetValue("aim method");
print( aim_method ) -- prints 'silent'

local aim_fov = gui.GetValue("aim fov");
print( aim_fov )

gui.SetValue("blue team color", 0xcaffffff)

local activeWeapon = entities.GetLocalPlayer():GetPropEntity("m_hActiveWeapon")
local wpnId = activeWeapon:GetPropInt("m_iItemDefinitionIndex")
if wpnId ~= nil then
    local wpnName = itemschema.GetItemDefinitionByID(wpnId):GetName()
    draw.TextShadow(screenPos[1], screenPos[2], wpnName)
end

local function forEveryItem( itemDefinition )
    if itemDefinition:IsWearable() then
        print( "Found: " .. itemDefinition:GetName() )
    end
end

itemschema.Enumerate( forEveryItem )

callbacks.Register( "Draw", function ()

    local me = entities.GetLocalPlayer()
  
    local model = me:GetModel()
    local studioHdr = models.GetStudioModel(model)
  
    local myHitBoxSet = me:GetPropInt("m_nHitboxSet")
    local hitboxSet = studioHdr:GetHitboxSet(myHitBoxSet)
    local hitboxes = hitboxSet:GetHitboxes()
  
   --boneMatrices is an array of 3x4 float matrices
    local boneMatrices = me:SetupBones()
  
    for i = 1, #hitboxes do
      local hitbox = hitboxes[i]
      local bone = hitbox:GetBone()
  
      local boneMatrix = boneMatrices[bone]
  
      if boneMatrix == nil then
        goto continue
      end
  
      local bonePos = Vector3( boneMatrix[1][4], boneMatrix[2][4], boneMatrix[3][4] )
  
      local screenPos = client.WorldToScreen(bonePos)
  
      if screenPos == nil then
        goto continue
      end
  
      draw.Text( screenPos[1], screenPos[2], i )
  
      ::continue::
    end
  
  end)

  local casual = party.GetAllMatchGroups()["Casual"]

local reasons = party.CanQueueForMatchGroup( casual )

if reasons == true then
    party.QueueUp( casual )
else
    for k,v in pairs( reasons ) do
        print( v )
    end
end

local members = party.GetMembers()

for k, v in pairs( members ) do
    if v ~= party.GetLeader() then
        print( v )
    end
end

if #party.GetQueuedMatchGroups() > 0 then
    print( "I'm in queue!" )
end

-- Run only once
local grenadeModel = [[models/weapons/w_models/w_grenade_grenadelauncher.mdl]]
local env = physics.CreateEnvironment( )
env:SetGravity( Vector3( 0, 0, -800 ) )
env:SetAirDensity( 2.0 )
env:SetSimulationTimestep( globals.TickInterval() )
local solid, collisionModel = physics.ParseModelByName( grenadeModel )
local simulatedProjectile = nil

callbacks.Register( "Draw", function ()

  local me = entities.GetLocalPlayer()

  if simulatedProjectile == nil then 
    simulatedProjectile = env:CreatePolyObject(collisionModel, solid:GetSurfacePropName(), solid:GetObjectParameters())
    simulatedProjectile:Wake()
  end

  local startPos = me:GetAbsOrigin() + me:GetPropVector( "m_vecViewOffset[0]" )
  local startAngles = me:GetPropVector(  "m_angEyeAngles" )
  simulatedProjectile:SetPosition(startPos, startAngles, true)

  local velocity = Vector3(1000,600,200)
  local angularVelocity = Vector3(600,0,0) --Spin!

  simulatedProjectile:SetVelocity(velocity, angularVelocity)

  local tickInteval = globals.TickInterval()
  local simulationEnd = env:GetSimulationTime() + 2.0

  while env:GetSimulationTime() < simulationEnd do

    -- Where is it now?
    local currentPos, currentAngle = simulatedProjectile:GetPosition()

    -- draw line from startPos to currentPos
    local screenCurrentPos = client.WorldToScreen(currentPos)
    local screenStartPos = client.WorldToScreen(startPos)

    if screenCurrentPos ~= nil and screenStartPos ~= nil then
      draw.Color(255, 0, 255, 255)
      draw.Line(screenStartPos[1], screenStartPos[2], screenCurrentPos[1], screenCurrentPos[2])
    end

    startPos = currentPos

    -- Run the simulation
    env:Simulate(tickInteval)
  end

  env:ResetSimulationClock()

end)

callbacks.Register("Unload", function()
  -- Clean up afterwards
  if simulatedProjectile ~= nil then
    env:DestroyObject(simulatedProjectile)
  end

  physics.DestroyEnvironment( env )
end)

local color = playerlist.GetColor("STEAM_0:0:123456789");

local priority = 1;

playerlist.SetPriority("STEAM_0:0:123456789", priority);

local camW = 400
local camH = 300
local cameraTexture = materials.CreateTextureRenderTarget( "cameraTexture123", camW, camH )
local cameraMaterial = materials.Create( "cameraMaterial123", [[
    UnlitGeneric
    {
        $basetexture    "cameraTexture123"
    }
]] )

callbacks.Register("PostRenderView", function(view)
    customView = view
    customView.angles = EulerAngles(customView.angles.x, customView.angles.y + 180, customView.angles.z)

    render.Push3DView( customView, E_ClearFlags.VIEW_CLEAR_COLOR | E_ClearFlags.VIEW_CLEAR_DEPTH, cameraTexture )
    render.ViewDrawScene( true, true, customView )
    render.PopView()
    render.DrawScreenSpaceRectangle( cameraMaterial, 300, 300, camW, camH, 0, 0, camW, camH, camW, camH )
end)
