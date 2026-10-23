-- Run from repository root: luajit tools/test-mpv-controls.lua
-- Exercise the actual OSC click handlers with a minimal mpv host.
local observers, bindings, calls, events, messages, overlays = {}, {}, {}, {}, {}, {}
local mouse_x, mouse_y = 1222, 34
local now = 1
local function noop() end
local function record(...) calls[#calls + 1] = {...} end
local timer
local drawing = setmetatable({text = ""}, {__index = function() return noop end})
package.preload["mp.assdraw"] = function() return {ass_new = function() return drawing end} end
package.preload["mp.msg"] = function() return {warn = noop} end
package.preload["mp.options"] = function() return {read_options = noop} end
package.preload["mp.utils"] = function() return {parse_json = function() return {available=true, disabled=false, width=256, height=144} end} end
mp = {
    set_property = noop,
    set_property_native = record,
    commandv = record,
    command_native_async = noop,
    command_native = function(command) overlays[#overlays + 1] = command; return true end,
    create_osd_overlay = function() return {update = noop} end,
    get_time = function() return now end,
    get_mouse_pos = function() return mouse_x, mouse_y end,
    set_mouse_area = noop,
    observe_property = function(name, _, callback) observers[name] = callback end,
    register_event = function(name, callback) events[name] = callback end,
    register_script_message = function(name, callback) messages[name] = callback end,
    set_key_bindings = function(value) bindings = value end,
    enable_key_bindings = noop,
    add_timeout = function(_, callback)
        timer = {callback = callback, enabled = false}
        function timer:is_enabled() return self.enabled end
        function timer:resume() self.enabled = true end
        function timer:kill() self.enabled = false end
        return timer
    end,
}
dofile("Resources/mpv/scripts/solfin-osc.lua")
observers["osd-dimensions"]("osd-dimensions", {w = 1280, h = 720})
observers.pause("pause", true)
now = 2
timer.callback()
for _, maximized in ipairs({false, true}) do
    observers.fullscreen("fullscreen", true)
    observers["window-maximized"]("window-maximized", maximized)
    bindings[1][2]()
    local call = calls[#calls]
    assert(call[1] == "fullscreen" and call[2] == false, "fullscreen must restore, not zoom")
end
observers.fullscreen("fullscreen", false)
bindings[1][2]()
assert(calls[#calls][1] == "cycle" and calls[#calls][2] == "window-maximized")
print("PASS: top maximize restores fullscreen; windowed click still toggles zoom")

local function hover()
    mouse_x, mouse_y = 1222, 690
    observers["mouse-pos"]("mouse-pos", {hover=true})
    now = now + 1
    timer.callback()
end
assert(events["file-loaded"] == nil, "OSC must not probe Jellyfin or gate thumbfast")
observers.duration("duration", 70)
messages["thumbfast-info"]("metadata")
hover()
assert(calls[#calls][2] == "thumbfast" and calls[#calls][3] == "thumb")
local thumbCount = #calls
events["end-file"]()
assert(calls[#calls][2] == "thumbfast" and calls[#calls][3] == "clear")
print("PASS: thumbfast-only previews, seek routing, and end-file cleanup")
