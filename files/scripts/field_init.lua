-- Runs once on every projectile cast together with Field resonance. Only static circle fields keep the tick and
-- re-apply scripts; anything else in the same cast drops them again.
local fi = dofile_once("mods/field_imbue/files/scripts/fi_lib.lua")

local e = GetUpdatedEntityID()
local ticks = EntityGetComponentIncludingDisabled(e, "LuaComponent", "fi_tick") or {}
local reapplies = EntityGetComponentIncludingDisabled(e, "LuaComponent", "fi_reapply") or {}

local function keep_first(list, keep)
	for i = keep + 1, #list do
		EntityRemoveComponent(e, list[i])
	end
end

-- a second Field resonance card in the same cast merges a second copy: the first init already set things up
if fi.get_str(e, "fi_payload", nil) ~= nil then
	keep_first(ticks, 1)
	keep_first(reapplies, 1)
	return
end

if not fi.is_static_field(e) then
	-- another projectile of the field's shot: give back what the cast hook kept off the shot
	local ids = fi.payload_from_markers(e)
	if #ids > 0 then
		fi.restore_cast_pieces(e, ids)
	end
	keep_first(ticks, 0)
	keep_first(reapplies, 0)
	return
end

local ids = fi.payload_from_markers(e)
if #ids == 0 then
	keep_first(ticks, 0)
	keep_first(reapplies, 0)
	return
end

local radius = ComponentGetValue2(EntityGetFirstComponentIncludingDisabled(e, "GameAreaEffectComponent"), "radius")
fi.set_str(e, "fi_payload", table.concat(ids, ","))
fi.set_float(e, "fi_radius", radius)
EntityAddTag(e, "fi_field")
fi.setup_converters(e, radius, ids)
fi.tint(e, radius, ids)
for _, list in ipairs({ ticks, reapplies }) do
	if list[1] then
		EntitySetComponentIsEnabled(e, list[1], true)
	end
	keep_first(list, 1)
end
