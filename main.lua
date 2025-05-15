
menu_version = "0.1"

if not is_jailbroken() then
    send_ps_notification("This script requires a jailbroken PS5.\nRun kernel exploit (e.g. umtx.lua) first")
    return
end

require("module/misc")

require("module/elf_loader")
require("module/elf_sender")

require("module/manage")
require("module/list_payloads")
require("module/load_payload")

HTML_CONTENT = [[html_include:html/index.html]]

HTML_MANAGE_CONTENT = [[html_include:html/manage.html]]


require("module/httpserver")
