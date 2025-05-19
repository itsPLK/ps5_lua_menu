
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
        return true
    else
        local err_msg = "Error: Failed to remove file: " .. file_path .. " (System Error: " .. result .. ")"
        print(err_msg)
        return false, err_msg
    end
end
