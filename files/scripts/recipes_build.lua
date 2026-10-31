-- Runs once from init.lua's OnModPostInit, after every mod's gun_actions appends are registered. Evaluates each
-- modifier the way vanilla builds spell tooltips (reflecting = true, as in gun_collect_metadata.lua and the
-- Potent Potions mod) and records what it does to the shot state. Writes virtual files:
--   mods/field_imbue/files/gen/recipes.lua   modifier id -> recipe (what imbuing a projectile with it means)
--   mods/field_imbue/files/gen/skipped.lua   modifier id -> why it has no recipe
--   mods/field_imbue/files/gen/mod/<ID>.xml  marker the cast hook merges onto imbuing fields
-- Every peer runs this with the same mods, so the recipes are identical everywhere (Entangled Worlds).

local GEN = "mods/field_imbue/files/gen/"

-- never imbued: Field resonance itself; RANDOM_MODIFIER (the modifier it picks is recorded on its own); and, unless
-- the "Allow Nuke orbit and Chaos magic" setting is on (settings.lua), modifiers that would hand out nukes / black holes
-- on every projectile crossing a field for 2 minutes. Settings are applied before mod init, so this is the run's value.
local SKIP = {
	FIELD_IMBUE = "the opt-in card itself",
	RANDOM_MODIFIER = "the modifier it picks is recorded instead",
	DAMAGE_RANDOM = "re-rolls every cast (seeds from the frame number, so the stability check can't see it)",
}
if not ModSettingGet("field_imbue.allow_destructive") then
	SKIP.ORBIT_NUKES = "a nuke orbit on every projectile is too destructive (setting: Allow Nuke orbit and Chaos magic)"
	SKIP.RANDOM_EXPLOSION = "can spawn nukes and black holes on every projectile (setting: Allow Nuke orbit and Chaos magic)"
end

-- shot-state fields that mean something on a projectile that is already flying
local ADD = {
	"damage_projectile_add", "damage_melee_add", "damage_electricity_add", "damage_fire_add", "damage_explosion_add",
	"damage_ice_add", "damage_slice_add", "damage_healing_add", "damage_curse_add", "damage_drill_add",
	"explosion_radius", "damage_critical_chance", "knockback_force", "lifetime_add", "bounces", "gravity",
}
local LIST = { "extra_entities", "game_effect_entities", "trail_material" }

local ENGINE_STUBS = { "EntityLoad", "BeginProjectile", "EndProjectile", "RegisterProjectile", "RegisterGunAction",
	"RegisterGunShotEffects", "BeginTriggerTimer", "BeginTriggerHitWorld", "BeginTriggerDeath", "EndTrigger",
	"SetProjectileConfigs", "StartReload", "ActionUsesRemainingChanged", "ActionUsed", "LogAction", "OnActionPlayed",
	"OnNotEnoughManaForAction" }

local backup = {}
for k, v in pairs(_G) do
	backup[k] = v
end
-- dofile/dofile_once caches live in these engine tables; entries added here must go too, or later dofile_once
-- calls in this Lua state would think gun.lua's helpers are still loaded after the restore below
local cache_keys = {}
for _, name in ipairs({ "__loadonce", "__loaded" }) do
	cache_keys[name] = {}
	for k in pairs(type(_G[name]) == "table" and _G[name] or {}) do
		cache_keys[name][k] = true
	end
end

local recipes, skipped = {}, {}

local function split(s)
	local out = {}
	for part in (s or ""):gmatch("[^,]+") do
		out[#out + 1] = part
	end
	return out
end

local function file_text(path)
	local ok, text = pcall(ModTextFileGetContent, path)
	return ok and text or ""
end

local function serialize(v, indent)
	indent = indent or ""
	if type(v) == "string" then
		return ("%q"):format(v)
	elseif type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in ipairs(keys) do
		local key = type(k) == "number" and "" or (("[%q] = "):format(k))
		parts[#parts + 1] = indent .. "\t" .. key .. serialize(v[k], indent .. "\t")
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local spawned = 0

-- On-hit effects (HitEffectComponent) that also mean something for a creature standing in a field: loading a game
-- effect or a child entity, maybe only onto creatures that have some effect or status. Critical hits and damage boosts
-- are part of the hit itself, so those stay imbue-only.
local HIT_EFFECT_KINDS = { LOAD_UNIQUE_GAME_EFFECT = "effect", LOAD_GAME_EFFECT = "effect",
	LOAD_UNIQUE_CHILD_ENTITY = "child", LOAD_CHILD_ENTITY = "child" }
-- children that remove themselves right away and leave something else behind: the root tag that means the creature
-- already has it (Venomous curse's curse_init.xml stacks +0.08 damage on every load otherwise)
local HIT_GUARD_TAGS = { ["data/entities/misc/curse_init.xml"] = "effect_CURSE" }
local status_effect -- status id (SLIMY, RADIOACTIVE, ...) -> the game effect it gives, read in build()

local function attr(s, name)
	local v = s:match("%s" .. name .. '%s*=%s*"([^"]*)"')
	if v ~= "" and v ~= "NONE" then
		return v
	end
end

-- The colour an imbuing field shows for a modifier (a spark material, see fi_lib.tint): the first match in what the
-- modifier puts on a projectile, in this order: its game effects, words starting its trail materials and files (a
-- converter "<a>_to_<b>" by what it makes), its damage types. Anything else gets a colour for its kind: on-hit effects
-- purple, other extras teal, only numbers white.
local EFFECT_COLOURS = { FROZEN = "spark_blue", ON_FIRE = "spark_yellow", ELECTROCUTION = "spark_electric",
	CHARM = "spark_purple_bright", WET = "spark_blue_dark", RADIOACTIVE = "spark_green", POISON = "spark_green",
	BERSERK = "spark_red", BLOODY = "spark_red", OILED = "spark_player", SLIMY = "spark_purple_bright" }
local WORD_COLOURS = {
	{ "curse", "spark_purple" }, { "freez", "spark_blue" }, { "ice", "spark_blue" }, { "snow", "spark_blue" },
	{ "fire", "spark_yellow" }, { "burn", "spark_yellow" }, { "lava", "spark_yellow" }, { "electr", "spark_electric" },
	{ "lightning", "spark_electric" }, { "water", "spark_blue_dark" }, { "poison", "spark_green" }, { "acid", "spark_green" },
	{ "toxic", "spark_green" }, { "radioactive", "spark_green" }, { "blood", "spark_red" }, { "explo", "spark_red" },
	{ "gunpowder", "spark_red" }, { "heal", "spark_green_bright" }, { "oil", "spark_player" }, { "slime", "spark_purple_bright" },
}
local ADD_COLOURS = {
	{ "damage_ice_add", "spark_blue" }, { "damage_fire_add", "spark_yellow" }, { "damage_electricity_add", "spark_electric" },
	{ "damage_curse_add", "spark_purple" }, { "damage_healing_add", "spark_green_bright" },
	{ "damage_explosion_add", "spark_red" }, { "explosion_radius", "spark_red" },
}

local function colour(r)
	for _, ef in ipairs(r.effects or {}) do
		if EFFECT_COLOURS[ef.effect] then
			return EFFECT_COLOURS[ef.effect]
		end
	end
	local words, extras = {}, 0
	for _, list in ipairs({ r.trail_material or {}, r.game_effect_entities or {}, r.extra_entities or {} }) do
		for _, w in ipairs(list) do
			if not w:find("data/entities/particles/", 1, true) then -- shared sparkles say nothing about the modifier
				local name = w:match("[^/]*$")
				words[#words + 1] = name:match("_to_(.*)") or name
				extras = extras + (list == r.extra_entities and 1 or 0)
			end
		end
	end
	local text = table.concat(words, ",")
	for _, wc in ipairs(WORD_COLOURS) do
		if text:find("%f[%a]" .. wc[1]) then
			return wc[2]
		end
	end
	for _, kc in ipairs(ADD_COLOURS) do
		if (r.add or {})[kc[1]] then
			return kc[2]
		end
	end
	if #(r.effects or {}) > 0 or #(r.game_effect_entities or {}) > 0 then
		return "spark_purple"
	elseif extras > 0 then
		return "spark_teal"
	end
	return "spark_white"
end

local function hit_effect(attrs, from)
	local kind, file = HIT_EFFECT_KINDS[attr(attrs, "effect_hit") or ""], attr(attrs, "value_string")
	if not kind or not file then
		return nil
	end
	local hit = { from = from, file = file, cond = {} }
	local ce, cs = attr(attrs, "condition_effect"), attr(attrs, "condition_status")
	if ce then
		hit.cond[#hit.cond + 1] = ce
	end
	if cs then
		if not status_effect[cs] then
			return nil -- can't tell who has it
		end
		hit.cond[#hit.cond + 1] = status_effect[cs]
	end
	if kind == "effect" then
		hit.effect = file_text(file):match('%seffect%s*=%s*"([%w_]+)"')
		if not hit.effect or hit.effect == "CUSTOM" then
			return nil
		end
	elseif file_text(file):find("<ProjectileComponent", 1, true) then
		-- a projectile child (Explosion on slimy/drunk enemies, Personal gravity field) has no owner to spare the caster,
		-- its herd and other players, and would go off again on every re-apply: those stay imbue-only
		return nil
	else
		hit.child, hit.guard = true, HIT_GUARD_TAGS[file]
	end
	return hit
end

-- what one modifier does to a fresh shot, with the wand's mana and the RNG seed given
local function evaluate(a, wand_mana, seed)
	local base = {}
	ConfigGunActionInfo_Init(base)
	c = {}
	ConfigGunActionInfo_Init(c)
	shot_effects = {}
	ConfigGunShotEffects_Init(shot_effects)
	current_reload_time, spawned, mana = 0, 0, wand_mana
	if SetRandomSeed then
		SetRandomSeed(seed, seed)
	end
	reflecting, dont_draw_actions = true, true
	local ok = pcall(a.action, 1, 1)
	reflecting, dont_draw_actions = false, false
	if not ok then
		return nil, "error while evaluating"
	elseif spawned > 0 then
		return nil, "adds projectiles"
	end
	local r, useful = {}, false
	for _, k in ipairs(ADD) do
		if type(c[k]) == "number" and c[k] ~= base[k] then
			r.add = r.add or {}
			r.add[k] = c[k] - base[k]
			useful = true
		end
	end
	if c.speed_multiplier ~= base.speed_multiplier and base.speed_multiplier ~= 0 then
		r.speed = c.speed_multiplier / base.speed_multiplier
		useful = true
	end
	if c.friendly_fire ~= base.friendly_fire then
		r.friendly = c.friendly_fire
		useful = true
	end
	if c.damage_null_all ~= base.damage_null_all then
		r.null = true
	end
	for _, k in ipairs(LIST) do
		local v, b = c[k] or "", base[k] or ""
		if v ~= b then
			r[k] = split(v:sub(1, #b) == b and v:sub(#b + 1) or v)
			useful = useful or #r[k] > 0
		end
	end
	if r.trail_material and #r.trail_material > 0 then
		r.trail_amount = c.trail_material_amount - base.trail_material_amount
	end
	if not useful then
		return nil, "nothing that works on a flying projectile"
	end
	return r
end

local function build()
	for _, name in ipairs(ENGINE_STUBS) do
		_G[name] = function() end
	end
	Reflection_RegisterProjectile = function()
		spawned = spawned + 1
	end
	dofile("data/scripts/gun/gun_enums.lua")
	dofile("data/scripts/gun/gun.lua") -- defines the shot helpers and loads gun_actions.lua with all appends
	draw_actions = function() end -- gun.lua defines these, so they are stubbed afterwards
	draw_action = function() end
	status_effect = {}
	if pcall(dofile, "data/scripts/status_effects/status_list.lua") then
		for _, s in ipairs(status_effects or {}) do
			local effect = s.effect_entity and s.effect_entity ~= "" and file_text(s.effect_entity):match('%seffect%s*=%s*"([%w_]+)"')
			if effect and effect ~= "CUSTOM" and not status_effect[s.id] then
				status_effect[s.id] = effect
			end
		end
	end

	for _, a in ipairs(actions or {}) do
		if a.type == ACTION_TYPE_MODIFIER and type(a.id) == "string" then
			if SKIP[a.id] then
				skipped[a.id] = SKIP[a.id]
			elseif not a.id:match("^[%w_]+$") then
				skipped[a.id] = "id can't be used in a file name"
			else
				-- twice, with a different wand mana and RNG seed: anything that depends on either (Mana to damage,
				-- Random damage, other mods' random modifiers) can't be described by one fixed recipe
				local r, why = evaluate(a, 0, 0)
				local r2 = r and evaluate(a, 1000, 4242)
				if not r then
					skipped[a.id] = why
				elseif serialize(r) ~= serialize(r2) then
					skipped[a.id] = "depends on the wand's mana or on randomness"
				else
					-- game effect names, so the field can re-apply them without stacking. CUSTOM effects (e.g.
					-- Necromancy) can't be counted by name: they still imbue projectiles but are not re-applied.
					r.effects = {}
					for _, f in ipairs(r.game_effect_entities or {}) do
						local effect = file_text(f):match('%seffect%s*=%s*"([%w_]+)"')
						r.effects[#r.effects + 1] = { file = f, effect = effect ~= "CUSTOM" and effect or nil }
					end
					-- extra entities with an active material converter also work over the field's area, and so do their
					-- on-hit effects that load something onto the creature hit
					for _, f in ipairs(r.extra_entities or {}) do
						local text = file_text(f)
						for attrs in text:gmatch("<HitEffectComponent(.-)>") do
							r.effects[#r.effects + 1] = hit_effect(attrs, f)
						end
						local conv = text:match("<MagicConvertMaterialComponent[^>]*")
						if conv and not conv:find('_enabled%s*=%s*"0"') then
							r.converters = r.converters or {}
							r.converters[#r.converters + 1] = f
						end
					end
					r.colour = colour(r)
					recipes[a.id] = r
				end
			end
		end
	end
end

local ok, err = pcall(build)

-- undo everything gun.lua / gun_actions.lua defined in this (init.lua) Lua state, including other mods' overrides
for k in pairs(_G) do
	if backup[k] == nil then
		_G[k] = nil
	end
end
for k, v in pairs(backup) do
	if _G[k] ~= v then
		_G[k] = v
	end
end
for name, keys in pairs(cache_keys) do
	local cache = _G[name]
	if type(cache) == "table" then
		for k in pairs(cache) do
			if not keys[k] then
				cache[k] = nil
			end
		end
	end
end

if not ok then
	print("[field_imbue] could not evaluate modifiers, Field resonance will do nothing: " .. tostring(err))
end
local count = 0
for id in pairs(recipes) do
	count = count + 1
	ModTextFileSetContent(GEN .. "mod/" .. id .. ".xml",
		('<Entity><VariableStorageComponent _tags="fi_mod" name="fi_mod" value_string="%s" /></Entity>'):format(id))
	-- Sign Flip (another mod) can flip a modifier in the cast; gun_append.lua then marks the field with this one
	ModTextFileSetContent(GEN .. "mod/" .. id .. ".neg.xml",
		('<Entity><VariableStorageComponent _tags="fi_mod" name="fi_mod" value_string="-%s" /></Entity>'):format(id))
end
ModTextFileSetContent(GEN .. "recipes.lua", "return " .. serialize(recipes) .. "\n")
ModTextFileSetContent(GEN .. "skipped.lua", "return " .. serialize(skipped) .. "\n")
print(("[field_imbue] %d modifiers can imbue"):format(count))
