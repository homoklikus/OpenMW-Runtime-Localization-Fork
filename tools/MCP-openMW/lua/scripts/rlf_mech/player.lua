-- MCP-openMW: porównanie wzorów RPG (etap 7 planu) – scenariusz na graczu, te same wejścia co w OpenMWGodot.
-- Żądanie: scripts/rlf_mech/request.lua (generowane przez MCP). Wynik w openmw.log: "RLF_MECH <rodzaj> <id> <json>".
-- Testy: statystyki pochodne, wymagania postępu umiejętności, postęp za użycie (I.SkillProgression.skillUsed),
-- awans (skillLevelUp → postęp poziomu, premie atrybutów i specjalizacji), pancerz (I.Combat.getArmorRating,
-- getEffectiveArmorRating, adjustDamageForArmor), ładunek przedmiotów zaklętych (itemData.enchantmentCharge –
-- getEnchantmentCharge), mikstury jako aktywne czary (atrybuty/umiejętności w trakcie, zdrowie/magia/kondycja po
-- wygaśnięciu; czas trwania mierzony – ta sama wartość trafia do OpenMWGodot).
local core = require('openmw.core')
local types = require('openmw.types')
local self = require('openmw.self')
local I = require('openmw.interfaces')
local R = require('scripts.rlf_mech.request')
local Actor, NPC = types.Actor, types.NPC

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
        return string.format('%.9g', v)
    end
    if t == 'string' then return '"' .. esc(v) .. '"' end
    if d > 5 then return '"<deep>"' end
    if t == 'table' and #v > 0 then
        local parts = {}
        for i = 1, #v do parts[#parts + 1] = enc(v[i], d + 1) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local ok, res = pcall(function()
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = enc(tostring(k)) .. ':' .. enc(x, d + 1) end
        return '{' .. table.concat(parts, ',') .. '}'
    end)
    if ok then return res end
    return enc(tostring(v))
end

local function out(kind, id, t) print('RLF_MECH ' .. kind .. ' ' .. enc(id) .. ' ' .. enc(t)) end

local steps, waitFrames, waitTime, created, finished, built = {}, 0, 0, false, false, false
local clock = 0
local function step(f) steps[#steps + 1] = f end
local function frames(n) waitFrames = n end
local function seconds(s) waitTime = s end

local function attrs()
    local t = {}
    for _, a in ipairs(R.attributes) do
        local s = Actor.stats.attributes[a](self)
        t[#t + 1] = { s.base, s.modified }
    end
    return t
end

local function skills()
    local t = {}
    for _, k in ipairs(R.skills) do
        local s = NPC.stats.skills[k](self)
        t[#t + 1] = { s.base, s.modified, s.progress }
    end
    return t
end

local function dyn()
    local t = {}
    for _, n in ipairs({ 'health', 'magicka', 'fatigue' }) do
        local s = Actor.stats.dynamic[n](self)
        local mod = s.base
        pcall(function() mod = s.base + s.modifier end)
        t[n] = { s.base, s.current, mod }
    end
    return t
end

local function setBase()
    for i, a in ipairs(R.attributes) do Actor.stats.attributes[a](self).base = R.input.attributes[i] end
    for i, k in ipairs(R.skills) do
        local s = NPC.stats.skills[k](self)
        s.base = R.input.skills[i]
        s.progress = 0
    end
end

local function resetDyn()
    for _, n in ipairs({ 'health', 'magicka', 'fatigue' }) do
        local s = Actor.stats.dynamic[n](self)
        s.current = s.base
    end
end

local function find(id)
    local inv = Actor.inventory(self)
    local ok, o = pcall(function() return inv:find(id) end)
    if ok then return o end
    return nil
end

local function build()
    step(function()
        core.sendGlobalEvent('RlfMechCreate', { player = self.object, ids = R.create })
    end)
    step(function() if not created then return 'again' end end)
    step(function()
        setBase()
        local lv = Actor.stats.level(self)
        lv.current = R.input.level
        frames(3)
    end)
    step(function()
        resetDyn()
        frames(2)
    end)
    step(function()
        local spells = {}
        for _, s in pairs(Actor.spells(self)) do spells[#spells + 1] = s.id end
        local rec = NPC.record(self)
        local bs = nil
        pcall(function() bs = types.Player.getBirthSign(self) end)
        local req = {}
        for _, k in ipairs(R.skills) do
            local ok, v = pcall(function() return I.SkillProgression.getSkillProgressRequirement(k) end)
            req[#req + 1] = ok and v or nil
        end
        out('stats', 'player', { attributes = attrs(), skills = skills(), dynamic = dyn(), spells = spells,
            class = rec.class, race = rec.race, female = not rec.isMale, birthsign = bs,
            level = Actor.stats.level(self).current, requirement = req })
    end)
    for i, u in ipairs(R.skill_uses) do
        step(function()
            local s = NPC.stats.skills[u.skill](self)
            s.progress = 0
            I.SkillProgression.skillUsed(u.skill, { useType = u.use, scale = u.scale })
            out('skill_use', i, { skill = u.skill, use = u.use, scale = u.scale, progress = s.progress, base = s.base })
            s.base = R.input.skills[u.index]
            s.progress = 0
        end)
    end
    step(function()
        local lv = Actor.stats.level(self)
        lv.progress = 0
        for _, a in ipairs(R.attributes) do lv.skillIncreasesForAttribute[a] = 0 end
        for _, sp in ipairs({ 'combat', 'magic', 'stealth' }) do lv.skillIncreasesForSpecialization[sp] = 0 end
        for _, k in ipairs(R.levelups) do I.SkillProgression.skillLevelUp(k, 'usage') end
        local inc, spec = {}, {}
        for _, a in ipairs(R.attributes) do inc[#inc + 1] = lv.skillIncreasesForAttribute[a] end
        for _, sp in ipairs({ 'combat', 'magic', 'stealth' }) do spec[#spec + 1] = lv.skillIncreasesForSpecialization[sp] end
        out('levelup', 'sequence', { skills = R.levelups, progress = lv.progress, attribute = inc, specialization = spec,
            after = skills() })
        setBase()
    end)
    for i, set in ipairs(R.armor_sets) do
        step(function()
            local eq = {}
            for _, it in ipairs(set.items) do
                local o = find(it.id)
                if o then eq[Actor.EQUIPMENT_SLOT[it.slot]] = o end
            end
            Actor.setEquipment(self, eq)
            frames(3)
        end)
        step(function()
            local items, adj = {}, {}
            for _, it in ipairs(set.items) do
                local o = find(it.id)
                local ok, v = pcall(function() return I.Combat.getEffectiveArmorRating(o, self) end)
                items[#items + 1] = { it.id, ok and v or nil }
            end
            for _, dmg in ipairs(R.damages) do
                local ok, v = pcall(function() return I.Combat.adjustDamageForArmor(dmg, self) end)
                adj[#adj + 1] = ok and v or nil
            end
            local ok, rating = pcall(function() return I.Combat.getArmorRating(self) end)
            out('armor', i, { items = items, rating = ok and rating or nil, adjusted = adj, damages = R.damages })
            Actor.setEquipment(self, {})
            frames(2)
        end)
    end
    step(function()
        for _, id in ipairs(R.enchanted) do
            local o = find(id)
            local ch = nil
            if o then pcall(function() ch = types.Item.itemData(o).enchantmentCharge end) end
            out('charge', id, { charge = ch })
        end
    end)
    for _, p in ipairs(R.potions) do
        local t0 = 0
        step(function()
            resetDyn()
            for _, n in ipairs({ 'health', 'magicka', 'fatigue' }) do
                local s = Actor.stats.dynamic[n](self)
                s.current = math.floor(s.base * 0.5)
            end
            frames(2)
        end)
        step(function()
            local idx = {}
            for i = 1, p.effects do idx[#idx + 1] = i - 1 end
            out('potion_before', p.id, { dynamic = dyn() })
            Actor.activeSpells(self):add({ id = p.id, effects = idx, stackable = true })
            t0 = clock
            frames(3)
        end)
        step(function()
            out('potion_during', p.id, { attributes = attrs(), skills = skills(), dynamic = dyn(), elapsed = clock - t0 })
            seconds(p.duration + 1.0)
        end)
        step(function()
            out('potion_after', p.id, { attributes = attrs(), skills = skills(), dynamic = dyn(), elapsed = clock - t0 })
            resetDyn()
            frames(2)
        end)
    end
end

return {
    engineHandlers = {
        onUpdate = function(dt)
            clock = clock + dt
            if finished then return end
            if not built then built = true; build() end
            if waitFrames > 0 then waitFrames = waitFrames - 1 return end
            if waitTime > 0 then waitTime = waitTime - dt return end
            local f = steps[1]
            if f == nil then
                finished = true
                print('RLF_MECH DONE')
                return
            end
            local ok, res = pcall(f)
            if not ok then print('RLF_MECH ERROR ' .. tostring(res)) end
            if not (ok and res == 'again') then table.remove(steps, 1) end
        end,
    },
    eventHandlers = {
        RlfMechCreated = function() created = true end,
    },
}
