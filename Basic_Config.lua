local Menu = { -- this is the config that will be loaded every time u load the script

    tabs = { -- thsoe are tabs for your menu if needed
        Main = true,
        Aimbot = false,
        Misc = false,
        Visuals = false,
    },

    Main = {
        Active = true,  --disable lua
        Insta_Hit = true,
        Keybind = "B",
        keybind_Idx = KEY_B,
        Is_Listening_For_Key = false,
    },

    Aimbot = {
        Aimbot = true,
        AimbotFOV = 360,
        MaxDistance = 1000,
        Silent = true,
        AutoAttack = true,
        Smooth = false, --unrecomended
        smoothness = 0.1, --how quickly it will move to the target
    },

    Misc = {
        Auto_CritRefill = true,
        ChargeReach = false,
        TroldierAssist = false,
        ChargeControl = false,
        ChargeSensitivity = 50,
    },

    Visuals = {
        EnableVisuals = false,
        VisualizeHitbox = false,
        Visualize_Attack_Range = false,
        Visualize_Attack_Point = false,
        Visualize_Pred_Local = false,
        Visualize_Pred_Enemy = false,
    },
}

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")

local function CreateCFG(folder_name, table)
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    local filepath = tostring(fullPath .. "/config.cfg")
    local file = io.open(filepath, "w")
    
    if file then
        local function serializeTable(tbl, level)
            level = level or 0
            local result = string.rep("    ", level) .. "{\n"
            for key, value in pairs(tbl) do
                result = result .. string.rep("    ", level + 1)
                if type(key) == "string" then
                    result = result .. '["' .. key .. '"] = '
                else
                    result = result .. "[" .. key .. "] = "
                end
                if type(value) == "table" then
                    result = result .. serializeTable(value, level + 1) .. ",\n"
                elseif type(value) == "string" then
                    result = result .. '"' .. value .. '",\n'
                else
                    result = result .. tostring(value) .. ",\n"
                end
            end
            result = result .. string.rep("    ", level) .. "}"
            return result
        end
        
        local serializedConfig = serializeTable(table)
        file:write(serializedConfig)
        file:close()
        printc( 255, 183, 0, 255, "["..os.date("%H:%M:%S").."] Saved Config to ".. tostring(fullPath))
    end
end

local function LoadCFG(folder_name)
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    local filepath = tostring(fullPath .. "/config.cfg")
    local file = io.open(filepath, "r")

    if file then
        local content = file:read("*a")
        file:close()
        local chunk, err = load("return " .. content)
        if chunk then
            printc( 0, 255, 140, 255, "["..os.date("%H:%M:%S").."] Loaded Config from ".. tostring(fullPath))
            return chunk()
        else
            CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
            print("Error loading configuration:", err)
        end
    end
end

local status, loadedMenu = pcall(function() return assert(LoadCFG(string.format([[Lua %s]], Lua__fileName))) end) --auto load config

if status then --ensure config is not causing errors
    local allFunctionsExist = true
    for k, v in pairs(Menu) do
        if type(v) == 'function' then
            if not loadedMenu[k] or type(loadedMenu[k]) ~= 'function' then
                allFunctionsExist = false
                break
            end
        end
    end

    if allFunctionsExist then
        Menu = loadedMenu
    else
        CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
    end
end

--[[ Remove the menu when unloaded ]]--
local function OnUnload()                                -- Called when the script is unloaded
    CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
    UnloadLib() --unloading lualib
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

callbacks.Unregister("Unload", "Config_Unload")                    -- Unregister the "Unload" callback

callbacks.Register("Unload", "ConfigUnload", OnUnload)                         -- Register the "Unload" callback