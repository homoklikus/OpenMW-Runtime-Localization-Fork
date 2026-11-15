-- MCP-openMW: ustawianie ujęć do porównań wizualnych (tylko testowy profil uruchomienia, nie mod do gry).
-- Scenariusz: scripts/rlf_capture/scenario.lua (generowany przez MCP). Znaczniki w openmw.log: "RLF_CAPTURE ...".
local world = require('openmw.world')
local core = require('openmw.core')
local util = require('openmw.util')
local types = require('openmw.types')
local S = require('scripts.rlf_capture.scenario')

local player = nil
local phase = 'wait_player'
local deadline = 0
local index = 0

local function log(msg)
    print('RLF_CAPTURE ' .. msg)
end

-- Weryfikacja geometrii MCP (etap 2b): granice obiektów policzone przez silnik (getBoundingBox).
-- Format: RLF_BBOX <ujęcie> <typ> <id> <recordId> <środek x y z> <połowa rozmiaru x y z> <pozycja x y z>
local dumpedCells = {}
local bboxTypes = { Static = types.Static, Activator = types.Activator, Door = types.Door,
                    Container = types.Container, Light = types.Light }

local function dumpBounds(shot)
    if S.dumpBounds == false then return end
    local n = 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            local cx, cy = shot.cell[1] + dx, shot.cell[2] + dy
            local key = cx .. ',' .. cy
            if not dumpedCells[key] then
                dumpedCells[key] = true
                local ok, err = pcall(function()
                    local cell = world.getExteriorCell(cx, cy)
                    for name, t in pairs(bboxTypes) do
                        for _, o in ipairs(cell:getAll(t)) do
                            local bb = o:getBoundingBox()
                            local p = o.position
                            print(string.format('RLF_BBOX %s %s %s %s %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f',
                                shot.id, name, o.id, o.recordId, bb.center.x, bb.center.y, bb.center.z,
                                bb.halfSize.x, bb.halfSize.y, bb.halfSize.z, p.x, p.y, p.z))
                            n = n + 1
                        end
                    end
                end)
                if not ok then log('WARN bbox ' .. key .. ' ' .. tostring(err)) end
            end
        end
    end
    log('BBOX ' .. shot.id .. ' ' .. n)
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
                dumpBounds(S.shots[index])
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
