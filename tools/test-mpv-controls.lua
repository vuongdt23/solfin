-- Run from repository root: luajit tools/test-mpv-controls.lua
-- Exercise the actual OSC with a minimal mpv host, including geometry/rendering.
local observers, sections, calls, events, messages, enabled = {}, {}, {}, {}, {}, {}
local mouse_x, mouse_y, now = 0, 0, 1
local function noop() end
local function record(...) calls[#calls + 1] = {...} end
local timer, overlay
package.preload["mp.assdraw"] = function()
    return {ass_new = function()
        return setmetatable({text = "", append = function(self, text) self.text = self.text .. text end},
            {__index = function() return noop end})
    end}
end
package.preload["mp.msg"] = function() return {warn = noop} end
package.preload["mp.options"] = function() return {read_options = noop} end
package.preload["mp.utils"] = function() return {parse_json = function()
    return {available=true, disabled=false, width=256, height=144}
end} end
mp = {
    set_property = record, set_property_number = record, set_property_native = record,
    commandv = record, command_native_async = noop,
    command_native = function(command)
        if command[1] == "escape-ass" then
            return command[2]:gsub("\\", "\\\239\187\191"):gsub("{", "\\{"):gsub("}", "\\}")
        end
        record(command)
    end,
    create_osd_overlay = function() overlay = {update = noop}; return overlay end,
    get_time = function() return now end,
    get_mouse_pos = function() return mouse_x, mouse_y end,
    set_mouse_area = noop,
    observe_property = function(name, _, callback) observers[name] = callback end,
    register_event = function(name, callback) events[name] = callback end,
    register_script_message = function(name, callback) messages[name] = callback end,
    set_key_bindings = function(value, name) sections[name] = value end,
    enable_key_bindings = function(name) enabled[name] = true end,
    disable_key_bindings = function(name) enabled[name] = false end,
    add_timeout = function(_, callback)
        timer = {callback = callback, enabled = false}
        function timer:is_enabled() return self.enabled end
        function timer:resume() self.enabled = true end
        function timer:kill() self.enabled = false end
        return timer
    end,
}
dofile("Resources/mpv/scripts/solfin-osc.lua")
local function captured(fn, wanted)
    for i=1,100 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
end
local state = assert(captured(timer.callback, "state"))
local render = assert(captured(timer.callback, "render"))
local function boxes() return assert(captured(render, "hitboxes")) end
local function observe(name, value) observers[name](name, value) end
local function tick(dt) now = now + (dt or 0); timer.callback() end
local function move(x, y)
    mouse_x, mouse_y = x, y
    observe("mouse-pos", {hover=true})
    tick()
end
local mouse = sections["solfin-osc-mouse"][1]
local function click(x, y) move(x,y); mouse[3](); mouse[2](); tick() end
local function click_box(name)
    local b = assert(boxes()[name], name)
    click((b.x1+b.x2)/2, (b.y1+b.y2)/2)
end
local function last_is(a,b) local c=calls[#calls]; return c and c[1]==a and c[2]==b end
observe("osd-dimensions", {w=1280,h=720})
observe("pause", true)
observe("duration", 2979)
observe("time-pos", 376)
observe("seekable", true)
tick(1)
for _, maximized in ipairs({false,true}) do
    observe("fullscreen", true); observe("window-maximized", maximized)
    click_box("maximize")
    assert(last_is("fullscreen", false))
end
observe("fullscreen", false); click_box("maximize")
assert(last_is("cycle", "window-maximized"))
print("PASS: fullscreen restore and window zoom")

local b = boxes().playpause
click((b.x1+b.x2)/2,b.y1+1)
assert(last_is("cycle", "pause"), "Play top edge must not seek")
local seek = boxes().seekbar
assert(seek.y2 < b.y1, "seek and button targets must not overlap")
assert(b.y1 - seek.y2 == 2, "timeline/button spacing should stay compact")
move((b.x1+b.x2)/2,(b.y1+b.y2)/2); mouse[3](); move(640,360); mouse[2]()
assert(last_is("cycle", "pause"), "release elsewhere must not activate another target")
local count = #calls
click(640,710); assert(#calls==count, "empty chrome must not pause")
print("PASS: disjoint targets, press/release capture and empty chrome")

click_box("subtitle")
local panel = boxes().menu_area
count = #calls
click(panel.x1+10,panel.y1+8)
assert(#calls==count and state.menu.open, "header click must be consumed")
click(640,360); assert(not state.menu.open and #calls==count, "outside dismiss must not pause")
observe("track-list", {{type="sub",id=1,title="English",codec="subrip",selected=true},
    {type="audio",id=2,title="Stereo",lang="en",codec="aac",selected=true}})
click_box("subtitle")
assert(enabled["solfin-osc-menu"])
local keys = sections["solfin-osc-menu"]
keys[3][2](); keys[4][2]()
assert(last_is("sid", "no") and not enabled["solfin-osc-menu"])
click_box("audio"); tick(); keys[1][2](); assert(not state.menu.open)
print("PASS: menus capture background, outside dismiss and keyboard navigation")

observe("seekable", false)
count = #calls; click_box("skip_fwd"); click_box("seekbar")
assert(#calls==count and state.feedback=="Seeking unavailable")
observe("seekable", true); click_box("seekbar")
assert(calls[#calls][1]=="seek" and calls[#calls][3]=="absolute+exact")
observe("volume-max", 130)
b=boxes().volslider; click(b.x2,(b.y1+b.y2)/2)
assert(last_is("volume",130), "slider must expose configured headroom")
print("PASS: seekability gating, exact seek and volume boost")

observe("sub-pos",98); tick()
assert(last_is("sub-pos",86), "visible controls raise text subtitles")
observe("track-list", {{type="sub",id=1,codec="ass",selected=true}}); tick()
assert(last_is("sub-pos",98), "authored ASS must retain original position")
observe("track-list", {{type="sub",id=1,codec="subrip",selected=true}}); tick()
state.menu.open=false; observe("pause",false); move(640,360)
tick(2); assert(state.anim=="out")
tick(0.1); local opacity=state.opacity
move(641,360); assert(state.anim=="in" and math.abs(state.opacity-opacity)<0.001)
tick(0.3); assert(state.visible and state.opacity==1)
tick(2); tick(0.3)
assert(not state.visible and last_is("sub-pos",98), "hide restores subtitle position")
move(640,360); tick(0.3)
assert(timer.timeout==0.1, "static controls must not render at 60 Hz")
print("PASS: fade reversal, subtitle restoration and idle scheduling")

observe("media-title", "A {\\bord99} title\\Nnext\nline")
tick()
assert(not overlay.data:find("{\\bord99}",1,true), "metadata must not inject ASS tags")
assert(not overlay.data:find("\\Nnext",1,true), "metadata must not inject line breaks")
local volume_box = boxes().volume
move((volume_box.x1+volume_box.x2)/2,(volume_box.y1+volume_box.y2)/2)
assert(overlay.data:find("Mute",1,true), "hover tooltip must appear without advancing time")
observe("speed",1.5); tick()
assert(overlay.data:find("Speed 1.5×",1,true))
print("PASS: escaped metadata, immediate tooltips and action feedback")

local fullscreen_icon = assert(captured(render,"icon_fullscreen"))
for _, fullscreen in ipairs({false,true}) do
    local rectangles=0
    local icon_ass = setmetatable({
        rect_cw=function(_,x1,y1,x2,y2)
            rectangles=rectangles+1
            assert(x2>x1 and y2>y1 and (x2-x1<=1.61 or y2-y1<=1.61))
        end,
        line_to=function() error("fullscreen brackets must not use closing stroke paths") end,
    },{__index=function() return noop end})
    fullscreen_icon(icon_ass,0,0,"FFFFFF",0,fullscreen)
    assert(rectangles==8, "four fullscreen brackets require eight explicit bars")
end
print("PASS: fullscreen icon uses clean rectangular brackets")

for _, dim in ipairs({{w=800,h=720},{w=560,h=720},{w=320,h=900},{w=1920,h=1080}}) do
    observe("osd-dimensions",dim); tick()
    local all=boxes()
    for name,box in pairs(all) do
        assert(box.x1>=0 and box.x2<=state.playresx+1, name.." must fit horizontally")
    end
    local names={"prev","skip_back","playpause","skip_fwd","next","speed","audio","subtitle","media_info","fullscreen","volume","volslider","more"}
    for i,name in ipairs(names) do
        local a=all[name]
        if a then for j=i+1,#names do
            local c=all[names[j]]
            if c then assert(a.x2<=c.x1 or c.x2<=a.x1 or a.y2<=c.y1 or c.y2<=a.y1,
                name.." overlaps "..names[j]) end
        end end
    end
    if state.compact then
        assert(all.more and not all.audio)
        -- Convert the mock cursor's virtual hitbox coordinates to real pixels.
        local original_scale = state.scale
        local more = all.more
        click((more.x1+more.x2)/2/original_scale,(more.y1+more.y2)/2/original_scale)
        tick()
        local panel=boxes().menu_area
        assert(panel.y1>=0)
        local row=boxes().menu_row_1
        click((row.x1+row.x2)/2/original_scale,(row.y1+row.y2)/2/original_scale)
        tick()
        assert(state.menu.open and state.menu.kind=="audio", "nested More menu navigation")
        keys[1][2](); tick()
    end
end
print("PASS: responsive controls and overflow menu")

for _, height in ipairs({720,1080,1440,2160}) do
    observe("osd-dimensions",{w=height*16/9,h=height}); tick()
    assert(math.abs(1/state.scale-height/720)<0.001,
        "OSC must scale proportionally with output height, without a 4K size cap")
    local timeline,button=boxes().seekbar,boxes().playpause
    local timeline_y=timeline.y1+10
    local button_y=button.y1+10
    assert(math.abs((button_y-timeline_y)/state.scale/height-20/720)<0.001,
        "compact timeline spacing must remain proportional at every resolution")
    assert(timeline.y2<button.y1, "scaled timeline and button targets must stay separate")
end
print("PASS: proportional 720p through 4K scaling with compact spacing")

observe("osd-dimensions",{w=1280,h=720}); tick()
messages["thumbfast-info"]("metadata")
click_box("seekbar")
local preview_box = boxes().seekbar
move(1200,(preview_box.y1+preview_box.y2)/2); tick()
assert(calls[#calls][2]=="thumbfast" and calls[#calls][3]=="thumb")
events["end-file"]()
assert(calls[#calls][2]=="thumbfast" and calls[#calls][3]=="clear")
print("PASS: thumbfast preview routing and cleanup")
