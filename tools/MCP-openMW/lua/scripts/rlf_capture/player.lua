-- MCP-openMW: kamera statyczna i ukryty HUD dla ujęć porównawczych.
local camera = require('openmw.camera')
local util = require('openmw.util')
local I = require('openmw.interfaces')

return {
    eventHandlers = {
        RlfCaptureCamera = function(shot)
            if I.Camera then
                I.Camera.disableModeControl('rlf_capture')
                I.Camera.disableZoom('rlf_capture')
                I.Camera.disableHeadBobbing('rlf_capture')
            end
            camera.setMode(camera.MODE.Static, true)
            camera.setStaticPosition(util.vector3(shot.camera[1], shot.camera[2], shot.camera[3]))
            camera.setYaw(shot.yaw)
            camera.setPitch(shot.pitch)
            if shot.fov then camera.setFieldOfView(shot.fov) end
            if I.UI and I.UI.setHudVisibility then I.UI.setHudVisibility(false) end
        end,
    },
}
