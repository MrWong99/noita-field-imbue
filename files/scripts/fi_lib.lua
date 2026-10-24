-- Shared field_imbue logic, loaded by the field LuaComponents.
-- Under Entangled Worlds these run on every peer's local copy of the field, so everything here must stay
-- deterministic: no Random(), no GameGetFrameNum() timing, and no decision that depends on entity ids
-- matching across peers.

local M = {}

-- vanilla only lets projectile game effects land on these; players carry "prey" too, see is_target()
M.TARGET_TAGS = { "enemy", "prey" }
M.PLAYER_TAGS = { "player_unit", "ew_client", "ew_peer", "ew_notplayer", "polymorphed_player" }
-- projectiles move at most ~17 px/frame (terminal velocity 1000 px/s, measured in game); the margin only has to
-- cover one frame of movement on top of the radius
M.MAX_STEP = 128
-- setting "Imbue enemy projectiles" (settings.lua, off by default): otherwise only projectiles shot by players are
-- imbued. New-game scope, so the value is fixed for the whole run.
M.IMBUE_ENEMY_PROJECTILES = ModSettingGet ~= nil and ModSettingGet("field_imbue.imbue_enemy_projectiles") == true

local DAMAGE_TYPES = {
	damage_melee_add = "melee",
	damage_electricity_add = "electricity",
	damage_fire_add = "fire",
	damage_ice_add = "ice",
	damage_slice_add = "slice",
	damage_healing_add = "healing",
	damage_curse_add = "curse",
	damage_drill_add = "drill",
}

-- modifier id -> recipe, generated at mod init by files/scripts/recipes_build.lua
local recipes
function M.recipes()
	if recipes == nil then
		local ok, r = pcall(dofile_once, "mods/field_imbue/files/gen/recipes.lua")
		recipes = ok and type(r) == "table" and r or {}
	end
	return recipes
end

-- Sign Flip (another mod) can flip a modifier in a cast; the field then carries "-<ID>" (files/gun_append.lua). Its
-- recipe adds the numbers the other way round and inverts the speed factor. Negative damage does nothing in the
-- engine, so damage it would take away heals instead. What the modifier adds becomes its opposite from Sign Flip's
-- table (its files/scripts/opposites_build.lua): Homing steers away, converters run backwards, a trail eats its
-- material (on bolts and over the field) and drops its on-hit effect. Same rules as Sign Flip applies in the cast.
local HEAL_INSTEAD = { damage_projectile_add = true, damage_melee_add = true, damage_electricity_add = true,
	damage_fire_add = true, damage_ice_add = true, damage_slice_add = true, damage_curse_add = true, damage_drill_add = true }

local sf_opposites
local function opposites()
	if sf_opposites == nil then
		local ok, o = pcall(dofile_once, "mods/sign_flip/files/gen/opposites.lua")
		sf_opposites = ok and type(o) == "table" and o or false
	end
	return sf_opposites
end

-- the negated recipe, and whether it differs from the plain one at all
local function negate(r)
	local n, different = {}, false
	for k, v in pairs(r) do
		n[k] = v
	end
	n.add, n.negated = {}, true
	for k, v in pairs(r.add or {}) do
		if HEAL_INSTEAD[k] and v > 0 then
			k = "damage_healing_add"
		end
		n.add[k] = (n.add[k] or 0) - v
		different = true
	end
	if r.speed and r.speed ~= 0 and r.speed ~= 1 then
		n.speed = 1 / r.speed
		different = true
	end
	local O = opposites()
	if O then
		local drop = false
		n.extra_entities, n.converters = {}, {}
		for _, f in ipairs(r.extra_entities or {}) do
			local to = O.extra[f]
			if to then
				different = true
				if O.drops_effects[f] then -- a poured material became an eater: it works over the field too
					drop = true
					n.converters[#n.converters + 1] = to
				end
			end
			n.extra_entities[#n.extra_entities + 1] = to or f
		end
		for _, f in ipairs(r.converters or {}) do
			n.converters[#n.converters + 1] = O.extra[f] or f
		end
		local eaters = {}
		for _, m in ipairs(r.trail_material or {}) do
			eaters[#eaters + 1] = O.eat[m]
		end
		if #eaters > 0 then
			n.trail_material, n.trail_amount = nil, nil
			for _, e in ipairs(eaters) do
				n.extra_entities[#n.extra_entities + 1] = e
				n.converters[#n.converters + 1] = e
			end
			different, drop = true, true
		end
		if drop then
			n.game_effect_entities, n.effects = {}, {}
		end
	end
	return n, different
end

-- the recipe for a payload id, "-<ID>" included (a negation that changes nothing is the plain recipe)
local negated = {}
function M.recipe(id)
	local R = M.recipes()
	if id:sub(1, 1) ~= "-" then
		return R[id]
	end
	if negated[id] == nil then
		local r = R[id:sub(2)]
		if r then
			local n, different = negate(r)
			negated[id] = different and n or r
		else
			negated[id] = false
		end
	end
	return negated[id] or nil
end

-- state lives in VariableStorageComponents tagged with their own name (cheap lookup by tag)
local function vsc(e, name)
	return EntityGetFirstComponentIncludingDisabled(e, "VariableStorageComponent", name)
end

function M.get_str(e, name, default)
	local v = vsc(e, name)
	if v then
		return ComponentGetValue2(v, "value_string")
	end
	return default
end

function M.set_str(e, name, value)
	local v = vsc(e, name)
	if v then
		ComponentSetValue2(v, "value_string", value)
	else
		EntityAddComponent2(e, "VariableStorageComponent", { _tags = name, name = name, value_string = value })
	end
end

function M.get_float(e, name, default)
	local v = vsc(e, name)
	if v then
		return ComponentGetValue2(v, "value_float")
	end
	return default
end

function M.set_float(e, name, value)
	local v = vsc(e, name)
	if v then
		ComponentSetValue2(v, "value_float", value)
	else
		EntityAddComponent2(e, "VariableStorageComponent", { _tags = name, name = name, value_float = value })
	end
end

-- the field's modifier ids, ignoring anything without a recipe (e.g. an old save after a mod was removed)
function M.payload(e)
	local out = {}
	for id in (M.get_str(e, "fi_payload", "") or ""):gmatch("[^,]+") do
		if M.recipe(id) then
			out[#out + 1] = id
		end
	end
	return out
end

-- which modifiers were cast with this field: files/gun_append.lua merged one marker per modifier onto it
function M.payload_from_markers(e)
	local out, seen = {}, {}
	for _, v in ipairs(EntityGetComponentIncludingDisabled(e, "VariableStorageComponent", "fi_mod") or {}) do
		local id = ComponentGetValue2(v, "value_string")
		local r = M.recipe(id)
		if r and not r.negated then
			id = id:gsub("^%-", "") -- a negation that changes nothing for a projectile: the plain modifier
		end
		if r and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	return out
end

-- a circle field: area effect component and a projectile that never moves. Excludes moving bolts that another mod
-- (e.g. Spellbound) merged a field XML into.
function M.is_static_field(e)
	local pc = EntityGetFirstComponentIncludingDisabled(e, "ProjectileComponent")
	local gaec = EntityGetFirstComponentIncludingDisabled(e, "GameAreaEffectComponent")
	return pc ~= nil and gaec ~= nil and ComponentGetValue2(pc, "speed_max") == 0
end

-- did the projectile's path over the last frame touch the circle? (fast bolts can skip over a radius check)
function M.crossed(px, py, vx, vy, cx, cy, r)
	local dx, dy = vx / 60, vy / 60
	local ax, ay = px - dx - cx, py - dy - cy
	local len2 = dx * dx + dy * dy
	local t = 0
	if len2 > 1e-6 then
		t = math.max(0, math.min(1, -(ax * dx + ay * dy) / len2))
	end
	local qx, qy = ax + t * dx, ay + t * dy
	return qx * qx + qy * qy <= r * r
end

local function has_any_tag(e, tags)
	for _, tag in ipairs(tags) do
		if EntityHasTag(e, tag) then
			return true
		end
	end
	return false
end

-- Projectiles a field may imbue: no fields, no static projectiles (clouds, holes, Lua fields would become permanent
-- sources), nothing the field spawned, no clones, nothing shot by another projectile (chain shot children, ray and
-- orbit spawns, trigger payloads: no spawner cascades), and by default only player shots.
local function imbuable(p, field)
	if EntityHasTag(p, "projectile_not") or EntityHasTag(p, "projectile_cloned") or EntityHasTag(p, "fi_field") then
		return nil
	end
	if EntityGetFirstComponentIncludingDisabled(p, "GameAreaEffectComponent") then
		return nil
	end
	local pc = EntityGetFirstComponentIncludingDisabled(p, "ProjectileComponent")
	if not pc or ComponentGetValue2(pc, "speed_max") == 0 then
		return nil
	end
	local who, parent = ComponentGetValue2(pc, "mWhoShot"), ComponentGetValue2(pc, "mEntityThatShot")
	if who == field or parent == field then
		return nil
	end
	if parent ~= 0 and parent ~= who and (not EntityGetIsAlive(parent) or EntityHasTag(parent, "projectile")) then
		return nil
	end
	if not M.IMBUE_ENEMY_PROJECTILES and not (who ~= 0 and EntityGetIsAlive(who) and has_any_tag(who, M.PLAYER_TAGS)) then
		return nil
	end
	return pc
end

-- load an extra-entity XML onto a flying projectile; trail emitters added mid-flight would otherwise draw from a
-- stale previous position, so start them where the projectile is
local function load_extra(p, file)
	local before = {}
	for _, comp in ipairs(EntityGetComponentIncludingDisabled(p, "ParticleEmitterComponent") or {}) do
		before[comp] = true
	end
	EntityLoadToEntity(file, p)
	local px, py = EntityGetTransform(p)
	for _, comp in ipairs(EntityGetComponentIncludingDisabled(p, "ParticleEmitterComponent") or {}) do
		if not before[comp] and ComponentGetValue2(comp, "is_trail") then
			ComponentSetValue2(comp, "mExPosition", px, py)
		end
	end
end

-- material trail (Fire trail, Acid trail, ...): same kind of emitter the engine gives a projectile at cast time
local function add_trail(p, materials, amount)
	local px, py = EntityGetTransform(p)
	for _, m in ipairs(materials) do
		local pe = EntityAddComponent2(p, "ParticleEmitterComponent", {
			emitted_material_name = m,
			emit_real_particles = true,
			create_real_particles = false,
			emit_cosmetic_particles = false,
			is_trail = true,
			is_emitting = true,
			count_min = math.max(1, amount + 1),
			count_max = math.max(1, amount + 3),
			lifetime_min = 5,
			lifetime_max = 10,
			emission_interval_min_frames = 0,
			emission_interval_max_frames = 0,
			emitter_lifetime_frames = -1,
			collide_with_grid = true,
			render_on_grid = true,
		})
		ComponentSetValue2(pe, "mExPosition", px, py)
	end
end

local function add_number(p, pc, k, v)
	if k == "damage_projectile_add" then
		ComponentSetValue2(pc, "damage", ComponentGetValue2(pc, "damage") + v)
	elseif DAMAGE_TYPES[k] then
		local t = DAMAGE_TYPES[k]
		ComponentObjectSetValue2(pc, "damage_by_type", t, (ComponentObjectGetValue2(pc, "damage_by_type", t) or 0) + v)
	elseif k == "damage_explosion_add" then
		ComponentObjectSetValue2(pc, "config_explosion", "damage", ComponentObjectGetValue2(pc, "config_explosion", "damage") + v)
	elseif k == "explosion_radius" then
		local radius = ComponentObjectGetValue2(pc, "config_explosion", "explosion_radius")
		ComponentObjectSetValue2(pc, "config_explosion", "explosion_radius", math.max(0, radius + v))
		if v > 0 then
			ComponentSetValue2(pc, "on_death_explode", true)
		end
	elseif k == "damage_critical_chance" then
		ComponentObjectSetValue2(pc, "damage_critical", "chance", ComponentObjectGetValue2(pc, "damage_critical", "chance") + v)
	elseif k == "knockback_force" then
		ComponentSetValue2(pc, "knockback_force", ComponentGetValue2(pc, "knockback_force") + v)
	elseif k == "lifetime_add" then
		local l = ComponentGetValue2(pc, "lifetime")
		if l > 0 then -- -1 means endless; don't make it finite
			ComponentSetValue2(pc, "lifetime", math.max(1, l + v))
		end
	elseif k == "bounces" then
		ComponentSetValue2(pc, "bounces_left", math.max(0, ComponentGetValue2(pc, "bounces_left") + v))
	elseif k == "gravity" then
		local vc = EntityGetFirstComponentIncludingDisabled(p, "VelocityComponent")
		if vc then
			ComponentSetValue2(vc, "gravity_y", ComponentGetValue2(vc, "gravity_y") + v)
		end
	end
end

-- Does the projectile already carry this modifier from its own cast? Only the modifier's own extra entities and game
-- effects count; shared sparkle particles (data/entities/particles/) would match unrelated modifiers. Modifiers that
-- are only numbers can't be recognised (the field's own cast siblings are marked in field_init.lua instead). A negated
-- modifier ("-<ID>") can't be recognised either: its numbers can't be read back, and without Sign Flip its extras are
-- the plain ones. Whole entries only: Sign Flip's flipped files (mods/sign_flip/files/gen/flip/data/...) contain the
-- vanilla path.
local function already_has(pc, r)
	if r.negated then
		return false
	end
	local own = "," .. (ComponentObjectGetValue2(pc, "config", "extra_entities") or "") .. ","
		.. (ComponentGetValue2(pc, "damage_game_effect_entities") or "") .. ","
	local any = false
	for _, list in ipairs({ r.extra_entities or {}, r.game_effect_entities or {} }) do
		for _, f in ipairs(list) do
			if not f:find("data/entities/particles/", 1, true) then
				any = true
				if not own:find("," .. f .. ",", 1, true) then
					return false
				end
			end
		end
	end
	return any
end

-- give one modifier to a projectile that is already flying
function M.apply(p, pc, r)
	if already_has(pc, r) then
		return
	end
	for k, v in pairs(r.add or {}) do
		add_number(p, pc, k, v)
	end
	if r.speed then
		local vc = EntityGetFirstComponentIncludingDisabled(p, "VelocityComponent")
		if vc then
			local vx, vy = ComponentGetValue2(vc, "mVelocity")
			ComponentSetValue2(vc, "mVelocity", vx * r.speed, vy * r.speed)
		end
	end
	if r.friendly then
		ComponentSetValue2(pc, "friendly_fire", true)
	end
	local list = ComponentGetValue2(pc, "damage_game_effect_entities") or ""
	for _, f in ipairs(r.game_effect_entities or {}) do
		if not ("," .. list .. ","):find("," .. f .. ",", 1, true) then
			if list ~= "" and list:sub(-1) ~= "," then
				list = list .. ","
			end
			list = list .. f .. ","
		end
	end
	ComponentSetValue2(pc, "damage_game_effect_entities", list)
	for _, f in ipairs(r.extra_entities or {}) do
		load_extra(p, f)
	end
	if r.trail_material and #r.trail_material > 0 then
		add_trail(p, r.trail_material, r.trail_amount or 0)
	end
end

-- imbue every projectile that crossed the circle this frame; each modifier at most once per projectile, however
-- many fields it crosses
function M.imbue_crossing(field, x, y, radius, ids)
	if #ids == 0 then
		return
	end
	local key = "," .. field .. ","
	for _, p in ipairs(EntityGetInRadiusWithTag(x, y, radius + M.MAX_STEP, "projectile") or {}) do
		if p ~= field then
			local px, py = EntityGetTransform(p)
			local vx, vy = 0, 0
			local vc = EntityGetFirstComponentIncludingDisabled(p, "VelocityComponent")
			if vc then
				vx, vy = ComponentGetValue2(vc, "mVelocity")
			end
			-- a projectile from an imbuing shot whose init hasn't run yet (LuaComponent order within a frame is not
			-- fixed): wait a frame, its init first restores the shot's own modifiers and marks them as carried
			local pending = vsc(p, "fi_mod") and not vsc(p, "fi_mods")
			if not pending and M.crossed(px, py, vx, vy, x, y, radius) then
				local pc = imbuable(p, field)
				local seen = pc and M.get_str(p, "fi_seen", ",")
				if seen and not seen:find(key, 1, true) then
					M.set_str(p, "fi_seen", seen .. field .. ",")
					local applied = M.get_str(p, "fi_mods", ",")
					for _, id in ipairs(ids) do
						if not applied:find("," .. id .. ",", 1, true) then
							applied = applied .. id .. ","
							M.apply(p, pc, M.recipe(id))
						end
					end
					M.set_str(p, "fi_mods", applied)
				end
			end
		end
	end
end

-- material converters from the modifiers (Water to poison, Freeze charge's freezing, ...) work over the whole
-- circle: load them onto the field, keep only the converters and widen them to the field radius
function M.setup_converters(e, radius, ids)
	-- each file once: "-<ID>" and "<ID>" in one field share the same converters
	local files, done = {}, {}
	for _, id in ipairs(ids) do
		for _, f in ipairs(M.recipe(id).converters or {}) do
			if not done[f] then
				done[f] = true
				files[#files + 1] = f
			end
		end
	end
	for _, f in ipairs(files) do
		local before = {}
		for _, comp in ipairs(EntityGetAllComponents(e) or {}) do
			before[comp] = true
		end
		EntityLoadToEntity(f, e)
		for _, comp in ipairs(EntityGetAllComponents(e) or {}) do
			if not before[comp] then
				-- disabled converters wait for a script (Transmutation picks its materials in Lua); that script is not
				-- kept on the field, so drop them too
				if ComponentGetTypeName(comp) == "MagicConvertMaterialComponent" and ComponentGetIsEnabled(comp) then
					ComponentSetValue2(comp, "radius", math.floor(radius))
					ComponentSetValue2(comp, "is_circle", true)
					ComponentSetValue2(comp, "loop", true)
					ComponentSetValue2(comp, "kill_when_finished", false)
				else
					EntityRemoveComponent(e, comp)
				end
			end
		end
	end
end

-- A projectile cast in the same shot as an imbuing field that is not a field itself (a multicast bolt, a wall, a
-- black hole): files/gun_append.lua kept the modifiers' own pieces off the whole shot, so give them back, and mark the
-- projectile as already carrying the shot's modifiers so its sibling field doesn't add their numbers a second time.
function M.restore_cast_pieces(p, ids)
	local applied = M.get_str(p, "fi_mods", ",")
	for _, id in ipairs(ids) do
		local r = M.recipe(id)
		if applied:find("," .. id .. ",", 1, true) then
			r = {} -- already carries it
		end
		for _, f in ipairs(r.extra_entities or {}) do
			load_extra(p, f)
		end
		if r.trail_material and #r.trail_material > 0 then
			add_trail(p, r.trail_material, r.trail_amount or 0)
		end
		if r.add and r.add.gravity then
			add_number(p, nil, "gravity", r.add.gravity)
		end
		if r.null and not EntityGetFirstComponentIncludingDisabled(p, "NullDamageComponent") then
			EntityAddComponent2(p, "NullDamageComponent", { null_chance = 1 })
		end
		if not applied:find("," .. id .. ",", 1, true) then
			applied = applied .. id .. ","
		end
	end
	M.set_str(p, "fi_mods", applied)
end

-- Without friendly fire: no players (they carry "prey"), and nobody in the caster's herd.
local function is_target(t, friendly, shooter_herd)
	if friendly then
		return true
	end
	if has_any_tag(t, M.PLAYER_TAGS) then
		return false
	end
	local genome = EntityGetFirstComponentIncludingDisabled(t, "GenomeDataComponent")
	return not (genome and ComponentGetValue2(genome, "herd_id") == shooter_herd)
end

-- Under EW only touch creatures this peer owns: a non-owner's local effect is overwritten anyway, and a local
-- ignition on a mirror could still spread real fire into the world. ew_do_i_own is true for unsynced entities.
local function owned_here(t)
	if not CrossCall or not ModIsEnabled("quant.ew") then
		return true
	end
	if EntityHasTag(t, "ew_client") then -- local copy of another player: their own peer decides their effects
		return false
	end
	local ok, mine = pcall(CrossCall, "ew_do_i_own", t)
	return not ok or mine ~= false
end

-- re-apply the modifiers' game effects to creatures inside the field (never the caster, matching the vanilla
-- circle, §6.2). Effects whose name could not be read are skipped, so nothing stacks.
function M.reapply_area(field, x, y, radius, ids)
	local effects = {}
	for _, id in ipairs(ids) do
		for _, ef in ipairs(M.recipe(id).effects or {}) do
			if ef.effect then
				effects[#effects + 1] = ef
			end
		end
	end
	if #effects == 0 then
		return
	end
	local pc = EntityGetFirstComponentIncludingDisabled(field, "ProjectileComponent")
	if not pc then
		return
	end
	local shooter = ComponentGetValue2(pc, "mWhoShot")
	local friendly = ComponentGetValue2(pc, "friendly_fire")
	local shooter_herd = ComponentGetValue2(pc, "mShooterHerdId")
	local seen = {}
	for _, tag in ipairs(M.TARGET_TAGS) do
		for _, t in ipairs(EntityGetInRadiusWithTag(x, y, radius, tag) or {}) do
			if not seen[t] then
				seen[t] = true
				if t ~= shooter and EntityGetRootEntity(t) == t and is_target(t, friendly, shooter_herd) and owned_here(t) then
					for _, ef in ipairs(effects) do
						if GameGetGameEffectCount(t, ef.effect) == 0 then
							LoadGameEffectEntityTo(t, ef.file)
						end
					end
				end
			end
		end
	end
end

return M
