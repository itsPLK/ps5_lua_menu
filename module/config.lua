
function get_config()
    local config_path = "/data/ps5_lua_loader/menu_config.txt"
    local config_table = {}
    
    local config_file = io.open(config_path, "r")
    
    if config_file then
        for line in config_file:lines() do
            -- Skip empty lines and comments
            if line ~= "" and line:sub(1, 1) ~= "#" then
                -- Split the line at the equals sign
                local name, value = line:match("([^=]+)=(.+)")
                if name and value then
                    name = name:gsub("%s+$", "") -- Trim trailing spaces
                    value = value:gsub("^%s+", "") -- Trim leading spaces
                    
                    -- Convert string values to appropriate types
                    if value == "true" then
                        value = true
                    elseif value == "false" then
                        value = false
                    elseif tonumber(value) then
                        value = tonumber(value)
                    end
                    
                    config_table[name] = value
                end
            end
        end
        config_file:close()
    end
    
    return config_table
end

function set_config(name, value)
    if not name then
        print("Error: Configuration name cannot be nil")
        return false
    end
    local config_table = get_config()
    config_table[name] = value
    return save_config(config_table)
end

function save_config(config_table)
    if type(config_table) ~= "table" then
        print("Error: Configuration must be a table")
        return false
    end
    
    local config_path = "/data/ps5_lua_loader/menu_config.txt"
    
    ensure_directory_exists("/data/ps5_lua_loader/")
    
    local config_file = io.open(config_path, "w")
    if not config_file then
        print("Error: Failed to open config file: " .. config_path)
        return false
    end

    for name, value in pairs(config_table) do
        config_file:write(name .. "=" .. tostring(value) .. "\n")
    end
    
    config_file:close()
    
    print("Configuration saved successfully to: " .. config_path)
    return true
end
