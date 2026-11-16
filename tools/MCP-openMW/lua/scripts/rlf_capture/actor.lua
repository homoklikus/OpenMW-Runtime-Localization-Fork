-- MCP-openMW: aktor „zamrożony” na czas ujęcia porównawczego (bez pakietów AI, bez ruchu) – tylko profil testowy.
local I = require('openmw.interfaces')
local self = require('openmw.self')

local function hold()
    pcall(function() I.AI.removePackages() end)
    pcall(function()
        self.controls.movement = 0
        self.controls.sideMovement = 0
        self.controls.run = false
    end)
end

return { engineHandlers = { onActive = hold, onUpdate = hold } }
