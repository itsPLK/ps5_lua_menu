
function get_savedata_path()
    local path = "/savedata0/"
    if is_jailbroken() then
        path = "/mnt/sandbox/" .. get_title_id() .. "_000/savedata0/"
    end
    return path
end

function load_and_run_lua(path)
    local lua_code = file_read(path, "r")
    run_lua_code(lua_code)
end

syscall.resolve({
    kill = 0x25,
})

function kill_this_app()
    syscall.kill(syscall.getpid(), 15)
end



local old_print = print
local old_printf = printf

local print_history = {}
local max_history_size = 100

function print(...)
    old_print(...)
        local args = {...}
    local message = ""
    for i, v in ipairs(args) do
        message = message .. tostring(v)
        if i < #args then
            message = message .. "\t"
        end
    end
    table.insert(print_history, message)
    if #print_history > max_history_size then
        table.remove(print_history, 1)
    end
end

function printf(...)
    old_printf(...)
    local args = {...}
    local message = ""
    for i, v in ipairs(args) do
        message = message .. tostring(v)
        if i < #args then
            message = message .. "\t"
        end
    end
    table.insert(print_history, message)
    if #print_history > max_history_size then
        table.remove(print_history, 1)
    end
end

function get_print_history()
    return print_history
end


function convert_to_json(t, name)
    local json_result = "{"
    json_result = json_result .. "\"" .. name .. "\":["
    for i, v in ipairs(t) do
        -- First escape backslashes (must be done first)
        v = v:gsub('\\', '\\\\')
        -- Then escape other special characters
        v = v:gsub('"', '\\"')
        v = v:gsub('\n', '\\n')
        v = v:gsub('\r', '\\r')
        v = v:gsub('\t', '\\t')
        v = v:gsub('\b', '\\b')
        v = v:gsub('\f', '\\f')
        json_result = json_result .. '"' .. v .. '"'
        if i < #t then
            json_result = json_result .. ","
        end
    end
    json_result = json_result .. "]}"
    return json_result
end





-- read_klog source: https://github.com/shahrilnet/remote_lua_loader/blob/main/payloads/read_klog.lua
syscall.resolve({
    select = 0x5d
})
function read_klog()

    local data_size = PAGE_SIZE
    local data_mem = memory.alloc(data_size)

    local flags = bit32.bor(O_RDONLY, O_NONBLOCK)

    local klog_fd = syscall.open("/dev/klog", flags):tonumber()
    if klog_fd == -1 then
        error("open() error: " .. get_error_string())
    end

    local readfds = memory.alloc(8 * 16)
    local timeval = memory.alloc(0x10)

    memory.write_dword(timeval, 0) -- tv_sec
    memory.write_dword(timeval + 8, 1000*10) -- tv_usec (10ms)

    for i=0,16-1 do
        memory.write_qword(readfds + i*8, 0)
    end

    local idx = math.floor(klog_fd / 64)
    local cur = memory.read_qword(readfds + idx*8)
    cur = bit64.bor(cur, bit64.lshift(1, klog_fd % 64))
    memory.write_qword(readfds + idx*8, cur)

    while true do

        local select_ret = syscall.select(1024, readfds, nil, nil, timeval):tonumber()

        if select_ret == -1 then -- error
            error("select() error: " .. get_error_string())
            break

        elseif select_ret == 0 then -- time	limit expires
            break

        else
            local read_size = syscall.read(klog_fd, data_mem, data_size):tonumber()
            if read_size > 0 then
                local log_content = memory.read_buffer(data_mem, read_size)
                syscall.close(klog_fd)
                return log_content
            end
        end
    end
    syscall.close(klog_fd)
    return log_content
end


function htons(port)
    return bit32.bor(bit32.lshift(port, 8), bit32.rshift(port, 8)) % 0x10000
end

syscall.resolve({
    getsockname = 32,
})

function get_local_ip_address()
    -- Create a UDP socket
    local sock = syscall.socket(2, 2, 0):tonumber() -- AF_INET=2, SOCK_DGRAM=2
    print("Socket fd:", sock)
    assert(sock >= 0, "socket creation failed")
    
    -- Prepare address structure for Google's DNS (8.8.8.8:53)
    local addr = memory.alloc(16)
    memory.write_byte(addr + 0, 16)       -- sa_len
    memory.write_byte(addr + 1, 2)        -- AF_INET
    memory.write_word(addr + 2, htons(53)) -- Port 53 (DNS)
    
    -- 8.8.8.8 (Google DNS)
    memory.write_byte(addr + 4, 8)
    memory.write_byte(addr + 5, 8)
    memory.write_byte(addr + 6, 8)
    memory.write_byte(addr + 7, 8)
    
    -- Connect (this doesn't actually establish a connection for UDP)
    local result = syscall.connect(sock, addr, 16):tonumber()
    if result < 0 then
        syscall.close(sock)
        print("Connect failed")
        return nil
    end

    local local_addr = memory.alloc(16)
    local addr_len = memory.alloc(4)
    memory.write_dword(addr_len, 16)
    
    result = syscall.getsockname(sock, local_addr, addr_len):tonumber()
    if result < 0 then
        syscall.close(sock)
        print("Getsockname failed")
        return nil
    end
    
    local ip1 = memory.read_byte(local_addr + 4):tonumber()
    local ip2 = memory.read_byte(local_addr + 5):tonumber()
    local ip3 = memory.read_byte(local_addr + 6):tonumber()
    local ip4 = memory.read_byte(local_addr + 7):tonumber()
    
    syscall.close(sock)
    
    local ip_address = string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
    print("Local IP address:", ip_address)
    return ip_address
end
