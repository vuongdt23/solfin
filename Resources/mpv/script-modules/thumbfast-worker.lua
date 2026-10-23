-- Companion to Solfin's MPL-2.0 thumbfast fork (see scripts/thumbfast.lua).
-- Lua polling replaces the shell/chmod/tail bridge on macOS. The parent creates
-- the append-only mailbox before launch, retaining seeks during HTTP startup.
-- This Source Code Form is subject to the Mozilla Public License, v. 2.0.
-- A copy is available at https://mozilla.org/MPL/2.0/.
local path = mp.get_opt("solfin-thumbfast-mailbox")
if not path then return end

local position = 0
mp.add_periodic_timer(0.05, function()
    local file = io.open(path, "r")
    if not file then return end
    file:seek("set", position)
    local commands = file:read("*a")
    file:close()
    local complete = commands:match("^(.*\n)")
    if not complete then return end
    position = position + #complete
    local seek
    for command in complete:gmatch("[^\n]+") do
        if command:match("^async seek ") then
            seek = command -- latest hover wins; don't replay stale queued seeks
        else
            mp.command(command)
        end
    end
    if seek then mp.command(seek) end
end)
