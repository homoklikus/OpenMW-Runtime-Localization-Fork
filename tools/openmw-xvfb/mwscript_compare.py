#!/usr/bin/env python3
"""Porównanie skutków MWScript w OpenMW i OpenMWGodot na tych samych danych.

Przypadek (JSON): {"name", "cell", "commands": [wiersze konsoli MWScript], "actors": [id], "items": [id],
"globals": [nazwa], "locals": [[id_obiektu, zmienna]], "frames": N}.

  openmw  – uruchamia OpenMW (tools/openmw-xvfb/run.sh) na Xvfb z --skip-menu --start KOMÓRKA, wykonuje polecenia
            przez --script-run, po N klatkach skrypt Lua (globalny, dołączany tylko do kopii konfiguracji w katalogu
            roboczym) zapisuje migawkę stanu do dziennika (wiersz MWSNAP) i kończy grę;
  compile – kompiluje polecenia kompilatorem konwertera (mwconv.mwscript) do JSON dla sondy Godota
            (godot/tests/probe_mwscript.gd), która wykonuje je i zapisuje taką samą migawkę;
  diff    – porównuje migawki pole po polu (tolerancja liczbowa).

Migawka zawiera tylko liczby i identyfikatory (bez tekstów gry). Oryginalne pliki Morrowinda nie są zmieniane;
konfiguracja OpenMW jest kopiowana do katalogu roboczego."""
import argparse
import json
import re
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent

ATTRS = ["strength", "intelligence", "willpower", "agility", "speed", "endurance", "personality", "luck"]
SKILLS = ["block", "armorer", "mediumarmor", "heavyarmor", "bluntweapon", "longblade", "axe", "spear", "athletics",
          "enchant", "destruction", "alteration", "illusion", "conjuration", "mysticism", "restoration", "alchemy",
          "unarmored", "security", "sneak", "acrobatics", "lightarmor", "shortblade", "marksman", "mercantile",
          "speechcraft", "handtohand"]
# rodzina efektów (statsextensions.cpp): nazwa → (efekt dodatni, ujemny, tarcza) – identyfikatory Lua
EFFECTS = {"resistmagicka": ("resistmagicka", "weaknesstomagicka", None),
           "resistfire": ("resistfire", "weaknesstofire", "fireshield"),
           "resistfrost": ("resistfrost", "weaknesstofrost", "frostshield"),
           "resistshock": ("resistshock", "weaknesstoshock", "lightningshield"),
           "resistdisease": ("resistcommondisease", "weaknesstocommondisease", None),
           "resistblight": ("resistblightdisease", "weaknesstoblightdisease", None),
           "resistcorprus": ("resistcorprusdisease", "weaknesstocorprusdisease", None),
           "resistpoison": ("resistpoison", "weaknesstopoison", None),
           "resistparalysis": ("resistparalysis", None, None),
           "resistnormalweapons": ("resistnormalweapons", "weaknesstonormalweapons", None),
           "waterbreathing": ("waterbreathing", None, None), "chameleon": ("chameleon", None, None),
           "waterwalking": ("waterwalking", None, None), "swimspeed": ("swiftswim", None, None),
           "superjump": ("jump", None, None), "flying": ("levitate", None, None), "armorbonus": ("shield", None, None),
           "castpenalty": ("sound", None, None), "silence": ("silence", None, None), "blindness": ("blind", None, None),
           "paralysis": ("paralyze", None, None), "invisible": ("invisibility", None, None),
           "attackbonus": ("fortifyattack", None, None), "defendbonus": ("sanctuary", None, None)}

# identyfikatory efektów OpenMW (ESM::MagicEffect, kolejność indeksów 0–142) – klucze pełnej mapy efektów „fx”
EFFECT_IDS = {n.lower(): i for i, n in enumerate(['WaterBreathing', 'SwiftSwim', 'WaterWalking', 'Shield', 'FireShield', 'LightningShield', 'FrostShield', 'Burden', 'Feather', 'Jump', 'Levitate', 'SlowFall', 'Lock', 'Open', 'FireDamage', 'ShockDamage', 'FrostDamage', 'DrainAttribute', 'DrainHealth', 'DrainMagicka', 'DrainFatigue', 'DrainSkill', 'DamageAttribute', 'DamageHealth', 'DamageMagicka', 'DamageFatigue', 'DamageSkill', 'Poison', 'WeaknessToFire', 'WeaknessToFrost', 'WeaknessToShock', 'WeaknessToMagicka', 'WeaknessToCommonDisease', 'WeaknessToBlightDisease', 'WeaknessToCorprusDisease', 'WeaknessToPoison', 'WeaknessToNormalWeapons', 'DisintegrateWeapon', 'DisintegrateArmor', 'Invisibility', 'Chameleon', 'Light', 'Sanctuary', 'NightEye', 'Charm', 'Paralyze', 'Silence', 'Blind', 'Sound', 'CalmHumanoid', 'CalmCreature', 'FrenzyHumanoid', 'FrenzyCreature', 'DemoralizeHumanoid', 'DemoralizeCreature', 'RallyHumanoid', 'RallyCreature', 'Dispel', 'Soultrap', 'Telekinesis', 'Mark', 'Recall', 'DivineIntervention', 'AlmsiviIntervention', 'DetectAnimal', 'DetectEnchantment', 'DetectKey', 'SpellAbsorption', 'Reflect', 'CureCommonDisease', 'CureBlightDisease', 'CureCorprusDisease', 'CurePoison', 'CureParalyzation', 'RestoreAttribute', 'RestoreHealth', 'RestoreMagicka', 'RestoreFatigue', 'RestoreSkill', 'FortifyAttribute', 'FortifyHealth', 'FortifyMagicka', 'FortifyFatigue', 'FortifySkill', 'FortifyMaximumMagicka', 'AbsorbAttribute', 'AbsorbHealth', 'AbsorbMagicka', 'AbsorbFatigue', 'AbsorbSkill', 'ResistFire', 'ResistFrost', 'ResistShock', 'ResistMagicka', 'ResistCommonDisease', 'ResistBlightDisease', 'ResistCorprusDisease', 'ResistPoison', 'ResistNormalWeapons', 'ResistParalysis', 'RemoveCurse', 'TurnUndead', 'SummonScamp', 'SummonClannfear', 'SummonDaedroth', 'SummonDremora', 'SummonAncestralGhost', 'SummonSkeletalMinion', 'SummonBonewalker', 'SummonGreaterBonewalker', 'SummonBonelord', 'SummonWingedTwilight', 'SummonHunger', 'SummonGoldenSaint', 'SummonFlameAtronach', 'SummonFrostAtronach', 'SummonStormAtronach', 'FortifyAttack', 'CommandCreature', 'CommandHumanoid', 'BoundDagger', 'BoundLongsword', 'BoundMace', 'BoundBattleAxe', 'BoundSpear', 'BoundLongbow', 'ExtraSpell', 'BoundCuirass', 'BoundHelm', 'BoundBoots', 'BoundShield', 'BoundGloves', 'Corprus', 'Vampirism', 'SummonCenturionSphere', 'SunDamage', 'StuntedMagicka', 'SummonFabricant', 'SummonWolf', 'SummonBear', 'SummonBonewolf', 'SummonCreature04', 'SummonCreature05'])}

# Skrypt MENU: zapis i odczyt gry na żądanie sondy (pole „save_load”) – menu.saveGame, potem menu.loadGame.
MENU_LUA = r'''
local menu = require('openmw.menu')
local pending = nil
return {
  eventHandlers = { mwprobe_save = function() menu.saveGame('mwprobe', 'mwprobe'); pending = 0 end },
  engineHandlers = {
    onFrame = function(dt)
      if pending == nil then return end
      pending = pending + 1
      if pending < 3 then return end
      local dir = menu.getCurrentSaveDir()
      for name, info in pairs(dir and menu.getSaves(dir) or {}) do
        if info.description == 'mwprobe' then
          pending = nil
          print('MWLOAD ' .. name)
          menu.loadGame(dir, name)
          return
        end
      end
      if pending > 600 then pending = nil; print('MWSAVEERR brak zapisu') end
    end,
  },
}
'''

# Sterowanie graczem (skrypt PLAYER): odcinki [t0, t1, {forward, back, left, right, run, jump, sneak, yaw, pitch}]
# w sekundach od chwili poleceń; nadpisuje sterowanie wejściem (I.Controls) tylko na czas przypadku.
PLAYER_LUA = r'''
local self = require('openmw.self')
local I = require('openmw.interfaces')
local camera = require('openmw.camera')
local util = require('openmw.util')
local LOOK = __LOOK__
local CTRL = __CONTROLS__
local KEYS = __KEYS__
local CAST = __CAST__
local UIMODE = __UIMODE__
local uidone = {}
local types = require('openmw.types')
local t = -1
local casted = {}
local core = require('openmw.core')
local rt, rt0 = 0, nil
local jumped = {}
local keyed = {}
return {
  eventHandlers = { mwprobe_start = function() t = 0 end,
                    mwprobe_save = function() types.Player.sendMenuEvent(self, 'mwprobe_save', {}) end },
  engineHandlers = {
    onSave = function() return {t = t, casted = casted, jumped = jumped, keyed = keyed, uidone = uidone} end,
    onLoad = function(d)
      if not d then return end
      t, casted, jumped, keyed, uidone = d.t, d.casted or {}, d.jumped or {}, d.keyed or {}, d.uidone or {}
    end,
    onFrame = function(dt)
      -- klawisze wg czasu rzeczywistego (onFrame): okna (np. odpoczynek) wstrzymują czas symulacji
      if t >= 0 then
        local now = core.getRealTime()
        if rt0 == nil then rt0 = now end
        rt = now - rt0
      end
      for i, k in ipairs(KEYS) do
        if t >= 0 and rt >= k[1] and not keyed[i] then keyed[i] = true; print('MWKEY ' .. k[2]) end
      end
      if t >= 0 and LOOK[1] then          -- wycelowanie kamery w punkt (obrót i pochylenie)
        local d = util.vector3(LOOK[1], LOOK[2], LOOK[3]) - camera.getPosition()
        local yaw = math.atan2(d.x, d.y)
        local pitch = -math.atan2(d.z, math.sqrt(d.x * d.x + d.y * d.y))
        local dy = yaw - camera.getYaw()
        while dy > math.pi do dy = dy - 2 * math.pi end
        while dy < -math.pi do dy = dy + 2 * math.pi end
        self.controls.yawChange = dy
        self.controls.pitchChange = pitch - camera.getPitch()
        if __FRAMELOG__ then print(string.format('MWCAM %.2f %.2f %.2f', camera.getPosition().x, camera.getPosition().y, camera.getPosition().z)) end
      end
      -- rzucenie czaru gracza: [t, id] – wybór czaru, postawa magii, „use” od t+1 s przez 0,8 s
      for i, c in ipairs(CAST) do
        if t >= c[1] and not casted[i] then
          casted[i] = true
          I.Controls.overrideCombatControls(true)
          types.Actor.setSelectedSpell(self, c[2])
        end
        if t >= c[1] and t < c[1] + 1.0 and types.Actor.getStance(self) ~= types.Actor.STANCE.Spell then
          types.Actor.setStance(self, types.Actor.STANCE.Spell)
        end
        if t >= c[1] + 1.0 and t < c[1] + 1.8 then
          I.Controls.overrideCombatControls(true)
          self.controls.use = 1
        elseif t >= c[1] + 1.8 and t < c[1] + 2.2 then
          self.controls.use = 0
        end
        if __FRAMELOG__ and t >= c[1] and t < c[1] + 2.5 then
          local ss = types.Actor.getSelectedSpell(self)
          print(string.format('MWCAST t=%.2f stance=%s spell=%s use=%s', t, tostring(types.Actor.getStance(self)),
            ss and ss.id or 'nil', tostring(self.controls.use)))
        end
      end
      -- okno interfejsu (I.UI.setMode), np. odpoczynek: [czas rzeczywisty, tryb]
      for i, u in ipairs(UIMODE) do
        if t >= 0 and rt >= u[1] and not uidone[i] then uidone[i] = true; I.UI.setMode(u[2]) end
      end
      if t >= 0 and __FRAMELOG__ then print(string.format('MWFRAME %.4f %.4f %.2f %.2f %.2f', t, dt, self.position.x, self.position.y, self.position.z)) end
      if t < 0 or #CTRL == 0 then return end
      I.Controls.overrideMovementControls(true)
      local mv, side, run, jump, sneak = 0, 0, false, false, false
      for i, c in ipairs(CTRL) do
        if t >= c[1] and t < c[2] then
          local o = c[3]
          mv = mv + (o.forward or 0) - (o.back or 0)
          side = side + (o.right or 0) - (o.left or 0)
          run = run or (o.run or false)
          sneak = sneak or (o.sneak or false)
          if o.jump and not jumped[i] then jumped[i] = true; jump = true end
          if o.yaw then self.controls.yawChange = o.yaw * dt end
          if o.pitch then self.controls.pitchChange = o.pitch * dt end
        end
      end
      self.controls.movement = mv
      self.controls.sideMovement = side
      self.controls.run = run
      self.controls.sneak = sneak
      self.controls.jump = jump
    end,
    onUpdate = function(dt) if t >= 0 then t = t + dt end end,
  },
}
'''

LUA = r'''
local world = require('openmw.world')
local types = require('openmw.types')
local core = require('openmw.core')
local CFG = __CFG__
local ATTRS = __ATTRS__
local SKILLS = __SKILLS__
local EFFECTS = __EFFECTS__
local EFFECT_IDS = __EFFECT_IDS__
local t_after = -1
local samples_done = {}
local track = {}
local spells_done = {}
local frame = 0
local done = false
local saved_once = false

local function enc(v)
  local t = type(v)
  if t == 'nil' then return 'null' end
  if t == 'boolean' then return v and 'true' or 'false' end
  if t == 'number' then
    if v ~= v then return 'null' end
    return string.format('%.4f', v)
  end
  if t == 'string' then return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
  local parts = {}
  if #v > 0 then
    for _, x in ipairs(v) do parts[#parts + 1] = enc(x) end
    return '[' .. table.concat(parts, ',') .. ']'
  end
  for k, x in pairs(v) do parts[#parts + 1] = enc(tostring(k)) .. ':' .. enc(x) end
  return '{' .. table.concat(parts, ',') .. '}'
end

local function find(id)
  local player = world.players[1]
  if id == 'player' then return player end
  for _, a in ipairs(world.activeActors) do
    if a.recordId == id then return a end
  end
  for _, o in ipairs(player.cell:getAll()) do
    if o.recordId == id then return o end
  end
  if player.cell.isExterior then          -- sąsiednie komórki aktywnej siatki 3 × 3
    for dx = -1, 1 do
      for dy = -1, 1 do
        local c = world.getExteriorCell(player.cell.gridX + dx, player.cell.gridY + dy)
        for _, o in ipairs(c and c:getAll() or {}) do
          if o.recordId == id then return o end
        end
      end
    end
  end
  return nil
end

local function effect(ae, id)
  if not id then return 0 end
  local ok, e = pcall(function() return ae:getEffect(id) end)
  if ok and e then return e.magnitude or 0 end
  return 0
end

local function actor(o)
  local s = {}
  local A = types.Actor
  s.dead = A.isDead(o)
  s.level = A.stats.level(o).current
  s.attributes = {}
  for _, n in ipairs(ATTRS) do
    local a = A.stats.attributes[n](o)
    s.attributes[n] = {a.base, a.modified}
  end
  if types.NPC.objectIsInstance(o) then
    s.skills = {}
    for _, n in ipairs(SKILLS) do
      local k = types.NPC.stats.skills[n](o)
      s.skills[n] = {k.base, k.modified}
    end
    s.werewolf = types.NPC.isWerewolf(o)
  end
  s.dynamic = {}
  for _, n in ipairs({'health', 'magicka', 'fatigue'}) do
    local d = A.stats.dynamic[n](o)
    s.dynamic[n] = {d.base, d.current, d.base + d.modifier}
  end
  local ae = A.activeEffects(o)
  -- static_cast<int> jak w MWScript (OpGetMagicEffect) – obcięcie w stronę zera, nie floor
  local function trunc(v) if v < 0 then return math.ceil(v) end return math.floor(v) end
  s.effects = {}
  for name, ids in pairs(EFFECTS) do
    local v = effect(ae, ids[1]) - effect(ae, ids[2]) + effect(ae, ids[3])
    s.effects[name] = trunc(v)
  end
  -- pełna mapa efektów (MagicEffects): "indeks" albo "indeks:atrybut/umiejętność" → wielkość (bez zerowych)
  s.fx = {}
  local AIDX, SIDX = {}, {}
  for i, n in ipairs(ATTRS) do AIDX[n] = i - 1 end
  for i, n in ipairs(SKILLS) do SIDX[n] = i - 1 end
  for _, e in pairs(ae) do
    local idx = EFFECT_IDS[string.lower(e.id)]
    if idx and e.magnitude and trunc(e.magnitude) ~= 0 then
      local key = tostring(idx)
      if e.affectedAttribute then key = key .. ':' .. tostring(AIDX[string.lower(e.affectedAttribute)])
      elseif e.affectedSkill then key = key .. ':' .. tostring(SIDX[string.lower(e.affectedSkill)]) end
      s.fx[key] = (s.fx[key] or 0) + trunc(e.magnitude)
    end
  end
  local okq, eq = pcall(function() return A.getEquipment(o) end)
  s.equipment = {}
  if okq and eq then
    for slot, item in pairs(eq) do s.equipment[tostring(slot)] = item.recordId end
  end
  s.condition = {}                         -- stan (CellRef charge) broni i pancerza w slotach
  if okq and eq then
    for slot, item in pairs(eq) do
      local okc, c = pcall(function() return types.Item.itemData(item).condition end)
      if okc and c and (types.Weapon.objectIsInstance(item) or types.Armor.objectIsInstance(item)) then
        s.condition[tostring(slot)] = math.floor(c)
      end
    end
  end
  local ai = A.stats.ai
  s.ai = {ai.fight(o).modified, ai.hello(o).modified, ai.flee(o).modified, ai.alarm(o).modified}
  if types.NPC.objectIsInstance(o) and o ~= world.players[1] then
    s.factions = {}
    for _, fid in ipairs(types.NPC.getFactions(o)) do s.factions[fid] = types.NPC.getFactionRank(o, fid) end
  end
  return s
end

local function object(o)
  local s = {}
  s.pos = {o.position.x, o.position.y, o.position.z}
  s.rotz = o.rotation:getYaw()
  s.scale = o.scale
  s.enabled = o.enabled
  s.cell = o.cell and o.cell.name or ''
  if types.Lockable.objectIsInstance(o) then
    s.lock = types.Lockable.isLocked(o) and types.Lockable.getLockLevel(o) or 0
  end
  return s
end

local function snapshot()
  local player = world.players[1]
  local out = {actors = {}, objects = {}, items = {}, globals = {}, locals = {}, player = {}, vars = {}}
  for _, id in ipairs(CFG.actors) do
    local o = find(id)
    if o then
      out.actors[id] = actor(o)
      out.objects[id] = object(o)
    end
  end
  for _, id in ipairs(CFG.objects or {}) do
    local o = find(id)
    if o then out.objects[id] = object(o) end
  end
  local inv = types.Actor.inventory(player)
  for _, id in ipairs(CFG.items) do out.items[id] = inv:countOf(id) end
  out.npc_items = {}
  for _, p in ipairs(CFG.npc_items or {}) do
    local o = find(p[1])
    if o then out.npc_items[p[1] .. '.' .. p[2]] = types.Actor.inventory(o):countOf(p[2]) end
  end
  local g = world.mwscript.getGlobalVariables(player)
  for _, n in ipairs(CFG.globals) do out.globals[n] = g[n] end
  for _, p in ipairs(CFG.locals or {}) do
    local o = find(p[1])
    local sc = o and world.mwscript.getLocalScript(o, player)
    out.locals[p[1] .. '.' .. p[2]] = sc and sc.variables[p[2]] or nil
  end
  local gs = world.mwscript.getGlobalScript('mwprobe_run', player)
  out.vars = {}
  if gs then
    for _, n in ipairs(CFG.vars) do out.vars[n] = gs.variables[n] end
  end
  out.player.crime = types.Player.getCrimeLevel(player)
  out.player.teleporting = types.Player.isTeleportingEnabled(player)
  out.player.cell = player.cell.name
  out.player.water = player.cell.waterLevel
  out.track = track
  return out
end

return {
  engineHandlers = {
    -- stan sondy zachowany w zapisie gry (przypadki z „save_load”)
    onSave = function() return {frame = frame, t_after = t_after, spells_done = spells_done, samples_done = samples_done,
                                track = track, saved_once = saved_once, done = done} end,
    onLoad = function(d)
      if not d then return end
      frame, t_after, spells_done, samples_done = d.frame, d.t_after, d.spells_done or {}, d.samples_done or {}
      track, saved_once, done = d.track or {}, d.saved_once, d.done
      print(string.format('MWLOADED t=%.2f frame=%d', t_after, frame))
    end,
    onUpdate = function(dt)
      frame = frame + 1
      -- czary nakładane bezpośrednio (ActiveSpells:add – jak applyMagicEffects): [przesunięcie, cel, czar, rzucający]
      for si, sp in ipairs(CFG.spells or {}) do
        -- piąty element: chwila w sekundach od poleceń (zamiast klatki) – niezależnie od liczby klatek na sekundę
        local due_sp
        if sp[5] then due_sp = t_after >= 0 and t_after >= sp[5] and not spells_done[si]
        else due_sp = frame == CFG.delay + sp[1] end
        if due_sp then
          spells_done[si] = true
          local o = find(sp[2])
          local rec = core.magic.spells.records[sp[3]]
          local rid, effs = nil, nil
          if rec then rid, effs = rec.id, rec.effects
          else
            -- przedmiot zaklęty (ARMO/CLOT/WEAP/BOOK): efekty zaklęcia przedmiotu
            for _, ty in ipairs({types.Clothing, types.Armor, types.Weapon, types.Book}) do
              local ir = ty.records[sp[3]]
              if ir and ir.enchant and ir.enchant ~= '' then
                local en = core.magic.enchantments.records[ir.enchant]
                if en then rid, effs = ir.id, en.effects end
                break
              end
            end
          end
          if o and rid then
            -- OpenMW 0.51: tylko indeksy efektów rekordu (własne wielkości – czary testowe „custom_spells”)
            local idx = {}
            for i = 1, #effs do idx[i] = i - 1 end
            local c = (sp[4] and sp[4] ~= '') and find(sp[4]) or nil
            types.Actor.activeSpells(o):add({id = rid, effects = idx, caster = c, stackable = CFG.stackable})
          end
        end
      end
      -- usunięcie czaru (ActiveSpells:remove) w klatce: [przesunięcie, cel, czar]
      for _, rm in ipairs(CFG.remove or {}) do
        if frame == CFG.delay + rm[1] then
          local o = find(rm[2])
          if o then
            local list = {}
            for _, a in pairs(types.Actor.activeSpells(o)) do
              if a.id == rm[3] then list[#list + 1] = a.activeSpellId end
            end
            for _, aid in ipairs(list) do types.Actor.activeSpells(o):remove(aid) end
          end
        end
      end
      -- przeniesienie bez stawiania na podłożu (Lua teleport, onGround = false): [przesunięcie, id, x, y, z]
      for _, tp in ipairs(CFG.teleport or {}) do
        if frame == CFG.delay + tp[1] then
          local o = find(tp[2])
          if o then
            local util = require('openmw.util')
            o:teleport(o.cell, util.vector3(tp[3], tp[4], tp[5]), {onGround = false})
          end
        end
      end
      -- wyłączenie stworzeń (np. ryb atakujących w wodzie) – izolacja testu od AI
      if CFG.disable_creatures and frame == CFG.delay then
        for _, a in ipairs(world.activeActors) do
          if types.Creature.objectIsInstance(a) then a.enabled = false end
        end
      end
      if frame == CFG.delay then
        for _, pl in ipairs(world.players) do pl:sendEvent('mwprobe_start', {}) end
      end
      if frame == CFG.delay then t_after = 0 elseif t_after >= 0 then t_after = t_after + dt end
      -- zapis i odczyt gry w chwili CFG.save_load (s): gracz → skrypt MENU (menu.saveGame / menu.loadGame)
      if CFG.save_load and t_after >= CFG.save_load and not saved_once then
        saved_once = true
        print(string.format('MWSAVE t=%.2f', t_after))
        for _, pl in ipairs(world.players) do pl:sendEvent('mwprobe_save', {}) end
      end
      -- próbki położenia w czasie (sekundy od chwili poleceń): track[id] = [[t, x, y, z], …]
      for i, t in ipairs(CFG.samples or {}) do
        if t_after >= t and not samples_done[i] then
          samples_done[i] = true
          for _, id in ipairs(CFG.track or {}) do
            local o = find(id)
            if o then
              track[id] = track[id] or {}
              track[id][#track[id] + 1] = {t, o.position.x, o.position.y, o.position.z}
            end
          end
        end
      end
      if CFG.debug and t_after >= 0 and frame % 5 == 0 then
        local pl = world.players[1]
        print(string.format('MWDBG t=%.2f z=%.1f hp=%.1f', t_after, pl.position.z, types.Actor.stats.dynamic.health(pl).current))
      end
      local due
      if CFG.seconds and CFG.seconds > 0 then due = t_after >= CFG.seconds else due = frame == CFG.frames end
      if due and not done then
        done = true
        local ok, res = pcall(snapshot)
        if ok then
          -- krótkie fragmenty: długi wiersz bywa przerywany wpisami innych wątków dziennika
          local js = enc(res)
          local n = math.ceil(#js / 300)
          for i = 1, n do print(string.format('MWSNAP %d/%d %s|', i, n, js:sub((i - 1) * 300 + 1, i * 300))) end
        else print('MWSNAPERR ' .. tostring(res)) end
        core.quit()
      end
    end,
  },
}
'''


class KeySender:
    """Naciśnięcia klawiszy w oknie OpenMW na Xvfb (XTest, python-xlib z OMW/pylib albo systemowy).
    Aktywacja (A_Activate) i inne akcje wejścia nie są dostępne z Lua – tylko z klawiatury."""

    def __init__(self, display, omw_dir=""):
        for d in (str(omw_dir), "/tmp/omwx"):
            if d and (Path(d) / "pylib").is_dir() and str(Path(d) / "pylib") not in sys.path:
                sys.path.insert(0, str(Path(d) / "pylib"))
        from Xlib import X, XK, display as xdisplay
        from Xlib.ext import xtest
        self.X, self.XK, self.xtest = X, XK, xtest
        self.d = xdisplay.Display(f":{display}")

    def press(self, name):
        kc = self.d.keysym_to_keycode(self.XK.string_to_keysym(name))
        self.xtest.fake_input(self.d, self.X.KeyPress, kc)
        self.d.sync()
        time.sleep(0.25)                 # kilka klatek OpenMW (2–7 kl./s)
        self.xtest.fake_input(self.d, self.X.KeyRelease, kc)
        self.d.sync()


def lua_table(v):
    if isinstance(v, dict):
        return "{" + ",".join(f"[{lua_table(k)}]={lua_table(x)}" for k, x in v.items()) + "}"
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(lua_table(x) for x in v) + "}"
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return json.dumps(str(v))


DELAY = 30     # klatek od startu do wykonania poleceń (aktorzy komórki już zainicjowani, zdolności nałożone)


def probe_script(case: dict) -> str:
    """Skrypt globalny wykonujący polecenia przypadku raz, w klatce DELAY (OpenMW i sonda Godota – ta sama chwila)."""
    lines = ["begin mwprobe_run", "short mwprobe_f"] + [f"{t} {n}" for t, n in case.get("vars", [])]
    lines += ["set mwprobe_f to mwprobe_f + 1", f"if ( mwprobe_f == {int(case.get('delay', DELAY))} )"]
    lines += ["  " + c for c in case.get("setup", []) + case.get("commands", [])]
    lines += ["endif"]
    # co klatkę od chwili poleceń: "every": [polecenie, …]
    if case.get("every"):
        lines += [f"if ( mwprobe_f > {int(case.get('delay', DELAY))} )"] + ["  " + c for c in case["every"]] + ["endif"]
    # polecenia w kolejnych klatkach: "after": [[klatka_po_poleceniach, polecenie], …]
    for d, c in case.get("after", []):
        lines += [f"if ( mwprobe_f == {int(case.get('delay', DELAY)) + int(d)} )", "  " + c, "endif"]
    # polecenia po czasie (s) od chwili poleceń – niezależnie od fps: "after_s": [[sekundy, polecenie], …]
    if case.get("after_s"):
        lines[2:2] = ["float mwprobe_t"] + [f"short mwprobe_d{i}" for i in range(len(case["after_s"]))]
        lines += [f"if ( mwprobe_f > {int(case.get('delay', DELAY))} )", "  set mwprobe_t to mwprobe_t + GetSecondsPassed",
                  "endif"]
        for i, (t, c) in enumerate(case["after_s"]):
            lines += [f"if ( mwprobe_t >= {float(t)} )", f"  if ( mwprobe_d{i} == 0 )", "    " + c,
                      f"    set mwprobe_d{i} to 1", "  endif", "endif"]
    lines += ["end"]
    return "\n".join(lines) + "\n"


def probe_esp(case: dict) -> bytes:
    """Dodatek testowy (nie dane gry): jeden rekord SCPT ze skryptem probe_script; master Morrowind.esm."""
    sys.path.insert(0, str(HERE.parents[1] / "converter"))
    import struct
    from mwconv.esm import writer as W
    src = probe_script(case)
    schd = b"mwprobe_run".ljust(32, b"\0") + struct.pack("<5i", 1, 0, 0, 0, 0)
    rec = W.record("SCPT", [W.sub("SCHD", schd), W.sub("SCTX", src.replace("\n", "\r\n").encode("cp1252"))])
    # czary testowe przypadku („custom_spells”: id → {name, type, effects}) – rekordy SPEL tylko w dodatku testowym,
    # dla efektów bez czaru w danych gry (np. ExtraSpell, przywołania bez stworzenia)
    recs = [rec]
    for sid, sp in case.get("custom_spells", {}).items():
        enams = [W.sub("ENAM", struct.pack("<hbbiiiii", int(e["effect"]), int(e.get("skill", -1)), int(e.get("attribute", -1)),
                                           int(e.get("range", 0)), int(e.get("area", 0)), int(e.get("duration", 0)),
                                           int(e.get("min", 0)), int(e.get("max", 0)))) for e in sp.get("effects", [])]
        recs.append(W.record("SPEL", [W.sub("NAME", W.zs(sid)), W.sub("FNAM", W.zs(sp.get("name", sid))),
                                      W.sub("SPDT", struct.pack("<iii", int(sp.get("type", 0)), 0, 0))] + enams))
    return W.header([("Morrowind.esm", 0)], len(recs), desc="mwscript compare probe", is_master=False) + b"".join(recs)


def baseline(case: dict) -> dict:
    """Przypadek bazowy: tylko polecenia „setup” (stan przed poleceniami przypadku)."""
    b = dict(case)
    b["name"] = case.get("name", "case") + "_base"
    b["commands"] = []
    b["spells"] = []
    b["remove"] = []
    return b


def run_openmw(case: dict, omw_dir: Path, cfg_src: Path, work: Path, display: int, timeout: float) -> dict:
    work.mkdir(parents=True, exist_ok=True)
    cfg_dir = work / "cfg"
    if cfg_dir.exists():
        shutil.rmtree(cfg_dir)
    shutil.copytree(cfg_src, cfg_dir / "openmw")
    probe = work / "probe"
    (probe / "scripts" / "mwprobe").mkdir(parents=True, exist_ok=True)
    cfg = {"actors": case.get("actors", []), "objects": case.get("objects", []), "items": case.get("items", []),
           "globals": case.get("globals", []), "locals": case.get("locals", []),
           "vars": [n for _, n in case.get("vars", [])], "npc_items": case.get("npc_items", []),
           "frames": int(case.get("delay", DELAY)) + int(case.get("frames", 10)),
           "delay": int(case.get("delay", DELAY)), "spells": case.get("spells", []), "remove": case.get("remove", []), "debug": bool(case.get("debug", False)), "teleport": case.get("teleport", []),
           "disable_creatures": bool(case.get("disable_creatures", False)),
           "stackable": bool(case.get("stackable", False)),
           "save_load": case.get("save_load"),
           "seconds": float(case.get("seconds", 0)), "samples": case.get("samples", []), "track": case.get("track", [])}
    lua = (LUA.replace("__CFG__", lua_table(cfg)).replace("__ATTRS__", lua_table(ATTRS))
           .replace("__SKILLS__", lua_table(SKILLS)).replace("__EFFECTS__", lua_table({k: list(v) for k, v in EFFECTS.items()}))
           .replace("__EFFECT_IDS__", lua_table(EFFECT_IDS)))
    (probe / "scripts" / "mwprobe" / "global.lua").write_text(lua, encoding="utf-8")
    (probe / "scripts" / "mwprobe" / "player.lua").write_text(
        PLAYER_LUA.replace("__CONTROLS__", lua_table(case.get("controls", [])))
        .replace("__FRAMELOG__", "true" if case.get("framelog") else "false")
        .replace("__KEYS__", lua_table(case.get("keys", [])))
        .replace("__CAST__", lua_table(case.get("cast", [])))
        .replace("__UIMODE__", lua_table(case.get("ui_mode", [])))
        .replace("__LOOK__", lua_table(case.get("look_at", []))), encoding="utf-8")
    (probe / "scripts" / "mwprobe" / "menu.lua").write_text(MENU_LUA, encoding="utf-8")
    (probe / "mwprobe.omwscripts").write_text("GLOBAL: scripts/mwprobe/global.lua\nPLAYER: scripts/mwprobe/player.lua\n"
                                              "MENU: scripts/mwprobe/menu.lua\n", encoding="utf-8")
    (probe / "mwprobe.esp").write_bytes(probe_esp(case))
    with open(cfg_dir / "openmw" / "openmw.cfg", "a", encoding="utf-8") as f:
        f.write(f'\ndata="{probe}"\ncontent=mwprobe.esp\ncontent=mwprobe.omwscripts\n')
    cmds = work / "commands.txt"
    cmds.write_text("startscript mwprobe_run\n", encoding="utf-8")
    log = work / "openmw.out"
    env = dict(os.environ, DISPLAY=f":{display}")
    xvfb = subprocess.Popen(["Xvfb", f":{display}", "-screen", "0", "1024x768x24", "+extension", "GLX", "-nolisten", "tcp"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
    try:
        args = [str(HERE / "run.sh"), str(omw_dir), str(cfg_dir), "--skip-menu", "--start", case.get("cell", "Seyda Neen"),
                "--script-run", str(cmds)]
        with open(log, "w") as out:
            p = subprocess.Popen(args, stdout=out, stderr=subprocess.STDOUT, env=env)
            t0 = time.time()
            keys = KeySender(display, omw_dir) if case.get("keys") else None
            sent = 0
            while p.poll() is None and time.time() - t0 < timeout:
                time.sleep(0.05 if keys else 1)
                text = log.read_text(errors="replace")
                if keys:                         # MWKEY z gracza (Lua) → naciśnięcie klawisza przez XTest
                    names = re.findall(r"MWKEY (\S+)", text)
                    for name in names[sent:]:
                        if case.get("key_shots"):    # zrzut przed klawiszem – tylko lokalnie (obraz gry)
                            subprocess.run(["import", "-display", f":{display}", "-window", "root",
                                            str(work / f"key{sent}.png")], stdout=subprocess.DEVNULL,
                                           stderr=subprocess.DEVNULL, timeout=20)
                        keys.press(name)
                    sent = len(names)
                if "Quitting peacefully" in text:
                    time.sleep(1)
                    break
            if p.poll() is None:
                p.kill()
    finally:
        xvfb.kill()
    text = log.read_text(errors="replace")
    parts = {}
    total = 0
    for line in text.splitlines():
        if "MWSNAPERR" in line:
            raise SystemExit("błąd migawki OpenMW: " + line.split("MWSNAPERR", 1)[1].strip())
        m = re.search(r"MWSNAP (\d+)/(\d+) (.*)\|\s*$", line)
        if m:
            parts[int(m.group(1))] = m.group(3)
            total = int(m.group(2))
    if total and len(parts) == total:
        return json.loads("".join(parts[i] for i in range(1, total + 1)))
    raise SystemExit(f"brak pełnej migawki OpenMW ({len(parts)}/{total}; dziennik: {log})")


def compile_case(case: dict, converter: Path) -> dict:
    sys.path.insert(0, str(converter))
    from mwconv.mwscript import compile_script
    out = dict(case)
    r = compile_script(probe_script(case), "mwprobe_run")
    if r["errors"]:
        raise SystemExit(f"błąd kompilacji skryptu sondy: {r['errors']}")
    out["script"] = {"body": r["body"], "locals": r["locals"], "warnings": r["warnings"]}
    out["delay"] = int(case.get("delay", DELAY))
    return out


def _cmp(a, b, path, tol, out):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                out.append((path + "." + k, a.get(k, "∅"), b.get(k, "∅")))
            else:
                _cmp(a[k], b[k], path + "." + k, tol, out)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append((path, a, b))
        for i, (x, y) in enumerate(zip(a, b)):
            _cmp(x, y, f"{path}[{i}]", tol, out)
    elif isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        if abs(float(a) - float(b)) > tol:
            out.append((path, a, b))
    elif a != b:
        out.append((path, a, b))


def _leaves(v, path="", out=None):
    out = {} if out is None else out
    if isinstance(v, dict):
        for k, x in v.items():
            _leaves(x, path + "." + k, out)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            _leaves(x, f"{path}[{i}]", out)
    else:
        out[path] = v
    return out


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def diff(a: dict, b: dict, tol: float, ignore=(), base_a=None, base_b=None, tols=None) -> list:
    """Różnice migawek. Z migawkami bazowymi (te same polecenia „setup”, bez poleceń przypadku): gdy wartości
    bazowe obu silników są równe – porównanie wartości po; gdy różne – porównanie zmian (po − przed)."""
    la, lb = _leaves(a), _leaves(b)
    ba, bb = (_leaves(base_a), _leaves(base_b)) if base_a is not None and base_b is not None else ({}, {})
    out = []
    for k in sorted(set(la) | set(lb)):
        if any(k.startswith(i) or i in k for i in ignore):
            continue
        x, y = la.get(k, "∅"), lb.get(k, "∅")
        t = max([tol] + [float(v) for p, v in (tols or {}).items() if p in k])
        if ba and k in ba and k in bb and _num(x) and _num(y) and _num(ba[k]) and _num(bb[k]) \
                and abs(float(ba[k]) - float(bb[k])) > t:
            # różne wartości bazowe: zgodne, gdy równe wartości po (Set…) albo równe zmiany (Mod…)
            dx, dy = float(x) - float(ba[k]), float(y) - float(bb[k])
            if abs(dx - dy) > t and abs(float(x) - float(y)) > t:
                out.append((k + " (zmiana)", round(dx, 4), round(dy, 4)))
            continue
        if ba and ba.get(k, "∅") != bb.get(k, "∅") and x == ba.get(k, "∅") and y == bb.get(k, "∅"):
            continue            # różnica już w stanie bazowym, bez zmiany w żadnym silniku
        if _num(x) and _num(y):
            if abs(float(x) - float(y)) > max(t, 1e-6 * max(abs(float(x)), abs(float(y)))):
                out.append((k, x, y))
        elif x != y:
            out.append((k, x, y))
    return out


def main(argv):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    o = sub.add_parser("openmw")
    o.add_argument("--case", required=True)
    o.add_argument("--omw", default="/tmp/omwx")
    o.add_argument("--cfg", default="/tmp/omwx/cfg/openmw")
    o.add_argument("--work", required=True)
    o.add_argument("--display", type=int, default=70)
    o.add_argument("--timeout", type=float, default=120)
    o.add_argument("--out", required=True)
    o.add_argument("--baseline", action="store_true", help="tylko polecenia setup")
    c = sub.add_parser("compile")
    c.add_argument("--case", required=True)
    c.add_argument("--converter", default=str(HERE.parents[1] / "converter"))
    c.add_argument("--out", required=True)
    c.add_argument("--baseline", action="store_true", help="tylko polecenia setup")
    d = sub.add_parser("diff")
    d.add_argument("a")
    d.add_argument("b")
    d.add_argument("--tol", type=float, default=0.01)
    d.add_argument("--ignore", nargs="*", default=[])
    d.add_argument("--base-a")
    d.add_argument("--base-b")
    d.add_argument("--case", help="przypadek: pola ignore i tol (tolerancje dla fragmentów ścieżek)")
    a = ap.parse_args(argv)
    if a.cmd == "openmw":
        case = json.loads(Path(a.case).read_text(encoding="utf-8"))
        if a.baseline:
            case = baseline(case)
        snap = run_openmw(case, Path(a.omw), Path(a.cfg), Path(a.work), a.display, a.timeout)
        Path(a.out).write_text(json.dumps(snap, indent=1, sort_keys=True), encoding="utf-8")
        print("migawka OpenMW:", a.out)
    elif a.cmd == "compile":
        case = json.loads(Path(a.case).read_text(encoding="utf-8"))
        if a.baseline:
            case = baseline(case)
        Path(a.out).write_text(json.dumps(compile_case(case, Path(a.converter))), encoding="utf-8")
        print("skompilowano:", a.out)
    else:
        x = json.loads(Path(a.a).read_text(encoding="utf-8"))
        y = json.loads(Path(a.b).read_text(encoding="utf-8"))
        ld = (lambda p: json.loads(Path(p).read_text(encoding="utf-8")) if p else None)
        cs = ld(a.case) or {}
        ds = diff(x, y, a.tol, list(a.ignore) + cs.get("ignore", []), ld(a.base_a), ld(a.base_b), cs.get("tol", {}))
        for p, va, vb in ds:
            print(f"{p}: OpenMW={va} Godot={vb}")
        print(f"różnice: {len(ds)}")
        return 1 if ds else 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
