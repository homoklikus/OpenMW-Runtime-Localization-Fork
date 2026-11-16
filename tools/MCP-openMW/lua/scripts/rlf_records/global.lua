-- MCP-openMW: zrzut rekordów z silnika OpenMW (porównanie z danymi OpenMWGodot, etap 1 planu).
-- Żądanie: scripts/rlf_records/request.lua (generowane przez MCP). Wynik w openmw.log: "RLF_REC <rodzaj> <id> <json>".
local core = require('openmw.core')
local types = require('openmw.types')
local world = require('openmw.world')
local R = require('scripts.rlf_records.request')

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
        return string.format('%.9g', v)
    end
    if t == 'string' then return '"' .. esc(v) .. '"' end
    if d > 4 then return '"<deep>"' end
    local okn, n = pcall(function() return #v end)
    if okn and type(n) == 'number' and n > 0 then
        local parts = {}
        for i = 1, n do parts[#parts + 1] = enc(v[i], d + 1) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local okp, res = pcall(function()
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = enc(tostring(k)) .. ':' .. enc(x, d + 1) end
        return '{' .. table.concat(parts, ',') .. '}'
    end)
    if okp then return res end
    return enc(tostring(v))
end

local stores = {
    Weapon = types.Weapon.records, Armor = types.Armor.records, Clothing = types.Clothing.records,
    Book = types.Book.records, Miscellaneous = types.Miscellaneous.records, Apparatus = types.Apparatus.records,
    Lockpick = types.Lockpick.records, Probe = types.Probe.records, Repair = types.Repair.records,
    Light = types.Light.records, NPC = types.NPC.records, Creature = types.Creature.records,
    Race = types.NPC.races.records, Class = types.NPC.classes.records, BirthSign = types.Player.birthSigns.records,
    Faction = core.factions.records, Skill = core.stats.Skill.records,
}

local function get(rec, f)
    local ok, v = pcall(function() return rec[f] end)
    if ok then return v end
    return nil
end

local function textSum(s)
    if s == nil then return nil end
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
    return { #s, h }
end

local function special(kind, rec, t)
    if kind == 'Book' then
        t.textSum = textSum(get(rec, 'text'))
    elseif kind == 'Race' then
        t.attrs = {}
        for _, a in ipairs(R.attributes) do
            local ok, v = pcall(function() return rec.attributes[a] end)
            if ok and v then t.attrs[a] = { male = get(v, 'male'), female = get(v, 'female') } end
        end
        t.skillBonus = {}
        for _, s in ipairs(R.skills) do
            local ok, v = pcall(function() return rec.skills[s] end)
            if ok and v and v ~= 0 then t.skillBonus[s] = v end
        end
        t.heightM = get(get(rec, 'height') or {}, 'male')
        t.heightF = get(get(rec, 'height') or {}, 'female')
        t.weightM = get(get(rec, 'weight') or {}, 'male')
        t.weightF = get(get(rec, 'weight') or {}, 'female')
    elseif kind == 'Faction' then
        local ranks = {}
        local okr, rr = pcall(function() return rec.ranks end)
        if okr and rr then
            for i = 1, #rr do
                local r = rr[i]
                ranks[#ranks + 1] = { name = get(r, 'name'), attributeValues = get(r, 'attributeValues'),
                    primarySkillValue = get(r, 'primarySkillValue'), favouredSkillValue = get(r, 'favouredSkillValue'),
                    factionReaction = get(r, 'factionReaction') }
            end
        end
        t.rankList = ranks
    end
end

local function dump()
    for _, req in ipairs(R.items) do
        local st = stores[req.kind]
        for _, id in ipairs(req.ids) do
            local ok, rec = pcall(function() return st[id] end)
            if not ok or rec == nil then
                print('RLF_REC ' .. req.kind .. ' ' .. enc(id) .. ' null')
            else
                local t = {}
                for _, f in ipairs(req.fields) do if f ~= 'text' then t[f] = get(rec, f) end end  -- tekst: tylko suma (długie linie log dzieli)
                special(req.kind, rec, t)
                print('RLF_REC ' .. req.kind .. ' ' .. enc(id) .. ' ' .. enc(t))
            end
        end
    end
    for _, n in ipairs(R.gmst or {}) do
        local ok, v = pcall(core.getGMST, n)
        print('RLF_REC GMST ' .. enc(n) .. ' ' .. enc({ value = ok and v or nil }))
    end
    local okg, g = pcall(function() return world.mwscript.getGlobalVariables() end)
    for _, n in ipairs(R.globals or {}) do
        local v = nil
        if okg and g then
            local ok, x = pcall(function() return g[n] end)
            if ok then v = x end
        end
        print('RLF_REC GLOB ' .. enc(n) .. ' ' .. enc({ value = v }))
    end
    print('RLF_REC DONE')
end

local done = false
return {
    engineHandlers = {
        onUpdate = function()
            if not done then
                done = true
                local ok, err = pcall(dump)
                if not ok then print('RLF_REC ERROR ' .. tostring(err)) ; print('RLF_REC DONE') end
            end
        end,
    },
}
