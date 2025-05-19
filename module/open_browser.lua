
local libSystemService = find_mod_by_name("libSceSystemService.sprx")
sceSystemServiceLaunchWebBrowser = fcall(dlsym(libSystemService.handle, "sceSystemServiceLaunchWebBrowser"))

function openBrowser(port)
    local url = memory.alloc(256)
    memory.write_buffer(url, "http://127.0.0.1:" .. port .. "/\0")
    local ret = sceSystemServiceLaunchWebBrowser(url, 0):tonumber()
end
