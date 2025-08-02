--[[
    Class Priority System for Lmaobox
    Uses TimMenu to manage player priorities based on their class
]]

local TimMenu = require("TimMenu")

-- TF2 Class definitions (in the same order as Team Fortress 2 shows them)
local TF2_CLASSES = {
    "Scout",
    "Soldier",
    "Pyro",
    "Demoman",
    "Heavy",
    "Engineer",
    "Medic",
    "Sniper",
    "Spy"
}

-- Class priority settings (0-10 scale)
local classPriorities = {
    Scout = 0,
    Soldier = 0,
    Pyro = 0,
    Demoman = 0,
    Heavy = 0,
    Engineer = 0,
    Medic = 0,
    Sniper = 0,
    Spy = 0
}

-- TF2 Class constants (correct internal game values)
local E_Character = {
    TF2_Scout = 1,
    TF2_Soldier = 3,
    TF2_Pyro = 7,
    TF2_Demoman = 4,
    TF2_Heavy = 6,
    TF2_Engineer = 9,
    TF2_Medic = 5,
    TF2_Sniper = 2,
    TF2_Spy = 8,
}

-- Map internal class indices to class names
local CLASS_INDEX_TO_NAME = {
    [E_Character.TF2_Scout] = "Scout",
    [E_Character.TF2_Soldier] = "Soldier",
    [E_Character.TF2_Pyro] = "Pyro",
    [E_Character.TF2_Demoman] = "Demoman",
    [E_Character.TF2_Heavy] = "Heavy",
    [E_Character.TF2_Engineer] = "Engineer",
    [E_Character.TF2_Medic] = "Medic",
    [E_Character.TF2_Sniper] = "Sniper",
    [E_Character.TF2_Spy] = "Spy",
}

-- Function to get player class
local function GetPlayerClass(player)
    if not player or not player:IsValid() then
        return nil
    end

    -- Get player class using the correct internal class index
    local classIndex = player:GetPropInt("m_iClass")

    -- If classIndex is 0, the player might not have selected a class yet
    if classIndex == 0 then
        return nil
    end

    -- Use the correct class mapping
    return CLASS_INDEX_TO_NAME[classIndex]
end

-- Function to set player priority based on their class
local function SetPlayerPriorityByClass(player)
    if not player or not player:IsValid() then
        return false
    end

    local playerClass = GetPlayerClass(player)
    if not playerClass or not classPriorities[playerClass] then
        return false
    end

    -- Only set priority if it's different from current value
    local currentPriority = playerlist.GetPriority(player)
    local targetPriority = classPriorities[playerClass]

    if currentPriority ~= targetPriority then
        playerlist.SetPriority(player, targetPriority)
        return true -- Indicate that we made a change
    end

    return false -- No change made
end

-- Function to update all player priorities
local function UpdateAllPlayerPriorities()
    local players = entities.FindByClass("CTFPlayer")
    if not players then
        return
    end

    for _, player in pairs(players) do
        if player:IsValid() and player:IsAlive() then
            SetPlayerPriorityByClass(player)
        end
    end
end



-- TimMenu draw function
local function OnDraw()
    -- Only show menu when Lmaobox menu is open
    if not gui.IsMenuOpen() then
        return
    end

    if TimMenu.Begin("Class Priority Settings") then
        -- Compact header with tooltip
        TimMenu.Text("Class Priorities (0-10)")
        TimMenu.Tooltip("Set priority for each class. Higher numbers = higher priority. 0 = ignore class.")

        TimMenu.Separator()

        -- Create sliders for each class in a proper vertical layout
        for i, className in ipairs(TF2_CLASSES) do
            -- Slider already includes class name, no need for separate text
            classPriorities[className] = TimMenu.Slider(className, classPriorities[className], 0, 10, 1)

            -- Force next line after each class
            TimMenu.NextLine()

            -- Add spacing between classes
            TimMenu.Spacing(5)
        end

        TimMenu.Separator()

        -- Compact reset button with tooltip
        if TimMenu.Button("Reset All") then
            for _, className in ipairs(TF2_CLASSES) do
                classPriorities[className] = 0
            end
        end
        TimMenu.Tooltip("Reset all class priorities to 0")
    end
end

-- Register the draw callback
callbacks.Register("Draw", "ClassPriorityDraw", OnDraw)

-- Register a callback to update priorities every tick
callbacks.Register("CreateMove", "ClassPriorityUpdate", function()
    UpdateAllPlayerPriorities()
end)

-- Unload function
local function Unload()
    callbacks.Unregister("Draw", "ClassPriorityDraw")
    callbacks.Unregister("CreateMove", "ClassPriorityUpdate")
end

callbacks.Register("Unload", "ClassPriorityUnload", Unload)

printc(150, 255, 150, 255, "[CLASS PRIORITY] Class priority system loaded")
