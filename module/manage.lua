
function ensure_directory_exists(path)
    local st = memory.alloc(128)
    local stat_result = syscall.stat(path, st):tonumber()
    if stat_result < 0 then
        -- Directory doesn't exist, create it
        -- chmod 0755
        local result = syscall.mkdir(path, 0x1ED):tonumber()
        if result < 0 then
            print("Failed to create directory: " .. path)
            return false
        else
            print("Created directory: " .. path)
            return true
        end
    end
    return true
end

function process_uploaded_file(filename, file_content)
    ensure_directory_exists("/data/ps5_lua_loader/")

    if filename:match("/") or filename:match("%.%./") or filename:match("/%.%." ) or filename == ".." then
        local err_msg = "Error: Invalid filename. Path traversal attempt detected: " .. filename
        print(err_msg)
        return false, err_msg
    end

    local file_path = "/data/ps5_lua_loader/" .. filename
    
    local check_file = io.open(file_path, "rb")
    if check_file then
        check_file:close()
        print("Error: File already exists: " .. filename)
        return false, "Error: File already exists: " .. filename
    end
    
    local file_handle = io.open(file_path, "wb")
    if not file_handle then
        return false, "Error: Failed to open file for writing: " .. file_path
    end
    
    local success, err = file_handle:write(file_content)
    file_handle:close()

    local dir_fd = syscall.open("/data/ps5_lua_loader/", 0, 0):tonumber()
    if dir_fd >= 0 then
        syscall.fsync(dir_fd)
        syscall.close(dir_fd)
    end
        
    if not success then
        return false, "Error: Failed to write file content: " .. (err or "unknown error")
    end
    
    return true
end


function remove_file(filename)
    local file_path = "/data/ps5_lua_loader/" .. filename
    print("Attempting to remove file: " .. file_path)

    if filename:match("/") or filename:match("%.%./") or filename:match("/%.%." ) or filename == ".." then
        local err_msg = "Error: Invalid filename. Path traversal attempt detected: " .. filename
        print(err_msg)
        return false, err_msg
    end

    local result = syscall.unlink(file_path):tonumber()

    if result == 0 then
        print("Successfully removed file: " .. file_path)
        -- Sync the directory to ensure changes are written to disk
        local dir_fd = syscall.open("/data/ps5_lua_loader/", 0, 0):tonumber()
        if dir_fd >= 0 then
            syscall.fsync(dir_fd)
            syscall.close(dir_fd)
        end
        return true -- Success
    else
        local err_msg = "Error: Failed to remove file: " .. file_path .. " (System Error: " .. result .. ")"
        print(err_msg)
        return false, err_msg
    end
end
