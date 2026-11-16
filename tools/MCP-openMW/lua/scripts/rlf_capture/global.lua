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

-- Aktorzy w kadrze (ujęcia NPC, etap 2d): na czas ujęcia bez AI i na pozycji z danych (jak w porcie Godot,
-- gdzie NPC stoją w miejscu). shot.actors = { { id = recordId, pos = {x,y,z}, rotz = kąt } }.
local frozen = {}

local function freezeActors(shot)
    frozen = {}
    if not shot.actors then return end
    local want = {}
    for _, a in ipairs(shot.actors) do want[string.lower(a.id)] = a end
    for _, actor in ipairs(world.activeActors) do
        local a = want[string.lower(actor.recordId)]
        if a and actor ~= player then
            local ok, err = pcall(function() actor:addScript('scripts/rlf_capture/actor.lua') end)
            if not ok then log('WARN actor script ' .. tostring(err)) end
            table.insert(frozen, { obj = actor, pos = util.vector3(a.pos[1], a.pos[2], a.pos[3]),
                                   rot = util.transform.rotateZ(a.rotz or 0) })
            want[string.lower(actor.recordId)] = nil
        end
    end
    log('FROZEN ' .. shot.id .. ' ' .. #frozen)
end

local function holdActors(force)
    for _, f in ipairs(frozen) do
        if f.obj:isValid() and (force or (f.obj.position - f.pos):length() > 2) then
            local cellName = (f.obj.cell and not f.obj.cell.isExterior) and f.obj.cell.name or ''
            pcall(function() f.obj:teleport(cellName, f.pos, { rotation = f.rot }) end)
        end
    end
end

-- Etap 5 (MWScript): stan włączenia obiektów ze skryptem lokalnym w komórce ujęcia i sąsiednich.
-- Format: RLF_ENABLED <ujęcie> <recordId> <skrypt> <x> <y> <z> <0|1>
local enabledTypes = { types.Static, types.Activator, types.Door, types.Container, types.Light, types.NPC,
                       types.Creature, types.Miscellaneous, types.Weapon, types.Armor, types.Clothing, types.Book,
                       types.Ingredient, types.Potion }
local function dumpEnabled(shot)
    if not shot.dump_enabled then return end
    local n = 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            local ok, err = pcall(function()
                local cell = world.getExteriorCell(shot.cell[1] + dx, shot.cell[2] + dy)
                for _, t in ipairs(enabledTypes) do
                    for _, o in ipairs(cell:getAll(t)) do
                        local rec = o.type.record(o)
                        local scr = rec and rec.mwscript or nil
                        if scr ~= nil and scr ~= '' then
                            local p = o.position
                            print(string.format('RLF_ENABLED %s %s %s %.1f %.1f %.1f %d', shot.id,
                                o.recordId:gsub(' ', '_'), tostring(scr):gsub(' ', '_'), p.x, p.y, p.z, o.enabled and 1 or 0))
                            n = n + 1
                        end
                    end
                end
            end)
            if not ok then log('WARN enabled ' .. tostring(err)) end
        end
    end
    log('ENABLED ' .. shot.id .. ' ' .. n)
end

local function setHour(hour)
    local ok, err = pcall(function()
        world.mwscript.getGlobalVariables(player).gamehour = hour
    end)
    if not ok then log('WARN gamehour ' .. tostring(err)) end
end

local function startShot(shot)
    if shot.interior then
        -- etap 10: ujęcie we wnętrzu (bez pogody)
        player:teleport(shot.interior, util.vector3(shot.player[1], shot.player[2], shot.player[3]), { onGround = true })
        player:sendEvent('RlfCaptureCamera', shot)
        return
    end
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
                dumpEnabled(S.shots[index])
                freezeActors(S.shots[index])
                holdActors(true)
                world.setGameTimeScale(0)
                setHour(S.shots[index].hour)
                player:sendEvent('RlfCaptureCamera', S.shots[index])
                phase = 'render'
                deadline = now + S.renderSeconds
            elseif (phase == 'render' or phase == 'capture') and #frozen > 0 and now < deadline then
                holdActors(false)
            elseif phase == 'render' and now >= deadline then
                log('READY ' .. S.shots[index].id)
                phase = 'capture'
                deadline = now + S.captureSeconds
            elseif phase == 'capture' and now >= deadline then
                frozen = {}
                phase = 'next'
                deadline = now
            elseif phase == 'quit' and now >= deadline then
                phase = 'done'
                core.quit()
            end
        end,
    },
}
