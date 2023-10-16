--[[
    viewmodel override fix and upgrade
    Author: LNX (github.com/DemonLoverHvH)
    fixed by: terminator (github.com/titaniummachine1)
]]
---@type boolean, ImMenu
local menuLoaded, ImMenu = pcall(require, "ImMenu")
assert(menuLoaded, "ImMenu not found, please install it!")

local tahoma_bold = draw.CreateFont("Tahoma", 12, 800, FONTFLAG_OUTLINE)


local options = {
    enable = true,
    Viewmodel_x = 0,
    Viewmodel_y = 0,
    Viewmodel_z = 0
}

--remove cvar protection
client.RemoveConVarProtection("tf_viewmodels_offset_override")
client.RemoveConVarProtection("cl_wpn_sway_interp")
client.RemoveConVarProtection("cl_wpn_sway_scale")

--menu backend
local function CreateMove(pCmd)
    if options.enable == true then

        local x, y, z = options.Viewmodel_x, options.Viewmodel_y, options.Viewmodel_z  -- Replace these with your actual values
        local convarValue = string.format("%d %d %d", x, y, z)
        client.SetConVar("tf_viewmodels_offset_override", convarValue)

        -- local sway = WpnSwayScale:GetValue() -- couldn't get it to work :/ if you do please make pull request
        client.SetConVar("cl_wpn_sway_scale", 7) -- change numbers to switch sway ammount i just like it like this
        client.SetConVar("cl_wpn_sway_interp", 5)

    end
end

local lastToggleTime = 0
local Lbox_Menu_Open = true
local function toggleMenu()
    local currentTime = globals.RealTime()
    if currentTime - lastToggleTime >= 0.1 then
        if Lbox_Menu_Open == false then
            Lbox_Menu_Open = true
        elseif Lbox_Menu_Open == true then
            Lbox_Menu_Open = false
        end
        lastToggleTime = currentTime
    end
end

local function doDraw()
    draw.Color(255, 255, 255, 255)
    if input.IsButtonPressed( KEY_INSERT )then
        toggleMenu()
    end
        if engine.IsGameUIVisible() and ImMenu.Begin("Viewmodel Override", true)
        or Lbox_Menu_Open and ImMenu.Begin("Viewmodel Override", true) then
            ImMenu.BeginFrame(1)
            options.enable = ImMenu.Checkbox("Enable", options.enable)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            options.Viewmodel_x = ImMenu.Slider("Viewmodel X", options.Viewmodel_x, 1, 180)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            options.Viewmodel_y = ImMenu.Slider("Viewmodel Y", options.Viewmodel_y, 1, 180)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            options.Viewmodel_z = ImMenu.Slider("Viewmodel Z", options.Viewmodel_z, 1, 180)
            ImMenu.EndFrame()

           
        end
      
end

local function Unload()
    MenuLib.RemoveMenu(menu)

    client.Command('play "ui/buttonclickrelease"', true)
end


callbacks.Unregister("CreateMove", "MT_CreateMove") 
callbacks.Register("CreateMove", "MT_CreateMove", CreateMove)

callbacks.Unregister("Unload", "MT_Unload") 
callbacks.Register("Unload", "MT_Unload", Unload)

callbacks.Unregister("Draw", "MCT_Draw")                                   -- unregister the "Draw" callback
callbacks.Register("Draw", "MCT_Draw", doDraw)                              -- Register the "Draw" callback 


client.Command('play "ui/buttonclick"', true)