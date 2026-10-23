-- Opt-in card: every projectile in the cast gets field_imbue.xml merged in, but its scripts only stay
-- active on circle fields (see files/scripts/field_init.lua). Vanilla circles without this card are untouched.
table.insert(actions, {
	id = "FIELD_IMBUE",
	name = "Field resonance",
	description = "A field cast with this keeps applying its modifiers inside its circle and imbues projectiles flying through it",
	sprite = "mods/field_imbue/files/ui_gfx/field_imbue.png",
	related_extra_entities = { "mods/field_imbue/files/entities/field_imbue.xml" },
	type = ACTION_TYPE_MODIFIER,
	spawn_level = "2,3,4,5,6",
	spawn_probability = "0.3,0.4,0.4,0.4,0.4",
	price = 180,
	mana = 25,
	action = function()
		c.extra_entities = c.extra_entities .. "mods/field_imbue/files/entities/field_imbue.xml,"
		c.fi_imbue = true -- read by files/gun_append.lua when the shot is registered
		draw_actions(1, true)
	end,
})
