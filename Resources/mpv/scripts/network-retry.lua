-- Retry interrupted network media without involving the host application.
-- mpv can report a failed HTTP read as an ordinary EOF, so this script uses
-- demuxer-via-network and the remaining duration to distinguish a truncated
-- stream from normal completion.

local msg = require "mp.msg"

local max_retries = 10
local backoff = { 0.25, 0.5, 1, 1, 2, 2, 4, 4, 8, 8 }
local retries = 0
local retry_timer
local replacing = false

local function retryable()
    local network = mp.get_property_native("demuxer-via-network")
    local duration = mp.get_property_number("duration", 0)
    local position = mp.get_property_number("time-pos", 0)
    return network == true and duration > 0 and (duration - position) > 5
end

local function retry()
    retry_timer = nil
    if not retryable() then
        return
    end
    if retries >= max_retries then
        msg.error("network retry budget exhausted")
        mp.commandv("script-message", "solfin-network-retry-exhausted")
        return
    end

    retries = retries + 1
    mp.commandv("script-message", "solfin-network-retrying", retries, max_retries)
    local delay = backoff[retries] or backoff[#backoff]
    msg.warn(string.format("network stream retry %d/%d in %gs", retries, max_retries, delay))

    retry_timer = mp.add_timeout(delay, function()
        if not retryable() then return end
        local url = mp.get_property("path")
        local position = math.max(0, mp.get_property_number("time-pos", 0) - 1)
        if not url or url == "" then return end
        replacing = true
        mp.commandv("loadfile", url, "replace", "start=" .. position)
    end)
end

mp.register_event("end-file", function(event)
    local reason = event.reason
    if replacing then
        replacing = false
        return
    end
    if reason == "eof" or reason == "error" then
        if retryable() then
            retry()
        else
            -- This includes the case where the final buffered data has drained
            -- and mpv can no longer report a useful remaining duration.
            mp.commandv("script-message", "solfin-network-retry-exhausted")
        end
    end
end)

mp.register_event("playback-restart", function()
    -- A reload that reaches playback is a successful recovery.
    retries = 0
end)

mp.register_event("shutdown", function()
    if retry_timer then retry_timer:kill() end
end)
