-- MCP-openMW: porównanie wzorów RPG (etap 7 planu) – część globalna: przedmioty testowe do ekwipunku gracza.
local world = require('openmw.world')
local types = require('openmw.types')

return {
    eventHandlers = {
        RlfMechCreate = function(data)
            local inv = types.Actor.inventory(data.player)
            for _, id in ipairs(data.ids) do
                local ok, err = pcall(function() world.createObject(id, 1):moveInto(inv) end)
                if not ok then print('RLF_MECH WARN create ' .. tostring(id) .. ' ' .. tostring(err)) end
            end
            data.player:sendEvent('RlfMechCreated', {})
        end,
    },
}
