--[[
    SlowWalk.lua for lmaobox
    Author: github.com/titaniummachine1
]]

local menuLoaded, MenuLib = pcall(require, "Menu")                               -- Load MenuLib
assert(menuLoaded, "MenuLib not found, please install it!")                      -- If not found, throw error
assert(MenuLib.Version >= 1.44, "MenuLib version is too old, please update it!") -- If version is too old, throw error

--[[ Menu ]]
local menu         = MenuLib.Create("SlowWalk", MenuFlags.AutoSize)
menu.Style.TitleBg = { 125, 155, 255, 255 }
menu.Style.Outline = true

menu:AddComponent(MenuLib.Label("                   [ Misc ]", ItemFlags.FullWidth))
local mslowwalk = menu:AddComponent(MenuLib.Slider("Walk Speed", 1, 200, 1))
local mSKey = menu:AddComponent(MenuLib.Keybind("Key", KEY_LSHIFT, ItemFlags.FullWidth))
local mShowCoords = menu:AddComponent(MenuLib.Checkbox("Show Coordinates", true))

menu:AddComponent(MenuLib.Label("                [ View Angle ]", ItemFlags.FullWidth))
local mForceAngles = menu:AddComponent(MenuLib.Checkbox("Force Angles", false))
local mPitch = menu:AddComponent(MenuLib.Slider("Pitch", -90, 90, 0))
local mYaw = menu:AddComponent(MenuLib.Slider("Yaw", -180, 180, 0))
local mAngleKey = menu:AddComponent(MenuLib.Keybind("Angles Key", KEY_LALT, ItemFlags.FullWidth))

-- OnTickUpdate
local function OnCreateMove(userCmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal then return end
    if not pLocal:IsAlive() then return end

    if mslowwalk:GetValue() ~= 100 and input.IsButtonDown(mSKey:GetValue()) then
        local slowwalk = mslowwalk:GetValue() * 0.01
        userCmd:SetForwardMove(userCmd:GetForwardMove() * slowwalk)
        userCmd:SetSideMove(userCmd:GetSideMove() * slowwalk)
        userCmd:SetUpMove(userCmd:GetUpMove() * slowwalk)
    end

    -- Force view angles if enabled and key is pressed
    if mForceAngles:GetValue() and input.IsButtonDown(mAngleKey:GetValue()) then
        local viewAngles = EulerAngles(-mPitch:GetValue(), mYaw:GetValue(), 0)
        engine.SetViewAngles(viewAngles)
    end
end

-- Create a font for displaying coordinates
local coordFont = draw.CreateFont("Verdana", 14, 800)

-- Function to draw coordinates on screen
local function OnDraw()
    if not mShowCoords:GetValue() then return end

    -- Check if in menus
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end

    local pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then return end

    -- Get player position
    local pos = pLocal:GetAbsOrigin()

    -- Format coordinates
    local coordText = string.format("X: %.2f  Y: %.2f  Z: %.2f", pos.x, pos.y, pos.z)

    -- Draw coordinates
    draw.SetFont(coordFont)
    draw.Color(255, 255, 255, 255)
    draw.Text(10, 100, coordText)

    -- Draw current view angles if force angles is enabled
    if mForceAngles:GetValue() and input.IsButtonDown(mAngleKey:GetValue()) then
        local viewAngles = engine.GetViewAngles()
        local angleText = string.format("Pitch: %.2f  Yaw: %.2f", viewAngles.pitch, viewAngles.yaw)
        draw.Text(10, 30, angleText)
    end
end

--[[ Remove the menu when unloaded ]]
local function OnUnload()                                -- Called when the script is unloaded
    MenuLib.RemoveMenu(menu)                             -- Remove the menu
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
callbacks.Unregister("CreateMove", "SlowWalk.CreateMove")
callbacks.Unregister("Unload", "SlowWalk_Unload")    -- Unregister the "Unload" callback
callbacks.Unregister("Draw", "SlowWalk.Draw")        -- Unregister the "Draw" callback

callbacks.Register("CreateMove", "SlowWalk.CreateMove", OnCreateMove)
callbacks.Register("Unload", "SlowWalk_Unload", OnUnload) -- Register the "Unload" callback
callbacks.Register("Draw", "SlowWalk.Draw", OnDraw)       -- Register the "Draw" callback
