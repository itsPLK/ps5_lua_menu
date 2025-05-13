

local libSystemService = find_mod_by_name("libSceSystemService.sprx")
sceSystemServiceLaunchWebBrowser = fcall(dlsym(libSystemService.handle, "sceSystemServiceLaunchWebBrowser"))

local http_server = {}

http_server.port = 8084
http_server.last_keepalive = os.time()
http_server.should_shutdown = false

local AF_INET = 2
local SOCK_STREAM = 1
local SOL_SOCKET = 0xFFFF
local SO_REUSEADDR = 0x00000004
local INADDR_ANY = 0

server_fd = nil

syscall.resolve({
    recv = 29,
    send = 133,
})

-- HTTP response template
local HTTP_RESPONSE = [[HTTP/1.1 200 OK
Content-Type: text/html; charset=UTF-8
Connection: close
Content-Length: %d

%s]]

-- HTML_CONTENT is set in main.lua

function http_server.htons(port)
    return bit32.bor(bit32.lshift(port, 8), bit32.rshift(port, 8)) % 0x10000
end

function http_server.shutdown()
    if server_fd then
        print("Closing server socket")
        syscall.close(server_fd)
        server_fd = nil
    end
end


function http_server.create_server(port)
    -- Create socket
    local sockfd = syscall.socket(AF_INET, SOCK_STREAM, 0):tonumber()
    print("Server socket fd:", sockfd)
    assert(sockfd >= 0, "Server socket creation failed")
    
    -- Set socket options
    local enable = memory.alloc(4)
    memory.write_dword(enable, 1)
    local setsockopt_result = syscall.setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, enable, 4):tonumber()
    -- print("setsockopt result:", setsockopt_result)


    local enable = memory.alloc(4)
    memory.write_dword(enable, 1)

    -- Prepare sockaddr structure
    local sockaddr = memory.alloc(16)
    memory.write_byte(sockaddr + 0, 16)       -- sa_len
    memory.write_byte(sockaddr + 1, AF_INET)  -- sa_family
    memory.write_word(sockaddr + 2, http_server.htons(port)) -- sin_port
    memory.write_dword(sockaddr + 4, INADDR_ANY) -- sin_addr (0.0.0.0)

    -- Bind socket
    local bind_result = syscall.bind(sockfd, sockaddr, 16):tonumber()
    if bind_result < 0 then
        print("Bind failed:", bind_result)
        syscall.close(sockfd)
        return nil
    end
    
    -- Listen for connections
    local listen_result = syscall.listen(sockfd, 5):tonumber()
    if listen_result < 0 then
        print("Listen failed:", listen_result)
        syscall.close(sockfd)
        return nil
    end
    
    print("HTTP server listening on port", port)
    return sockfd
end

function http_server.accept_client(server_fd)
    local client_addr = memory.alloc(16)
    local addr_len = memory.alloc(4)
    memory.write_dword(addr_len, 16)
    
    local client_fd = syscall.accept(server_fd, client_addr, addr_len):tonumber()
    if client_fd < 0 then
        print("Accept failed:", client_fd)
        return nil
    end
    
    return client_fd
end


function http_server.accept_client_with_timeout(server_fd, timeout_ms)
    -- Set socket to non-blocking
    local flags = syscall.fcntl(server_fd, 3, 0):tonumber() -- F_GETFL = 3
    syscall.fcntl(server_fd, 4, bit32.bor(flags, 0x4)):tonumber() -- F_SETFL = 4, O_NONBLOCK = 0x4
    
    local client_fd = syscall.accept(server_fd, nil, nil):tonumber()
    
    -- If no client, sleep a bit and return nil
    if client_fd < 0 then
        sleep(timeout_ms, "ms")
        return nil
    end
    
    -- Set client socket back to blocking mode
    flags = syscall.fcntl(client_fd, 3, 0):tonumber()
    syscall.fcntl(client_fd, 4, bit32.band(flags, bit32.bnot(0x4))):tonumber()
    
    return client_fd
end


function http_server.read_request(client_fd)
    -- First read the headers with a smaller buffer
    local header_buffer = memory.alloc(4096)
    local bytes_read = syscall.recv(client_fd, header_buffer, 4096, 0):tonumber()
    
    if bytes_read <= 0 then
        return nil
    end
    
    local headers = memory.read_buffer(header_buffer, bytes_read)
    
    -- Check if this is a POST request with content
    local method = headers:match("^(%S+)%s+")
    local content_length = headers:match("Content%-Length:%s*(%d+)")
    
    if method == "POST" and content_length then
        content_length = tonumber(content_length)
        
        -- If we have a large POST, process it in chunks
        if content_length > 0 then
            -- Check if we already received the full content
            local header_end = headers:find("\r\n\r\n")
            local body_start = header_end and header_end + 4 or nil
            
            if body_start and bytes_read - body_start + 1 >= content_length then
                -- We already have the full request
                return headers
            else
                -- Need to read more data in chunks
                local CHUNK_SIZE = 1024 * 1024  -- 1MB chunks
                
                -- Calculate how much of the body we already have
                local body_bytes_received = bytes_read - body_start + 1
                local body_bytes_remaining = content_length - body_bytes_received
                
                -- Create a buffer for the full request
                local full_request = headers
                
                -- Read the rest of the body in chunks
                while body_bytes_remaining > 0 do
                    local chunk_size = math.min(CHUNK_SIZE, body_bytes_remaining)
                    local chunk_buffer = memory.alloc(chunk_size)
                    
                    local chunk_bytes_read = syscall.recv(client_fd, chunk_buffer, chunk_size, 0):tonumber()
                    if chunk_bytes_read <= 0 then
                        print("Error reading chunk: " .. chunk_bytes_read)
                        break
                    end
                    
                    -- Append this chunk to our full request
                    full_request = full_request .. memory.read_buffer(chunk_buffer, chunk_bytes_read)
                    
                    -- Update our counters
                    body_bytes_remaining = body_bytes_remaining - chunk_bytes_read
                end
                
                return full_request
            end
        end
    end
    
    return headers
end



function http_server.extract_post_data(request)
    -- Find the boundary from the Content-Type header
    local boundary = request:match("Content%-Type: multipart/form%-data; boundary=([^\r\n]+)")
    if not boundary then return nil end
    
    -- Format the boundary as it appears in the content
    local content_boundary = "--" .. boundary
    
    -- Find the start of the file content
    local file_start_pattern = content_boundary .. "\r\n" ..
                              "Content%-Disposition: form%-data; name=\"[^\"]+\"; filename=\"[^\"]+\"\r\n" ..
                              "Content%-Type: [^\r\n]+\r\n\r\n"
    
    local content_start = request:match(file_start_pattern .. "()")
    if not content_start then return nil end
    
    -- Find the end boundary
    local content_end = request:find("\r\n" .. content_boundary .. "--", content_start)
    if not content_end then return nil end
    
    -- Extract just the file content between the header and end boundary
    local file_content = request:sub(content_start, content_end - 1)
    return file_content
end


function http_server.send_response(client_fd, content)
    local response = string.format(HTTP_RESPONSE, #content, content)
    local buffer = memory.alloc(#response)
    memory.write_buffer(buffer, response)
    
    local bytes_sent = syscall.send(client_fd, buffer, #response, 0):tonumber()
    return bytes_sent
end

function http_server.parse_request(request)
    local method, path = request:match("^(%S+)%s+(%S+)")
    return method, path
end

function http_server.handle_request(request)
    local method, path = http_server.parse_request(request)
    
    if not method or not path then
        return "Invalid request"
    end
    
    http_server.last_keepalive = os.time()

    -- print("Received", method, "request for", path)
    
    -- Handle different paths
    if path == "/" or path == "/index.html" then
        return HTML_CONTENT

    elseif path == "/manage" then
        return HTML_MANAGE_CONTENT

    elseif path == "/shutdown" then
        http_server.should_shutdown = true
        send_ps_notification("Shutting down HTTP server...")
        return "Server shutting down..."

    elseif path == "/keepalive" then
        http_server.last_keepalive = os.time()
        return "OK"

    elseif path == "/log" then
        return convert_to_json(get_print_history(), "logs")

    elseif path == "/list_payloads" then
        return convert_to_json(list_payloads(), "payloads")

    elseif path == "/list_payloads:only_data" then
        return convert_to_json(list_payloads(true), "payloads")

    elseif path:match("^/loadpayload:") then
        local payload_path = path:match("^/loadpayload:(.*)")
        payload_path = payload_path:gsub("%%(%x%x)", function(h)
            return string.char(tonumber(h, 16))
        end)
        load_payload(payload_path)
        http_server.last_keepalive = os.time()
        return "Payload loaded: " .. payload_path

    elseif path:match("^/manage:upload%?filename=(.+)$") and method == "POST" then
        local filename = path:match("^/manage:upload%?filename=(.+)$")
        filename = filename:gsub("%%(%x%x)", function(h)
            return string.char(tonumber(h, 16))
        end)
        
        local file_content = http_server.extract_post_data(request)
        
        if file_content then
            local success, message = process_uploaded_file(filename, file_content)
            return "OK"
        else
            return "Error: No file content received"
        end
    
    elseif path == "/getip" then
        local ip = get_local_ip_address()
        if ip then
            return ip
        else
            return "error"
        end
    else
        print("404: Received", method, "request for", path)
        return "404 Not Found"
    end
end


function http_server.run(port)
    port = port or 8080
    server_fd = http_server.create_server(port)
    
    if not server_fd then
        print("Failed to create server")
        return
    end
    
    http_server.openBrowser()

    http_server.should_shutdown = false
    
    -- Main server loop
    while not http_server.should_shutdown do

        -- Check if client is active
        local current_time = os.time()
        if current_time - http_server.last_keepalive > 4 and payload_is_currently_loading ~= true then
            send_ps_notification("Reopening browser...\nUse EXIT button to close it.")
            print("Browser seems closed (no keepalive for 4 seconds). Reopening...")
            http_server.openBrowser()
            --send_ps_notification("Shutting down HTTP server...")
            --http_server.should_shutdown = true
        end

        local client_fd = http_server.accept_client_with_timeout(server_fd, 50)

        if client_fd then
            local request = http_server.read_request(client_fd)
            if request then
                local response = http_server.handle_request(request)
                http_server.send_response(client_fd, response)
            end
            syscall.close(client_fd)
        end
    end

    print("Shutting down HTTP server...")
    syscall.close(server_fd)
end

function http_server.openBrowser()
    http_server.last_keepalive = os.time()
    local url = memory.alloc(256)
    memory.write_buffer(url, "http://127.0.0.1:" .. http_server.port .. "/\0")
    local ret = sceSystemServiceLaunchWebBrowser(url, 0):tonumber()
end

http_server.run(http_server.port)

