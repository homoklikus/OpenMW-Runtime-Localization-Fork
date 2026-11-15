-- MCP-openMW: kamera statyczna i ukryty HUD dla ujęć porównawczych.
-- Postać testowa stoi poza kadrem i może zostać zaatakowana (np. Azura's Coast, 2026-11-14): zdrowie jest
-- uzupełniane co klatkę, a tryb kamery statycznej przywracany, gdyby silnik go zmienił (kamera śmierci).
local camera = require('openmw.camera')
local util = require('openmw.util')
local types = require('openmw.types')
local self = require('openmw.self')
local I = require('openmw.interfaces')

local current = nil

local function applyCamera(shot)
    camera.setMode(camera.MODE.Static, true)
    camera.setStaticPosition(util.vector3(shot.camera[1], shot.camera[2], shot.camera[3]))
    camera.setYaw(shot.yaw)
    camera.setPitch(shot.pitch)
    if shot.fov then camera.setFieldOfView(shot.fov) end
end

return {
    engineHandlers = {
        onUpdate = function()
            if current == nil then return end
            pcall(function()
                local h = types.Actor.stats.dynamic.health(self)
                if h.current < h.base then h.current = h.base end
            end)
            if camera.getMode() ~= camera.MODE.Static then
                print('RLF_CAPTURE WARN kamera zmieniona przez silnik (tryb ' .. tostring(camera.getMode()) .. ') — przywracam')
                applyCamera(current)
            end
        end,
    },
    eventHandlers = {
        RlfCaptureCamera = function(shot)
            if I.Camera then
                I.Camera.disableModeControl('rlf_capture')
                I.Camera.disableZoom('rlf_capture')
                I.Camera.disableHeadBobbing('rlf_capture')
            end
            current = shot
            applyCamera(shot)
            if I.UI and I.UI.setHudVisibility then I.UI.setHudVisibility(false) end
        end,
    },
}
