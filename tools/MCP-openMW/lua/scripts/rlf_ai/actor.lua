-- MCP-openMW: porównanie zachowań AI (etap 8 planu) – skrypt aktora: aktywny pakiet AI na żądanie skryptu globalnego.
local core = require('openmw.core')
local self = require('openmw.self')
local I = require('openmw.interfaces')

local function pkg()
    local ok, p = pcall(function() return I.AI.getActivePackage() end)
    if not ok or p == nil then return { type = 'none' } end
    local t = { type = tostring(p.type) }
    pcall(function() t.distance = p.distance end)
    pcall(function() t.isRepeat = p.isRepeat end)
    pcall(function() if p.target then t.target = p.target.recordId end end)
    pcall(function() if p.destPosition then t.dest = { p.destPosition.x, p.destPosition.y, p.destPosition.z } end end)
    return t
end

return {
    eventHandlers = {
        RlfAiQuery = function(data)
            core.sendGlobalEvent('RlfAiPackage', { actor = self.object, tag = data.tag, pkg = pkg() })
        end,
    },
}
