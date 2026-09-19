-- solfin-osc.lua — bespoke on-screen controller for the solfin Jellyfin client.
--
-- Pointer-first, web/VLC-like OSC written from scratch for mpv. This replaces the
-- vendored ModernZ script. mpv.conf sets `osc=no` so this script owns all on-screen
-- drawing. It is intentionally self-contained: no external dependencies in Phase 1
-- (thumbnails via thumbfast arrive in a later phase).
--
-- Coordinate system
-- -----------------
-- We draw on a fixed *virtual* canvas 720 units tall (playresx scales with the video
-- aspect) so control sizes stay constant regardless of the real output resolution /
-- HiDPI backing scale. Real pixel <-> virtual conversions go through `scale()`.
--
-- Licensed under LGPLv2.1 (consistent with mpv's osc.lua lineage).

local assdraw = require "mp.assdraw"
local msg      = require "mp.msg"
local opt      = require "mp.options"
local utils    = require "mp.utils"

mp.set_property("osc", "no")

--------------------------------------------------------------------------------
-- User options (override in script-opts/solfin-osc.conf)
--------------------------------------------------------------------------------

local user_opts = {
    accent_color      = "#FF4F0F", -- solar orange, matches the SwiftUI app tint
    solar_gold_color  = "#FFAD29", -- warm highlight for the Solfin sun motif
    solar_red_color   = "#F2140F", -- hot inner accent for the Solfin sun motif
    logo_path         = "",        -- optional raw BGRA Jellyfin logo rendered in the top bar
    logo_width        = 0,         -- source pixel width for logo_path
    logo_height       = 0,         -- source pixel height for logo_path
    logo_overlay_id   = 43,        -- mpv overlay id reserved for the title logo
    hidetimeout       = 1800,      -- ms of pointer stillness before the OSC hides
    fadeduration      = 200,       -- ms fade in/out
    seek_precise      = true,      -- exact seeks from the seekbar (accurate, slower)
    jump_amount       = 10,        -- seconds for the skip-back / skip-forward buttons
}

--------------------------------------------------------------------------------
-- Design system (virtual units; mirrors Sources/App/DesignSystem.swift intent)
--------------------------------------------------------------------------------

local DS = {
    playresy      = 720,        -- virtual canvas height
    bar_height    = 46,         -- bottom control bar height
    bar_pad_x     = 20,         -- horizontal padding inside the bar
    seek_height   = 3,          -- seekbar track thickness
    seek_handle_r = 4,          -- seek handle radius
    row_gap       = 7,          -- gap between seekbar row and button row
    btn_size      = 20,         -- clickable button box (square)
    btn_gap       = 11,         -- gap between buttons
    time_size     = 13,         -- timecode font size
    control_size  = 13,         -- compact text-control font size
    now_title_size = 12,        -- small media title above the progress bar
    title_size    = 24,         -- top-bar title font size
    corner_r      = 3,          -- rounded-rect radius for the seekbar
    scrim_alpha   = 0x60,       -- bottom gradient scrim opacity (00=opaque)
    top_alpha     = 0x78,       -- top gradient scrim opacity
    track_alpha   = 0x40,       -- seekbar background track opacity
    buffer_alpha  = 0x74,       -- buffered range tint opacity
    buffer_hi_alpha = 0xA8,     -- buffered range inner highlight opacity
    top_height    = 68,         -- top bar height
    vol_slider_w  = 60,         -- compact volume slider width (shown on hover)
    font          = "Inter",    -- bundled UI font (Resources/mpv/fonts/Inter.ttf)
}

--------------------------------------------------------------------------------
-- Color helpers  (ASS uses &HBBGGRR& / alpha &HAA& where 00 = opaque)
--------------------------------------------------------------------------------

-- "#RRGGBB" -> "BBGGRR" for use inside \1c&H...&
local function hex_to_ass(hex)
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return "FFFFFF" end
    return b .. g .. r
end

local COL = {}
local function rebuild_colors()
    COL.accent = hex_to_ass(user_opts.accent_color)
    COL.gold   = hex_to_ass(user_opts.solar_gold_color)
    COL.red    = hex_to_ass(user_opts.solar_red_color)
    COL.white  = "FFFFFF"
    COL.track  = "FFFFFF"
    COL.black  = "000000"
end
rebuild_colors()

--------------------------------------------------------------------------------
-- Runtime state
--------------------------------------------------------------------------------

local state = {
    osd_w = 0, osd_h = 0,          -- real output pixel size
    scale = 1,                     -- virtual units per real pixel (playresy / osd_h)
    playresx = 1280,               -- virtual canvas width (aspect-adjusted)

    pause        = false,
    time_pos     = nil,
    duration     = nil,
    seekable     = false,
    speed        = 1.0,
    volume       = 100,
    volume_max   = 130,
    mute         = false,
    fullscreen   = false,
    window_maximized = false,
    title        = "",
    cache_ranges = {},             -- {{start=,stop=}, ...} buffered seconds (demuxer-cache-state)
    chapters     = {},             -- {{title=,time=}, ...}
    audio_tracks = {},             -- {{id,title,lang,codec,selected}, ...}
    sub_tracks   = {},
    queue_index  = 0,              -- zero-based index supplied by Solfin
    queue_count  = 1,
    menu         = { open = false, kind = nil, items = {}, scroll = 0 },  -- popup track/settings menu
    thumbfast    = nil,            -- {width,height,disabled,available} from thumbfast-info
    thumb_shown  = false,          -- whether we currently have a thumbnail requested
    logo_shown   = false,          -- whether the top-bar logo overlay is currently visible
    logo_draw    = nil,            -- last rendered logo geometry/path to avoid overlay spam

    mouse_x      = -1,             -- virtual coords, -1 when outside window
    mouse_y      = -1,
    mouse_down   = false,
    drag         = nil,            -- nil | "seek" | "volume" (active drag target)

    visible      = false,
    show_time    = 0,              -- mp.get_time() of last activity
    anim         = nil,            -- "in" | "out" | nil
    anim_start   = 0,
    opacity      = 0,              -- 0..1 current fade level

    hovered      = nil,            -- name of element under pointer
    tick_timer   = nil,
    tick_last    = 0,
    initialized  = false,
}

local overlay = mp.create_osd_overlay("ass-events")
local clear_thumb
local clear_logo

-- Hit-testable elements, rebuilt each layout pass: name -> {x1,y1,x2,y2}
local hitboxes = {}

--------------------------------------------------------------------------------
-- Geometry helpers
--------------------------------------------------------------------------------

local function update_scale()
    if state.osd_h and state.osd_h > 0 then
        state.scale = DS.playresy / state.osd_h
        state.playresx = state.osd_w * state.scale
    end
end

-- real pixel -> virtual
local function to_virt(px) return px * state.scale end
-- virtual -> real pixel
local function to_real(v)  return v / state.scale end

local function point_in(box, x, y)
    return box and x >= box.x1 and x <= box.x2 and y >= box.y1 and y <= box.y2
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

--------------------------------------------------------------------------------
-- Time formatting
--------------------------------------------------------------------------------

local function format_time(seconds)
    if not seconds then return "--:--" end
    seconds = math.floor(seconds + 0.5)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%02d:%02d", m, s)
end

--------------------------------------------------------------------------------
-- Visibility / fade
--------------------------------------------------------------------------------

local function request_tick()
    if not state.tick_timer then return end
    if not state.tick_timer:is_enabled() then
        state.tick_timer.timeout = 0
        state.tick_timer:resume()
    end
end

local function register_activity()
    state.show_time = mp.get_time()
    if not state.visible then
        state.visible = true
        if user_opts.fadeduration > 0 then
            state.anim = "in"
            state.anim_start = mp.get_time()
        else
            state.opacity = 1
        end
    end
    request_tick()
end

local function begin_hide()
    if not state.visible then return end
    clear_thumb()
    if user_opts.fadeduration > 0 then
        state.anim = "out"
        state.anim_start = mp.get_time()
    else
        state.visible = false
        state.opacity = 0
    end
    request_tick()
end

-- Advance the fade animation; returns true while still animating.
local function advance_opacity()
    if not state.anim then return false end
    local dur = user_opts.fadeduration / 1000
    local t = (mp.get_time() - state.anim_start) / dur
    if t >= 1 then
        if state.anim == "in" then
            state.opacity = 1
        else
            state.opacity = 0
            state.visible = false
        end
        state.anim = nil
        return false
    end
    state.opacity = (state.anim == "in") and t or (1 - t)
    return true
end

--------------------------------------------------------------------------------
-- Layout + render
--------------------------------------------------------------------------------

-- Build one ASS event header for a filled shape at (an7) origin.
local function shape_style(color, alpha)
    return string.format("{\\bord0\\shad0\\1c&H%s&\\1a&H%02X&}", color, alpha or 0)
end

local function seek_fraction()
    if not state.duration or state.duration <= 0 or not state.time_pos then return 0 end
    return clamp(state.time_pos / state.duration, 0, 1)
end

-- Title of the chapter containing time `t` (chapters are start times), or nil.
local function chapter_at(t)
    local title
    for _, c in ipairs(state.chapters) do
        if c.time <= t then title = c.title else break end
    end
    return title
end

-- Rough text width in virtual units (no font metrics available in ASS).
local function estimate_text_width(text, size)
    return #tostring(text) * size * 0.52
end

local function logo_available()
    return user_opts.logo_path ~= "" and user_opts.logo_width > 0 and user_opts.logo_height > 0
end

local function logo_virtual_size(max_w, max_h)
    local lw, lh = user_opts.logo_width, user_opts.logo_height
    local scale = math.min(max_w / lw, max_h / lh, 1)
    return lw * scale, lh * scale
end

clear_logo = function()
    if state.logo_shown then
        mp.command_native_async({"overlay-remove", user_opts.logo_overlay_id}, function() end)
        state.logo_shown = false
        state.logo_draw = nil
    end
end

local function render_logo(x, y, w, h)
    if not logo_available() then
        clear_logo()
        return
    end
    local draw = {
        path = user_opts.logo_path,
        x = math.floor(to_real(x)),
        y = math.floor(to_real(y)),
        w = math.floor(to_real(w)),
        h = math.floor(to_real(h)),
        src_w = user_opts.logo_width,
        src_h = user_opts.logo_height,
    }
    local prev = state.logo_draw
    if prev and prev.path == draw.path and prev.x == draw.x and prev.y == draw.y
       and prev.w == draw.w and prev.h == draw.h
       and prev.src_w == draw.src_w and prev.src_h == draw.src_h then
        return
    end
    mp.command_native_async({"overlay-add", user_opts.logo_overlay_id,
                             draw.x, draw.y,
                             draw.path, 0, "bgra",
                             draw.src_w, draw.src_h,
                             draw.src_w * 4,
                             draw.w, draw.h}, function() end)
    state.logo_shown = true
    state.logo_draw = draw
end

-- Vertical gradient scrim built from stacked bands (ASS has no native gradient).
local function draw_scrim(ass, W, y_top, y_bot, max_alpha, alpha_fn)
    local bands = 14
    local h = (y_bot - y_top) / bands
    for i = 0, bands - 1 do
        -- 0 at top (fully transparent) -> 1 at bottom
        local frac = (i + 1) / bands
        local band_alpha = math.floor(0xFF - (0xFF - max_alpha) * frac)
        ass:new_event()
        ass:append(shape_style(COL.black, alpha_fn(band_alpha)))
        ass:pos(0, 0)
        ass:draw_start()
        ass:rect_cw(0, y_top + i * h, W, y_top + (i + 1) * h + 1)
        ass:draw_stop()
    end
end

-- Seek to the fraction under the given virtual x within the seekbar box.
local function seekbar_fraction_at(x)
    local box = hitboxes.seekbar
    if not box then return nil end
    return clamp((x - box.x1) / (box.x2 - box.x1), 0, 1)
end

--------------------------------------------------------------------------------
-- Icon glyphs (vector; slim SF/VLC-inspired controls)
--------------------------------------------------------------------------------

local stroked_icon_style

local function icon_subtitle(ass, cx, cy, color, ab)
    ass:new_event()
    ass:append(stroked_icon_style(color, ab, 1.6))
    ass:pos(cx, cy)
    ass:draw_start()
    ass:round_rect_cw(-10, -7, 10, 7, 2.5)
    ass:move_to(-6, 1); ass:line_to(-1, 1)
    ass:move_to(3, 1);  ass:line_to(7, 1)
    ass:move_to(-6, 5); ass:line_to(6, 5)
    ass:draw_stop()
end

-- Volume speaker; shows mute/level state.
local function icon_volume(ass, cx, cy, color, ab, muted, level)
    ass:new_event()
    ass:append(stroked_icon_style(color, ab, 1.6))
    ass:pos(cx, cy)
    ass:draw_start()
    ass:move_to(-7, -3); ass:line_to(-4, -3); ass:line_to(0, -6)
    ass:line_to(0, 6);   ass:line_to(-4, 3);  ass:line_to(-7, 3); ass:line_to(-7, -3)
    ass:draw_stop()
    ass:new_event()
    ass:append(stroked_icon_style(color, ab, 1.4))
    ass:pos(cx, cy)
    ass:draw_start()
    if muted or (level and level <= 0) then
        ass:move_to(4, -4); ass:line_to(10, 4); ass:move_to(10, -4); ass:line_to(4, 4)
    else
        if not level or level > 0 then
            ass:move_to(4, -3); ass:line_to(4, 3)
        end
        if not level or level > 45 then
            ass:move_to(8, -5); ass:line_to(8, 5)
        end
    end
    ass:draw_stop()
end

-- Audio-track selection: compact sliders icon, clearer than a large music note.
local function icon_tracks(ass, cx, cy, color, ab)
    ass:new_event()
    ass:append(stroked_icon_style(color, ab, 1.7))
    ass:pos(cx, cy)
    ass:draw_start()
    ass:move_to(-10, -6); ass:line_to(10, -6)
    ass:move_to(-10, 0);  ass:line_to(10, 0)
    ass:move_to(-10, 6);  ass:line_to(10, 6)
    ass:draw_stop()
    ass:new_event()
    ass:append(shape_style(color, ab))
    ass:pos(cx, cy)
    ass:draw_start()
    ass:round_rect_cw(-5, -9, -1, -3, 2)
    ass:round_rect_cw(3, -3, 7, 3, 2)
    ass:round_rect_cw(-8, 3, -4, 9, 2)
    ass:draw_stop()
end

function stroked_icon_style(color, ab, width)
    return string.format("{\\bord%.1f\\shad0\\3c&H%s&\\3a&H%02X&\\1a&HFF&}", width or 1.8, color, ab)
end

local function icon_fullscreen(ass, cx, cy, color, ab, is_fs)
    ass:new_event()
    ass:append(stroked_icon_style(color, ab, 1.5))
    ass:pos(cx, cy)
    ass:draw_start()
    if is_fs then
        -- Leave fullscreen: inward corners.
        ass:move_to(-7, -2); ass:line_to(-2, -2); ass:line_to(-2, -7)
        ass:move_to(7, -2);  ass:line_to(2, -2);  ass:line_to(2, -7)
        ass:move_to(-7, 2);  ass:line_to(-2, 2);  ass:line_to(-2, 7)
        ass:move_to(7, 2);   ass:line_to(2, 2);   ass:line_to(2, 7)
    else
        -- Enter fullscreen: simple outward corners.
        ass:move_to(-7, -2); ass:line_to(-7, -7); ass:line_to(-2, -7)
        ass:move_to(7, -2);  ass:line_to(7, -7);  ass:line_to(2, -7)
        ass:move_to(-7, 2);  ass:line_to(-7, 7);  ass:line_to(-2, 7)
        ass:move_to(7, 2);   ass:line_to(7, 7);   ass:line_to(2, 7)
    end
    ass:draw_stop()
end

local function icon_minimize(ass, cx, cy, color, ab)
    ass:new_event()
    ass:append(stroked_icon_style(color, ab, 1.35))
    ass:pos(cx, cy)
    ass:draw_start()
    ass:move_to(-5, 4); ass:line_to(5, 4)
    ass:draw_stop()
end

local function icon_window(ass, cx, cy, color, ab, restore)
    ass:new_event()
    ass:append(stroked_icon_style(color, ab, 1.35))
    ass:pos(cx, cy)
    ass:draw_start()
    if restore then
        ass:rect_cw(-2.5, -6, 5.5, 2)
        ass:rect_cw(-5.5, -2, 2.5, 6)
    else
        ass:rect_cw(-5.5, -5.5, 5.5, 5.5)
    end
    ass:draw_stop()
end

local function icon_solar_mark(ass, cx, cy, radius, alpha_fn, hot)
    -- Small Solfin signature: a warm sun tucked into the progress track.
    -- Layered circles fake a radial glow with ASS primitives.
    local glow_alpha = hot and 0xA8 or 0xC4
    local mid_alpha = hot and 0x48 or 0x64

    ass:new_event()
    ass:append(shape_style(COL.gold, alpha_fn(glow_alpha)))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(cx - radius * 2.1, cy - radius * 2.1,
                      cx + radius * 2.1, cy + radius * 2.1, radius * 2.1)
    ass:draw_stop()

    ass:new_event()
    ass:append(shape_style(COL.accent, alpha_fn(mid_alpha)))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(cx - radius * 1.35, cy - radius * 1.35,
                      cx + radius * 1.35, cy + radius * 1.35, radius * 1.35)
    ass:draw_stop()

    ass:new_event()
    ass:append(shape_style(hot and COL.red or COL.gold, alpha_fn(0)))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(cx - radius, cy - radius, cx + radius, cy + radius, radius)
    ass:draw_stop()

    ass:new_event()
    ass:append(shape_style(COL.gold, alpha_fn(hot and 0x18 or 0x28)))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(cx - radius * 0.42, cy - radius * 0.42,
                      cx + radius * 0.42, cy + radius * 0.42, radius * 0.42)
    ass:draw_stop()
end

local function icon_close(ass, cx, cy, color, ab)
    ass:new_event()
    ass:append(string.format("{\\bord1.8\\shad0\\3c&H%s&\\3a&H%02X&\\1a&HFF&}", color, ab))
    ass:pos(cx, cy)
    ass:draw_start()
    ass:move_to(-7, -7); ass:line_to(7, 7); ass:move_to(7, -7); ass:line_to(-7, 7)
    ass:draw_stop()
end

local function icon_queue_prev_next(ass, cx, cy, color, ab, forward)
    ass:new_event()
    ass:append(shape_style(color, ab))
    ass:pos(cx, cy)
    ass:draw_start()
    if forward then
        -- >>| : two play chevrons plus a stop bar. Keep the bar close to,
        -- but not overlapping, the chevrons so disabled/alpha rendering stays crisp.
        ass:move_to(-10, -7); ass:line_to(-3, 0); ass:line_to(-10, 7); ass:line_to(-10, -7)
        ass:move_to(-2, -7);  ass:line_to(5, 0);  ass:line_to(-2, 7);  ass:line_to(-2, -7)
        ass:rect_cw(7, -7, 9, 7)
    else
        -- |<< : mirror of the forward icon with matching non-overlapping spacing.
        ass:rect_cw(-9, -7, -7, 7)
        ass:move_to(2, -7);  ass:line_to(-5, 0); ass:line_to(2, 7);  ass:line_to(2, -7)
        ass:move_to(10, -7); ass:line_to(3, 0);  ass:line_to(10, 7); ass:line_to(10, -7)
    end
    ass:draw_stop()
end

--------------------------------------------------------------------------------
-- Popup menu
--------------------------------------------------------------------------------

local MENU = { row_h = 34, pad = 8, width = 320, title_h = 32, scroll_h = 28, top_margin = 76 }

local function track_label(tr)
    local parts = {}
    if tr.lang and #tr.lang > 0 then parts[#parts + 1] = tr.lang:upper() end
    if tr.title and #tr.title > 0 then parts[#parts + 1] = tr.title
    elseif tr.codec and #tr.codec > 0 then parts[#parts + 1] = tr.codec end
    local s = table.concat(parts, "  ·  ")
    if #s == 0 then s = "Track " .. tostring(tr.id) end
    return s
end

local SPEEDS = { 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0 }

-- "1×", "1.5×", "0.5×"
local function speed_text(v)
    if math.abs(v - math.floor(v)) < 0.001 then
        return string.format("%d×", math.floor(v))
    end
    local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
    return s .. "×"
end

local function build_menu_items(kind)
    local items = {}
    if kind == "speed" then
        for _, v in ipairs(SPEEDS) do
            items[#items + 1] = {
                label = speed_text(v) .. (v == 1.0 and "   Normal" or ""),
                selected = math.abs(state.speed - v) < 0.01,
                apply = function() mp.set_property_number("speed", v) end,
            }
        end
    elseif kind == "audio" then
        for _, tr in ipairs(state.audio_tracks) do
            items[#items + 1] = { label = track_label(tr), selected = tr.selected,
                apply = function() mp.set_property_number("aid", tr.id) end }
        end
    elseif kind == "subtitle" then
        local none = true
        for _, tr in ipairs(state.sub_tracks) do if tr.selected then none = false end end
        items[#items + 1] = { label = "Off", selected = none,
            apply = function() mp.set_property("sid", "no") end }
        for _, tr in ipairs(state.sub_tracks) do
            items[#items + 1] = { label = track_label(tr), selected = tr.selected,
                apply = function() mp.set_property_number("sid", tr.id) end }
        end
    end
    return items
end

local MENU_TITLES = { audio = "Audio", subtitle = "Subtitles", speed = "Playback speed" }

local function render_menu(ass, a, W, bar_top)
    if not state.menu.open then hitboxes.menu_area = nil; return end
    local items = build_menu_items(state.menu.kind)
    state.menu.items = items
    if #items == 0 then return end

    local mw = MENU.width
    local max_content_h = math.max(MENU.row_h, bar_top - MENU.top_margin - MENU.title_h - MENU.pad)
    local visible_count = math.max(1, math.min(#items, math.floor(max_content_h / MENU.row_h)))
    local can_scroll = #items > visible_count
    state.menu.scroll = clamp(state.menu.scroll or 0, 0, math.max(0, #items - visible_count))
    state.menu.visible_start = state.menu.scroll + 1
    state.menu.visible_count = visible_count

    local mh = MENU.title_h + visible_count * MENU.row_h + MENU.pad + (can_scroll and MENU.scroll_h or 0)
    local anchor = hitboxes[state.menu.kind]
    local ax = anchor and (anchor.x1 + anchor.x2) / 2 or (W - 160)
    local mx1 = clamp(ax - mw / 2, DS.bar_pad_x, W - DS.bar_pad_x - mw)
    local my2 = bar_top - 12
    local my1 = my2 - mh
    hitboxes.menu_area = { x1 = mx1, y1 = my1, x2 = mx1 + mw, y2 = my2 }

    -- Panel background
    ass:new_event()
    ass:append(shape_style(COL.black, a(0x14)))
    ass:pos(0, 0)
    ass:draw_start(); ass:round_rect_cw(mx1, my1, mx1 + mw, my2, 12); ass:draw_stop()

    -- Title
    ass:new_event()
    ass:append(string.format("{\\an4\\fs20\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                             DS.font, COL.white, a(0x30)))
    ass:pos(mx1 + 18, my1 + MENU.title_h / 2 + 2)
    ass:append(MENU_TITLES[state.menu.kind] or "")

    if can_scroll then
        local count_text = string.format("%d–%d / %d", state.menu.visible_start,
                                         state.menu.visible_start + visible_count - 1, #items)
        ass:new_event()
        ass:append(string.format("{\\an6\\fs15\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                                 DS.font, COL.white, a(0x70)))
        ass:pos(mx1 + mw - 18, my1 + MENU.title_h / 2 + 2)
        ass:append(count_text)
    end

    -- Rows
    for visual = 1, visible_count do
        local i = state.menu.visible_start + visual - 1
        local item = items[i]
        local ry1 = my1 + MENU.title_h + (visual - 1) * MENU.row_h
        local ry2 = ry1 + MENU.row_h
        hitboxes["menu_row_" .. visual] = { x1 = mx1, y1 = ry1, x2 = mx1 + mw, y2 = ry2, item_index = i }
        local hovered = (state.hovered == "menu_row_" .. visual)

        if hovered then
            ass:new_event()
            ass:append(shape_style(COL.white, a(0xC4)))
            ass:pos(0, 0)
            ass:draw_start()
            ass:round_rect_cw(mx1 + 6, ry1 + 3, mx1 + mw - 6, ry2 - 3, 8)
            ass:draw_stop()
        end

        -- Selected dot
        if item.selected then
            ass:new_event()
            ass:append(shape_style(COL.accent, a(0)))
            ass:pos(mx1 + 22, (ry1 + ry2) / 2)
            ass:draw_start(); ass:round_rect_cw(-4, -4, 4, 4, 4); ass:draw_stop()
        end

        -- Label
        local lcol = item.selected and COL.accent or COL.white
        ass:new_event()
        ass:append(string.format("{\\an4\\fs18\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                                 DS.font, lcol, a(0)))
        ass:pos(mx1 + 40, (ry1 + ry2) / 2)
        ass:append(item.label)
    end

    if can_scroll then
        local sy1, sy2 = my2 - MENU.scroll_h, my2
        local half = mw / 2
        hitboxes.menu_scroll_up = { x1 = mx1, y1 = sy1, x2 = mx1 + half, y2 = sy2 }
        hitboxes.menu_scroll_down = { x1 = mx1 + half, y1 = sy1, x2 = mx1 + mw, y2 = sy2 }

        ass:new_event()
        ass:append(shape_style(COL.white, a(0xDD)))
        ass:pos(0, 0)
        ass:draw_start(); ass:rect_cw(mx1 + 10, sy1, mx1 + mw - 10, sy1 + 1); ass:draw_stop()

        local up_col = state.menu.scroll > 0 and COL.white or COL.track
        local down_col = state.menu.scroll < (#items - visible_count) and COL.white or COL.track
        if state.hovered == "menu_scroll_up" and state.menu.scroll > 0 then up_col = COL.accent end
        if state.hovered == "menu_scroll_down" and state.menu.scroll < (#items - visible_count) then down_col = COL.accent end

        ass:new_event()
        ass:append(string.format("{\\an5\\fs18\\b1\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                                 DS.font, up_col, a(0)))
        ass:pos(mx1 + mw * 0.25, sy1 + MENU.scroll_h / 2 + 1)
        ass:append("▲")

        ass:new_event()
        ass:append(string.format("{\\an5\\fs18\\b1\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                                 DS.font, down_col, a(0)))
        ass:pos(mx1 + mw * 0.75, sy1 + MENU.scroll_h / 2 + 1)
        ass:append("▼")
    else
        hitboxes.menu_scroll_up, hitboxes.menu_scroll_down = nil, nil
    end
end

local function open_menu(kind)
    if state.menu.open and state.menu.kind == kind then
        state.menu.open = false
    else
        state.menu.open, state.menu.kind = true, kind
        state.menu.scroll = 0
    end
    register_activity()
    request_tick()
end

local function close_menu()
    if state.menu.open then state.menu.open = false; request_tick() end
end

--------------------------------------------------------------------------------
-- thumbfast integration (companion script draws the actual thumbnail overlay)
--------------------------------------------------------------------------------

local function thumb_usable()
    local tf = state.thumbfast
    return tf and tf.available and not tf.disabled and tf.width and tf.width > 0
end

local function thumb_virtual_size()
    local tf = state.thumbfast
    if not tf then return 0, 0 end
    -- thumbfast-info dimensions are already display dimensions (scale_factor applied).
    return (tf.width or 0) * state.scale, (tf.height or 0) * state.scale
end

local function request_thumb(time, x_v, top_v)
    local rx = math.floor(to_real(x_v) + 0.5)
    local ry = math.floor(to_real(top_v) + 0.5)
    -- Do not pass our script name here. With explicit x/y coordinates thumbfast draws
    -- using mpv's overlay API itself; if a script name is also supplied, thumbfast's
    -- clear() path assumes an external renderer owns the image and skips overlay-remove.
    mp.commandv("script-message-to", "thumbfast", "thumb",
                tostring(time), tostring(rx), tostring(ry))
    state.thumb_shown = true
end

clear_thumb = function()
    if state.thumb_shown then
        mp.commandv("script-message-to", "thumbfast", "clear")
        state.thumb_shown = false
    end
end

local function render()
    hitboxes = {}
    local ass = assdraw.ass_new()

    local W, H = state.playresx, DS.playresy
    local alpha_mul = state.opacity            -- 0..1
    if alpha_mul <= 0 then
        clear_thumb()
        clear_logo()
        overlay.data = ""
        overlay:update()
        return
    end
    -- Convert opacity to an ASS alpha byte (00 opaque .. FF transparent).
    local function a(base) return math.floor(base + (0xFF - base) * (1 - alpha_mul)) end

    local bar_top = H - DS.bar_height

    ----------------------------------------------------------------------------
    -- Bottom gradient scrim
    ----------------------------------------------------------------------------
    draw_scrim(ass, W, bar_top - 56, H, DS.scrim_alpha, a)

    ----------------------------------------------------------------------------
    -- Top bar: title + window controls (top scrim fades downward)
    ----------------------------------------------------------------------------
    do
        local bands = 12
        local h = DS.top_height / bands
        for i = 0, bands - 1 do
            local frac = (i + 1) / bands            -- 0 opaque at top .. 1 transparent at bottom
            local band_alpha = math.floor(DS.top_alpha + (0xFF - DS.top_alpha) * frac)
            ass:new_event()
            ass:append(shape_style(COL.black, a(band_alpha)))
            ass:pos(0, 0)
            ass:draw_start(); ass:rect_cw(0, i * h, W, (i + 1) * h + 1); ass:draw_stop()
        end
        local top_y = DS.top_height / 2
        if logo_available() then
            local lw, lh = logo_virtual_size(math.min(W * 0.42, 420), 42)
            render_logo(DS.bar_pad_x, top_y - lh / 2 - 1, lw, lh)
        elseif state.title and #state.title > 0 then
            clear_logo()
            ass:new_event()
            ass:append(string.format("{\\an4\\fs%d\\b1\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                                     DS.title_size, DS.font, COL.white, a(0)))
            ass:pos(DS.bar_pad_x, top_y - 2)
            ass:append(state.title)
        else
            clear_logo()
        end
        local clx = W - DS.bar_pad_x - DS.btn_size / 2
        local maxx = clx - 28
        local minx = maxx - 28
        local top_hit = DS.btn_size / 2 + 3
        hitboxes.close = { x1 = clx - top_hit, y1 = top_y - top_hit, x2 = clx + top_hit, y2 = top_y + top_hit }
        hitboxes.maximize = { x1 = maxx - top_hit, y1 = top_y - top_hit, x2 = maxx + top_hit, y2 = top_y + top_hit }
        hitboxes.minimize = { x1 = minx - top_hit, y1 = top_y - top_hit, x2 = minx + top_hit, y2 = top_y + top_hit }
        icon_minimize(ass, minx, top_y,
                      (state.hovered == "minimize") and COL.accent or COL.white, a(0))
        icon_window(ass, maxx, top_y,
                    (state.hovered == "maximize") and COL.accent or COL.white, a(0),
                    state.window_maximized)
        icon_close(ass, clx, top_y,
                   (state.hovered == "close") and COL.accent or COL.white, a(0))
    end

    ----------------------------------------------------------------------------
    -- Seekbar row
    ----------------------------------------------------------------------------
    local sb_x1 = DS.bar_pad_x
    local sb_x2 = W - DS.bar_pad_x
    local sb_w  = sb_x2 - sb_x1
    local sb_y  = H - 30
    local sb_hh = DS.seek_height / 2
    hitboxes.seekbar = { x1 = sb_x1, y1 = sb_y - 12, x2 = sb_x2, y2 = sb_y + 12 }

    local dur = (state.duration and state.duration > 0) and state.duration or nil

    -- Small now-playing identity directly above the progress bar. For episodes this
    -- is the forced media title from Swift: “Series · S1E2 · Episode Name”. Movies
    -- use their media name. Clipped to the seekbar width so it never hits controls.
    if state.title and #state.title > 0 then
        ass:new_event()
        ass:append(string.format("{\\an1\\fs%d\\b1\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&\\clip(%d,%d,%d,%d)}",
                                 DS.now_title_size, DS.font, COL.white, a(0x24),
                                 math.floor(sb_x1), math.floor(sb_y - 28), math.floor(sb_x2), math.floor(sb_y - 8)))
        ass:pos(sb_x1, sb_y - 14)
        ass:append(state.title)
    end

    local function time_to_x(t)
        if not dur then return sb_x1 end
        return sb_x1 + sb_w * clamp(t / dur, 0, 1)
    end

    -- Track background
    ass:new_event()
    ass:append(shape_style(COL.track, a(DS.track_alpha)))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(sb_x1, sb_y - sb_hh, sb_x2, sb_y + sb_hh, DS.corner_r)
    ass:draw_stop()

    -- Buffered (cached) ranges: a subtle accent wash plus a soft white core keeps
    -- cache state readable over dark scenes without competing with played progress.
    if dur then
        for _, r in ipairs(state.cache_ranges) do
            local rx1, rx2 = time_to_x(r.start), time_to_x(r.stop)
            if rx2 - rx1 >= 1 then
                ass:new_event()
                ass:append(shape_style(COL.accent, a(DS.buffer_alpha)))
                ass:pos(0, 0)
                ass:draw_start()
                ass:rect_cw(rx1, sb_y - sb_hh - 1, rx2, sb_y + sb_hh + 1)
                ass:draw_stop()

                ass:new_event()
                ass:append(shape_style(COL.white, a(DS.buffer_hi_alpha)))
                ass:pos(0, 0)
                ass:draw_start()
                ass:rect_cw(rx1, sb_y - sb_hh, rx2, sb_y + sb_hh)
                ass:draw_stop()
            end
        end
    end

    -- Progress fill
    local frac = (state.drag == "seek") and (seekbar_fraction_at(state.mouse_x) or seek_fraction()) or seek_fraction()
    local fill_x = sb_x1 + sb_w * frac
    ass:new_event()
    ass:append(shape_style(COL.accent, a(0)))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(sb_x1, sb_y - sb_hh, fill_x, sb_y + sb_hh, DS.corner_r)
    ass:draw_stop()

    -- Solar signature at the live edge of playback: replaces the old blue-only feel
    -- with Solfin's sun motif while staying tiny enough not to fight thumbnails/chapters.
    if dur and frac > 0.006 then
        icon_solar_mark(ass, fill_x, sb_y, 3.2, a, state.hovered == "seekbar" or state.drag == "seek")
    end

    -- Chapter ticks
    if dur and #state.chapters > 1 then
        for _, c in ipairs(state.chapters) do
            if c.time > 0 and c.time < dur then
                local cx = time_to_x(c.time)
                ass:new_event()
                ass:append(shape_style(COL.black, a(0x40)))
                ass:pos(0, 0)
                ass:draw_start()
                ass:rect_cw(cx - 1, sb_y - sb_hh, cx + 1, sb_y + sb_hh)
                ass:draw_stop()
            end
        end
    end

    -- Handle (shown on hover/drag)
    if state.hovered == "seekbar" or state.drag == "seek" then
        ass:new_event()
        ass:append(shape_style(COL.accent, a(0)))
        ass:pos(0, 0)
        ass:draw_start()
        ass:round_rect_cw(fill_x - DS.seek_handle_r, sb_y - DS.seek_handle_r,
                          fill_x + DS.seek_handle_r, sb_y + DS.seek_handle_r, DS.seek_handle_r)
        ass:draw_stop()
    end

    -- Hover tooltip: thumbnail + time (+ chapter name) at the cursor position
    if dur and (state.hovered == "seekbar" or state.drag == "seek") and state.mouse_x >= 0 then
        local hx = clamp(state.mouse_x, sb_x1, sb_x2)
        local ht = clamp((hx - sb_x1) / sb_w, 0, 1) * dur
        local label = format_time(ht)
        local chap = chapter_at(ht)
        if chap and #chap > 0 then label = label .. "  ·  " .. chap end

        local pad = 10
        local fs = 18
        local tw = estimate_text_width(label, fs) + pad * 2
        local th = fs + pad
        local tx = clamp(hx, sb_x1 + tw / 2, sb_x2 - tw / 2)
        local ty = sb_y - 22 - th

        -- Thumbnail frame above the pill (thumbfast overlays the image on top).
        if thumb_usable() then
            local tf = state.thumbfast
            local border = 3
            local tw_v, th_v = thumb_virtual_size()
            local cx_v = clamp(hx, sb_x1 + tw_v / 2 + border, sb_x2 - tw_v / 2 - border)
            local fb = ty - 8                       -- frame bottom
            local ft = fb - th_v - border * 2       -- frame top
            local fx1 = cx_v - tw_v / 2 - border

            ass:new_event()
            ass:append(string.format("{\\bord%d\\shad0\\1c&H%s&\\1a&H%02X&\\3c&H%s&\\3a&H%02X&}",
                                     2, COL.black, a(0x10), COL.white, a(0x80)))
            ass:pos(0, 0)
            ass:draw_start()
            ass:round_rect_cw(fx1, ft, fx1 + tw_v + border * 2, fb, 8)
            ass:draw_stop()

            request_thumb(ht, cx_v - tw_v / 2, ft + border)
        else
            clear_thumb()
        end

        ass:new_event()
        ass:append(shape_style(COL.black, a(0x20)))
        ass:pos(0, 0)
        ass:draw_start()
        ass:round_rect_cw(tx - tw / 2, ty, tx + tw / 2, ty + th, 5)
        ass:draw_stop()

        ass:new_event()
        ass:append(string.format("{\\an5\\fs%d\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                                 fs, DS.font, COL.white, a(0)))
        ass:pos(tx, ty + th / 2)
        ass:append(label)
    else
        clear_thumb()
    end

    ----------------------------------------------------------------------------
    -- Button row (play/pause + jump) and timecodes
    ----------------------------------------------------------------------------
    local row_y = H - 13
    local cx = DS.bar_pad_x + DS.btn_size / 2

    -- Skip-back
    local function place_button(name)
        local box = { x1 = cx - DS.btn_size / 2, y1 = row_y - DS.btn_size / 2,
                      x2 = cx + DS.btn_size / 2, y2 = row_y + DS.btn_size / 2 }
        hitboxes[name] = box
        return box
    end

    local col_for = function(name)
        return (state.hovered == name) and COL.accent or COL.white
    end

    -- Previous queued item. Disabled when there is no previous episode.
    place_button("prev")
    local prev_enabled = state.queue_index > 0 or ((state.time_pos or 0) > 5)
    icon_queue_prev_next(ass, cx, row_y,
                         prev_enabled and col_for("prev") or COL.track,
                         a(prev_enabled and 0 or 0x86), false)

    cx = cx + DS.btn_size + DS.btn_gap

    -- Skip back: text is cleaner and more legible than tiny custom vector arrows.
    place_button("skip_back")
    ass:new_event()
    ass:append(string.format("{\\an5\\fs%d\\b1\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                             DS.control_size, DS.font, col_for("skip_back"), a(0)))
    ass:pos(cx, row_y)
    ass:append("−" .. tostring(user_opts.jump_amount))

    cx = cx + DS.btn_size + DS.btn_gap

    -- Play / pause
    place_button("playpause")
    ass:new_event()
    ass:append(shape_style(col_for("playpause"), a(0)))
    ass:pos(cx, row_y)
    ass:draw_start()
    if state.pause then
        local s = DS.btn_size * 0.34
        ass:move_to(-s * 0.62, -s); ass:line_to(s * 0.85, 0); ass:line_to(-s * 0.62, s)
    else
        local s = DS.btn_size * 0.34
        local bw = s * 0.45
        ass:rect_cw(-s * 0.75, -s, -s * 0.75 + bw, s)
        ass:rect_cw(s * 0.75 - bw, -s, s * 0.75, s)
    end
    ass:draw_stop()

    cx = cx + DS.btn_size + DS.btn_gap

    -- Skip forward
    place_button("skip_fwd")
    ass:new_event()
    ass:append(string.format("{\\an5\\fs%d\\b1\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                             DS.control_size, DS.font, col_for("skip_fwd"), a(0)))
    ass:pos(cx, row_y)
    ass:append("+" .. tostring(user_opts.jump_amount))

    cx = cx + DS.btn_size + DS.btn_gap

    -- Next queued item. Disabled when this is the end of the queue.
    place_button("next")
    local has_next = state.queue_index + 1 < state.queue_count
    icon_queue_prev_next(ass, cx, row_y,
                         has_next and col_for("next") or COL.track,
                         a(has_next and 0 or 0x86), true)

    -- Timecodes (position / duration), left cluster
    local pos_txt = format_time(state.time_pos)
    local dur_txt = format_time(state.duration)
    ass:new_event()
    ass:append(string.format("{\\an4\\fs%d\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                             DS.time_size, DS.font, COL.white, a(0)))
    ass:pos(cx + DS.btn_size / 2 + 14, row_y)
    ass:append(pos_txt .. "  /  " .. dur_txt)

    -- Right cluster (right → left): fullscreen, media info, volume(+slider), subtitle, tracks, speed
    local function place_at(name, bx)
        hitboxes[name] = { x1 = bx - DS.btn_size / 2, y1 = row_y - DS.btn_size / 2,
                           x2 = bx + DS.btn_size / 2, y2 = row_y + DS.btn_size / 2 }
    end
    local function menu_col(name)
        return (state.hovered == name or (state.menu.open and state.menu.kind == name))
               and COL.accent or COL.white
    end
    local rx = W - DS.bar_pad_x - DS.btn_size / 2

    -- Fullscreen (rightmost)
    place_at("fullscreen", rx)
    icon_fullscreen(ass, rx, row_y,
                    (state.hovered == "fullscreen") and COL.accent or COL.white, a(0), state.fullscreen)
    rx = rx - (DS.btn_size + DS.btn_gap)

    -- Media info toggle
    place_at("media_info", rx)
    ass:new_event()
    ass:append(string.format("{\\an5\\fs%d\\b1\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                             DS.control_size, DS.font,
                             (state.hovered == "media_info") and COL.accent or COL.white, a(0)))
    ass:pos(rx, row_y)
    ass:append("i")
    rx = rx - (DS.btn_size + DS.btn_gap)

    -- Volume speaker
    place_at("volume", rx)
    local vhover = (state.hovered == "volume" or state.hovered == "volslider" or state.drag == "volume")
    icon_volume(ass, rx, row_y, vhover and COL.accent or COL.white, a(0),
                state.mute, state.mute and 0 or state.volume)

    -- Volume slider (to the left of the speaker)
    local vs_y  = row_y
    local vs_x2 = rx - DS.btn_size / 2 - 8
    local vs_x1 = vs_x2 - DS.vol_slider_w
    hitboxes.volslider = { x1 = vs_x1, y1 = vs_y - 10, x2 = vs_x2, y2 = vs_y + 10 }
    local vfrac = state.mute and 0 or clamp(state.volume / 100, 0, 1)
    local vfx = vs_x1 + (vs_x2 - vs_x1) * vfrac
    ass:new_event()
    ass:append(shape_style(COL.white, a(DS.track_alpha)))
    ass:pos(0, 0); ass:draw_start(); ass:round_rect_cw(vs_x1, vs_y - 2, vs_x2, vs_y + 2, 2); ass:draw_stop()
    ass:new_event()
    ass:append(shape_style(COL.accent, a(0)))
    ass:pos(0, 0); ass:draw_start(); ass:round_rect_cw(vs_x1, vs_y - 2, vfx, vs_y + 2, 2); ass:draw_stop()
    if vhover then
        ass:new_event()
        ass:append(shape_style(COL.accent, a(0)))
        ass:pos(0, 0); ass:draw_start(); ass:round_rect_cw(vfx - 5, vs_y - 5, vfx + 5, vs_y + 5, 5); ass:draw_stop()
    end
    rx = vs_x1 - DS.btn_gap - DS.btn_size / 2

    -- Subtitles: compact CC label avoids ambiguous glyphs.
    place_at("subtitle", rx)
    ass:new_event()
    ass:append(string.format("{\\an5\\fs%d\\b1\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                             DS.control_size, DS.font, menu_col("subtitle"), a(0)))
    ass:pos(rx, row_y)
    ass:append("CC")
    rx = rx - (DS.btn_size + DS.btn_gap)

    -- Audio tracks: compact language/audio label instead of a decorative icon.
    place_at("audio", rx)
    ass:new_event()
    ass:append(string.format("{\\an5\\fs%d\\b1\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                             DS.control_size, DS.font, menu_col("audio"), a(0)))
    ass:pos(rx, row_y)
    ass:append("A")
    rx = rx - (DS.btn_size + DS.btn_gap)

    -- Speed (text pill; accent when not 1× or hovered/open)
    local sp_w = 54
    hitboxes.speed = { x1 = rx - sp_w / 2, y1 = row_y - DS.btn_size / 2,
                       x2 = rx + sp_w / 2, y2 = row_y + DS.btn_size / 2 }
    local spcol = (state.hovered == "speed" or (state.menu.open and state.menu.kind == "speed")
                   or math.abs(state.speed - 1.0) > 0.01) and COL.accent or COL.white
    ass:new_event()
    ass:append(string.format("{\\an5\\fs%d\\bord0\\shad0\\fn%s\\1c&H%s&\\1a&H%02X&}",
                             DS.control_size, DS.font, spcol, a(0)))
    ass:pos(rx, row_y)
    ass:append(speed_text(state.speed))

    -- Popup menu (drawn last so it sits above the bar)
    render_menu(ass, a, W, bar_top)

    overlay.res_x = math.floor(W)
    overlay.res_y = H
    overlay.data = ass.text
    overlay:update()
end

--------------------------------------------------------------------------------
-- Hover / hit resolution
--------------------------------------------------------------------------------

local function resolve_hover()
    local x, y = state.mouse_x, state.mouse_y
    local prev = state.hovered
    state.hovered = nil
    local names = {}
    -- Menu controls/rows take precedence when the popup is open.
    if state.menu.open and state.menu.items then
        names[#names + 1] = "menu_scroll_up"
        names[#names + 1] = "menu_scroll_down"
        local visible_count = state.menu.visible_count or #state.menu.items
        for i = 1, visible_count do names[#names + 1] = "menu_row_" .. i end
    end
    for _, n in ipairs({ "close", "maximize", "minimize", "playpause", "prev", "skip_back", "skip_fwd", "next", "speed", "audio",
                         "subtitle", "media_info", "fullscreen", "volume", "volslider", "seekbar" }) do
        names[#names + 1] = n
    end
    for _, name in ipairs(names) do
        if point_in(hitboxes[name], x, y) then
            state.hovered = name
            break
        end
    end
    if state.hovered ~= prev then
        if prev == "seekbar" and state.hovered ~= "seekbar" and state.drag ~= "seek" then
            clear_thumb()
        end
        request_tick()
    end
end

--------------------------------------------------------------------------------
-- Tick
--------------------------------------------------------------------------------

local function tick()
    state.tick_last = mp.get_time()

    if state.osd_h == 0 then
        -- No dimensions yet; try again shortly.
        return
    end

    -- Auto-hide when idle (unless paused, dragging, or a menu is open).
    if state.visible and not state.anim and not state.drag
       and not state.pause and not state.menu.open then
        local idle = (mp.get_time() - state.show_time) * 1000
        if idle >= user_opts.hidetimeout and state.hovered == nil then
            begin_hide()
        end
    end

    local animating = advance_opacity()
    resolve_hover()
    render()

    -- Keep ticking while animating or visible (for the auto-hide countdown).
    if animating or (state.visible and not state.pause) then
        state.tick_timer.timeout = 1 / 60
        state.tick_timer:resume()
    elseif state.visible then
        -- Paused & idle: slow tick to keep the countdown alive cheaply.
        state.tick_timer.timeout = 0.25
        state.tick_timer:resume()
    end
end

state.tick_timer = mp.add_timeout(0.1, tick)
state.tick_timer:kill()

--------------------------------------------------------------------------------
-- Input: pointer + click section
--------------------------------------------------------------------------------

local function update_mouse()
    local mx, my = mp.get_mouse_pos()
    if mx and my and state.osd_h > 0 and state.mouse_in_window ~= false then
        state.mouse_x = to_virt(mx)
        state.mouse_y = to_virt(my)
    else
        state.mouse_x, state.mouse_y = -1, -1
        clear_thumb()
    end
end

local function do_seek(frac)
    if not state.duration then return end
    local flags = user_opts.seek_precise and "absolute+exact" or "absolute+keyframes"
    mp.commandv("seek", state.duration * frac, flags)
end

local function set_volume_from_x(x)
    local box = hitboxes.volslider
    if not box then return end
    local frac = clamp((x - box.x1) / (box.x2 - box.x1), 0, 1)
    local vol = math.floor(frac * 100 + 0.5)
    mp.set_property_number("volume", vol)
    if state.mute and vol > 0 then mp.set_property_native("mute", false) end
end

local function on_mouse_move()
    update_mouse()
    if state.drag == "volume" then
        set_volume_from_x(state.mouse_x)
    end
    register_activity()
    if state.drag then request_tick() end
end

local function on_mbtn_down()
    update_mouse()
    register_activity()
    local mx, my = state.mouse_x, state.mouse_y
    if point_in(hitboxes.seekbar, mx, my) then
        close_menu()
        state.drag = "seek"
        request_tick()
    elseif point_in(hitboxes.volslider, mx, my) then
        state.drag = "volume"
        set_volume_from_x(mx)
        request_tick()
    end
end

local function on_mbtn_up()
    update_mouse()
    local mx, my = state.mouse_x, state.mouse_y
    if state.drag == "seek" then
        local frac = seekbar_fraction_at(mx)
        if frac then do_seek(frac) end
        state.drag = nil
        request_tick()
        return
    elseif state.drag == "volume" then
        state.drag = nil
        request_tick()
        return
    end
    -- Click actions. Controls remain clickable while visible, and a click on
    -- the video itself toggles playback. Keep this active when the OSC has
    -- auto-hidden so the video can still be used as a pause/resume surface.

    -- Menu scrolling/row selection takes precedence.
    if state.menu.open and state.menu.items then
        if point_in(hitboxes.menu_scroll_up, mx, my) then
            state.menu.scroll = clamp((state.menu.scroll or 0) - math.max(1, (state.menu.visible_count or 1) - 1),
                                      0, math.max(0, #state.menu.items - (state.menu.visible_count or #state.menu.items)))
            request_tick()
            return
        elseif point_in(hitboxes.menu_scroll_down, mx, my) then
            state.menu.scroll = clamp((state.menu.scroll or 0) + math.max(1, (state.menu.visible_count or 1) - 1),
                                      0, math.max(0, #state.menu.items - (state.menu.visible_count or #state.menu.items)))
            request_tick()
            return
        end
        local visible_count = state.menu.visible_count or #state.menu.items
        for visual = 1, visible_count do
            local box = hitboxes["menu_row_" .. visual]
            local item = box and state.menu.items[box.item_index or visual]
            if item and point_in(box, mx, my) then
                item.apply()
                close_menu()
                request_tick()
                return
            end
        end
    end

    if point_in(hitboxes.playpause, mx, my) then
        mp.commandv("cycle", "pause"); close_menu()
    elseif point_in(hitboxes.prev, mx, my) then
        if state.queue_index > 0 or ((state.time_pos or 0) > 5) then mp.commandv("script-message", "solfin-prev") end
        close_menu()
    elseif point_in(hitboxes.skip_back, mx, my) then
        mp.commandv("seek", -user_opts.jump_amount, "relative+exact"); close_menu()
    elseif point_in(hitboxes.skip_fwd, mx, my) then
        mp.commandv("seek", user_opts.jump_amount, "relative+exact"); close_menu()
    elseif point_in(hitboxes.next, mx, my) then
        if state.queue_index + 1 < state.queue_count then mp.commandv("script-message", "solfin-next") end
        close_menu()
    elseif point_in(hitboxes.audio, mx, my) then
        open_menu("audio")
    elseif point_in(hitboxes.subtitle, mx, my) then
        open_menu("subtitle")
    elseif point_in(hitboxes.speed, mx, my) then
        open_menu("speed")
    elseif point_in(hitboxes.volume, mx, my) then
        mp.commandv("cycle", "mute"); close_menu()
    elseif point_in(hitboxes.media_info, mx, my) then
        mp.commandv("script-binding", "stats/display-stats-toggle"); close_menu()
    elseif point_in(hitboxes.fullscreen, mx, my) then
        mp.commandv("cycle", "fullscreen"); close_menu()
    elseif point_in(hitboxes.minimize, mx, my) then
        mp.set_property_native("window-minimized", true); close_menu()
    elseif point_in(hitboxes.maximize, mx, my) then
        mp.commandv("cycle", "window-maximized"); close_menu()
    elseif point_in(hitboxes.close, mx, my) then
        mp.commandv("quit")
    elseif state.menu.open and not point_in(hitboxes.menu_area, mx, my) then
        -- Click outside the open panel dismisses it without also toggling
        -- playback.
        close_menu()
    else
        -- Any unclaimed left click is on the video frame. This deliberately
        -- uses mpv's pause property so the IPC observer keeps the app state
        -- and Jellyfin progress reporting in sync.
        mp.commandv("cycle", "pause")
        close_menu()
    end
    request_tick()
end

local function on_wheel(delta)
    update_mouse()
    register_activity()
    if state.menu.open and state.menu.items and point_in(hitboxes.menu_area, state.mouse_x, state.mouse_y) then
        local visible_count = state.menu.visible_count or #state.menu.items
        local max_scroll = math.max(0, #state.menu.items - visible_count)
        local step = delta > 0 and -3 or 3
        state.menu.scroll = clamp((state.menu.scroll or 0) + step, 0, max_scroll)
        request_tick()
        return
    end
    mp.commandv("add", "volume", delta)
    if state.mute and delta > 0 then mp.set_property_native("mute", false) end
end

mp.set_key_bindings({
    { "mbtn_left",     on_mbtn_up, on_mbtn_down },
    { "mbtn_left_dbl", "ignore" },
    { "wheel_up",      function() on_wheel(5) end },
    { "wheel_down",    function() on_wheel(-5) end },
}, "solfin-osc-mouse", "force")
mp.enable_key_bindings("solfin-osc-mouse", "allow-vo-dragging+allow-hide-cursor")

-- Pointer movement (fires the OSC show + hover).
mp.observe_property("mouse-pos", "native", function(_, val)
    if type(val) == "table" then
        state.mouse_in_window = val.hover
    end
    on_mouse_move()
end)

--------------------------------------------------------------------------------
-- Property observers -> state
--------------------------------------------------------------------------------

mp.observe_property("osd-dimensions", "native", function(_, dim)
    if type(dim) == "table" and dim.w and dim.h then
        state.osd_w, state.osd_h = dim.w, dim.h
        -- Capture pointer events across the whole window (real pixel coords).
        mp.set_mouse_area(0, 0, dim.w, dim.h, "solfin-osc-mouse")
        update_scale()
        request_tick()
    end
end)

mp.observe_property("pause", "bool", function(_, v)
    state.pause = (v == true)
    if state.pause then register_activity() end   -- reveal controls when paused
    request_tick()
end)

mp.observe_property("time-pos", "number", function(_, v)
    state.time_pos = v
    if state.visible then request_tick() end
end)

mp.observe_property("duration", "number", function(_, v)
    state.duration = v
    request_tick()
end)

mp.observe_property("seekable", "bool", function(_, v)
    state.seekable = (v == true)
end)

mp.observe_property("speed", "number", function(_, v)
    state.speed = v or 1.0
    if state.visible then request_tick() end
end)

mp.observe_property("volume", "number", function(_, v)
    if v then state.volume = v; if state.visible then request_tick() end end
end)

mp.observe_property("volume-max", "number", function(_, v)
    if v and v > 0 then state.volume_max = v end
end)

mp.observe_property("mute", "bool", function(_, v)
    state.mute = (v == true); request_tick()
end)

mp.observe_property("fullscreen", "bool", function(_, v)
    state.fullscreen = (v == true); request_tick()
end)

mp.observe_property("window-maximized", "bool", function(_, v)
    state.window_maximized = (v == true); request_tick()
end)

mp.observe_property("media-title", "string", function(_, v)
    state.title = v or ""; request_tick()
end)

mp.register_event("shutdown", function()
    clear_thumb()
    clear_logo()
end)

mp.register_script_message("set-logo", function(path, width, height)
    user_opts.logo_path = path or ""
    user_opts.logo_width = tonumber(width) or 0
    user_opts.logo_height = tonumber(height) or 0
    request_tick()
end)

mp.register_script_message("solfin-queue", function(index, count)
    state.queue_index = tonumber(index) or 0
    state.queue_count = math.max(tonumber(count) or 1, 1)
    request_tick()
end)

-- thumbfast announces its thumbnail dimensions / availability here.
mp.register_script_message("thumbfast-info", function(json)
    local data = utils.parse_json(json)
    if type(data) == "table" then
        state.thumbfast = data
        request_tick()
    end
end)

mp.observe_property("demuxer-cache-state", "native", function(_, val)
    local ranges = {}
    if type(val) == "table" and type(val["seekable-ranges"]) == "table" then
        for _, r in ipairs(val["seekable-ranges"]) do
            if r.start and r["end"] then
                ranges[#ranges + 1] = { start = r.start, stop = r["end"] }
            end
        end
    end
    state.cache_ranges = ranges
    if state.visible then request_tick() end
end)

mp.observe_property("chapter-list", "native", function(_, val)
    local chapters = {}
    if type(val) == "table" then
        for _, c in ipairs(val) do
            chapters[#chapters + 1] = { title = c.title, time = c.time or 0 }
        end
    end
    state.chapters = chapters
    request_tick()
end)

mp.observe_property("track-list", "native", function(_, list)
    local audio, subs = {}, {}
    if type(list) == "table" then
        for _, tr in ipairs(list) do
            local entry = { id = tr.id, title = tr.title, lang = tr.lang,
                            codec = tr.codec, selected = (tr.selected == true) }
            if tr.type == "audio" then audio[#audio + 1] = entry
            elseif tr.type == "sub" then subs[#subs + 1] = entry end
        end
    end
    state.audio_tracks = audio
    state.sub_tracks = subs
    request_tick()
end)

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

opt.read_options(user_opts, "solfin-osc", function()
    rebuild_colors()
    request_tick()
end)
rebuild_colors()

-- Reveal briefly on load so the user sees the controls.
register_activity()
