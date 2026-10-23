-- Every 60 frames on an imbuing field: re-apply its effects to creatures inside it.
local fi = dofile_once("mods/field_imbue/files/scripts/fi_lib.lua")

local e = GetUpdatedEntityID()
local x, y = EntityGetTransform(e)
if x ~= x or y ~= y then
	return
end

fi.reapply_area(e, x, y, fi.get_float(e, "fi_radius", 28), fi.payload(e))
