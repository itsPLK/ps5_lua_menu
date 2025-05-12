
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
