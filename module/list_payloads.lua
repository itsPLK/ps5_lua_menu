
function list_payloads(only_data)

    print("Scanning for payloads in:")
    print("/data/ps5_lua_loader/")
    if not only_data then
        print("/mnt/usb*/ps5_lua_loader/")
    end

    -- Initialize empty array for results
    local matching_files = {}
    
    -- Define the directories to scan
    local directories = {"/data/ps5_lua_loader/"}
    
    -- Add USB directories
    if not only_data then
        for i = 0, 7 do
            table.insert(directories, "/mnt/usb" .. i .. "/ps5_lua_loader/")
        end
    end

    -- Allocate memory for file operations
    local st = memory.alloc(128)  -- stat structure
    local contents = memory.alloc(4096)  -- buffer for directory entries

    -- Scan each directory
    for _, dir_path in ipairs(directories) do
        -- print("Scanning directory: " .. dir_path)
        
        local fd = syscall.open(dir_path, 0, 0):tonumber()
        if fd < 0 then
            -- print("Failed to open directory: " .. dir_path)
        else
            syscall.fsync(fd)

            while true do
                local nread = sceGetdents(fd, contents, 4096)
                if nread <= 0 then break end
                
                local entry = contents
                local end_ptr = contents + nread
                
                while entry < end_ptr do
                    local length = read_u16(entry + 0x4)
                    if length == 0 then break end
                    
                    local name = memory.read_buffer(entry + 0x8, 64)
                    name = name:match("([^%z]+)") -- Remove null terminator
                    
                    -- Check if it's a valid file (not . or ..) and doesn't start with a dot
                    if name and name ~= '.' and name ~= '..' and not name:match("^%.") then
                        local full_path = dir_path .. name
                        
                        -- Check if the file exists
                        local stat_result = sceStat(full_path, st)
                        
                        if stat_result >= 0 then
                            -- Add file if it matches our extensions
                            if name:match("%.lua$") or name:match("%.elf$") or name:match("%.bin$") then
                                if name ~= "ps5_lua_menu.lua" and name ~= "elfldr.elf" then
                                    table.insert(matching_files, full_path)
                                end
                            end
                        end
                    end
                    
                    entry = entry + length
                end
            end
            syscall.close(fd)
        end
    end
    
    print("Found " .. #matching_files .. " matching files")
    return matching_files
end
