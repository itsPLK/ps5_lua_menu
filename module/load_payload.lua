

function load_payload(full_path)
    if full_path:match("%.elf$") or full_path:match("%.bin$") then
        elf_sender:load_from_file(full_path):send_to_localhost(9021)
    elseif full_path:match("%.lua$") then
        load_and_run_lua(full_path)
    end
end
