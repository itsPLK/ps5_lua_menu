
elf_sender = {}
elf_sender.__index = elf_sender

function elf_sender:load_from_file(filepath)

    if not elf_loader_active and autoloading then
        elf_loader:main()
        sleep(4000, "ms")
    end

    if file_exists(filepath) then
        print("Loading elf from:", filepath)
    else
        self.error = "File not found: " .. filepath
        return self
    end

    local self = setmetatable({}, elf_sender)
    self.filepath = filepath
    self.elf_data = file_read(filepath)
    self.elf_size = #self.elf_data

    print("elf size: " .. self.elf_size .. " bytes")
    return self
end

function elf_sender:sceNetSend(sockfd, buf, len, flags, addr, addrlen)
    return syscall.send(sockfd, buf, len, flags, addr, addrlen):tonumber()
end
function elf_sender:sceNetSocket(domain, type, protocol)
    return syscall.socket(domain, type, protocol):tonumber()
end
function elf_sender:sceNetSocketClose(sockfd)
    return syscall.close(sockfd):tonumber()
end
function elf_sender:htons(port)
    return bit32.bor(bit32.lshift(port, 8), bit32.rshift(port, 8)) % 0x10000
end

function elf_sender:send_to_localhost(port)

    if self.error then
        print("[-] Error: " .. self.error)
        send_ps_notification("[-] Error: " .. self.error)
        return false
    end

    if not elf_sender:check_if_elfloader_is_running(9021) then
        elf_loader:main()
        sleep(4000, "ms")
    end

    local sockfd = elf_sender:sceNetSocket(2, 1, 0) -- AF_INET=2, SOCK_STREAM=1
    assert(sockfd >= 0, "socket creation failed")
    local enable = memory.alloc(4)
    memory.write_dword(enable, 1)
    syscall.setsockopt(sockfd, 1, 2, enable, 4) -- SOL_SOCKET=1, SO_REUSEADDR=2

    local sockaddr = memory.alloc(16)

    memory.write_byte(sockaddr + 0, 16)
    memory.write_byte(sockaddr + 1, 2) -- AF_INET
    memory.write_word(sockaddr + 2, elf_sender:htons(port))

    memory.write_byte(sockaddr + 4, 0x7F) -- 127
    memory.write_byte(sockaddr + 5, 0x00) -- 0
    memory.write_byte(sockaddr + 6, 0x00) -- 0
    memory.write_byte(sockaddr + 7, 0x01) -- 1


    local connect_result = syscall.connect(sockfd, sockaddr, 16):tonumber()

    if connect_result < 0 then
        elf_sender:sceNetSocketClose(sockfd)
        print("[ERROR]:\nELF Loader not running")
        send_ps_notification("[ERROR]:\nELF Loader not running")
        return false
    end

    local buf = memory.alloc(#self.elf_data)
    memory.write_buffer(buf, self.elf_data)

    local total_sent = elf_sender:sceNetSend(sockfd, buf, #self.elf_data, 0, sockaddr, 16)
    elf_sender:sceNetSocketClose(sockfd)
    if total_sent < 0 then
        print("[-] error sending elf data to localhost")
        send_ps_notification("error sending elf data to localhost")
        return
    end
    print(string.format("Successfully sent %d bytes to loader", total_sent))
end


function elf_sender:check_if_elfloader_is_running(port)
    local sockfd = elf_sender:sceNetSocket(2, 1, 0) -- AF_INET=2, SOCK_STREAM=1
    assert(sockfd >= 0, "socket creation failed")
    local enable = memory.alloc(4)
    memory.write_dword(enable, 1)
    syscall.setsockopt(sockfd, 1, 2, enable, 4) -- SOL_SOCKET=1, SO_REUSEADDR=2

    local sockaddr = memory.alloc(16)

    memory.write_byte(sockaddr + 0, 16)
    memory.write_byte(sockaddr + 1, 2) -- AF_INET
    memory.write_word(sockaddr + 2, elf_sender:htons(port))

    memory.write_byte(sockaddr + 4, 0x7F) -- 127
    memory.write_byte(sockaddr + 5, 0x00) -- 0
    memory.write_byte(sockaddr + 6, 0x00) -- 0
    memory.write_byte(sockaddr + 7, 0x01) -- 1

    local connect_result = syscall.connect(sockfd, sockaddr, 16):tonumber()
    elf_sender:sceNetSocketClose(sockfd)

    if connect_result < 0 then
        print("ELF Loader not running, starting it")
        send_ps_notification("ELF Loader not running, starting it")
        return false
    else
        print("ELF Loader is already running")
        return true
    end
end
