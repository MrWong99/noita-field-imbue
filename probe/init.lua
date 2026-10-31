-- field_imbue probes: runs the single-player experiments from docs/RESEARCH.md §6 automatically after the player spawns
-- and prints every result as a "FIPROBE" line (logger.txt / stdout). Meant for an isolated prefix: it rewrites the
-- player's held starting wand, pins the player in the air and fires through ControlsComponent (the EW notplayer trick).

local MOD = "mods/field_imbue_probe/"

ModMagicNumbersFileAdd(MOD .. "files/magic_numbers.xml")
ModLuaFileAppend("data/scripts/gun/gun_actions.lua", MOD .. "files/actions_append.lua")

-- spell loadouts written onto the player's starting wand (the one the game itself has selected)
local WANDS = {
	field = "BERSERK_FIELD",
	freeze_field = "FREEZE,BERSERK_FIELD",
	burn_field = "BURN_TRAIL,BERSERK_FIELD",
	pierce_field = "PIERCING_SHOT,BERSERK_FIELD",
	bolt = "LIGHT_BULLET",
	burn_bolt = "BURN_TRAIL,LIGHT_BULLET",
	conv_field = "WATER_TO_POISON,BERSERK_FIELD",
	conv2_field = "BLOOD_TO_ACID,BERSERK_FIELD",
	marker_field = "FI_PROBE_MARKER,BERSERK_FIELD",
	marker_fire = "FI_PROBE_MARKER,CIRCLE_FIRE",
	marker_bolt = "FI_PROBE_MARKER,LIGHT_BULLET",
	-- prototype (needs the field_imbue mod)
	imbue_burn_field = "FIELD_IMBUE,BURN_TRAIL,BERSERK_FIELD",
	imbue_freeze_field = "FIELD_IMBUE,FREEZE,BERSERK_FIELD",
	imbue_bolt = "FIELD_IMBUE,LIGHT_BULLET",
	fast_bolt = "SPEED,SPEED,SPEED,LIGHT_BULLET",
	freeze_bolt = "FREEZE,LIGHT_BULLET",
	resonant_freeze = "FREEZE,RESONANT_FIELD",
	resonant_plain = "RESONANT_FIELD",
	-- 0.5.0: hit effects over the area, Field resonance in a trigger payload, tinted fields
	resonant_curse = "CURSE,RESONANT_FIELD",
	resonant_wither = "CURSE_WITHER_PROJECTILE,RESONANT_FIELD",
	resonant_petrify = "HITFX_PETRIFY,RESONANT_FIELD",
	resonant_toxic_charm = "HITFX_TOXIC_CHARM,RESONANT_FIELD",
	resonant_slime_explosion = "HITFX_EXPLOSION_SLIME,RESONANT_FIELD",
	trigger_freeze_field = "LIGHT_BULLET_TRIGGER,FIELD_IMBUE,FREEZE,BERSERK_FIELD",
	timer_freeze_field = "LIGHT_BULLET_TIMER,FIELD_IMBUE,FREEZE,BERSERK_FIELD",
	timer_resonant_freeze = "LIGHT_BULLET_TIMER,FREEZE,RESONANT_FIELD",
	timer_plain_field = "LIGHT_BULLET_TIMER,FREEZE,BERSERK_FIELD",
	timer_bolt = "LIGHT_BULLET_TIMER,LIGHT_BULLET",
	imbue_mixed_field = "FIELD_IMBUE,FREEZE,BURN_TRAIL,HOMING,BERSERK_FIELD",
}

-- suite.txt, first word: "prototype" / "sweep" / "ew"; anything else runs the research probes (§6).
-- For "sweep", an optional second line limits it to a comma-separated list of modifier ids.
local ok_suite, SUITE_TEXT = pcall(ModTextFileGetContent, MOD .. "suite.txt") -- written by tools/probe-run.sh
if not ok_suite or not SUITE_TEXT then
	SUITE_TEXT = "research"
end
local SUITE = SUITE_TEXT:match("%a+")
local SWEEP_ONLY = {}
for id in (SUITE_TEXT:match("\n([^\n]*)") or ""):gmatch("[%w_]+") do
	SWEEP_ONLY[id] = true
end
-- optional third line: field_imbue settings to force for this run ("enemy", "destructive"). Set here, at the top level
-- of init.lua, which runs before field_imbue's OnModPostInit reads them.
local SETTINGS_LINE = SUITE_TEXT:match("\n[^\n]*\n([^\n]*)") or ""
ModSettingSet("field_imbue.imbue_enemy_projectiles", SETTINGS_LINE:find("enemy", 1, true) ~= nil)
ModSettingSet("field_imbue.allow_destructive", SETTINGS_LINE:find("destructive", 1, true) ~= nil)
dofile_once("data/scripts/lib/utilities.lua") -- shoot_projectile

-- state -----------------------------------------------------------------------------------------------------------

local player, ctrl
local PX, PY -- pinned player position (in the air)
local pins = {} -- entity -> {x, y}
local runner -- the probe coroutine
local current_wand

local function log(...)
	local parts = { "FIPROBE" }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	local line = table.concat(parts, " ")
	print(line)
end

local function wait(frames)
	for _ = 1, frames do
		coroutine.yield()
	end
end

local function pin(e, x, y)
	pins[e] = { x, y }
end

local function apply_pins()
	if ctrl then
		ComponentSetValue2(ctrl, "enabled", false) -- EW may re-enable it; the real mouse would then steal the aim
	end
	for e, p in pairs(pins) do
		if EntityGetIsAlive(e) then
			EntitySetTransform(e, p[1], p[2])
			local cd = EntityGetFirstComponentIncludingDisabled(e, "CharacterDataComponent")
			if cd then
				ComponentSetValue2(cd, "mVelocity", 0, 0)
			end
		else
			pins[e] = nil
		end
	end
end

local function kill(...)
	for i = 1, select("#", ...) do
		local e = select(i, ...)
		if e and e ~= 0 and EntityGetIsAlive(e) then
			pins[e] = nil
			EntityKill(e)
		end
	end
end

local function aim(dx, dy)
	local d = math.sqrt(dx * dx + dy * dy)
	ComponentSetValue2(ctrl, "mAimingVector", dx, dy)
	ComponentSetValue2(ctrl, "mAimingVectorNormalized", dx / d, dy / d)
	ComponentSetValue2(ctrl, "mAimingVectorNonZeroLatest", dx, dy)
	ComponentSetValue2(ctrl, "mMousePosition", PX + dx, PY + dy)
end

local FIRE_MODE = "hold" -- chosen by calibrate_fire()

local function ability()
	return EntityGetFirstComponentIncludingDisabled(current_wand, "AbilityComponent")
end

local function shots()
	return ComponentGetValue2(ability(), "stat_times_player_has_shot")
end

local function wand_state(tag)
	local ab = ability()
	local psc = EntityGetFirstComponentIncludingDisabled(player, "PlatformShooterPlayerComponent")
	log(tag, "frame=" .. GameGetFrameNum(), ("mana=%.0f"):format(ComponentGetValue2(ab, "mana")), "shots=" .. shots(),
		"nextUsable=" .. ComponentGetValue2(ab, "mNextFrameUsable"), "reloadNext=" .. ComponentGetValue2(ab, "mReloadNextFrameUsable"),
		"ctrl.enabled=" .. tostring(ComponentGetValue2(ctrl, "enabled")), "down=" .. tostring(ComponentGetValue2(ctrl, "mButtonDownFire")),
		"bframe=" .. ComponentGetValue2(ctrl, "mButtonFrameFire"),
		"requireTrigger=" .. tostring(psc and ComponentGetValue2(psc, "mRequireTriggerPull")),
		"hidden=" .. tostring(psc and ComponentGetValue2(psc, "mItemTemporarilyHidden")))
end

-- returns true if the wand's shot counter went up
local function fire(dx, dy, mode)
	mode = mode or FIRE_MODE
	aim(dx, dy)
	wait(2) -- let the wand rotate
	local ab = ability()
	for _ = 1, 120 do -- wait out cast delay / recharge from the previous probe
		local ready = math.max(ComponentGetValue2(ab, "mNextFrameUsable"), ComponentGetValue2(ab, "mReloadNextFrameUsable"))
		if GameGetFrameNum() >= ready then
			break
		end
		wait(1)
	end
	local before = shots()
	if mode == "force" then
		local psc = EntityGetFirstComponentIncludingDisabled(player, "PlatformShooterPlayerComponent")
		ComponentSetValue2(psc, "mForceFireOnNextUpdate", true)
		wait(2)
	else
		for i = 1, 8 do
			local f = GameGetFrameNum()
			ComponentSetValue2(ctrl, "mButtonDownFire", true)
			ComponentSetValue2(ctrl, "mButtonDownFire2", true)
			if i == 1 then
				ComponentSetValue2(ctrl, "mButtonFrameFire", f + 1)
			end
			ComponentSetValue2(ctrl, "mButtonLastFrameFire", f)
			wait(1)
			if shots() > before then
				break
			end
		end
		ComponentSetValue2(ctrl, "mButtonDownFire", false)
		ComponentSetValue2(ctrl, "mButtonDownFire2", false)
	end
	return shots() > before
end

-- Rewrites the held starting wand's cards and stats. Swapping in a different wand entity and writing
-- Inventory2Component.mActiveItem leaves it unusable (the docs warn against touching that field).
local function equip(name)
	local w = current_wand
	for _, card in ipairs(EntityGetAllChildren(w) or {}) do
		if EntityGetFirstComponentIncludingDisabled(card, "ItemActionComponent") then
			EntityRemoveFromParent(card)
			EntityKill(card)
		end
	end
	local n = 0
	for id in WANDS[name]:gmatch("[^,]+") do
		local card = CreateItemActionEntity(id, PX, PY)
		EntityAddChild(w, card)
		EntitySetComponentsWithTagEnabled(card, "enabled_in_world", false)
		n = n + 1
	end
	local ab = ability()
	ComponentObjectSetValue2(ab, "gun_config", "deck_capacity", n + 1)
	ComponentObjectSetValue2(ab, "gun_config", "actions_per_round", 1)
	ComponentObjectSetValue2(ab, "gun_config", "reload_time", 0)
	ComponentObjectSetValue2(ab, "gun_config", "shuffle_deck_when_empty", false)
	ComponentObjectSetValue2(ab, "gunaction_config", "fire_rate_wait", 30)
	ComponentSetValue2(ab, "mana_max", 10000)
	ComponentSetValue2(ab, "mana_charge_speed", 10000)
	ComponentSetValue2(ab, "mana", 10000)
	-- vanilla's way to make the held wand rebuild its deck (perk_list.lua, infinite spells perk)
	local inv = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
	ComponentSetValue2(inv, "mActualActiveItem", 0)
	wait(5)
	log("equip", name, "held_ok=" .. tostring(ComponentGetValue2(inv, "mActualActiveItem") == w), "cards=" .. n)
end

local PROJ_TAGS = { "projectile", "projectile_player" }

local function snapshot()
	local s = {}
	for _, tag in ipairs(PROJ_TAGS) do
		for _, e in ipairs(EntityGetWithTag(tag)) do
			s[e] = true
		end
	end
	return s
end

-- waits up to max_frames for a new projectile whose filename contains `pattern`
local function wait_new(snap, pattern, max_frames)
	for _ = 1, max_frames do
		for _, tag in ipairs(PROJ_TAGS) do
			for _, e in ipairs(EntityGetWithTag(tag)) do
				if not snap[e] then
					snap[e] = true
					local fname = EntityGetFilename(e) or ""
					if fname:find(pattern, 1, true) then
						return e
					end
				end
			end
		end
		wait(1)
	end
end

local function spawn_sheep(x, y)
	local s = EntityLoad("data/entities/animals/sheep.xml", x, y)
	local dm = EntityGetFirstComponentIncludingDisabled(s, "DamageModelComponent")
	if dm then
		ComponentSetValue2(dm, "max_hp", 40)
		ComponentSetValue2(dm, "hp", 40)
	end
	pin(s, x, y)
	return s
end

local function effects(e)
	if not EntityGetIsAlive(e) then
		return "dead"
	end
	local out = {}
	for _, name in ipairs({ "BERSERK", "FROZEN", "ON_FIRE", "OILED", "WET", "CHARM" }) do
		out[#out + 1] = name .. "=" .. GameGetGameEffectCount(e, name)
	end
	local genome = EntityGetFirstComponentIncludingDisabled(e, "GenomeDataComponent")
	if genome then
		out[#out + 1] = "herd=" .. HerdIdToString(ComponentGetValue2(genome, "herd_id"))
	end
	local dm = EntityGetFirstComponentIncludingDisabled(e, "DamageModelComponent")
	if dm then
		out[#out + 1] = ("hp=%.3f burning=%s fireframes=%d"):format(ComponentGetValue2(dm, "hp"),
			tostring(ComponentGetValue2(dm, "is_on_fire")), ComponentGetValue2(dm, "mFireFramesLeft"))
	end
	return table.concat(out, " ")
end

local function describe(tag, e)
	if not e or not EntityGetIsAlive(e) then
		log(tag, "describe: entity missing")
		return
	end
	log(tag, "file", EntityGetFilename(e), "tags", EntityGetTags(e) or "")
	local pc = EntityGetFirstComponentIncludingDisabled(e, "ProjectileComponent")
	if pc then
		log(tag, "pc.damage_game_effect_entities=" .. tostring(ComponentGetValue2(pc, "damage_game_effect_entities")))
		log(tag, "config.game_effect_entities=" .. tostring(ComponentObjectGetValue2(pc, "config", "game_effect_entities")))
		log(tag, "config.extra_entities=" .. tostring(ComponentObjectGetValue2(pc, "config", "extra_entities")))
		log(tag, "pc.friendly_fire=" .. tostring(ComponentGetValue2(pc, "friendly_fire")),
			"pc.damage=" .. tostring(ComponentGetValue2(pc, "damage")))
	else
		log(tag, "no ProjectileComponent")
	end
	local gaec = EntityGetFirstComponentIncludingDisabled(e, "GameAreaEffectComponent")
	if gaec then
		local ok, v = pcall(ComponentGetVector, gaec, "game_effect_entitities", "string")
		if ok then
			v = v or {}
			log(tag, "gaec.game_effect_entitities n=" .. #v, table.concat(v, "|"))
		else
			log(tag, "gaec vector read failed:", v)
		end
		log(tag, "gaec.radius=" .. tostring(ComponentGetValue2(gaec, "radius")),
			"frame_length=" .. tostring(ComponentGetValue2(gaec, "frame_length")))
	end
	local names = {}
	for _, comp in ipairs(EntityGetAllComponents(e) or {}) do
		names[#names + 1] = ComponentGetTypeName(comp)
	end
	log(tag, "components:", table.concat(names, ","))
	for _, v in ipairs(EntityGetComponentIncludingDisabled(e, "VariableStorageComponent") or {}) do
		log(tag, "vsc", ComponentGetValue2(v, "name"), ComponentGetValue2(v, "value_string"))
	end
	local kids = EntityGetAllChildren(e) or {}
	log(tag, "children=" .. #kids)
	for _, k in ipairs(kids) do
		log(tag, "  child", EntityGetFilename(k), "vscs=" .. #(EntityGetComponentIncludingDisabled(k, "VariableStorageComponent") or {}))
	end
end

local function angle(e)
	local vc = EntityGetFirstComponentIncludingDisabled(e, "VelocityComponent")
	if not vc then
		return "novel"
	end
	local vx, vy = ComponentGetValue2(vc, "mVelocity")
	return ("%.1fdeg |v|=%.0f"):format(math.deg(math.atan2(vy, vx)), math.sqrt(vx * vx + vy * vy))
end

-- probes ------------------------------------------------------------------------------------------------------------

local PAD_DX = 120

local protection_entity
local function set_protection(on)
	if on then
		local comp, eff = GetGameEffectLoadTo(player, "PROTECTION_ALL", true)
		if comp then
			ComponentSetValue2(comp, "frames", -1)
		end
		protection_entity = eff
	elseif protection_entity and EntityGetIsAlive(protection_entity) then
		EntityKill(protection_entity)
		protection_entity = nil
	end
end

-- §6.1: does a modifier's game effect spread over a vanilla circle?
local function probe_field_effects(name, move_field)
	equip(name)
	local snap = snapshot()
	fire(1, 0)
	local field = wait_new(snap, "berserk_field", 20)
	if not field then
		log("T1", name, "NO FIELD FOUND")
		return
	end
	local fx, fy = PX + PAD_DX, PY
	if move_field then
		EntitySetTransform(field, fx, fy)
	else
		fx, fy = EntityGetTransform(field)
	end
	-- 4 sheep 18px out (inside r=28, outside the ~4px centre emitters); ignition is a per-application roll
	local flock = {}
	for _, o in ipairs({ { 18, 0 }, { -18, 0 }, { 0, 18 }, { 0, -18 } }) do
		flock[#flock + 1] = spawn_sheep(fx + o[1], fy + o[2])
	end
	log("T1", name, "field at", ("%.0f,%.0f"):format(fx, fy), "4 sheep at 18px")
	for t = 1, 120 do
		wait(1)
		if t == 5 or t == 40 or t == 120 then
			for i, s in ipairs(flock) do
				log("T1", name, "t=" .. t, "sheep" .. i .. ":", effects(s))
			end
			log("T1", name, "t=" .. t, "player:", effects(player))
		end
	end
	describe("T1 " .. name, field)
	kill(field, unpack(flock))
	wait(10)
end

-- §6.2: mid-flight imbue on a spark bolt
local function probe_midflight_homing(imbue)
	equip("bolt")
	local sheep = spawn_sheep(PX + 170, PY - 60)
	local snap = snapshot()
	fire(1, 0)
	local bolt = wait_new(snap, "light_bullet", 10)
	if not bolt then
		log("T2 homing", "NO BOLT")
		kill(sheep)
		return
	end
	for t = 1, 30 do
		if not EntityGetIsAlive(bolt) then
			log("T2 homing imbue=" .. tostring(imbue), "t=" .. t, "bolt gone; sheep:", effects(sheep))
			break
		end
		if t == 4 and imbue then
			EntityLoadToEntity("data/entities/misc/homing.xml", bolt)
			log("T2 homing", "loaded homing.xml at t=4, HomingComponents=" ..
				#(EntityGetComponentIncludingDisabled(bolt, "HomingComponent") or {}))
		end
		if t % 2 == 0 then
			local bx, by = EntityGetTransform(bolt)
			log("T2 homing imbue=" .. tostring(imbue), "t=" .. t, angle(bolt), ("pos=%.0f,%.0f"):format(bx - PX, by - PY))
		end
		wait(1)
	end
	kill(bolt, sheep)
	wait(10)
end

local function probe_midflight_freeze(imbue)
	equip("bolt")
	local sx, sy = PX + 150, PY - 4
	local sheep = spawn_sheep(sx, sy)
	wait(3)
	local snap = snapshot()
	fire(sx - PX, sy - (PY - 4))
	local bolt = wait_new(snap, "light_bullet", 10)
	if not bolt then
		log("T2 freeze", "NO BOLT")
		kill(sheep)
		return
	end
	wait(2)
	if imbue and EntityGetIsAlive(bolt) then
		local pc = EntityGetFirstComponentIncludingDisabled(bolt, "ProjectileComponent")
		local old = ComponentGetValue2(pc, "damage_game_effect_entities")
		ComponentSetValue2(pc, "damage_game_effect_entities", old .. "data/entities/misc/effect_frozen.xml,")
		log("T2 freeze", "appended effect_frozen at t=2, now:", ComponentGetValue2(pc, "damage_game_effect_entities"))
	end
	for t = 1, 40 do
		wait(1)
		if t % 5 == 0 then
			log("T2 freeze imbue=" .. tostring(imbue), "t=" .. t, "bolt_alive=" .. tostring(EntityGetIsAlive(bolt)), "sheep:", effects(sheep))
		end
	end
	kill(bolt, sheep)
	wait(10)
end

-- does the engine copy config.game_effect_entities into damage_game_effect_entities on a normal bolt?
local function probe_bolt_config()
	equip("burn_bolt")
	local snap = snapshot()
	fire(0, -1)
	local bolt = wait_new(snap, "light_bullet", 10)
	describe("T2 burn_bolt", bolt)
	kill(bolt)
	wait(10)
end

-- §6.3: do execute_on_added LuaComponents run when loaded via EntityLoadToEntity?
local function probe_added()
	local a = EntityCreateNew("fi_probe_added_ltoe")
	EntitySetTransform(a, PX, PY - 40)
	EntityLoadToEntity(MOD .. "files/added_probe.xml", a)
	local b = EntityLoad(MOD .. "files/added_probe.xml", PX, PY - 40)
	local c3 = EntityCreateNew("fi_probe_once_ltoe")
	EntitySetTransform(c3, PX, PY - 40)
	EntityLoadToEntity(MOD .. "files/once_probe.xml", c3)
	wait(10)
	log("T3", "execute_on_added via EntityLoadToEntity ran=" .. GlobalsGetValue("fi_probe_added_" .. a, "0"))
	log("T3", "execute_on_added via EntityLoad (control) ran=" .. GlobalsGetValue("fi_probe_added_" .. b, "0"))
	log("T3", "every_n_frame=1+remove_after_executed via EntityLoadToEntity ran=" .. GlobalsGetValue("fi_probe_once_" .. c3, "0"),
		"lua_left=" .. #(EntityGetComponentIncludingDisabled(c3, "LuaComponent") or {}))
	kill(a, b, c3)
end

-- §6.4: does a merged converter keep converting on a static field?
local function probe_converter(name)
	equip(name)
	local snap = snapshot()
	fire(1, 0)
	local field = wait_new(snap, "berserk_field", 20)
	if not field then
		log("T4", name, "NO FIELD")
		return
	end
	EntitySetTransform(field, PX + PAD_DX, PY)
	for t = 0, 300, 10 do
		local parts = {}
		for i, mc in ipairs(EntityGetComponentIncludingDisabled(field, "MagicConvertMaterialComponent") or {}) do
			parts[#parts + 1] = ("#%d en=%s loop=%s kill=%s radius=%s mRadius=%s"):format(i,
				tostring(ComponentGetIsEnabled(mc)), tostring(ComponentGetValue2(mc, "loop")),
				tostring(ComponentGetValue2(mc, "kill_when_finished")), tostring(ComponentGetValue2(mc, "radius")),
				tostring(ComponentGetValue2(mc, "mRadius")))
		end
		log("T4", name, "t=" .. t, #parts == 0 and "no MagicConvertMaterialComponent" or table.concat(parts, " ; "))
		wait(10)
	end
	kill(field)
	wait(10)
end

-- design option B: does a marker in c.extra_entities land on fields / material circles / bolts?
local function probe_marker(name, pattern, dx, dy)
	equip(name)
	local snap = snapshot()
	fire(dx, dy)
	local e = wait_new(snap, pattern, 20)
	describe("T5 " .. name, e)
	kill(e)
	wait(10)
end

-- prototype checks -----------------------------------------------------------------------------------------------

local function fi_get(e, name)
	for _, v in ipairs(EntityGetComponentIncludingDisabled(e, "VariableStorageComponent") or {}) do
		if ComponentGetValue2(v, "name") == name then
			return ComponentGetValue2(v, "value_string")
		end
	end
	return nil -- explicit: tostring() with zero arguments throws
end

local function luas(tag, e)
	for _, comp in ipairs(EntityGetComponentIncludingDisabled(e, "LuaComponent") or {}) do
		log(tag, "lua", ComponentGetValue2(comp, "script_source_file"), "enabled=" .. tostring(ComponentGetIsEnabled(comp)))
	end
	log(tag, "fi_payload=" .. tostring(fi_get(e, "fi_payload")), "fi_seen=" .. tostring(fi_get(e, "fi_seen")),
		"tags=" .. tostring(EntityGetTags(e)))
end

-- a trigger wand's field comes from the payload: the hit-world bolt is fired down at the ground, the timer bolt to
-- the side; either way the field is moved where the check wants it once it appears
local function cast_field(wand, x, y)
	equip(wand)
	local snap = snapshot()
	local trigger = wand:find("trigger", 1, true) ~= nil
	if trigger then
		fire(0, 1)
	else
		fire(1, 0)
	end
	local slow = trigger or wand:find("timer", 1, true) ~= nil
	local field = wait_new(snap, wand:find("resonant", 1, true) and "resonant_field" or "berserk_field", slow and 120 or 20)
	if field then
		EntitySetTransform(field, x, y)
	end
	return field
end

-- P1: the imbuing fire field keeps re-rolling ignition on creatures inside it
local function proto_area_fire()
	local fx, fy = PX + PAD_DX, PY
	local field = cast_field("imbue_burn_field", fx, fy)
	if not field then
		log("P1 NO FIELD")
		return
	end
	local flock = {}
	for _, o in ipairs({ { 18, 0 }, { -18, 0 }, { 0, 18 }, { 0, -18 } }) do
		flock[#flock + 1] = spawn_sheep(fx + o[1], fy + o[2])
	end
	for t = 1, 300 do
		wait(1)
		if t == 5 or t % 60 == 2 then
			local burning = 0
			for _, s in ipairs(flock) do
				if EntityGetIsAlive(s) and GameGetGameEffectCount(s, "ON_FIRE") > 0 then
					burning = burning + 1
				end
			end
			log("P1 t=" .. t, "burning sheep " .. burning .. "/4")
		end
	end
	luas("P1 field", field)
	kill(field, unpack(flock))
	wait(10)
end

-- P2/P3/P5: a spark bolt fired through a field towards a sheep 90px beyond it (outside the field's own reach)
local function proto_bolt_through(tag, field_wand, effect)
	local field = cast_field(field_wand, PX + 90, PY - 4)
	if not field then
		log(tag, "NO FIELD")
		return
	end
	-- a payload field's carrier bolt is still flying (towards where the sheep goes): remove it and anything else
	for _, p in ipairs(EntityGetWithTag("projectile") or {}) do
		if p ~= field then
			kill(p)
		end
	end
	wait(2)
	local sx, sy = PX + 180, PY - 4
	local sheep = spawn_sheep(sx, sy)
	equip("bolt")
	local snap = snapshot()
	fire(sx - PX, sy - (PY - 4))
	local bolt = wait_new(snap, "light_bullet", 10)
	if not bolt then
		log(tag, "NO BOLT")
		kill(field, sheep)
		return
	end
	if effect == "ON_FIRE" then
		-- ignition is a 50% roll per hit: fire a few more bolts through the field before judging
		for _ = 1, 3 do
			fire(sx - PX, sy - (PY - 4))
		end
	end
	local logged = false
	for t = 1, 40 do
		wait(1)
		if EntityGetIsAlive(bolt) then
			local bx, by = EntityGetTransform(bolt)
			if t % 3 == 0 then
				local hx, hy = EntityGetTransform(sheep)
				log(tag, "trace t=" .. t, ("bolt rel=%+.0f,%+.0f"):format(bx - PX, by - PY), angle(bolt),
					("sheep rel=%+.0f,%+.0f"):format((hx or 0) - PX, (hy or 0) - PY))
			end
			if not logged and bx > PX + 125 then -- past the field, before the sheep
				logged = true
				local pc = EntityGetFirstComponentIncludingDisabled(bolt, "ProjectileComponent")
				log(tag, "bolt after field: damage_game_effect_entities=" .. ComponentGetValue2(pc, "damage_game_effect_entities"),
					("ice=%.2f"):format(ComponentObjectGetValue2(pc, "damage_by_type", "ice")),
					"emitters=" .. #(EntityGetComponentIncludingDisabled(bolt, "ParticleEmitterComponent") or {}),
					"converters=" .. #(EntityGetComponentIncludingDisabled(bolt, "MagicConvertMaterialComponent") or {}),
					"fi_seen=" .. tostring(fi_get(bolt, "fi_seen")))
			end
		end
		if t % 10 == 0 then
			log(tag, "t=" .. t, "target sheep:", effects(sheep), "| " .. effect .. "=" .. GameGetGameEffectCount(sheep, effect))
		end
	end
	-- a bolt sometimes flies through the sheep without hitting it (plain bolts too, on the same path as the hits):
	-- after a miss, three more bolts through the field
	if EntityGetIsAlive(sheep) and GameGetGameEffectCount(sheep, effect) == 0 then
		for _ = 1, 3 do
			fire(sx - PX, sy - (PY - 4))
		end
		wait(20)
		log(tag, "after 3 more bolts: target sheep:", effects(sheep), "| " .. effect .. "=" .. GameGetGameEffectCount(sheep, effect))
	end
	kill(bolt, field, sheep)
	wait(10)
end

-- P4: a bolt cast together with Field resonance must drop the tick script (it is not a field)
local function proto_nonfield_host()
	equip("imbue_bolt")
	local snap = snapshot()
	fire(0, -1)
	local bolt = wait_new(snap, "light_bullet", 10)
	wait(3)
	if bolt and EntityGetIsAlive(bolt) then
		luas("P4 bolt", bolt)
	else
		log("P4 bolt gone/missing")
	end
	kill(bolt)
	wait(10)
end

-- P6: re-apply must skip the caster's herd (players carry "prey", so herd is what protects teammates)
local function proto_herd()
	local fx, fy = PX + PAD_DX, PY
	local field = cast_field("imbue_freeze_field", fx, fy)
	if not field then
		log("P6 NO FIELD")
		return
	end
	local ally = spawn_sheep(fx + 15, fy)
	local genome = EntityGetFirstComponentIncludingDisabled(ally, "GenomeDataComponent")
	ComponentSetValue2(genome, "herd_id", StringToHerdId("player"))
	local foe = spawn_sheep(fx - 15, fy)
	-- effect_frozen lasts 120 frames, so anything still frozen at t>=200 was re-applied by the field
	for t = 1, 300 do
		wait(1)
		if t == 5 or t == 140 or t == 200 or t == 260 then
			log("P6 t=" .. t, "player-herd sheep FROZEN=" .. GameGetGameEffectCount(ally, "FROZEN"),
				"| normal sheep FROZEN=" .. GameGetGameEffectCount(foe, "FROZEN"))
		end
	end
	kill(field, ally, foe)
	wait(10)
end

local function bolt_state(bolt)
	local pc = EntityGetFirstComponentIncludingDisabled(bolt, "ProjectileComponent")
	return ("effects=%s ice=%.2f converters=%d fi_seen=%s"):format(ComponentGetValue2(pc, "damage_game_effect_entities"),
		ComponentObjectGetValue2(pc, "damage_by_type", "ice"),
		#(EntityGetComponentIncludingDisabled(bolt, "MagicConvertMaterialComponent") or {}), tostring(fi_get(bolt, "fi_seen")))
end

-- P7/P9: shoot a bolt through an imbuing Freeze field and report what it carries afterwards
local function proto_bolt_kind(tag, wand)
	local field = cast_field("imbue_freeze_field", PX + 90, PY - 4)
	if not field then
		log(tag, "NO FIELD")
		return
	end
	equip(wand)
	local snap = snapshot()
	fire(1, 0)
	local bolt = wait_new(snap, "light_bullet", 10)
	if bolt then
		log(tag, "launch speed " .. angle(bolt), "state:", bolt_state(bolt))
		for _ = 1, 30 do -- until the bolt is past the field (centre +90, radius 28)
			wait(1)
			if not EntityGetIsAlive(bolt) or EntityGetTransform(bolt) > PX + 125 then
				break
			end
		end
		if EntityGetIsAlive(bolt) then
			local bx = EntityGetTransform(bolt)
			log(tag, ("past the field x=%+.0f"):format(bx - PX), "state:", bolt_state(bolt))
		else
			log(tag, "bolt gone before passing the field")
		end
	else
		log(tag, "NO BOLT")
	end
	kill(bolt, field)
	wait(10)
end

-- P10: Resonant field on its own does nothing to creatures inside it, and carries no scripts
local function proto_resonant_plain()
	local fx, fy = PX + PAD_DX, PY
	local field = cast_field("resonant_plain", fx, fy)
	if not field then
		log("P10 NO FIELD")
		return
	end
	local sheep = spawn_sheep(fx + 15, fy)
	wait(90)
	log("P10 plain resonant field: sheep effects:", effects(sheep), "CHARM=" .. GameGetGameEffectCount(sheep, "CHARM"), "(want all 0)")
	luas("P10 field", field)
	kill(field, sheep)
	wait(10)
end

-- P8: a static projectile (water cloud, speed 0) inside the field must not be imbued
local function proto_static()
	local fx, fy = PX + PAD_DX, PY
	local field = cast_field("imbue_freeze_field", fx, fy)
	if not field then
		log("P8 NO FIELD")
		return
	end
	local cloud = EntityLoad("data/entities/projectiles/deck/cloud_water.xml", fx + 5, fy)
	wait(30)
	log("P8 cloud alive=" .. tostring(EntityGetIsAlive(cloud)), "fi_seen=" .. tostring(EntityGetIsAlive(cloud) and fi_get(cloud, "fi_seen")),
		"converters=" .. #(EntityGetComponentIncludingDisabled(cloud, "MagicConvertMaterialComponent") or {}))
	kill(cloud, field)
	wait(10)
end

-- Sweep: every modifier with a recipe, cast as Field resonance + <modifier> + Circle of Fervour, then a spark bolt
-- through the field. Per modifier: did the field get it, does the field carry none of the modifier's own pieces
-- (component types compared with a plain circle), and was the bolt imbued.
local SWEEP_IGNORE = { LuaComponent = true, VariableStorageComponent = true, MagicConvertMaterialComponent = true }
-- ORBIT_NUKES works, but a nuke per test run is not worth it; FI_PROBE_MARKER is this probe's own test card
local SWEEP_EXCLUDE = { ORBIT_NUKES = true, FI_PROBE_MARKER = true }

local function profile(e)
	local counts = {}
	for _, comp in ipairs(EntityGetAllComponents(e) or {}) do
		local t = ComponentGetTypeName(comp)
		if not SWEEP_IGNORE[t] and not ComponentHasTag(comp, "fi_tint") then -- the coloured rim is the field's own
			counts[t] = (counts[t] or 0) + 1
		end
	end
	return counts
end

local function profile_extra(base, now)
	local out = {}
	for t, n in pairs(now) do
		if n > (base[t] or 0) then
			out[#out + 1] = t .. "+" .. (n - (base[t] or 0))
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function quiet_cleanup()
	-- twice: killing e.g. a Chain spell bolt spawns its children on removal
	for _ = 1, 2 do
		for _, p in ipairs(EntityGetInRadiusWithTag(PX, PY, 800, "projectile") or {}) do
			for _, pc in ipairs(EntityGetComponentIncludingDisabled(p, "ProjectileComponent") or {}) do
				ComponentSetValue2(pc, "on_death_explode", false)
				ComponentSetValue2(pc, "on_lifetime_out_explode", false)
			end
			EntityKill(p)
		end
		wait(10)
	end
end

-- the spark bolt the player itself just shot (not a leftover child of an earlier test's projectile)
local function wait_own_bolt(snap)
	for _ = 1, 10 do
		for _, p in ipairs(EntityGetWithTag("projectile") or {}) do
			if not snap[p] and (EntityGetFilename(p) or ""):find("light_bullet", 1, true) then
				local pc = EntityGetFirstComponentIncludingDisabled(p, "ProjectileComponent")
				local parent = pc and ComponentGetValue2(pc, "mEntityThatShot") or 0
				if pc and ComponentGetValue2(pc, "mWhoShot") == player and (parent == 0 or not EntityHasTag(parent, "projectile")) then
					return p
				end
			end
		end
		wait(1)
	end
end

local function proto_sweep()
	local R = dofile_once("mods/field_imbue/files/gen/recipes.lua")
	local ids = {}
	log("SWEEP settings: enemy=" .. tostring(ModSettingGet("field_imbue.imbue_enemy_projectiles")),
		"destructive=" .. tostring(ModSettingGet("field_imbue.allow_destructive")),
		"recipes: ORBIT_NUKES=" .. tostring(R.ORBIT_NUKES ~= nil), "RANDOM_EXPLOSION=" .. tostring(R.RANDOM_EXPLOSION ~= nil))
	for id in pairs(R) do
		local wanted = next(SWEEP_ONLY) == nil and not SWEEP_EXCLUDE[id] or SWEEP_ONLY[id]
		if wanted then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	WANDS.plain_field = "BERSERK_FIELD"
	local plain = cast_field("plain_field", PX + 90, PY - 4)
	if not plain then
		log("SWEEP no baseline field")
		return
	end
	local base = profile(plain)
	quiet_cleanup()
	wait(5)
	local n_payload, n_clean, n_imbued = 0, 0, 0
	for _, id in ipairs(ids) do
		WANDS.sweep = "FIELD_IMBUE," .. id .. ",BERSERK_FIELD"
		local field = cast_field("sweep", PX + 90, PY - 4)
		if not field then
			log("SWEEP", id, "NO FIELD")
		else
			wait(2)
			local has = ("," .. (fi_get(field, "fi_payload") or "") .. ","):find("," .. id .. ",", 1, true) ~= nil
			local extra = profile_extra(base, profile(field))
			equip("bolt")
			local snap = snapshot()
			fire(1, 0)
			local bolt = wait_own_bolt(snap)
			local mods
			for _ = 1, 30 do
				if not bolt or not EntityGetIsAlive(bolt) then
					break
				end
				mods = fi_get(bolt, "fi_mods") or mods
				if EntityGetTransform(bolt) > PX + 125 then
					break
				end
				wait(1)
			end
			local imbued = mods ~= nil and mods:find("," .. id .. ",", 1, true) ~= nil
			n_payload = n_payload + (has and 1 or 0)
			n_clean = n_clean + (extra == "" and 1 or 0)
			n_imbued = n_imbued + (imbued and 1 or 0)
			log("SWEEP", id, "payload=" .. tostring(has), "centre=" .. (extra == "" and "clean" or ("EXTRA:" .. extra)),
				"bolt_imbued=" .. tostring(imbued))
		end
		quiet_cleanup()
		wait(5)
	end
	log(("SWEEP summary: %d modifiers, payload %d, clean centre %d, bolt imbued %d"):format(#ids, n_payload, n_clean, n_imbued))
end

-- Regressions from the second review: Field resonance without a field must not strip anything (B1), and a bolt cast
-- in the same multicast as its field must not get the shot's modifiers twice (B2).
local function first_own_bolt(wand, dx, dy)
	equip(wand)
	local snap = snapshot()
	fire(dx, dy)
	local bolt = wait_own_bolt(snap)
	wait(2)
	return bolt
end

local function speed_of(bolt)
	local vc = bolt and EntityGetIsAlive(bolt) and EntityGetFirstComponentIncludingDisabled(bolt, "VelocityComponent")
	if not vc then
		return -1
	end
	local vx, vy = ComponentGetValue2(vc, "mVelocity")
	return math.sqrt(vx * vx + vy * vy)
end

local function homing_count(bolt)
	return bolt and EntityGetIsAlive(bolt) and #(EntityGetComponentIncludingDisabled(bolt, "HomingComponent") or {}) or -1
end

-- E1: an enemy's projectile through an imbuing Freeze field (imbued only with "Imbue enemy projectiles" on)
local function proto_enemy()
	local field = cast_field("imbue_freeze_field", PX + 90, PY - 4)
	if not field then
		log("E1 NO FIELD")
		return
	end
	local shooter = spawn_sheep(PX + 30, PY - 4)
	local bolt = shoot_projectile(shooter, "data/entities/projectiles/deck/light_bullet.xml", PX + 40, PY - 4, 700, 0)
	local mods
	for _ = 1, 30 do
		if not bolt or not EntityGetIsAlive(bolt) then
			break
		end
		mods = fi_get(bolt, "fi_mods") or mods
		if EntityGetTransform(bolt) > PX + 125 then
			break
		end
		wait(1)
	end
	log("E1 enemy projectile through field: imbued=" .. tostring(mods ~= nil),
		"(setting imbue_enemy_projectiles=" .. tostring(ModSettingGet("field_imbue.imbue_enemy_projectiles")) .. ")")
	kill(shooter)
	quiet_cleanup()
end

local function proto_regress()
	WANDS.r1 = "FIELD_IMBUE,HOMING,LIGHT_BULLET"
	local b = first_own_bolt("r1", 0, -1)
	log("R1 no field in shot: bolt HomingComponents=" .. homing_count(b), "(want >=1)")
	quiet_cleanup()

	-- Heavy shot (x0.3) rather than Speed up: x2.5 already hits the ~1000 px/s cap, so doubling it would not show
	WANDS.r2_control = "BURST_2,HEAVY_SHOT,LIGHT_BULLET,BERSERK_FIELD"
	WANDS.r2 = "BURST_2,FIELD_IMBUE,HEAVY_SHOT,LIGHT_BULLET,BERSERK_FIELD"
	local s_control = speed_of(first_own_bolt("r2_control", 0, -1))
	quiet_cleanup()
	local s_imbue = speed_of(first_own_bolt("r2", 0, -1))
	log(("R2 multicast speed: control %.0f, with Field resonance %.0f (want equal, not x2.5 again)"):format(s_control, s_imbue))
	quiet_cleanup()

	-- repeated: the order of the field's and the bolt's first-frame scripts is not fixed
	WANDS.r3 = "BURST_2,FIELD_IMBUE,HOMING,LIGHT_BULLET,BERSERK_FIELD"
	for run = 1, 5 do
		equip("r3")
		local snap = snapshot()
		fire(0, -1)
		local bolt = wait_own_bolt(snap)
		local field = wait_new(snap, "berserk_field", 10)
		wait(3)
		log("R3." .. run .. " multicast homing: bolt HomingComponents=" .. homing_count(bolt), "(want 1)",
			"field HomingComponents=" .. (field and #(EntityGetComponentIncludingDisabled(field, "HomingComponent") or {}) or -1), "(want 0)",
			"bolt fi_mods=" .. tostring(bolt and EntityGetIsAlive(bolt) and fi_get(bolt, "fi_mods")))
		quiet_cleanup()
	end
end

local function children_from(e, file)
	local n = 0
	for _, k in ipairs(EntityGetIsAlive(e) and EntityGetAllChildren(e) or {}) do
		if EntityGetFilename(k) == file then
			n = n + 1
		end
	end
	return n
end

local function curse_damage(e)
	for _, k in ipairs(EntityGetIsAlive(e) and EntityGetAllChildren(e) or {}) do
		local v = EntityGetFirstComponentIncludingDisabled(k, "VariableStorageComponent", "effect_curse_damage")
		if v then
			return ("%.2f"):format(ComponentGetValue2(v, "value_float"))
		end
	end
	return "none"
end

-- P12: hit-effect modifiers act over a field's area: Venomous curse (keeps the sheep cursed, damage not stacking, never
-- the caster's herd), Weakening curse (one child), Petrify (only wounded sheep), Charm on toxic sludge (only the
-- radioactive sheep). Explosion on slimy enemies, Personal gravity field, Critical on wet and Critical plus stay on-hit (no
-- area entry in their recipes).
local function proto_hit_area()
	local R = dofile_once("mods/field_imbue/files/gen/recipes.lua")
	for _, id in ipairs({ "CURSE", "CURSE_WITHER_PROJECTILE", "HITFX_PETRIFY", "HITFX_TOXIC_CHARM", "HITFX_EXPLOSION_SLIME", "GRAVITY_FIELD_ENEMY", "FIREBALL_RAY_ENEMY", "HITFX_CRITICAL_WATER", "CRITICAL_HIT" }) do
		local parts = {}
		for _, ef in ipairs(R[id] and R[id].effects or {}) do
			parts[#parts + 1] = (ef.child and "child:" or "effect:") .. tostring(ef.effect or ef.file) .. "[" .. table.concat(ef.cond or {}, "+") .. "]"
		end
		log("P12 recipe", id, "area entries:", #parts > 0 and table.concat(parts, " ") or "none")
	end
	local fx, fy = PX + PAD_DX, PY

	local field = cast_field("resonant_curse", fx, fy)
	if not field then
		log("P12 curse NO FIELD")
	else
		local foe = spawn_sheep(fx + 15, fy)
		local ally = spawn_sheep(fx - 15, fy)
		ComponentSetValue2(EntityGetFirstComponentIncludingDisabled(ally, "GenomeDataComponent"), "herd_id", StringToHerdId("player"))
		-- the curse lasts 300 frames: still cursed at t=450 means the field cursed it again
		for t = 1, 460 do
			wait(1)
			if t == 70 or t == 200 or t == 330 or t == 450 then
				log("P12 curse t=" .. t, "sheep cursed=" .. tostring(EntityHasTag(foe, "effect_CURSE")),
					"curse children=" .. children_from(foe, "data/entities/misc/curse.xml"), "curse damage=" .. curse_damage(foe),
					"(want 0.08)", "| player-herd sheep cursed=" .. tostring(EntityHasTag(ally, "effect_CURSE")))
			end
		end
		kill(field, foe, ally)
		wait(10)
	end

	field = cast_field("resonant_wither", fx, fy)
	if not field then
		log("P12 wither NO FIELD")
	else
		local foe = spawn_sheep(fx + 15, fy)
		for t = 1, 200 do
			wait(1)
			if t == 70 or t == 190 then
				log("P12 wither t=" .. t, "curse_wither_projectile children=" .. children_from(foe, "data/entities/misc/curse_wither_projectile.xml"), "(want 1)")
			end
		end
		kill(field, foe)
		wait(10)
	end

	field = cast_field("resonant_petrify", fx, fy)
	if not field then
		log("P12 petrify NO FIELD")
	else
		local wounded = spawn_sheep(fx + 15, fy)
		local dm = EntityGetFirstComponentIncludingDisabled(wounded, "DamageModelComponent")
		ComponentSetValue2(dm, "hp", 12) -- 30% of 40: petrify works at 40% or less
		local healthy = spawn_sheep(fx - 15, fy)
		wait(75)
		log("P12 petrify: wounded sheep alive=" .. tostring(EntityGetIsAlive(wounded)), "(want false)",
			"| healthy sheep alive=" .. tostring(EntityGetIsAlive(healthy)), "(want true)")
		kill(field, wounded, healthy)
		wait(10)
	end

	field = cast_field("resonant_toxic_charm", fx, fy)
	if not field then
		log("P12 toxic charm NO FIELD")
	else
		local toxic = spawn_sheep(fx + 15, fy)
		LoadGameEffectEntityTo(toxic, "data/entities/misc/effect_radioactive.xml")
		local clean = spawn_sheep(fx - 15, fy)
		wait(75)
		log("P12 toxic charm: radioactive sheep CHARM=" .. GameGetGameEffectCount(toxic, "CHARM"), "(want 1)",
			"| clean sheep CHARM=" .. GameGetGameEffectCount(clean, "CHARM"), "(want 0)")
		kill(field, toxic, clean)
		wait(10)
	end

	-- explosions on slimy enemies stay imbue-only (an ownerless blast every second would hit the caster too)
	field = cast_field("resonant_slime_explosion", fx, fy)
	if not field then
		log("P12 slime explosion NO FIELD")
	else
		local slimy = spawn_sheep(fx + 15, fy)
		LoadGameEffectEntityTo(slimy, "data/entities/misc/effect_slimy.xml")
		local clean = spawn_sheep(fx - 15, fy)
		wait(75)
		log("P12 slime explosion (imbue-only): slimy sheep " .. effects(slimy), "(want hp=40)", "| clean sheep " .. effects(clean), "(want hp=40)")
		kill(field, slimy, clean)
		wait(10)
	end
end

-- P13: Field resonance inside a trigger payload makes the payload's circle an imbuing field (P13a hit-world trigger,
-- P13b timer, P13c Resonant field in a timer payload, P13d control: a payload circle without resonance stays vanilla)
local function proto_payload_field(tag, wand)
	local field = cast_field(wand, PX + 90, PY - 4)
	if not field then
		log(tag, "NO FIELD")
		return
	end
	wait(3)
	local pc = EntityGetFirstComponentIncludingDisabled(field, "ProjectileComponent")
	local parent = ComponentGetValue2(pc, "mEntityThatShot")
	log(tag, "payload field: shot by a projectile=" .. tostring(parent ~= 0 and parent ~= player), "who shot is player=" .. tostring(ComponentGetValue2(pc, "mWhoShot") == player))
	luas(tag .. " field", field)
	kill(field)
	quiet_cleanup()
end

-- P14: a payload bolt (shot by the timer bolt) crossing an imbuing field is still not imbued
local function proto_payload_bolt()
	local field = cast_field("imbue_freeze_field", PX + 200, PY)
	if not field then
		log("P14 NO FIELD")
		return
	end
	equip("timer_bolt")
	local snap = snapshot()
	fire(1, 0)
	local bolts = {}
	for _ = 1, 45 do
		for _, p in ipairs(EntityGetWithTag("projectile") or {}) do
			if not snap[p] and (EntityGetFilename(p) or ""):find("light_bullet", 1, true) then
				local b = bolts[p]
				if not b then
					local pc = EntityGetFirstComponentIncludingDisabled(p, "ProjectileComponent")
					local parent = pc and ComponentGetValue2(pc, "mEntityThatShot") or 0
					b = { payload = parent ~= 0 and parent ~= player, minx = 1e9, maxx = -1e9 }
					bolts[p] = b
				end
				b.mods = fi_get(p, "fi_mods") or b.mods
				b.minx = math.min(b.minx, (EntityGetTransform(p)) - PX)
				b.maxx = math.max(b.maxx, (EntityGetTransform(p)) - PX)
			end
		end
		wait(1)
	end
	for _, b in pairs(bolts) do
		log("P14 bolt payload=" .. tostring(b.payload), ("x from %+.0f to %+.0f"):format(b.minx, b.maxx), "(field 172..228: want across it)",
			"fi_mods=" .. tostring(b.mods), b.payload and "(want nil)" or "")
	end
	kill(field)
	quiet_cleanup()
end

local function tints(e)
	local out = {}
	for _, pe in ipairs(EntityGetComponentIncludingDisabled(e, "ParticleEmitterComponent", "fi_tint") or {}) do
		out[#out + 1] = ComponentGetValue2(pe, "emitted_material_name")
	end
	return #out > 0 and table.concat(out, ",") or "none"
end

-- P15: an imbuing field shows its payload's colours; plain vanilla circles get none
local function proto_tint()
	local R = dofile_once("mods/field_imbue/files/gen/recipes.lua")
	local by_colour, ids = {}, {}
	for id, r in pairs(R) do
		ids[#ids + 1] = id
		if not id:find("^FI_PROBE") then -- this probe's own test card
			by_colour[r.colour or "nil"] = (by_colour[r.colour or "nil"] or 0) + 1
		end
	end
	table.sort(ids)
	local summary = {}
	for c, n in pairs(by_colour) do
		summary[#summary + 1] = c .. "=" .. n
	end
	table.sort(summary)
	log("P15 recipe colours:", table.concat(summary, " "))
	for _, id in ipairs(ids) do
		log("P15 colour", id, tostring(R[id].colour))
	end
	for _, w in ipairs({ "imbue_freeze_field", "imbue_burn_field", "imbue_mixed_field", "resonant_freeze", "field", "freeze_field" }) do
		local field = cast_field(w, PX + PAD_DX, PY)
		if field then
			wait(3)
			log("P15", w, "tint emitters:", tints(field), "emitters total=" .. #(EntityGetComponentIncludingDisabled(field, "ParticleEmitterComponent") or {}))
		else
			log("P15", w, "NO FIELD")
		end
		kill(field)
		quiet_cleanup()
	end
end

local function run_prototype()
	proto_herd()
	proto_bolt_kind("P7 fast-bolt", "fast_bolt")
	proto_static()
	proto_bolt_kind("P9 freeze-bolt", "freeze_bolt")
	proto_area_fire()
	proto_bolt_through("P2 imbue-freeze", "imbue_freeze_field", "FROZEN")
	proto_bolt_through("P3 control-freeze", "freeze_field", "FROZEN")
	proto_nonfield_host()
	proto_bolt_through("P5 imbue-fire", "imbue_burn_field", "ON_FIRE")
	proto_bolt_through("P11 resonant-freeze", "resonant_freeze", "FROZEN")
	proto_resonant_plain()
	proto_hit_area()
	proto_payload_field("P13a trigger", "trigger_freeze_field")
	proto_payload_field("P13b timer", "timer_freeze_field")
	proto_payload_field("P13c timer-resonant", "timer_resonant_freeze")
	proto_payload_field("P13d timer-control", "timer_plain_field")
	proto_bolt_through("P13e timer-freeze bolt", "timer_freeze_field", "FROZEN")
	proto_bolt_through("P13f timer-resonant bolt", "timer_resonant_freeze", "FROZEN")
	proto_bolt_through("P13g trigger-freeze bolt", "trigger_freeze_field", "FROZEN")
	proto_payload_bolt()
	proto_tint()
end

-- Entangled Worlds two-peer check (docs/RESEARCH.md §6 test 6) -----------------------------------------------------
-- Both peers run this. The host acts; the client parks next to it and only observes. Compare the two logger.txt files.

local function ew_push_inventory()
	if ModIsEnabled("quant.ew") and CrossCall then
		dofile_once("mods/quant.ew/files/api/ew_crosscalls.lua").force_update_inventory()
	end
end

local ew_logged = {}
local function ew_observe(tag)
	for _, f in ipairs(EntityGetWithTag("fi_field") or {}) do
		local fx, fy = EntityGetTransform(f)
		log(tag, "field", ("rel=%.0f,%.0f"):format(fx - PX, fy - PY), "payload=" .. tostring(fi_get(f, "fi_payload")))
	end
	for _, p in ipairs(EntityGetWithTag("projectile") or {}) do
		if not ew_logged[p] and fi_get(p, "fi_seen") then
			ew_logged[p] = true
			local pc = EntityGetFirstComponentIncludingDisabled(p, "ProjectileComponent")
			local px, py = EntityGetTransform(p)
			log(tag, "imbued projectile", EntityGetFilename(p), ("rel=%.0f,%.0f"):format(px - PX, py - PY),
				"effects=" .. tostring(pc and ComponentGetValue2(pc, "damage_game_effect_entities")))
		end
	end
	for _, s in ipairs(EntityGetWithTag("sheep") or {}) do
		local sx, sy = EntityGetTransform(s)
		log(tag, "sheep", ("rel=%.0f,%.0f"):format(sx - PX, sy - PY), effects(s))
	end
end

local function wait_for_peer()
	for i = 1, 60 * 600 do
		if #EntityGetWithTag("ew_client") > 0 then
			log("EW peer present after " .. i .. " frames")
			return true
		end
		wait(1)
	end
	log("EW no peer within 10 minutes")
	return false
end

local function heartbeat(tag)
	local others = {}
	for _, c in ipairs(EntityGetWithTag("ew_client") or {}) do
		local cx, cy = EntityGetTransform(c)
		others[#others + 1] = ("%.0f,%.0f"):format(cx - PX, cy - PY)
	end
	local near, circles = 0, 0
	for _, p in ipairs(EntityGetInRadiusWithTag(PX, PY, 400, "projectile") or {}) do
		near = near + 1
		if (EntityGetFilename(p) or ""):find("berserk_field", 1, true) then
			circles = circles + 1
		end
	end
	log(tag, "heartbeat frame=" .. GameGetFrameNum(), "peers at " .. table.concat(others, " "),
		"sheep=" .. #(EntityGetWithTag("sheep") or {}), "prey=" .. #(EntityGetWithTag("prey") or {}),
		"projectiles<400px=" .. near, "fervour_circles=" .. circles, "fi_fields=" .. #(EntityGetWithTag("fi_field") or {}))
end

local function observe_for(tag, frames)
	for t = 1, frames do
		wait(1)
		if t % 20 == 0 then
			ew_observe(tag)
		end
		if t % 60 == 0 then
			heartbeat(tag)
		end
	end
end

local function ew_host_cast(wand)
	equip(wand)
	ew_push_inventory()
	wait(30)
	local snap = snapshot()
	fire(1, 0)
	return wait_new(snap, "berserk_field", 20)
end

local function ew_host()
	log("EW role=host")
	observe_for("EW host", 180) -- let the client arrive and settle
	-- 1) imbuing Freeze field: sheep inside (area re-apply) and a target beyond it (imbued bolt)
	local field = ew_host_cast("imbue_freeze_field")
	if not field then
		log("EW host NO FIELD")
		return
	end
	local fx, fy = EntityGetTransform(field)
	log("EW host freeze field", ("rel=%.0f,%.0f"):format(fx - PX, fy - PY))
	local inside = spawn_sheep(fx + 15, fy)
	local target = spawn_sheep(fx + 110, fy)
	observe_for("EW host", 120)
	equip("bolt")
	ew_push_inventory()
	wait(30)
	local hx, hy = EntityGetTransform(target)
	wand_state("EW host before bolt")
	fire(hx - PX, hy - (PY - 4))
	local ax, ay = ComponentGetValue2(ctrl, "mAimingVector")
	log("EW host bolt fired, aim=" .. ("%.0f,%.0f"):format(ax, ay), "wanted=" .. ("%.0f,%.0f"):format(hx - PX, hy - (PY - 4)))
	observe_for("EW host", 180)
	kill(field, inside, target)
	-- 2) imbuing fire field: 4 sheep inside, re-apply should ignite all within a few rolls
	field = ew_host_cast("imbue_burn_field")
	if field then
		fx, fy = EntityGetTransform(field)
		local flock = {}
		for _, o in ipairs({ { 18, 0 }, { 0, 18 }, { 0, -18 }, { 22, 10 } }) do
			flock[#flock + 1] = spawn_sheep(fx + o[1], fy + o[2])
		end
		observe_for("EW host", 360)
		kill(field, unpack(flock))
	end
	log("EW host sequence finished")
	observe_for("EW host", 120)
end

local function ew_client()
	log("EW role=client")
	pin(player, PX - 40, PY) -- next to the host, out of its bolt path
	observe_for("EW client", 60 * 80)
end

local function calibrate_fire()
	-- 1) untouched starting wand: isolates "does the trigger method work at all"
	for _, mode in ipairs({ "hold", "force" }) do
		wand_state("CAL starting-wand before " .. mode)
		local ok = fire(0, -1, mode)
		wand_state("CAL starting-wand after " .. mode)
		log("CAL starting-wand", mode, "shot_counter_up=" .. tostring(ok))
		wait(40)
	end
	-- 2) the same wand after rewriting its cards
	for _, mode in ipairs({ "hold", "force" }) do
		equip("bolt")
		wand_state("CAL before " .. mode)
		local snap = snapshot()
		local ok = fire(0, -1, mode)
		local bolt = wait_new(snap, "light_bullet", 10)
		wand_state("CAL after " .. mode)
		log("CAL", mode, "shot_counter_up=" .. tostring(ok), "bolt_found=" .. tostring(bolt ~= nil))
		kill(bolt)
		if ok or bolt then
			FIRE_MODE = mode
			return true
		end
	end
	return false
end

local function run_all()
	log("START frame=" .. GameGetFrameNum(), ("player pinned at %.0f,%.0f"):format(PX, PY))
	if SUITE == "ew" then
		-- the fire method is already calibrated ("hold"); calibration shots would only add noise on the other peer.
		-- Decide the role only once the peer is there: EW sets the host flag after the proxy link is up.
		if not wait_for_peer() then
			log("DONE frame=" .. GameGetFrameNum())
			return
		end
		if GameHasFlagRun("ew_flag_this_is_host") then
			ew_host()
		else
			ew_client()
		end
		log("DONE frame=" .. GameGetFrameNum())
		return
	end
	if not calibrate_fire() then
		log("ABORT no fire method worked")
		probe_added()
		log("DONE frame=" .. GameGetFrameNum())
		return
	end
	log("CAL using fire mode", FIRE_MODE)
	if SUITE == "sweep" then
		log("SUITE sweep, field_imbue enabled=" .. tostring(ModIsEnabled("field_imbue")))
		proto_enemy()
		proto_regress()
		proto_sweep()
		log("DONE frame=" .. GameGetFrameNum())
		return
	end
	if SUITE == "prototype" then
		log("SUITE prototype, field_imbue enabled=" .. tostring(ModIsEnabled("field_imbue")))
		run_prototype()
		log("DONE frame=" .. GameGetFrameNum())
		return
	end
	probe_field_effects("field", true) -- control: plain Circle of Fervour
	probe_field_effects("freeze_field", true)
	probe_field_effects("burn_field", true)
	set_protection(false) -- PROTECTION_ALL might be what keeps the caster out of the field
	probe_field_effects("pierce_field", false) -- field left on the caster
	set_protection(true)
	probe_bolt_config()
	probe_midflight_homing(false)
	probe_midflight_homing(true)
	probe_midflight_freeze(false)
	probe_midflight_freeze(true)
	probe_added()
	probe_converter("conv_field")
	probe_converter("conv2_field")
	probe_marker("marker_bolt", "light_bullet", 0, -1)
	probe_marker("marker_field", "berserk_field", 1, 0)
	probe_marker("marker_fire", "circle_fire", 1, 0)
	log("DONE frame=" .. GameGetFrameNum())
	GamePrint("field_imbue probes DONE")
end

-- setup -----------------------------------------------------------------------------------------------------------

local function find_clear_spot(x, y)
	-- climb until a 260px-wide horizontal band is free of cells
	for step = 0, 12 do
		local ty = y - 200 - step * 60
		local clear = true
		for _, oy in ipairs({ -70, -40, 0, 30 }) do
			if Raytrace(x - 40, ty + oy, x + 260, ty + oy) then
				clear = false
			end
		end
		if clear then
			return x, ty
		end
	end
	return x, y - 300
end

local started = false

function OnPlayerSpawned(player_entity)
	player = player_entity
end

function OnWorldPostUpdate()
	if not player or not EntityGetIsAlive(player) then
		return
	end
	if not started then
		if GameGetFrameNum() < 180 then
			return
		end
		started = true
		local x, y = EntityGetTransform(player)
		PX, PY = find_clear_spot(x, y)
		log("setup spawn", ("%.0f,%.0f"):format(x, y), "-> test spot", ("%.0f,%.0f"):format(PX, PY))
		set_protection(true)
		local inv = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
		current_wand = ComponentGetValue2(inv, "mActualActiveItem")
		log("setup held item", current_wand, current_wand ~= 0 and EntityGetFilename(current_wand) or "none",
			"holstered=" .. tostring(ComponentGetValue2(inv, "mItemHolstered")))
		if current_wand == 0 or not ability() then
			log("ABORT player holds no wand")
			log("DONE frame=" .. GameGetFrameNum())
			return
		end
		ctrl = EntityGetFirstComponentIncludingDisabled(player, "ControlsComponent")
		ComponentSetValue2(ctrl, "enabled", false)
		pin(player, PX, PY)
		runner = coroutine.create(run_all)
	end
	apply_pins()
	if runner and coroutine.status(runner) ~= "dead" then
		local ok, err = coroutine.resume(runner)
		if not ok then
			log("ERROR", err)
		end
	end
end
