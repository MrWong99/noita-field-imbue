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

-- A plain circle with Field resonance built in: modifiers cast before it go straight into the field. Being a static
-- projectile, files/gun_append.lua marks the shot as having a field, like any other circle.
table.insert(actions, {
	id = "RESONANT_FIELD",
	name = "Resonant field",
	description = "A field with no effect of its own that keeps applying its modifiers inside its circle and imbues projectiles flying through it",
	sprite = "mods/field_imbue/files/ui_gfx/resonant_field.png",
	related_projectiles = { "mods/field_imbue/files/entities/resonant_field.xml" },
	related_extra_entities = { "mods/field_imbue/files/entities/field_imbue.xml" },
	type = ACTION_TYPE_STATIC_PROJECTILE,
	spawn_level = "2,3,4,5,6",
	spawn_probability = "0.3,0.4,0.4,0.4,0.4",
	price = 220,
	mana = 45,
	max_uses = 15,
	action = function()
		add_projectile("mods/field_imbue/files/entities/resonant_field.xml")
		c.extra_entities = c.extra_entities .. "mods/field_imbue/files/entities/field_imbue.xml,"
		c.fi_imbue = true -- read by files/gun_append.lua when the shot is registered
		c.fire_rate_wait = c.fire_rate_wait + 15
	end,
})
