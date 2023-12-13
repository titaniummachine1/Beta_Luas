local function OnCreateMove()
    local pLocal = entities.GetLocalPlayer()
    gui.SetValue("trigger shoot delay (MS)", math.random(150, 350))
end
-- Unregister previous callbacks
callbacks.Unregister("CreateMove", "legit_CreateMove") -- Unregister the "CreateMove" callback
-- Register callbacks
callbacks.Register("CreateMove", "legit_CreateMove", OnCreateMove) -- Register the "CreateMove" callback