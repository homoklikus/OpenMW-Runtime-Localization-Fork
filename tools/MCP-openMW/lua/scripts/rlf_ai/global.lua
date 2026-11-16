-- MCP-openMW: porównanie zachowań AI (etap 8 planu) – scenariusz globalny, te same wejścia co w OpenMWGodot
-- (godot/tools/ai_compare.gd). Żądanie: scripts/rlf_ai/request.lua. Wynik w openmw.log: "RLF_AI <rodzaj> <id> <json>".
-- 1) gracz w punkcie z żądania; po ustabilizowaniu – co `step` s pozycje aktorów i ich aktywny pakiet AI
--    (I.AI.getActivePackage) przez `duration` s; 2) napaść gracza na wskazanego NPC przy strażniku
--    (I.Crimes.commitCrime): czy zauważona, grzywna, pakiety strażnika i ofiary.
local world = require('openmw.world')
local types = require('openmw.types')
local util = require('openmw.util')
local I = require('openmw.interfaces')
local R = require('scripts.rlf_ai.request')

local function esc(s)
    return (s:gsub('[%c"\\]', function(c) return string.format('\\u%04x', c:byte()) end))
end

local function enc(v, d)
    d = d or 0
    local t = type(v)
    if v == nil then return 'null' end
    if t == 'boolean' then return tostring(v) end
    if t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        if v == math.floor(v) and math.abs(v) < 9007199254740992 then return string.format('%.0f', v) end
        return string.format('%.6g', v)
    end
    if t == 'string' then return '"' .. esc(v) .. '"' end
    if d > 6 then return '"<deep>"' end
    if t == 'table' and #v > 0 then
        local parts = {}
        for i = 1, #v do parts[#parts + 1] = enc(v[i], d + 1) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = enc(tostring(k)) .. ':' .. enc(x, d + 1) end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function out(kind, id, t) print('RLF_AI ' .. kind .. ' ' .. enc(id) .. ' ' .. enc(t)) end

local player = nil
local clock, phase, next_t, samples_left = 0, 'start', 0, 0
local actors = {}          -- id → {recordId, start, samples, packages}
local pkgs = {}            -- tag → id → pkg
local tag = 0
local crime = {}
local initial = {}         -- id → pozycja w pierwszej klatce (przed ruchem AI) – do dopasowania aktorów

local function v3(p) return { math.floor(p.x + 0.5), math.floor(p.y + 0.5), math.floor(p.z + 0.5) } end

local function list()
    local t = {}
    for _, a in ipairs(world.activeActors) do
        if a ~= player and a:isValid() and a.enabled then t[#t + 1] = a end
    end
    return t
end

local function query(objs)
    tag = tag + 1
    pkgs[tag] = {}
    for _, a in ipairs(objs) do a:sendEvent('RlfAiQuery', { tag = tag }) end
    return tag
end

local function nearest(recordId, from)
    local best, bd = nil, math.huge
    for _, a in ipairs(list()) do
        if a.recordId == recordId then
            local d = (a.position - from):length()
            if d < bd then best, bd = a, d end
        end
    end
    return best
end

local function forward(obj)
    return obj.rotation:apply(util.vector3(0, 1, 0))
end

local function sample()
    local objs = list()
    local tg = query(objs)
    for _, a in ipairs(objs) do
        local e = actors[a.id]
        if e == nil then
            e = { recordId = a.recordId, start = initial[a.id] or v3(a.position), samples = {}, tags = {} }
            actors[a.id] = e
        end
        e.samples[#e.samples + 1] = v3(a.position)
        e.tags[#e.tags + 1] = tg
    end
end

local function finish_actors()
    for id, e in pairs(actors) do
        local ptypes = {}
        local first = nil
        for i, tg in ipairs(e.tags) do
            local p = (pkgs[tg] or {})[id]
            ptypes[i] = p and p.type or 'unknown'
            if first == nil and p then first = p end
        end
        out('actor', id, { recordId = e.recordId, start = e.start, samples = e.samples, packages = ptypes, package = first })
    end
end

local last_phase = nil
local function update(dt)
    clock = clock + dt
    if phase ~= last_phase then print('RLF_AI PHASE ' .. phase .. ' ' .. string.format('%.1f', clock)); last_phase = phase end
    if clock < next_t then return end
    if phase == 'start' then
        player = world.players[1]
        if player == nil then return end
        for _, a in ipairs(world.activeActors) do
            if a ~= player then initial[a.id] = v3(a.position) end
        end
        player:teleport(R.cell or '', util.vector3(R.pos[1], R.pos[2], R.pos[3]), { onGround = true })
        phase, next_t = 'settle', clock + (R.settle or 3)
    elseif phase == 'settle' then
        samples_left = math.floor((R.duration or 30) / (R.step or 1)) + 1
        phase, next_t = 'sample', clock
    elseif phase == 'sample' then
        sample()
        samples_left = samples_left - 1
        next_t = clock + (R.step or 1)
        if samples_left <= 0 then phase = 'collect' end
    elseif phase == 'collect' then
        finish_actors()
        if R.crime == nil then
            phase = 'done'
            return
        end
        local v = nearest(R.crime.victim, player.position)
        local g = nearest(R.crime.guard, player.position)
        if v == nil or g == nil then
            out('crime', 'assault', { error = 'victim or guard missing', victim = v ~= nil, guard = g ~= nil })
            phase = 'done'
            return
        end
        crime.v, crime.g = v, g
        local at = v.position + forward(v) * (R.crime.distance or 100)
        local cn = v.cell.isExterior and '' or v.cell.name     -- zewnętrze: pusta nazwa (komórka z pozycji)
        player:teleport(cn, at, { onGround = true })
        local gd = g.position - at
        gd = util.vector3(gd.x, gd.y, 0):normalize()
        g:teleport(cn, at + gd * (R.crime.guard_distance or 400) + util.vector3(0, 0, 50), { onGround = true })
        phase, next_t = 'commit', clock + 1.0
    elseif phase == 'commit' then
        local b0 = types.Player.getCrimeLevel(player)
        local ok, res = pcall(function()
            return I.Crimes.commitCrime(player, { type = types.Player.OFFENSE_TYPE.Assault, victim = crime.v })
        end)
        crime.seen = ok and res and res.wasCrimeSeen or false
        crime.err = (not ok) and tostring(res) or nil
        crime.bounty = types.Player.getCrimeLevel(player) - b0
        phase, next_t = 'react', clock + 0.1
    elseif phase == 'react' then
        -- 3 s obserwacji co 0,25 s: czy strażnik ścigał (Pursue), czy ofiara walczyła (Combat)
        crime.tags = crime.tags or {}
        crime.tags[#crime.tags + 1] = query({ crime.v, crime.g })
        next_t = clock + 0.25
        if #crime.tags >= 12 then phase, next_t = 'report', clock + 0.5 end
    elseif phase == 'report' then
        local gpur, vcom, gtypes = false, false, {}
        for _, tg in ipairs(crime.tags) do
            local p = pkgs[tg] or {}
            local gp, vp = p[crime.g.id], p[crime.v.id]
            if gp then gtypes[#gtypes + 1] = gp.type; gpur = gpur or gp.type == 'Pursue' end
            if vp then vcom = vcom or vp.type == 'Combat' end
        end
        out('crime', 'assault', { victim = crime.v.recordId, guard = crime.g.recordId, seen = crime.seen,
            bounty = crime.bounty, guard_pursue = gpur, victim_combat = vcom, guard_packages = gtypes, error = crime.err })
        phase = 'done'
    elseif phase == 'done' then
        print('RLF_AI DONE')
        phase = 'finished'
    end
end

return {
    engineHandlers = { onUpdate = function(dt)
        local ok, err = pcall(update, dt)
        if not ok then print('RLF_AI ERROR ' .. tostring(err)); phase = 'done' end
    end },
    eventHandlers = {
        RlfAiPackage = function(data)
            if pkgs[data.tag] and data.actor then pkgs[data.tag][data.actor.id] = data.pkg end
        end,
    },
}
