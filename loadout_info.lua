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