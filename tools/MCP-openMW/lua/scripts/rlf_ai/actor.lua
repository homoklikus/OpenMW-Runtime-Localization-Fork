-- MCP-openMW: porównanie zachowań AI (etap 8 planu) – skrypt aktora: aktywny pakiet AI na żądanie skryptu globalnego.
local core = require('openmw.core')
local self = require('openmw.self')
local I = require('openmw.interfaces')
local okAnim, anim = pcall(require, 'openmw.animation')
local IDLES = { 'idle2', 'idle3', 'idle4', 'idle5', 'idle6', 'idle7', 'idle8', 'idle9' }

local function pkg()
    local ok, p = pcall(function() return I.AI.getActivePackage() end)
    if not ok or p == nil then return { type = 'none' } end
    local t = { type = tostring(p.type) }
    pcall(function() t.distance = p.distance end)
    pcall(function() t.isRepeat = p.isRepeat end)
    pcall(function() if p.target then t.target = p.target.recordId end end)
    pcall(function() if p.destPosition then t.dest = { p.destPosition.x, p.destPosition.y, p.destPosition.z } end end)
    if okAnim then                         -- bezczynność wędrówki: która animacja idleN gra (AiWander::playIdle)
        for _, g in ipairs(IDLES) do
            local ok, playing = pcall(anim.isPlaying, self, g)
            if ok and playing then t.idle = g end
        end
    end
    return t
end

return {
    eventHandlers = {
        RlfAiQuery = function(data)
            core.sendGlobalEvent('RlfAiPackage', { actor = self.object, tag = data.tag, pkg = pkg() })
        end,
    },
}
