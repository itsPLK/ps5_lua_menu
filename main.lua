
menu_version = "0.1"

if not is_jailbroken() then
    send_ps_notification("This script requires a jailbroken PS5.\nRun kernel exploit (e.g. umtx.lua) first")
    return
end

syscall.resolve({
    unlink = 10,
    recv = 29,
    getsockname = 32,
    kill = 37,
    fcntl = 92,
    fsync = 95,
    send = 133,
    mkdir = 136,
    stat = 188, -- sys_stat2
    getdents = 272,
})

SERVER_PORT = 8084

HTML_CONTENT = [[html_include:html/index.html]]
HTML_MANAGE_CONTENT = [[html_include:html/manage.html]]

require("module/misc")
require("module/config")
require("module/elf_loader")
require("module/elf_sender")
require("module/manage")
require("module/list_payloads")
require("module/load_payload")
require("module/httpserver")
require("module/open_browser")

print("PLK's Lua Menu v" .. menu_version)

openBrowser(SERVER_PORT)
http_server.run(SERVER_PORT)
