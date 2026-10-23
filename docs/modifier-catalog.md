# Vanilla modifier catalog for field_imbue

All 143 active vanilla `ACTION_TYPE_MODIFIER` actions, classified by how they are implemented and how each one would work (1) as an
**area effect** of a field and (2) as an **imbue** onto a projectile already in flight. Another 36 sit in `--[[ ]]` comment blocks in
`gun_actions.lua` and are not listed.

Source: `data/scripts/gun/gun_actions.lua` from the installed game's `data.wak` (build "Jan 25 2025"). The line column is where each
action block starts. One research agent produced the table and an independent verifier re-parsed and spot-checked it; the verifier's
corrections are already applied below.

**Legend**
- **ELTE** = `EntityLoadToEntity("<the modifier's own vanilla extra-entity XML>", projectile)`.
- **R** = field radius (28 px for base_field circles).
- **WARNING** = vanilla already changes the field ITSELF when this modifier is cast with it. The mod has to neutralise that or accept it.

**Classes**
- **A** = stat deltas. They only take effect when the projectile is created, so imbuing means writing component fields directly.
- **B1** = path/homing components.
- **B2** = one-shot Lua patchers.
- **B3** = sub-projectile spawners.
- **B4** = engine-component auras (converters, AreaDamage, Light, Arc, CellEater).
- **C1** = `game_effect_entities` (applied on hit).
- **C2** = HitEffectComponent on-hit.
- **D** = trail/material.
- **E** = wand/cast-level (meaningless on a field).
- **F** = meta/cosmetic.

**Tiers**
- **1** = MVP: 33 modifiers, three code paths.
- **2** = later.
- **3** = niche or risky.
- **skip** = not applicable.
- **free** = works automatically (RANDOM_MODIFIER resolves at cast time).

Counts: A 16, B1 25, B2 17 (+2 reclassified from B1), B3 22, B4 15, C1 8, C2 19, D 3, E 7, F 11.

| # | ID (English) | gun_actions.lua | Class | Area effect (inside field radius) | Projectile imbue (already-flying projectile) | Tier |
|---|---|---|---|---|---|---|
| 1 | SPREAD_REDUCE (Reduce spread) | 4564 | E | none (cast-time wand stat) | none - spread/fire-rate/reload/recoil/mana only exist at cast time | skip |
| 2 | HEAVY_SPREAD (Heavy spread) | 4581 | E | optional: randomise heading of passing projectiles (scatter ring) | rotate `mVelocity` by random angle (position-seeded) | 3 |
| 3 | RECHARGE (Reduce recharge time) | 4599 | E | none (cast-time wand stat) | none - spread/fire-rate/reload/recoil/mana only exist at cast time | skip |
| 4 | LIFETIME (Increase lifetime) | 4617 | A | field lives by LifetimeComponent; extending it needs a write to the private `kill_frame` (vanilla curse_init.lua:40-41) - writing `lifetime` later is ignored | `ProjectileComponent.lifetime += 75`; SKIP projectiles with lifetime -1 (endless) or they become finite | 1 |
| 5 | LIFETIME_DOWN (Reduce lifetime) | 4636 | A | shorten field | `lifetime -= 42` (clamp >=1) | 2 |
| 6 | NOLLA (Nolla) | 4655 | B2 | 'eraser field': deletes passing projectiles; MUST be stripped from the field itself | ELTE nolla.xml (lifetime=1 -> dies next frame) | 2 |
| 7 | SLOW_BUT_STEADY (Slow But Steady) | 4675 | E | none (cast-time wand stat) | none - spread/fire-rate/reload/recoil/mana only exist at cast time | skip |
| 8 | EXPLOSION_REMOVE (Remove Explosion) | 4693 | B2 | 'defuse field': passing explosives lose their blast | ELTE explosion_remove.xml | 2 |
| 9 | EXPLOSION_TINY (Concentrated Explosion) | 4714 | B2 | none | ELTE (config_explosion.explosion_radius=5) | 3 |
| 10 | LASER_EMITTER_WIDER (Plasma Beam Enhancer) | 4735 | B2 | none | ELTE (only affects LaserEmitterComponent projectiles) | 3 |
| 11 | MANA_REDUCE (Add mana) | 4775 | E | none (cast-time wand stat) | none - spread/fire-rate/reload/recoil/mana only exist at cast time | skip |
| 12 | QUANTUM_SPLIT (Quantum Split) | 4941 | B3 | avoid (splits the field) | ELTE (needs projectile_file) | 3 |
| 13 | GRAVITY (Gravity) | 4959 | A | push projectiles in radius down (vel nudge like projectile_gravity.lua). WARNING: vanilla already sets the FIELD itself falling (base_field has a VelocityComponent) - neutralise on the field | `VelocityComponent.gravity_y += +/-600` | 1 |
| 14 | GRAVITY_ANTI (Anti-gravity) | 4976 | A | push projectiles in radius up. WARNING: vanilla already sets the FIELD itself rising - neutralise on the field | `VelocityComponent.gravity_y += +/-600` | 1 |
| 15 | SINEWAVE (Slithering path) | 5007 | B1 | none | ELTE (SineWaveComponent) + `mVelocity *= 2` | 2 |
| 16 | CHAOTIC_ARC (Chaotic path) | 5033 | B1 | none | ELTE (per-frame Lua velocity editor) + speed/lifetime deltas | 3 |
| 17 | PINGPONG_PATH (Ping-pong path) | 5059 | B1 | none | ELTE (per-frame Lua velocity editor) + speed/lifetime deltas | 3 |
| 18 | AVOIDING_ARC (Avoiding arc) | 5078 | B1 | none | ELTE (per-frame Lua velocity editor) + speed/lifetime deltas | 3 |
| 19 | FLOATING_ARC (Floating arc) | 5097 | B1 | none | ELTE (per-frame Lua velocity editor) + speed/lifetime deltas | 3 |
| 20 | FLY_DOWNWARDS (Fly downwards) | 5116 | B1 | none | ELTE (one-shot Lua after 20f) + `mVelocity *= 1.2` | 3 |
| 21 | FLY_UPWARDS (Fly upwards) | 5136 | B1 | none | ELTE (one-shot Lua after 20f) + `mVelocity *= 1.2` | 3 |
| 22 | HORIZONTAL_ARC (Horizontal path) | 5156 | B1 | none | ELTE (per-frame Lua velocity editor) + speed/lifetime deltas | 3 |
| 23 | LINE_ARC (Linear arc) | 5176 | B1 | none | ELTE (per-frame Lua velocity editor) + speed/lifetime deltas | 3 |
| 24 | ORBIT_SHOT (Orbiting Arc) | 5196 | B1 | none | ELTE spiraling_shot.xml: projectile circles in place, direction from shooter facing (XML names are swapped in vanilla) | 3 |
| 25 | SPIRALING_SHOT (Spiral Arc) | 5217 | B1 | vortex: passing projectiles spiral around imbue point | ELTE orbit_shot.xml (init stores origin = imbue point, guarded by tag) | 2 |
| 26 | PHASING_ARC (Phasing Arc) | 5238 | B1 | none | ELTE (per-frame Lua velocity editor) + speed/lifetime deltas | 3 |
| 27 | TRUE_ORBIT (True Orbit) | 5266 | B1 | none | ELTE; orbits the shooter (`mWhoShot`) - odd mid-flight | 3 |
| 28 | BOUNCE (Bounce) | 5287 | A | none (optional rim reflection, tier 3) | `bounces_left += 10` | 1 |
| 29 | REMOVE_BOUNCE (Remove Bounce) | 5304 | B2 | none | ELTE (bounces_left=0) | 3 |
| 30 | HOMING (Homing) | 5322 | B1 | none. WARNING: vanilla already makes the FIELD chase foes (wiki: Circle of Fervour) - decide whether to strip HomingComponent | ELTE (pure HomingComponent; cleanest imbue) | 1 |
| 31 | ANTI_HOMING (Anti Homing) | 5340 | B1 | none | ELTE (HomingComponent variant) | 2 |
| 32 | HOMING_WAND (Wand Homing) | 5359 | B1 | none | ELTE (HomingComponent variant) | 2 |
| 33 | HOMING_SHORT (Short-range Homing) | 5378 | B1 | none. WARNING: field chases foes in vanilla | ELTE (pure HomingComponent; cleanest imbue) | 1 |
| 34 | HOMING_ROTATE (Rotate towards foes) | 5396 | B1 | none. WARNING: field chases foes in vanilla | ELTE (pure HomingComponent; cleanest imbue) | 1 |
| 35 | HOMING_SHOOTER (Boomerang) | 5414 | B1 | none. WARNING: vanilla makes the field follow the caster | ELTE (HomingComponent variant) | 2 |
| 36 | AUTOAIM (Auto-Aim) | 5432 | B1 | none | ELTE (one-shot redirect to nearest foe within 200px) | 1 |
| 37 | HOMING_ACCELERATING (Accelerative Homing) | 5449 | B1 | none. WARNING: field chases foes in vanilla | ELTE (HomingComponent + per-frame Lua coefficient ramp - still fine) | 1 |
| 38 | HOMING_CURSOR (Aiming Arc) | 5467 | B1 | none | ELTE; steers by shooter aim (EW remote aim dependent) | 3 |
| 39 | HOMING_AREA (Projectile Area Teleport) | 5485 | B1 | none | ELTE (teleports proj onto target within 32px) | 2 |
| 40 | PIERCING_SHOT (Piercing shot) | 5532 | B2 | none | ELTE piercing_shot.xml (`on_collision_die=0`) + `friendly_fire=true`, `damage -= 0.6` | 2 |
| 41 | CLIPPING_SHOT (Drilling shot) | 5552 | B2 | none | ELTE clipping_shot.xml (`penetrate_world=1`) | 2 |
| 42 | DAMAGE (Damage Plus) | 5572 | A | small AreaDamageComponent DAMAGE_PROJECTILE scaled by delta | `damage += 0.4` + tinyspark_yellow | 1 |
| 43 | DAMAGE_RANDOM (Random damage) | 5595 | A | random-strength tick damage | `damage += 0.4*k`, k from position-seeded Random | 2 |
| 44 | BLOODLUST (Bloodlust) | 5624 | A | tick damage that also hits allies (friendly fire!) | `damage += 1.3`, `friendly_fire=true` | 2 |
| 45 | DAMAGE_FOREVER (Mana To Damage) | 5648 | A+E | use the captured damage delta as tick damage | `damage += captured delta` (mana drain is cast-time) | 2 |
| 46 | CRITICAL_HIT (Critical Plus) | 5678 | A | none | `damage_critical.chance += 15` (ComponentObjectSetValue2) | 1 |
| 47 | AREA_DAMAGE (Damage field) | 5696 | B4 | AreaDamageComponent with `circle_radius=R` AND `aabb_min/max=+-R` (circle only filters inside the aabb). Targets tag `homing_target`, which EW puts on teammates when `home_on_players` is on | ELTE area_damage.xml | 1 |
| 48 | SPELLS_TO_POWER (Spells to Power) | 5714 | F/B | absorb projectiles/essence in radius into field power | ELTE; world-scan script; EW ships patched copies | 3 |
| 49 | ESSENCE_TO_POWER (Essence to Power) | 5733 | F/B | absorb projectiles/essence in radius into field power | ELTE; world-scan script; EW ships patched copies | 3 |
| 50 | ZERO_DAMAGE (Null shot) | 5752 | B2+A | 'null field': neutralise passing projectiles (works on enemy shots) | ELTE zero_damage.xml + `lifetime += 280` | 2 |
| 51 | HEAVY_SHOT (Heavy Shot) | 5852 | A | slow zone: passing projectiles slowed + empowered (= imbue) | `damage += 1.75`, `mVelocity *= 0.3` | 1 |
| 52 | LIGHT_SHOT (Light shot) | 5883 | A | accelerator zone (= imbue) | `damage -= 1.0`, `mVelocity *= 7.5` (cap), expl radius -10 | 2 |
| 53 | KNOCKBACK (Knockback) | 5940 | A | push creatures outward from centre | `knockback_force += 5` | 2 |
| 54 | RECOIL (Recoil) | 5957 | E | none (cast-time wand stat) | none - spread/fire-rate/reload/recoil/mana only exist at cast time | skip |
| 55 | RECOIL_DAMPER (Recoil Damper) | 5974 | E | none (cast-time wand stat) | none - spread/fire-rate/reload/recoil/mana only exist at cast time | skip |
| 56 | SPEED (Speed Up) | 5991 | A | accelerator ring (= imbue) | `mVelocity *= 2.5` (cap 20x) | 1 |
| 57 | ACCELERATING_SHOT (Accelerating shot) | 6016 | B2 | none | ELTE (one-shot air_friction edit) + `mVelocity` scale | 2 |
| 58 | DECELERATING_SHOT (Decelerating shot) | 6045 | B2 | none | ELTE (one-shot air_friction edit) + `mVelocity` scale | 2 |
| 59 | EXPLOSIVE_PROJECTILE (Explosive projectile) | 6091 | A | bigger expiry blast (base_field already explodes on death); optional periodic mini-blasts | `config_explosion.explosion_radius += 15`, `config_explosion.damage += 0.2`, `on_death_explode=true` | 1 |
| 60 | CLUSTERMOD (Clusterbolt) | 6120 | B3+A | cluster burst when field expires | ELTE clusterbomb.xml (execute_on_removed) + explosion deltas | 2 |
| 61 | WATER_TO_POISON (Water to poison) | 6144 | B4 | MagicConvertMaterialComponent r=32 has NO loop (default 0) -> converts once on a static field; set `loop=1`, radius R | ELTE (r=32 converter rides the projectile) | 1 |
| 62 | BLOOD_TO_ACID (Blood to acid) | 6163 | B4 | converter already r=48 loop=1 (bigger than a 28px circle) | ELTE (r=32 converter rides the projectile) | 1 |
| 63 | LAVA_TO_BLOOD (Lava to blood) | 6182 | B4 | converter already r=48 loop=1 | ELTE (r=32 converter rides the projectile) | 1 |
| 64 | LIQUID_TO_EXPLOSION (Liquid Detonation) | 6201 | B4 | converter r=48 loop=1 (terrain-destructive, EW world sync) | ELTE | 2 |
| 65 | TOXIC_TO_ACID (Toxic sludge to acid) | 6220 | B4 | converter already r=48 loop=1 | ELTE (r=32 converter rides the projectile) | 1 |
| 66 | STATIC_TO_SAND (Ground to sand) | 6239 | B4 | same converter at field radius (terrain-destructive, EW world sync) | ELTE | 2 |
| 67 | TRANSMUTATION (Chaotic transmutation) | 6258 | B4 | converter with position-seeded random target | ELTE (position-seeded -> EW-deterministic) | 2 |
| 68 | RANDOM_EXPLOSION (Chaos magic) | 6277 | B2 | none (too strong) | ELTE (sets random spawn_entity; seeded by entity_id -> per-peer divergence) | 3 |
| 69 | NECROMANCY (Necromancy) | 6296 | C1 | LoadGameEffectEntityTo foes in radius -> killed inside rise | append effect_necromancy.xml to `damage_game_effect_entities` | 2 |
| 70 | LIGHT (Light) | 6315 | B4 | LightComponent + fog hole on field | ELTE | 1 |
| 71 | ELECTRIC_CHARGE (Electric charge) | 7002 | A (+cosmetic) | apply `effect_electricity.xml` to creatures in radius (as electrocution_field.xml) | `damage_by_type.electricity += 0.1` + load particles/electricity.xml (cosmetic only); `lightning_count` is engine-side, no runtime write known | 1 |
| 72 | MATTER_EATER (Matter eater) | 7023 | B4 | CellEaterComponent radius=R. WARNING: its LifetimeComponent (200+-50) caps the FIELD itself in vanilla | ELTE; XML carries LifetimeComponent 200+-50 (caps host) | 3 |
| 73 | FREEZE (Freeze charge) | 7042 | C1+B4 | apply effect_frozen.xml in radius (as freeze_field.xml) + water->ice converter | `damage_by_type.ice += 0.2`, append effect_frozen.xml, load freeze_charge.xml | 1 |
| 74 | HITFX_BURNING_CRITICAL_HIT (Critical on burning) | 7063 | C2 | none (optional bonus tick dmg vs matching status) | ELTE (HitEffect CRITICAL_HIT_BOOST if condition) | 2 |
| 75 | HITFX_CRITICAL_WATER (Critical on wet (water) enemies) | 7081 | C2 | none (optional bonus tick dmg vs matching status) | ELTE (HitEffect CRITICAL_HIT_BOOST if condition) | 2 |
| 76 | HITFX_CRITICAL_OIL (Critical on oiled enemies) | 7099 | C2 | none (optional bonus tick dmg vs matching status) | ELTE (HitEffect CRITICAL_HIT_BOOST if condition) | 2 |
| 77 | HITFX_CRITICAL_BLOOD (Critical on bloody enemies) | 7117 | C2 | none (optional bonus tick dmg vs matching status) | ELTE (HitEffect CRITICAL_HIT_BOOST if condition) | 2 |
| 78 | HITFX_TOXIC_CHARM (Charm on toxic sludge) | 7135 | C2 | charm RADIOACTIVE foes in radius | ELTE | 2 |
| 79 | HITFX_EXPLOSION_SLIME (Explosion on slimy enemies) | 7153 | C2 | SLIMY/DRUNK foes in radius explode (unique child) | ELTE | 2 |
| 80 | HITFX_EXPLOSION_SLIME_GIGA (Giant explosion on slimy enemies) | 7171 | C2 | same, giga blast | ELTE | 3 |
| 81 | HITFX_EXPLOSION_ALCOHOL (Explosion on drunk enemies) | 7189 | C2 | SLIMY/DRUNK foes in radius explode (unique child) | ELTE | 2 |
| 82 | HITFX_EXPLOSION_ALCOHOL_GIGA (Giant explosion on drunk enemies) | 7207 | C2 | same, giga blast | ELTE | 3 |
| 83 | HITFX_PETRIFY (Petrify) | 7225 | C2 | petrify foes in radius (herd-check players!) | ELTE | 2 |
| 84 | ROCKET_DOWNWARDS (Downwards bolt bundle) | 7258 | B3 | none | ELTE (splits into bolt bundle, kills host) | 3 |
| 85 | ROCKET_OCTAGON (Octagonal bolt bundle) | 7276 | B3 | none | ELTE (splits into bolt bundle, kills host) | 3 |
| 86 | FIZZLE (Fizzle) | 7294 | B3 | none | ELTE (10% kill+sparks; entity_id seed) | 3 |
| 87 | BOUNCE_EXPLOSION (Explosive bounce) | 7321 | B2 | none (optional: spawn the bounce_fx at rim) | ELTE (sets `bounce_fx_file`) + `bounces_left += 1` | 2 |
| 88 | BOUNCE_SPARK (Bubbly bounce) | 7342 | B2 | none (optional: spawn the bounce_fx at rim) | ELTE (sets `bounce_fx_file`) + `bounces_left += 1` | 2 |
| 89 | BOUNCE_LASER (Concentrated light bounce) | 7363 | B2 | none (optional: spawn the bounce_fx at rim) | ELTE (sets `bounce_fx_file`) + `bounces_left += 1` | 2 |
| 90 | BOUNCE_LASER_EMITTER (Plasma Beam Bounce) | 7384 | B2 | none (optional: spawn the bounce_fx at rim) | ELTE (sets `bounce_fx_file`) + `bounces_left += 1` | 2 |
| 91 | BOUNCE_LARPA (Larpa Bounce) | 7405 | B2 | none | ELTE + `bounces_left += 1` (larpa clones: perf) | 3 |
| 92 | BOUNCE_SMALL_EXPLOSION (Sparkly bounce) | 7426 | B2 | none (optional: spawn the bounce_fx at rim) | ELTE (sets `bounce_fx_file`) + `bounces_left += 1` | 2 |
| 93 | BOUNCE_LIGHTNING (Lightning bounce) | 7447 | B2 | none (optional: spawn the bounce_fx at rim) | ELTE (sets `bounce_fx_file`) + `bounces_left += 1` | 2 |
| 94 | BOUNCE_HOLE (Vacuum bounce) | 7468 | B2 | none | ELTE + `bounces_left += 1` (black holes: terrain) | 3 |
| 95 | FIREBALL_RAY (Fireball thrower) | 7490 | B3 | turret field: emits sub-projectiles every 10f (likely already vanilla when merged into field) | ELTE (passing proj becomes a thrower) | 2 |
| 96 | LIGHTNING_RAY (Lightning thrower) | 7508 | B3 | turret field: emits sub-projectiles every 10f (likely already vanilla when merged into field) | ELTE (passing proj becomes a thrower) | 2 |
| 97 | TENTACLE_RAY (Tentacler) | 7527 | B3 | turret field: emits sub-projectiles every 10f (likely already vanilla when merged into field) | ELTE (passing proj becomes a thrower) | 2 |
| 98 | LASER_EMITTER_RAY (Plasma Beam Thrower) | 7545 | B3 | turret field: emits sub-projectiles every 10f (likely already vanilla when merged into field) | ELTE (passing proj becomes a thrower) | 2 |
| 99 | FIREBALL_RAY_LINE (Two-way fireball thrower) | 7563 | B3 | turret field: emits sub-projectiles every 10f (likely already vanilla when merged into field) | ELTE (passing proj becomes a thrower) | 2 |
| 100 | FIREBALL_RAY_ENEMY (Personal fireball thrower) | 7581 | C2 | foes in radius get the unique *_enemy.xml child | ELTE | 2 |
| 101 | LIGHTNING_RAY_ENEMY (Personal lightning caster) | 7599 | C2 | foes in radius get the unique *_enemy.xml child | ELTE | 2 |
| 102 | TENTACLE_RAY_ENEMY (Personal tentacler) | 7618 | C2 | foes in radius get the unique *_enemy.xml child | ELTE | 2 |
| 103 | GRAVITY_FIELD_ENEMY (Personal gravity field) | 7636 | C2 | foes in radius get the unique *_enemy.xml child | ELTE | 2 |
| 104 | CURSE (Venomous Curse) | 7654 | C2 | load curse_init.xml onto foes in radius - needs OWN rate limit: manual load bypasses LOAD_UNIQUE, each application adds +0.08 dmg and refreshes 300f; loses kill attribution | ELTE hitfx_curse.xml | 1 |
| 105 | CURSE_WITHER_PROJECTILE (Weakening Curse - Projectiles) | 7671 | C2 | load curse_wither_*.xml child to foes in radius - check for an existing child first (each duplicate adds +0.25 multiplier) | ELTE | 1 |
| 106 | CURSE_WITHER_EXPLOSION (Weakening Curse - Explosives) | 7688 | C2 | as above - dedupe children yourself | ELTE | 1 |
| 107 | CURSE_WITHER_MELEE (Weakening Curse - Melee) | 7705 | C2 | as above - dedupe children yourself | ELTE | 1 |
| 108 | CURSE_WITHER_ELECTRICITY (Weakening Curse - Electricity) | 7722 | C2 | as above - dedupe children yourself | ELTE | 1 |
| 109 | ORBIT_DISCS (Sawblade Orbit) | 7739 | B3 | sawblades orbit the field | ELTE (spawns orbiters once) | 2 |
| 110 | ORBIT_FIREBALLS (Fireball Orbit) | 7757 | B3 | orbiters circle the field (likely vanilla already) | ELTE (spawns orbiters once) | 3 |
| 111 | ORBIT_NUKES (Nuke Orbit) | 7775 | B3 | avoid | avoid (nuke spam) | skip |
| 112 | ORBIT_LASERS (Plasma Beam Orbit) | 7795 | B3 | orbiters circle the field (likely vanilla already) | ELTE (spawns orbiters once) | 3 |
| 113 | ORBIT_LARPA (Orbit Larpa) | 7813 | B3 | orbiters circle the field (likely vanilla already) | ELTE (spawns orbiters once) | 3 |
| 114 | CHAIN_SHOT (Chain Spell) | 7831 | B3 | none | ELTE - vanilla itself does this (chain_shot_launch.lua:42) | 2 |
| 115 | ARC_ELECTRIC (Electric Arc) | 7965 | B4 | arcs between field and imbued projectiles? (ArcComponent targeting UNVERIFIED) | ELTE | 2 |
| 116 | ARC_FIRE (Fire Arc) | 7984 | B4 | arcs between field and imbued projectiles? (ArcComponent targeting UNVERIFIED) | ELTE | 2 |
| 117 | ARC_GUNPOWDER (Gunpowder Arc) | 8003 | B4 | arcs between field and imbued projectiles? (ArcComponent targeting UNVERIFIED) | ELTE | 2 |
| 118 | ARC_POISON (Poison Arc) | 8022 | B4 | arcs between field and imbued projectiles? (ArcComponent targeting UNVERIFIED) | ELTE | 2 |
| 119 | CRUMBLING_EARTH_PROJECTILE (Earthquake shot) | 8041 | B3 | earthquake when field expires (terrain/EW world-sync load) | ELTE (execute_on_removed) | 3 |
| 120 | UNSTABLE_GUNPOWDER (Firecrackers) | 8170 | D | dump firecracker powder on expiry / sprinkle | `config.material` write UNVERIFIED; safer: execute_on_removed Lua spawning gunpowder_unstable | 2 |
| 121 | ACID_TRAIL (Acid trail) | 8190 | D | acid particles in circle (dissolves terrain) | trail ParticleEmitter(acid, is_trail=1, real particles) | 1 |
| 122 | POISON_TRAIL (Poison trail) | 8209 | C1+D | game effect (POISON/OILED/WET) in radius + emit material in circle | append effect_apply_*.xml + trail ParticleEmitter(material) | 1 |
| 123 | OIL_TRAIL (Oil trail) | 8229 | C1+D | game effect (POISON/OILED/WET) in radius + emit material in circle | append effect_apply_*.xml + trail ParticleEmitter(material) | 1 |
| 124 | WATER_TRAIL (Water trail) | 8249 | C1+D | game effect (POISON/OILED/WET) in radius + emit material in circle | append effect_apply_*.xml + trail ParticleEmitter(material) | 1 |
| 125 | GUNPOWDER_TRAIL (Gunpowder trail) | 8294 | D | sprinkle gunpowder in circle | trail ParticleEmitter(gunpowder) | 2 |
| 126 | FIRE_TRAIL (Fire trail) | 8313 | C1+D | ON_FIRE to creatures in radius (herd/friendly-fire check!) + real fire ParticleEmitter with `area_circle_radius=R` | append effect_apply_on_fire.xml + add trail ParticleEmitter(fire, is_trail=1) | 1 |
| 127 | BURN_TRAIL (Burning trail) | 8333 | C1+B4 | ON_FIRE in radius (herd check) + real-fire emitter over the circle. burn.xml itself only emits within ~4px, so merged on a field it lights a dot at the centre | append effect_apply_on_fire.xml + load burn.xml | 1 |
| 128 | ENERGY_SHIELD_SHOT (Projectile energy shield) | 8419 | B4 | shield dome. WARNING: its LifetimeComponent 200 caps the field in vanilla | ELTE + `mVelocity *= 0.4`; LifetimeComponent 200 caveat | 3 |
| 129 | RANDOM_MODIFIER (Random modifier spell) | 8879 | F | resolved at cast: field sees whatever modifier it rolled | n/a (inherits rolled modifier; EW seeds its RNG) | free |
| 130 | LARPA_CHAOS (Chaos larpa) | 9540 | B3 | avoid (cloning fields = lag) | ELTE; needs `projectile_file` VariableStorage; LifetimeComponent caveat | 3 |
| 131 | LARPA_DOWNWARDS (Downwards larpa) | 9559 | B3 | avoid (cloning fields = lag) | ELTE; needs `projectile_file` VariableStorage; LifetimeComponent caveat | 3 |
| 132 | LARPA_UPWARDS (Upwards larpa) | 9578 | B3 | avoid (cloning fields = lag) | ELTE; needs `projectile_file` VariableStorage; LifetimeComponent caveat | 3 |
| 133 | LARPA_CHAOS_2 (Copy trail) | 9597 | B3 | avoid (cloning fields = lag) | ELTE; needs `projectile_file` VariableStorage; LifetimeComponent caveat | 3 |
| 134 | LARPA_DEATH (Larpa Explosion) | 9617 | B3 | avoid (cloning fields = lag) | ELTE; needs `projectile_file` VariableStorage; LifetimeComponent caveat | 3 |
| 135 | COLOUR_RED (Red Glimmer) | 10863 | F | tint field particles (colour_spell.lua recolours ParticleEmitters) | ELTE (cosmetic, EW-safe) | 2 |
| 136 | COLOUR_ORANGE (Orange Glimmer) | 10887 | F | tint field particles (colour_spell.lua recolours ParticleEmitters) | ELTE (cosmetic, EW-safe) | 2 |
| 137 | COLOUR_GREEN (Green Glimmer) | 10911 | F | tint field particles (colour_spell.lua recolours ParticleEmitters) | ELTE (cosmetic, EW-safe) | 2 |
| 138 | COLOUR_YELLOW (Yellow Glimmer) | 10935 | F | tint field particles (colour_spell.lua recolours ParticleEmitters) | ELTE (cosmetic, EW-safe) | 2 |
| 139 | COLOUR_PURPLE (Purple Glimmer) | 10959 | F | tint field particles (colour_spell.lua recolours ParticleEmitters) | ELTE (cosmetic, EW-safe) | 2 |
| 140 | COLOUR_BLUE (Blue Glimmer) | 10983 | F | tint field particles (colour_spell.lua recolours ParticleEmitters) | ELTE (cosmetic, EW-safe) | 2 |
| 141 | COLOUR_RAINBOW (Rainbow Glimmer) | 11007 | F | tint field particles (colour_spell.lua recolours ParticleEmitters) | ELTE (cosmetic, EW-safe) | 2 |
| 142 | COLOUR_INVIS (Invisible Spell) | 11031 | F | tint field particles (colour_spell.lua recolours ParticleEmitters) | ELTE (cosmetic, EW-safe) | 2 |
| 143 | RAINBOW_TRAIL (Rainbow trail) | 11055 | C1+D | rainbow farts in radius (joke) | append effect_rainbow_farts.xml + trail | 3 |
