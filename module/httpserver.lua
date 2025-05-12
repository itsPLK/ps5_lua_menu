

function menu_action(action)
    if action == "read_klog" then
        print(read_klog())
    elseif action == "elf_loader" then
        elf_loader:main()
    else
        print("Unknown action:", action)
    end
end


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
    -- print("Server socket fd:", sockfd)
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
    local buffer = memory.alloc(4096)
    local bytes_read = syscall.recv(client_fd, buffer, 4096, 0):tonumber()
    
    if bytes_read <= 0 then
        return nil
    end
    
    local request = memory.read_buffer(buffer, bytes_read)
    return request
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

    elseif path == "/shutdown" then
        http_server.should_shutdown = true
        return "Server shutting down..."

    elseif path == "/keepalive" then
        http_server.last_keepalive = os.time()
        return "OK"

    elseif path == "/log" then
        return convert_to_json(get_print_history(), "logs")

    elseif path == "/list_payloads" then
        return convert_to_json(list_payloads(), "payloads")

    elseif path:match("^/loadpayload:") then
        -- Extract the payload path from the URL
        local payload_path = path:match("^/loadpayload:(.*)")
        -- URL decode the path (in case it contains special characters)
        payload_path = payload_path:gsub("%%(%x%x)", function(h)
            return string.char(tonumber(h, 16))
        end)
        load_payload(payload_path)
        http_server.last_keepalive = os.time()
        return "Payload loaded: " .. payload_path

    elseif path:match("^/command%?action=(.+)$") then
        print("Received", method, "request for", path)
        local action = path:match("^/command%?action=(.+)$")
        menu_action(action)
        return "Command received: " .. action

    else
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
            --print("Browser seems closed (no keepalive for 4 seconds). Reopening...")
            --http_server.openBrowser()
            send_ps_notification("Shutting down HTTP server...")
            http_server.should_shutdown = true
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

