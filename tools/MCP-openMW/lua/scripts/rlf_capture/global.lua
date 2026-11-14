-- MCP-openMW: ustawianie ujęć do porównań wizualnych (tylko testowy profil uruchomienia, nie mod do gry).
-- Scenariusz: scripts/rlf_capture/scenario.lua (generowany przez MCP). Znaczniki w openmw.log: "RLF_CAPTURE ...".
local world = require('openmw.world')
local core = require('openmw.core')
local util = require('openmw.util')
local S = require('scripts.rlf_capture.scenario')

local player = nil
local phase = 'wait_player'
local deadline = 0
local index = 0

local function log(msg)
    print('RLF_CAPTURE ' .. msg)
end

local function setHour(hour)
    local ok, err = pcall(function()
        world.mwscript.getGlobalVariables(player).gamehour = hour
    end)
    if not ok then log('WARN gamehour ' .. tostring(err)) end
end

local function startShot(shot)
    local cell = world.getExteriorCell(shot.cell[1], shot.cell[2])
    if shot.weather and cell and cell.region then
        local record = core.weather.records[shot.weather]
        if record then
            local ok, err = pcall(core.weather.changeWeather, cell.region, record)
            if not ok then log('WARN weather ' .. tostring(err)) end
        end
    end
    player:teleport('', util.vector3(shot.player[1], shot.player[2], shot.player[3]), { onGround = true })
    player:sendEvent('RlfCaptureCamera', shot)
end

return {
    engineHandlers = {
        onPlayerAdded = function(p) player = p end,
        onUpdate = function()
            if player == nil then
                if world.players and world.players[1] then player = world.players[1] else return end
            end
            local now = core.getRealTime()
            if phase == 'wait_player' then
                log('START ' .. tostring(#S.shots))
                phase = 'next'
                deadline = now + S.initialDelay
            elseif phase == 'next' and now >= deadline then
                index = index + 1
                local shot = S.shots[index]
                if shot == nil then
                    log('DONE')
                    phase = 'quit'
                    deadline = now + 1.0
                    return
                end
                world.setGameTimeScale(S.fastTimeScale)
                startShot(shot)
                log('SHOT ' .. shot.id)
                phase = 'settle'
                deadline = now + S.settleSeconds
            elseif phase == 'settle' and now >= deadline then
                world.setGameTimeScale(0)
                setHour(S.shots[index].hour)
                player:sendEvent('RlfCaptureCamera', S.shots[index])
                phase = 'render'
                deadline = now + S.renderSeconds
            elseif phase == 'render' and now >= deadline then
                log('READY ' .. S.shots[index].id)
                phase = 'capture'
                deadline = now + S.captureSeconds
            elseif phase == 'capture' and now >= deadline then
                phase = 'next'
                deadline = now
            elseif phase == 'quit' and now >= deadline then
                phase = 'done'
                core.quit()
            end
        end,
    },
}
