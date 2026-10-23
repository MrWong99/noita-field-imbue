-- Test-only modifier: tags every projectile in the cast with a marker extra entity (design option B in RESEARCH.md §3.1)
table.insert(actions, {
	id = "FI_PROBE_MARKER",
	name = "FI probe marker",
	description = "field_imbue probe: adds a marker extra entity",
	sprite = "data/ui_gfx/gun_actions/homing.png",
	type = ACTION_TYPE_MODIFIER,
	spawn_level = "0",
	spawn_probability = "0",
	price = 0,
	mana = 0,
	action = function()
		c.extra_entities = c.extra_entities .. "mods/field_imbue_probe/files/marker.xml,"
		draw_actions(1, true)
	end,
})
