ModLuaFileAppend("data/scripts/gun/gun_actions.lua", "mods/field_imbue/files/actions.lua")
ModLuaFileAppend("data/scripts/gun/gun.lua", "mods/field_imbue/files/gun_append.lua")

-- every mod's spells are registered by now: work out what each modifier means for a projectile (files/gen/)
function OnModPostInit()
	dofile("mods/field_imbue/files/scripts/recipes_build.lua")
end
