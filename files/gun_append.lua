-- Appended to data/scripts/gun/gun.lua, so it runs after gun_actions.lua and every mod's appends: every modifier
-- in `actions` exists by now, and the deck (which clones `action`) is built later. Runs in the wand's Lua state on
-- every Entangled Worlds peer (each peer replays the cast), so it only looks at the shot itself.

-- recipes are generated in OnModPostInit; load them lazily, at cast time
local fi_recipes
local function fi_get_recipes()
	if fi_recipes == nil then
		local ok, r = pcall(dofile_once, "mods/field_imbue/files/gen/recipes.lua")
		fi_recipes = ok and type(r) == "table" and r or false
	end
	return fi_recipes
end

-- Sign Flip (another mod), if loaded: what a flipped modifier adds instead of its own pieces (its gen/opposites.lua)
local fi_sf_opposites
local function fi_get_sf_opposites()
	if fi_sf_opposites == nil then
		local ok, o = pcall(dofile_once, "mods/sign_flip/files/gen/opposites.lua")
		fi_sf_opposites = ok and type(o) == "table" and o or false
	end
	return fi_sf_opposites
end

-- remember which modifiers are cast in the shot (RANDOM_MODIFIER runs the one it picks, which records itself),
-- and whether the shot has a static projectile (RANDOM_STATIC_PROJECTILE runs the one it picks, too)
for _, a in ipairs(actions or {}) do
	if not a.fi_wrapped and a.id ~= "FIELD_IMBUE" then
		local action, id = a.action, a.id
		if a.type == ACTION_TYPE_MODIFIER then
			a.action = function(...)
				if not reflecting and c then
					c.fi_mods = (c.fi_mods or "") .. id .. ","
				end
				return action(...)
			end
			a.fi_wrapped = true
		elseif a.type == ACTION_TYPE_STATIC_PROJECTILE then
			a.action = function(...)
				if not reflecting and c then
					c.fi_static = true
				end
				return action(...)
			end
			a.fi_wrapped = true
		end
	end
end

-- remove one whole entry ("path,") from a comma-separated list
local function remove_entry(list, entry)
	local i = ("," .. list):find("," .. entry .. ",", 1, true)
	if not i then
		return list
	end
	return list:sub(1, i - 1) .. list:sub(i + #entry + 1)
end

-- When Field resonance and a static projectile are in the same shot: tag the projectiles with which modifiers were
-- cast, and keep those modifiers' own pieces (extra entities, trail, null damage, gravity) off them, so an imbuing
-- field has no burning or snowing centre and doesn't move. Projectiles of the shot that turn out not to be fields
-- get those pieces back on their first frame (files/scripts/field_init.lua). The game effects stay: the circle's
-- own area effect spreads them.
local fi_register_action = register_action
function register_action(state)
	if state.fi_imbue and state.fi_static and not reflecting then
		local recipes = fi_get_recipes()
		if recipes then
			local markers = {}
			-- Sign Flip (another mod) lists the modifiers it flipped in this shot. Counted per id: the same modifier can be
			-- in the shot both flipped and not. A flipped one put its opposite pieces into the shot (anti homing, a
			-- reversed converter, a trail's eater): those are the pieces kept off the field.
			local negated = {}
			for id in (state.sf_negated or ""):gmatch("[^,]+") do
				negated[id] = (negated[id] or 0) + 1
			end
			for id in (state.fi_mods or ""):gmatch("[^,]+") do
				local r = recipes[id]
				if r then
					local neg = (negated[id] or 0) > 0
					local O = neg and fi_get_sf_opposites()
					if neg then
						negated[id] = negated[id] - 1
					end
					markers[#markers + 1] = "mods/field_imbue/files/gen/mod/" .. id .. (neg and ".neg" or "") .. ".xml,"
					for _, f in ipairs(r.extra_entities or {}) do
						state.extra_entities = remove_entry(state.extra_entities, O and O.extra[f] or f)
					end
					for _, m in ipairs(O and r.trail_material or {}) do
						if O.eat[m] then
							state.extra_entities = remove_entry(state.extra_entities, O.eat[m])
						end
					end
				end
			end
			if #markers > 0 then
				state.extra_entities = state.extra_entities .. table.concat(markers)
				state.trail_material = ""
				state.trail_material_amount = 0
				state.damage_null_all = 0 -- Null shot: the engine would add a NullDamageComponent to the field
				state.gravity = 0 -- Gravity / Anti-gravity would make the field fall or rise away
			end
		end
	end
	state.fi_imbue, state.fi_mods, state.fi_static = nil, nil, nil
	return fi_register_action(state)
end
