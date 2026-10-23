-- Every frame on an imbuing field: give the field's modifiers to projectiles crossing it.
local fi = dofile_once("mods/field_imbue/files/scripts/fi_lib.lua")

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform(e)
if x ~= x or y ~= y then -- NaN-positioned fields (Fly Downwards exploit) would act on the whole world
	return
end

fi.imbue_crossing(e, x, y, fi.get_float(e, "fi_radius", 28), fi.payload(e))
