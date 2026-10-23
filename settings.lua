dofile("data/scripts/lib/mod_settings.lua")

-- Both settings only take effect when a new run starts (MOD_SETTING_SCOPE_NEW_GAME): they decide which modifiers get
-- recipes and which projectiles a field touches, and must not change in the middle of a run. With Entangled Worlds,
-- every player needs the same values (EW does not sync other mods' settings).

local mod_id = "field_imbue" -- must match the mod folder name
mod_settings_version = 1
mod_settings = {
	{
		id = "imbue_enemy_projectiles",
		ui_name = "Imbue enemy projectiles",
		ui_description = "Fields also give their modifiers to enemy shots flying through them.\n"
			.. "Off: only players' projectiles are imbued.\n"
			.. "With Entangled Worlds, enemy shots imbued with modifiers that spawn more projectiles\n"
			.. "(Chain spell, Larpa, orbits, throwers) can be duplicated for other players.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_NEW_GAME,
	},
	{
		id = "allow_destructive",
		ui_name = "Allow Nuke orbit and Chaos magic",
		ui_description = "Fields can also carry Nuke orbit and Chaos magic: every projectile crossing such a field\n"
			.. "gets nukes or random explosions (up to black holes and nukes) for the field's whole lifetime.\n"
			.. "Can cause heavy lag or crashes.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_NEW_GAME,
	},
}

function ModSettingsUpdate(init_scope)
	mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
	return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
	mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
