# field_imbue: research

Mod id: **field_imbue**, published as **Field Imbue**. This is the development log, written for the mod's author ("you") during development. Date: 2026-10-23.
Target: Noita build "Jan 25 2025" (modding API 12) and Entangled Worlds (EW, mod id `quant.ew`). EW 1.6.6 is installed; 1.6.8 is the latest release.

**The idea.** Static-projectile **fields** (the "Circle of …" spells) carry **modifiers**. A modifier on a field does two things:
1. **Area effect.** The field shows the modifier's effect inside its radius. For example, a fiery modifier sets everything in the circle on fire.
2. **Imbue.** Every projectile that flies through the field picks up that modifier.

**How this was researched.** Five research agents each covered one area: prior art, vanilla mechanics, the modifier catalog, EW sync, and the dev toolchain. Then an adversarial verifier re-checked the first four against source and the web. Their corrections are folded in below.
- Vanilla facts come from the installed `data.wak` (unpack it with `tools/unwak.py`).
- EW facts come from the installed 1.6.6 Lua (byte-identical to upstream `v1.6.6`) plus the upstream Rust `ewext` and proxy source.
- Labels: **[V]** = verified in source. **[I]** = inferred, needs an in-game test.

The full per-modifier table is in [modifier-catalog.md](modifier-catalog.md).

---

## TL;DR

- **Nothing published does this.** No published mod puts the wand's own modifiers on a field, spreads them over the field's area, and also passes them on to projectiles flying through. Two partial matches exist:
  - Closest generic match: **The Focus, "Modifying Lens"**. It is an unpublished GitHub prototype that copies the modifiers of the *first* projectile entering it onto every later one.
  - Closest published match: **Windows of Opportunity**. It has six line-shaped "window" spells, each giving passing projectiles one hard-coded effect.
  - Neither does the area effect, and neither is known to work with EW.
- **It can be built as a normal "safe" Lua mod** (Workshop-publishable, no native code). Every building block has a vanilla or mod precedent.
- **Vanilla already does part of it.**
  - The modifiers in a cast already land on the field entity itself. A Homing circle chases enemies, and Piercing makes a circle affect you.
  - Game-effect modifiers (Fire Trail, Burning Trail, Freeze Charge, the oil/water/poison trails) already spread over a circle's radius, **but only once per creature** **[V, §6.2]**. Freeze Charge froze 4/4 sheep; Burning Trail ignited 1/4 (a 50% ignition roll, applied once).
- **"Circle of Fire/Acid/Oil/Water" are not fields.** They are one-shot material rings (`ACTION_TYPE_MATERIAL`, with no ProjectileComponent). The real fields are Circle of Fervour, Thunder, Stillness, Vigour, Shielding, Transmogrification, Unstable Metamorphosis, Displacement and Buoyancy, plus the three Projectile Transmutation/Thunder/Gravity fields.
- **The "fiery" modifiers are Fire Trail (`FIRE_TRAIL`) and Burning Trail (`BURN_TRAIL`).** Both add `effect_apply_on_fire.xml`. There is no "Fire Arrow" modifier.
- **EW replays every player's wand cast on every peer.** A field and its Lua therefore run separately on every machine. The design has three rules:
  - work out the field's modifiers at cast time, which EW already syncs;
  - keep the per-frame field logic deterministic;
  - only let the owning peer spawn synced entities.

---

## 1. Does a mod like this already exist?

Overlap columns: (1) = area effect, (2) = imbue passing projectiles.

| Mod | Where | What it does | (1) area | (2) imbue | EW |
|---|---|---|---|---|---|
| **The Focus, "Modifying Lens"** (shoozzzh) | [GitHub](https://github.com/shoozzzh/The-Focus) only. README: not on Workshop, not for real runs. No license. | A static field with a `CollisionTriggerComponent` (`required_tag="projectile"`). It captures the `ProjectileComponent.config` of the first projectile that enters, then replays about 30 config fields onto every later one: stats, extra entities via `EntityLoadToEntity`, game effects via `HitEffectComponent LOAD_UNIQUE_GAME_EFFECT`, trails via a ParticleEmitter. | no | **yes, generic**, but learned from the first projectile, not the field's own cast | unknown |
| **Windows of Opportunity** (Fasteroid) | [Workshop 3576892938](https://steamcommunity.com/sharedfiles/filedetails/?id=3576892938), [GitHub](https://github.com/Fasteroid/noita-window-spells-mod). No license. | Six line-shaped static "windows": ignition, stillness, thunder, fervor, acceleration, nullification. A projectile crossing one gets a hard-coded effect, detected with a segment-crossing test. | no | fixed effects only | unknown |
| **Potent Potions** (Evaisa), installed | [Workshop 2373466827](https://steamcommunity.com/sharedfiles/filedetails/?id=2373466827) | At init it runs every modifier's `action()` in a sandbox and stores the shot-state delta. It then applies that delta to live projectiles shot by a creature with the potion status. A generic "modifier → live projectile" engine, but the trigger is a status, not a field. **Bug to avoid:** it puts game effects on the projectile itself (`LoadGameEffectEntityTo(projectile, …)`) instead of into its on-hit list. | no | generic engine, different trigger | unknown |
| **Copi's Things**: Larpa Lens and "Infliction" | [GitHub](https://github.com/Copious-Modding-Industries/copis_things) | Larpa Lens is a field that duplicates passing projectiles, using a CollisionTriggerComponent. "Infliction / Mass Infliction" is **commented out and abandoned**, described as "applies on-hit modifiers to enemies in a large area… Pair with modifiers!". That is a direct design precedent for (1). | abandoned precedent | one fixed effect | untested |
| D2D Content Pack: Circle of Phasing | [Workshop 3559987358](https://steamcommunity.com/sharedfiles/filedetails/?id=3559987358) | Projectiles inside phase through terrain. A per-projectile LuaComponent reverts this when they leave. | no | one fixed, temporary effect | unknown |
| Graham's Things, Oaken's Spells, Copi `circle_orbit/boost/anchor`, Boss Reworks "Soul of Motion" | wiki / GitHub | Phasing auras, projectile transformation, velocity pushes | no | motion or transform only | unknown |

**Code worth studying even though it doesn't overlap:**
- **Spellbound Bundle** (installed, 1976795806) reads a live projectile's modifier list from `ProjectileComponent.config` (`files/scripts/misc/attach_action_id.lua:9-21`).
- **Apotheosis** (installed, 3032128572) re-applies a captured cast config onto new projectiles (`files/scripts/projectiles/special/spell_worm_shoot.lua:78-150`). It is also the reference **safe-mod EW integration** (`init.lua:32-34`, `files/scripts/mod_compatibility/entangled_alt_fire_fix.lua`).

**What vanilla already does in this area:**
- The Projectile Transmutation, Thunder and Gravity fields scan every `projectile`-tagged entity each frame, then convert, kill or pull it. That includes enemy shots and other fields.
- Runestones, when kicked, do the same within 192 px.
- None of these *imbue* a projectile.

**How thorough the search was:**
- The full descriptions of all 1,931 Noita Workshop items were pulled through the Steam API and regex-searched.
- Also searched: modworkshop.net, the Noita wiki (main and Mod: namespaces), GitHub code search, and the source of the big spell packs (Apotheosis, Spellbound, Copi, Graham, Catgirl's Chaos Grimoire, D2D).
- Gaps: Discord (not searchable), and spell-by-spell checks of the largest packs.

**Verdict.** As a published, EW-aware mod that uses the field's *own* cast modifiers and adds the area effect, this is novel.
- None of the close prior art has a license. Reuse ideas, or ask the authors before copying code.
- Best references: The Focus's `files/utils/proj_cfg_utils.lua` for the imbue, and Windows' crossing test for detection.

---

## 2. How vanilla works (what the mod builds on)

### 2.1 A field is a projectile that doesn't move [V]

Every vanilla Circle inherits `data/entities/projectiles/deck/base_field.xml`. Its components:

| Component | Settings | Effect |
|---|---|---|
| ProjectileComponent | speed 0, `penetrate_entities=1`, `damage_every_x_frames=15`, `collide_with_world=0`, `on_death_explode=1`, `lifetime=9999999` | the field never travels |
| LifetimeComponent | `lifetime=7200` | this is what actually ends the field |
| GameAreaEffectComponent | radius 28 | applies the ProjectileComponent's `damage_game_effect_entities` to every `hittable` inside, e.g. `berserk_field.xml:4-6,61` |
| ProjectileComponent default | `damage_game_effect_entities=effect_charm.xml` | **must be overridden by any new field** |

Active vanilla fields:

| Spell | Internal id |
|---|---|
| Circle of fervour | `BERSERK_FIELD` |
| Circle of thunder | `ELECTROCUTION_FIELD` |
| Circle of stillness | `FREEZE_FIELD` |
| Circle of vigour | `REGENERATION_FIELD` (own LifetimeComponent 260) |
| Circle of shielding | `SHIELD_FIELD` |
| Circle of transmogrification | `POLYMORPH_FIELD` |
| Circle of unstable metamorphosis | `CHAOS_POLYMORPH_FIELD` |
| Circle of displacement | `TELEPORTATION_FIELD` |
| Circle of buoyancy | `LEVITATION_FIELD` (radius 56) |
| Projectile transmutation / thunder / gravity field | Lua-only, radius 48, 48 and 96 |

- Circle of seeing (`TELEPATHY_FIELD`) and `CHARM_FIELD` are commented out.
- Only about 15 of the 45 static-projectile spells are circles like this. The rest are black and white holes, walls, swarms, blasts, clouds and rains, so the mod needs its own **field registry**.
- **Material circles** (Circle of fire/acid/oil/water) are `ACTION_TYPE_MATERIAL`. They have no ProjectileComponent and are tagged only `projectile_player` (not `projectile`), and `circle_fire.xml` is a one-shot ring emitter. Supporting them means spawning a real field entity.

### 2.2 How modifiers reach a projectile [V]

- Each modifier's `action()` mutates the shot state `c`, e.g. `c.extra_entities ..=`, `c.game_effect_entities ..=` or `c.damage_*_add +=`.
- The whole cast's final `c` is handed to the engine **once**: `register_action → ConfigGunActionInfo_PassToGame → SetProjectileConfigs` (`gun.lua:154-165`).
- So **every projectile in the cast, including a field, gets all of that cast's modifiers**, whatever their order.
- The C++ engine applies them, not Lua:
  - `extra_entities` are **merged into the projectile entity**. Their components are added to it; tags and children are not.
  - Numeric deltas are written into component fields when the projectile is created.
  - The full state stays readable on the live projectile: `ComponentObjectGetValue2(pc, "config", "extra_entities")`, `"damage_projectile_add"`, and so on.
- There are **143 active modifiers**, plus 36 commented out.

### 2.3 What happens *today* if you cast a modifier together with a Circle

| Modifier kind | Effect on the field | Source |
|---|---|---|
| Game effects: Fire/Burning/Oil/Water/Poison trail, Freeze Charge, Necromancy | Appended to `damage_game_effect_entities` and applied across the whole circle by the GameAreaEffectComponent, **once per entity** | [V] §6.2 |
| Friendly fire (Piercing Shot, Bloodlust) | The field gets `friendly_fire=true`, but in the probe the **caster** was still not affected. The wiki says otherwise; same-herd others are untested | [V] §6.2 / wiki disagrees |
| Homing family | The circle chases foes. Boomerang makes it follow the caster | [V] wiki |
| Gravity / Anti-gravity | The circle falls or rises | [V] wiki |
| Larpa (chaos/up/down/copy trail), Matter Eater, Projectile Energy Shield | Their merged LifetimeComponent caps the field at about 150–300 frames. Nolla kills it | [V] |
| Position-local extras (Damage field r=16, converters r=32/48, Light, throwers, orbits) | Work around the field's **centre** at their own radius | [I] |
| Explosive projectile | The end-of-life blast becomes a real explosion | [I] |
| Speed, spread, bounce, lifetime | Nothing (speed 0, no world collision, LifetimeComponent governs) | [V] |

### 2.4 Templates for "projectiles passing through" [V]

- **Vanilla projectile fields** (`data/scripts/projectiles/projectile_{transmutation,thunder,gravity}.lua`): `EntityGetWithTag("projectile")` every frame, a Manhattan then a Euclidean distance check, then convert, kill or pull. They never need de-duplication because the projectile dies.
- **CollisionTriggerComponent** with `required_tag="projectile"`: an engine-side "entered the field" callback, used by Copi's Larpa Lens and The Focus. It fires once on entry.
- **Windows of Opportunity's crossing test**: checks the segment from `pos` to `pos + vel/60` against the shape, so fast bolts can't skip over a thin field.

### 2.5 Imbuing a projectile that is already flying

No API re-runs `action()` or re-applies a config to a live projectile. Each modifier class has to be emulated:

| Need | How | Precedent |
|---|---|---|
| Extra-entity modifiers (homing, piercing, converters, hit effects, throwers…) | `EntityLoadToEntity(xml, proj)`. It "does not load tags and other stuff" | `chain_shot_launch.lua:42`; Apotheosis `spell_worm_shoot.lua:111-116` |
| Game effects on hit | append to `ProjectileComponent.damage_game_effect_entities` | Apotheosis `wraith_returner_damage.lua:74-76`; Windows `window_fire.lua` |
| Damage / damage type | `damage`, `ComponentObjectSetValue2(pc,"damage_by_type","fire",…)` | `zero_damage.lua`, `spells_to_power.lua:61-71` |
| Explosion | `config_explosion.explosion_radius` / `.damage`, `on_death_explode=true` | `explosion_tiny.lua` |
| Speed / gravity | scale `VelocityComponent.mVelocity`, add to `gravity_y` | `runestone_slow.lua`, Apotheosis |
| Lifetime | `ProjectileComponent.lifetime += n`. **Skip −1 (endless).** To extend a *LifetimeComponent*, write its private `kill_frame` | `nolla.lua`; `curse_init.lua:40-41` |
| Crit | `ComponentObjectSetValue2(pc,"damage_critical","chance",…)` | Apotheosis |
| Trail | add a `ParticleEmitterComponent` with `is_trail=1`. Writing `config.trail_material` later probably does nothing | Spellbound, Potent Potions |
| Electric charge's `lightning_count`, Firecrackers' `material` | No known live write. Approximate it (Spellbound uses `config_explosion.create_cell_material`) | n/a |

Caveat [I]: every precedent edits a projectile in its *first frame*. Imbuing after many frames of flight is very likely fine, but it has not been tested.

---

## 3. Proposed design

```
cast (gun.lua hook)              field entity                         every frame
  modifier ids recorded  ──►  marker VSCs ("fi_mod=FIRE_TRAIL")  ──►  field_init: read markers, neutralise self-harm,
  when the cast has a field    merged onto the field by the engine      set up area appliers
                                                                      field_tick: area effects + imbue loop
                                                                        ─► crossing projectile? not seen yet?
                                                                        ─► apply handler(modifier) to it
```

### 3.1 Capturing which modifiers a field carries

There are two options.

**A. Read the field's own `ProjectileComponent.config` on frame 1.**
- Needs no wand hook; Spellbound and The Focus do this.
- Downsides: the result is *merged*. It mixes the wand's base stats, perk effects and the other spells in the multicast, and it can't name stat-only modifiers.
- Good for debugging and as a fallback.

**B (recommended). A `gun.lua` append that marks the field.**
- Wrap every `ACTION_TYPE_MODIFIER` action so it records its id on `c`.
- Wrap `add_projectile` **and** `add_projectile_trigger_timer` / `_hit_world` / `_death`, because fields cast through Add Trigger/Timer bypass `add_projectile`. Flag the shot when it contains a registered field.
- In `register_action`, append one tiny marker XML per modifier id to `state.extra_entities`. The engine then merges them onto the field, deterministically and on every EW peer.
- This covers always-casts, trigger payloads and Random Modifier.
- It composes with EW's `action_fix.lua` wrapper, as long as it passes through while `reflecting` is set.
- Known bypass: Spellbound temporarily swaps `add_projectile`.

How each modifier is applied:
- **MVP:** a hand-written handler table for tier 1 (§3.5).
- **Later:** a generic fallback for modded modifiers. Run each modifier's `action()` in reflection mode at `OnModPostInit` (as vanilla `gun_collect_metadata.lua` and Potent Potions do), diff `c` against `ConfigGunActionInfo_Init`, and apply the delta.

### 3.2 Field init (frame 1)

- **Act only on real fields.** Check speed 0 or our own VSC. Spellbound can merge whole projectile XMLs, including our patched field XMLs, into a moving bolt.
- **Neutralise self-harm** from vanilla merge behaviour, as a design choice: LifetimeComponents brought in by Larpa, Matter Eater or Energy Shield; gravity; homing. Note that removing them can race with those scripts' first-frame logic.
- **Set up area appliers**, see §3.3.
- **Store state in a VariableStorageComponent looked up by name** (radius, payload). Never use the first VSC found.

### 3.3 Area effect ("the field does the modifier")

| Modifier class | Area implementation |
|---|---|
| Game effects: fire, freeze, oil, water, poison, necromancy | The GameAreaEffectComponent already applies them, but **once per entity** (§6.2). The opt-in field must re-apply them: set `frame_length` at runtime if that works, otherwise loop over `hittable` entities in R with `LoadGameEffectEntityTo` plus **herd and friendly-fire checks**. Without the checks a fiery field burns the caster and teammates. |
| Trail materials (fire, acid, oil…) | A `ParticleEmitterComponent` with `create_real_particles=1` and `area_circle_radius=R`, so the ground in the circle actually burns. `burn.xml` alone only emits within about 4 px of the centre. |
| Material converters | `MagicConvertMaterialComponent`, radius R, `loop=1`. `water_to_poison.xml` has no loop, so it only converts once. |
| Damage plus / Damage field | `AreaDamageComponent` with `circle_radius=R` **and** `aabb_min/max=±R`. Note that it targets `homing_target`, which EW puts on teammates when `home_on_players` is on. |
| Curses | Load the curse entity onto foes in R yourself, with your **own** de-dupe and rate limit. A manual load bypasses `LOAD_UNIQUE`: each curse application adds +0.08 damage, and each duplicate wither curse adds +0.25 to the multiplier. |
| Stat modifiers (speed, heavy shot, damage, explosive…) | The imbue *is* the area effect: an accelerator ring, a "molasses" zone, an empower zone. |
| Wand-level modifiers (spread, recharge, mana, recoil) | No meaning on a field. Skip them. |

### 3.4 The imbue loop (per frame)

```lua
-- field_tick.lua (sketch)
local e = GetUpdatedEntityID(); local x, y = EntityGetTransform(e)
for _, p in ipairs(EntityGetInRadiusWithTag(x, y, R + 64, "projectile")) do
  local pc = EntityGetFirstComponent(p, "ProjectileComponent")
  if pc and p ~= e
     and not EntityHasTag(p, "fi_field")              -- all fields carry "projectile"
     and not EntityHasTag(p, "projectile_not")
     and not EntityHasTag(p, "projectile_cloned")     -- larpa/orbit clone cascades
     and ComponentGetValue2(pc, "mWhoShot") ~= e      -- things this field spawned
     and crossed(p, x, y, R)                          -- segment-vs-circle using mVelocity/60
     and not seen_by(p, e) then                       -- VSC list of field ids, NOT tags
    for _, id in ipairs(payload) do HANDLERS[id](p, pc) end
  end
end
```

- **Don't use per-field tags.** Noita has a single entity-tag registry that is never freed and is capped at 512 (raised from 256 in Jan 2025). Windows of Opportunity's `window_subject_<id>` tags leak. Use a VariableStorageComponent "virtual tag" instead, as The Focus does.
- **Skip NaN transforms.** Wiki: NaN-position fields apply effects globally.
- Optional: cap the number of imbues per projectile, and decide "permanent" vs "only while inside" (D2D reverts on exit).

### 3.5 MVP modifier set (tier 1, 33 modifiers, three code paths)

The three code paths are:
1. Append a game effect and add an emitter.
2. `EntityLoadToEntity` the vanilla XML.
3. Write a component field or scale velocity.

| Group | Modifiers |
|---|---|
| Fiery and elemental (the showcase) | `FIRE_TRAIL`, `BURN_TRAIL`, `OIL_TRAIL`, `WATER_TRAIL`, `POISON_TRAIL`, `ACID_TRAIL`, `FREEZE` (Freeze Charge), `ELECTRIC_CHARGE` |
| Curses | `CURSE` (Venomous) and the four `CURSE_WITHER_*` |
| Converters, aura | `WATER_TO_POISON`, `BLOOD_TO_ACID`, `LAVA_TO_BLOOD`, `TOXIC_TO_ACID`, `AREA_DAMAGE`, `LIGHT` |
| Stats | `DAMAGE`, `HEAVY_SHOT`, `SPEED`, `CRITICAL_HIT`, `EXPLOSIVE_PROJECTILE`, `LIFETIME`, `BOUNCE`, `GRAVITY`, `GRAVITY_ANTI` |
| Homing | `HOMING`, `HOMING_SHORT`, `HOMING_ROTATE`, `HOMING_ACCELERATING`, `AUTOAIM` |

Skip for now:
- Projectile spawners (throwers, orbits, Larpa, cluster) as imbues: they multiply entities, which hurts performance and EW traffic.
- Terrain-eaters as area effects.

Tiers 2 and 3 are in the catalog.

### 3.6 Interop hazards

| Mod | What it does | Risk |
|---|---|---|
| EW | wraps every action (`action_fix.lua`) and redefines `GetUpdatedEntityID` to return the *root* entity inside the gun context | our wand hook sees the root, not the updated entity |
| Apotheosis | wraps `ConfigGunActionInfo_PassToGame` to smuggle data through `action_description` | conflicts if we use the same channel |
| Spellbound | swaps `add_projectile` | bypasses our capture hook |
| Any mod | can rewrite the same field XMLs | patching with `ModTextFileSetContent` can clash; check `ModTextFileWhoSetContent` |

---

## 4. Entangled Worlds

### 4.1 What syncs and how [V]

| Thing | How EW handles it |
|---|---|
| **Player wand shots** | **Replayed, not synced.** The shooter sends a reliable `fire` message with seeds, wand position and mana. Every peer re-runs the cast with `np.UseItem` on its copy of that player, with deck order, action RNG and spread made identical. |
| **A field a player casts** | Exists separately on **every** peer, and its Lua runs on every peer. Only a hardcoded list (including `levitation_field`, `projectile_transmutation_field`, black holes) gets owner-driven position and lifetime sync via `ew_projectile_position_sync`. |
| **Enemies** | Native entity sync with one **owner** peer per entity (chosen by distance). On other peers, mirrors have their **HP pinned** to the owner's value, take almost no damage (curse and healing damage pass through), and have their **game effects replaced** with the owner's list. |
| **Enemy projectiles** | Sent once when fired, then simulated locally on each peer. |
| **Players** | Each peer is authoritative for its own player. Effects and stains are rebroadcast every 15 frames. In shared-health mode, fire, toxic and poison damage is divided by the player count. |
| **World pixels** | Synced per 128 px chunk. Authority goes to the peer whose player is nearest. Materials travel as int16 ids. |
| **Mod lists** | **Not checked.** EW does compare material tables and warns "MATERIALS DIFFER … CHECK MOD ORDER". |

### 4.2 Design rules that follow

1. **Layer 0: work out modifiers at cast time.** The §3.1 B hook runs inside the replayed cast, so every peer's copy of the field gets the same markers for free.
2. **Layer 1: deterministic field logic, no messages.**
   - Don't use `math.random`, unseeded `Random()`, entity ids, `GameGetFrameNum()` or float positions as seeds. Entity ids and frame numbers differ per peer, and replays lag.
   - Time things with a frame-age counter on the field.
   - It doesn't matter that peers apply fire to *mirror* enemies. The owner's copy of the same field ignites the real enemy, and that state syncs back.
3. **Layer 2: only the owning peer spawns synced entities** (enemies, items).
   - Find the owner from the field's `mWhoShot`: a shooter tagged `ew_client` is a remote player; otherwise the shooter's `ew_gid_lid` decides.
   - **Don't** use `ew_do_i_own(field)`. It returns *true* on every peer for entities that aren't synced, which includes normal fields.
   - Don't use `player_unit` as an "is this me" test either. EW adds it to the remote shooter for the length of the replayed cast.
4. **Sub-projectiles spawned by Lua** must use the field or the projectile as the shooter, not the player (that disturbs EW's seed queue) and not an owned enemy (EW would broadcast it and create duplicates). They also need deterministic speed and spread, because Lua shots never get EW's spread RNG.
5. **Friendly fire and PvP.**
   - Use herd relations, `mShooterHerdId`, `CrossCall("ew_ff")` and `CrossCall("ew_pvp")`.
   - Dead players can become AI "notplayers" that keep casting.
   - Homing imbues and AREA_DAMAGE can lock onto teammates when `home_on_players` is on.
   - Material fire ignores herds entirely.
6. **Custom effect files** sync by filename only when they use `effect="CUSTOM"`. Effects of a normal type are recreated on mirrors from the vanilla enum, so extra components in the file are lost.
7. **Load order.** EW's `action_fix` only wraps actions that already exist when its append runs. Options:
   - put field_imbue **above** quant.ew in the mod list;
   - reorder with `ModLuaFileSetAppends`;
   - keep the mod's `action()` functions RNG-free.
8. **Version and settings check.**
   - Add an extra module: `ModLuaFileAppend("mods/quant.ew/files/api/extra_modules.lua", "mods/field_imbue/files/compat/ew_module.lua")`, guarded by `ModIsEnabled("quant.ew")`, with an RPC namespace.
   - RPCs to a peer without the handler are **silently dropped**, so send hello, expect a reply, and time out.
   - Gameplay settings should be `NEW_GAME` scope, set the same on all peers.
9. **Optional:** add `ew_projectile_position_sync` to the field XML so the owner decides lifetime and despawn. This avoids [EW issue #520](https://github.com/IntQuant/noita_entangled_worlds/issues/520), where a Teleportation field vanished for the host but not the guest. It costs entity-sync traffic.
10. **Guard every `CrossCall`.** It only exists when EW and NoitaPatcher are loaded.
11. **Test against EW 1.6.8.** It changed world sync and explosion cuts, which matters for terrain-changing fields.

---

## 5. Dev setup (Linux, Steam + Proton; short version)

### Mod skeleton
- `mod.xml` with `request_no_api_restrictions="0"`. Unsafe mods can't go on the Workshop.
- `compatibility.xml` with `version_built_with="12"`.
- `init.lua`: put `ModLuaFileAppend` and `ModTextFileSetContent` calls at the top level. The translations CSV is appended into `data/translations/common.csv`.
- New spells are `table.insert(actions, {...})` with 16×16 RGBA icons.

### Running the dev build
Run `noita_dev.exe` under Proton the same way the EW proxy already launches Noita here:
```bash
STEAM=$HOME/.local/share/Steam
export STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM STEAM_COMPAT_DATA_PATH=$STEAM/steamapps/compatdata/881100 SteamAppId=881100 SteamGameId=881100
cd $STEAM/steamapps/common/Noita && /usr/share/steam/compatibilitytools.d/proton-cachyos-native/proton run noita_dev.exe -no_logo_splashes -windowed
```
- Debug keys: F1 shows the key map, F5 toggles debug mode, I+click opens the entity inspector.
- Logs go to `Noita/logger.txt`. EW's `enable_log` already turns on Lua `print` output there.
- There is **no reliable hot-reload**. Plan for restarts (Mods → "Restart with enabled mods active").

### Loading the mod
- Symlink this repo: `ln -s ~/field_imbue ~/.local/share/Steam/steamapps/common/Noita/mods/field_imbue`. Whether Wine follows the symlink is untested. The fallback is keeping the repo inside `mods/`.
- Place it above quant.ew in the mod list.

### Editor and checks
- lua-language-server is already in mason. Add the API definitions from [NathanSnail/AutoLuaAPI](https://github.com/NathanSnail/AutoLuaAPI) and [noita_stubs](https://github.com/NathanSnail/noita_stubs).
- Noita runs LuaJIT 2.0.4, and pure logic can be unit-tested with the local `luajit`.
- `luacheck` needs installing (`sudo pacman -S luacheck`). Feed it the 405 API names from `tools_modding/luacheck_config.lua`.

### In-game test helpers
- **cheatgui** (installed).
- **Spell Lab Shugged** (Workshop 3284126816). The installed `spell_lab` is the abandoned original.
- **Component Explorer** (3073419779).

### Solo EW test
EW's `contributing.md` describes two instances on one machine:
- the host proxy runs `--host 5123`;
- the client proxy runs with `NP_DISABLE_STEAM=1 NP_NOITA_ADDR=127.0.0.1:21252 --lobby 127.0.0.1:5123`, its own `--settings-path` and `--save-state-path`, and a second Proton prefix.

This is assembled from documentation and has not been tested here.

### Publishing
- Run `noita_dev.exe -workshop_upload field_imbue -workshop_upload_change_notes "…"` through Proton, with Steam running.
- It needs `workshop.xml` and a 16:9 `workshop_preview_image.png`.
- Only whitelisted file types are uploaded, so `docs/` and `tools/` can live in the repo.

### Vanilla data
Unpack it with `python3 -I tools/unwak.py ~/.local/share/Steam/steamapps/common/Noita/data/data.wak ~/noita-dev/` (or `noita.exe -wizard_unpak`). The research copy was in a temp folder.

---

## 6. Test these in game before building

1. **Burning Trail + Circle of Fervour** (with and without Piercing Shot).
   - Do enemies anywhere in the circle ignite?
   - On the field, `print` `damage_game_effect_entities` and `ComponentGetVector(gaec,"game_effect_entitities","string")`.
   - This decides how much of the area effect is free.
2. **Mid-flight imbue.** On a spark bolt 30 frames after it was fired:
   - `EntityLoadToEntity("data/entities/misc/homing.xml", p)`: does it home?
   - Append `effect_frozen.xml` to `damage_game_effect_entities`: does the hit freeze?
3. **Load hooks.** Do `execute_on_added` LuaComponents fire when loaded through `EntityLoadToEntity`? Until that is known, use `execute_every_n_frame=1` with `remove_after_executed`.
4. **Converter on a field.** Cast Water to Poison + a Circle: does it convert once or continuously?
5. **EW load order.** Make a test action that calls `Random()`, place it above or below quant.ew, and compare host vs client.
6. **Two-peer EW.**
   - Is a spark bolt fired through A's fiery field imbued on both screens?
   - Is an enemy owned by B ignited by A's field?
   - Does the field expire at the same time on both peers?

### 6.1 How the probes run

**Tests 1–4** are automated by the probe mod in `probe/` (mod id `field_imbue_probe`).
- `tools/probe-run.sh` starts Noita in a separate Proton prefix (`~/noita-dev/prefix-probe`), with its own saves and only the probe mod enabled.
- The probe pins the player in the air, deletes the starting items and builds wands from `add_these_child_actions`. It fires them by driving `ControlsComponent`, the same trick EW's notplayer AI uses.
- It places pinned 40-hp sheep as targets and prints every result as a `FIPROBE …` line in `Noita/logger.txt`.
- It also tests design option B (§3.1): a test-only `FI_PROBE_MARKER` modifier appends a marker XML to `c.extra_entities`. The probe then checks whether the marker lands on a bolt, a Circle of Fervour and a Circle of Fire.
- `logger.txt` is shared with any other running Noita, so only run the probe while no other instance is open.

**Tests 5–6** need two peers and the real opt-in mechanic, so they run after a minimal prototype exists. The prototype is one opt-in modifier card plus the field tick for `BURN_TRAIL` and `FREEZE`.
- **Setup.** Run two instances on this machine following EW `contributing.md`:
  - the host proxy with `--host 5123`;
  - the client proxy with `NP_DISABLE_STEAM=1 NP_NOITA_ADDR=127.0.0.1:21252 --lobby 127.0.0.1:5123`, its own `--settings-path` and `--save-state-path`, and a second prefix.
- **Test 5.** A probe action calls `SetRandomSeed` + `Random()` and logs the value. Run it once with field_imbue above quant.ew and once below, and compare the host and client logs.
- **Test 6.** Each peer logs the imbue decisions (`field gid/owner, projectile filename, frame-age`). Compare the logs side by side.

### 6.2 Results of tests 1–4 (run 2026-10-23, raw log: [probe-log-2026-10-23.txt](probe-log-2026-10-23.txt))

All cases use Circle of Fervour (`BERSERK_FIELD`) with 4 sheep pinned 18 px from the centre (radius 28), and spark bolts (`LIGHT_BULLET`).

| # | Question | Result |
|---|---|---|
| 1 | Plain circle (control) | 4/4 sheep berserked. `damage_game_effect_entities=effect_berserk.xml`. |
| 1 | Freeze Charge + circle | **Yes, vanilla already spreads it.** The engine appends the cast's `config.game_effect_entities` onto the field's `damage_game_effect_entities` (`effect_berserk.xml,effect_frozen.xml`). 4/4 sheep frozen and took 0.2 ice damage. `freeze_charge.xml` was merged as components (2 extra MagicConvertMaterialComponents, 0 children). |
| 1 | Burning Trail + circle | Merged the same way (`effect_apply_on_fire.xml`), but **1/4 sheep ignited**, and you saw it on screen too. The circle applies its list **once per entity** (`GameAreaEffectComponent.frame_length=-1`), and ON_FIRE then rolls against the target's `fire_probability_of_ignition` (0.5 for sheep). A reliable fiery field must re-apply periodically. |
| 1 | Piercing Shot + circle on the caster | The field gets `friendly_fire=true` and `damage=-0.6`. **The caster was not berserked**, with or without PROTECTION_ALL, so the wiki claim was not reproduced. Same-herd others such as EW teammates are untested. |
| 1 | Burning Trail on a normal bolt | The same merge happens on ordinary projectiles: `damage_game_effect_entities=effect_apply_on_fire.xml`. |
| 2 | Mid-flight homing | **Works.** The control bolt drifted from +0.5° to +11.5° (gravity) and flew past the sheep. With `EntityLoadToEntity(homing.xml)` at frame 4, the bolt turned from +1° to −157° and reached the sheep at (+181, −64). |
| 2 | Mid-flight on-hit effect | **Works.** The control hit the sheep without freezing it. With `effect_frozen.xml,` appended to `damage_game_effect_entities` 2 frames after firing, the hit froze the sheep. |
| 3 | `execute_on_added` via `EntityLoadToEntity` | **Runs.** `execute_every_n_frame=1` + `remove_after_executed` also runs once and removes itself. |
| 4 | Water to Poison on a circle | **Converts once.** 6 converters, `loop=false`. `mRadius` went 3 → 30 within 10 frames, then stayed at 30 for 300 frames. |
| 4 | Blood to Acid on a circle | `loop=true`, radius 48. `mRadius` read 0 at every sample, consistent with a full sweep every frame (`steps_per_frame` 48); inferred. |
| 5 | Design B marker in `c.extra_entities` | **Works** on a bolt and on Circle of Fervour: the VariableStorageComponent `fi_mod` is merged onto the field itself, with no child entity. It does **not** work on Circle of Fire: that entity only has Audio/Lifetime/ParticleEmitter, so material circles never receive extra entities. |

**Consequences for the design:**
- **Capture via markers (§3.1 B) is confirmed.** Material circles are out of scope unless the mod spawns its own field entity.
- **For game-effect modifiers the area effect is free.** Vanilla already does it on every GAEC circle, so vanilla behaviour is already like this without the mod. The opt-in field only has to make it **repeat**. The next thing to check is whether `frame_length` can be set at runtime; otherwise add our own periodic applier with herd checks.
- **Mid-flight imbuing works with both main paths** (`EntityLoadToEntity` of the modifier XML, and appending to `damage_game_effect_entities`). No first-frame-only restriction showed up.
- **Converters** need `loop=1`, set on the field or in our own copy.
- **Dev note (prototype results follow in §6.3):** firing from Lua works by driving `ControlsComponent` (`mButtonDownFire` / `mButtonFrameFire` / `mButtonLastFrameFire` with the component disabled), but only with the wand the game itself selected. Spawning a wand and writing `Inventory2Component.mActiveItem` leaves it unable to fire. The probe therefore rewrites the held wand's cards with `CreateItemActionEntity` and refreshes it via `mActualActiveItem=0` (vanilla's own perk pattern).


### 6.3 Opt-in prototype results (2026-10-23)

**The prototype.**
- Card: `FIELD_IMBUE` ("Field resonance").
- Scripts: `files/scripts/field_init.lua`, `field_tick.lua` (every frame: imbue crossing projectiles), `field_reapply.lua` (every 60 frames: re-apply the area effect), and `fi_lib.lua`.
- Supported modifiers: Burning trail, Fire trail and Freeze charge.
- An independent review found 2 bugs and 7 risks; all are fixed:
  - players carry `prey`, so re-apply now skips player tags and the caster's herd;
  - static non-field projectiles are not imbued;
  - fields must have `speed_max=0`;
  - no stacking on projectiles that already carry the modifier;
  - EW mirror enemies are skipped via `ew_do_i_own`;
  - trail emitters loaded mid-flight start at the bolt's position;
  - lookups by tagged component.

**Single player.** Run with `tools/probe-run.sh prototype`; raw log in [proto-log-2026-10-23.txt](proto-log-2026-10-23.txt).

| # | Check | Result |
|---|---|---|
| P1 | Fire field re-apply | 4 sheep inside: 1–2/4 burning from vanilla's single roll, **4/4 by frame 122**, and stays that way. |
| P2 | Bolt through an imbuing Freeze field | The bolt gets `effect_frozen`, +0.2 ice, the converters and `fi_seen`. The sheep 90 px beyond the field **froze**. One of three runs missed the sheep with a correctly imbued bolt (aim/spread). |
| P3 | Same without the card | Bolt unchanged, target not frozen: **vanilla circles stay vanilla**. |
| P4 | Bolt cast together with the card | No field scripts and no payload left on it. |
| P5 | Bolt through an imbuing fire field | Gets `effect_apply_on_fire` and the burn trail. The target ignites in some runs: it is the vanilla 50% roll per hit. |
| P6 | Sheep in the caster's herd inside a Freeze field | **Never frozen**, not even by the vanilla GAEC once. The normal sheep was re-frozen at frames 200 and 260 after thawing. |
| P7 | Speed Up ×3 bolt | Imbued. Projectiles are capped at 1000 px/s, so the wide search margin is only a safety net. |
| P8 | Static water cloud inside the field | Not imbued. |
| P9 | Freeze-charge bolt through a Freeze field | `fi_seen` set, ice stays 0.20, converters stay 2: **no stacking**. |

**Entangled Worlds, two peers on one machine** (`tools/ew-2p.sh`; logs in `ew-hostA-log-2026-10-23.txt` and `ew-clientB-log-2026-10-23.txt`).
- **Harness:** headless CLI proxies (`--host 5123` / `--lobby 127.0.0.1:5123`, with `--exe-path`, `NP_DISABLE_STEAM=1` and `NP_ALLOW_REUSE_ADDR=1`). Each peer has its own prefix; peer B runs from a shadow game folder so it gets its own `logger.txt`.
- **Connection:** both peers connect and see each other.
- **Host A, with EW active:** the field logic runs without errors. Imbuing Freeze/fire fields, re-apply and the imbued bolt all behave as in single player, and A sees B where expected.
- **Not verified yet: cross-peer behaviour.** Client B saw A's player but received **nothing else** from A: none of A's replayed shots (not even plain spark bolts) and none of A's EntityLoad'ed sheep. B logged "slot empty, requesting items" and A's items never arrived. Because plain vanilla shots and sheep don't replicate either, this is a harness/EW-sync issue, not field_imbue.
- **Second harness issue:** EW overwrites the local player's aim every frame (the scripted aim `102,-8` became `-264,-166`) even with `ControlsComponent` disabled. Scripted aiming under EW needs another approach, e.g. writing the aim in `OnWorldPreUpdate` with the probe mod loaded after `quant.ew`.
- **Next:** either a manual two-player session (real input, normal proxy), or debugging why EW inventory/DES sync doesn't reach B in this harness.
- **Done afterwards (2026-10-23):** a manual two-player session with the fire/freeze prototype passed every step of [EW-TEST-CHECKLIST.md](EW-TEST-CHECKLIST.md).


### 6.4 Generic modifier support (2026-10-23/24)

**Why it changed.** The two-player test went well, with two follow-ups from you:
- Imbuing fields still showed the modifiers' own centre effects: a fire leak from Fire trail, a burning centre from Burning trail, and snow from Freeze charge.
- As many modifiers as possible should imbue.

The hand-written fire/freeze table is replaced by a generic, data-driven system.

**1. Recipes at mod load** (`files/scripts/recipes_build.lua`, from `OnModPostInit`).
- Every `ACTION_TYPE_MODIFIER`, from vanilla and from any other mod, is evaluated in reflection mode, the same way vanilla builds spell tooltips. This mirrors Potent Potions.
- Each modifier is evaluated **twice**, with a different wand mana and RNG seed. Any result that changes depends on wand state or randomness and is skipped.
- A recipe holds:
  - damage by type, explosion damage and radius, crit, knockback, lifetime, bounces, gravity, speed multiplier, friendly fire and null damage;
  - the extra entities, on-hit game effects (with their effect names) and trail materials;
  - the active material converters.
- The output is the virtual file `files/gen/recipes.lua`, plus `skipped.lua` and one marker `files/gen/mod/<ID>.xml` per modifier. The init-state globals and the `dofile_once` caches are restored afterwards.
- **Vanilla result: 130 recipes.** Skipped:
  - the 7 wand-level modifiers (spread, recharge, mana, recoil, Slow but steady, Heavy spread);
  - Firecrackers (cast-time `material`);
  - Mana to damage (depends on wand mana);
  - Random damage and Random modifier;
  - **Nuke orbit and Chaos magic**, denied by default: a nuke or black hole on every projectile crossing a field for 2 minutes. The setting **Allow Nuke orbit and Chaos magic** turns them on.

**2. Cast hook** (`files/gun_append.lua`, appended to `gun.lua`, so it sees every mod's spells and runs before the deck is built).
- Modifier and static-projectile actions are wrapped so they record themselves on the shot.
- Only when **Field resonance and a static projectile are in the same shot**, `register_action`:
  - adds one marker per modifier;
  - removes those modifiers' own extra entities (whole comma-separated entries);
  - clears `trail_material`, `damage_null_all` and `gravity`.
- So the imbuing field carries none of the modifiers' own pieces: no fire, snow or homing at its centre, and it doesn't fly away. On-hit game effects stay, because the circle's area effect spreads them.
- Every **other** projectile of that shot (a multicast bolt, a wall, a black hole) gets the stripped pieces back on its first frame. It is marked as already carrying the shot's modifiers, so its sibling field doesn't add their numbers a second time.

**3. Field runtime** (`fi_lib.lua`).
- **Imbuing:** each projectile crossing the field gets each recipe once. Nothing is applied if it already has that modifier from its own cast; only real extras and effects count, not shared sparkle particles.
- **Not imbued:**
  - other fields, static projectiles and clones;
  - anything shot by another projectile, so chain-shot or ray children and trigger payloads can't cascade;
  - projectiles still waiting for their first-frame script (re-checked next frame);
  - by default, enemy projectiles. The setting **Imbue enemy projectiles** turns this on (decision #2). Note that imbued enemy spawners can be duplicated across EW peers.
- **Area:** on-hit effects with a countable name are re-applied every 60 frames, never to players without friendly fire, the caster's herd, or local copies of remote players. Active material converters run over the whole circle with `loop`.

**Sweep** (`tools/probe-run.sh sweep [IDS]`; final log: [sweep-log-2026-10-24.txt](sweep-log-2026-10-24.txt)).
- Every recipe was cast as Field resonance + modifier + Circle of fervour, with a spark bolt shot through it. Regression checks run first:
  - **R1:** a shot without a field keeps its homing.
  - **R2:** a multicast with Heavy shot doesn't slow the bolt twice (206 vs 224 px/s; doubled would be ~62).
  - **R3:** a multicast bolt keeps exactly one HomingComponent and the field none, 5 runs out of 5.
- Final result: **payload 130/130, clean centre 130/130, imbued bolt 130/130, no Lua errors.**
- The three effects you reported are gone. Fly upwards/downwards no longer moves an imbuing field (your test ran the earlier prototype).
- An independent review found 5 bugs and 9 risks. All bugs and the risky parts are fixed, as listed above.

**Settings** (`settings.lua`, both off by default, new-game scope so they can't change mid-run; under EW every player needs the same values):
- **Imbue enemy projectiles.**
- **Allow Nuke orbit and Chaos magic.**

Probe verification (2026-10-24, `tools/probe-run.sh sweep IDS "enemy destructive"`):
- **Defaults:** an enemy bolt through an imbuing field is not imbued, and there are no recipes for the two destructive modifiers.
- **Both on:** the enemy bolt is imbued, and Nuke orbit and Chaos magic pass the sweep (payload, clean centre, imbued bolt).
- The settings menu UI itself was not opened.

**Not covered yet, or known limits:**
- `lightning_count`: Electric charge's on-hit lightning is not imbued, only its electric damage and sparkle.
- Firecrackers' `material`.
- Area versions of hit-effect modifiers (curses, petrify, critical-on-X): they imbue projectiles only.
- The Transmutation converter: no area effect; it still imbues.
- Field resonance only works when it is in the **same shot** as the circle, not across a trigger.
- Perk modifiers are not recorded.
- Under EW, imbued Fizzle and Chaos-style extras use EW's fixed seed fallback, because the `ew_transmutation` VSC is only set at fire time.
- Circle of buoyancy, which EW position-syncs, is untested in multiplayer.
- **The generic version has not been re-tested with two players yet.**

---

## 7. Decisions for you

1. **Always-on or opt-in? DECIDED 2026-10-23: opt-in.**
   - A new modifier card, or new field spells, turns a field into an imbuing field.
   - Vanilla circles keep their vanilla behaviour. The §3.1 B hook only marks a field when the opt-in card or spell is in the cast.
2. **Whose projectiles get imbued? DECIDED 2026-10-24: a mod setting.** **Imbue enemy projectiles** is off by default, so only players' projectiles are imbued. With it on, enemy fireballs through your circle become fiery too, but imbued enemy spawners can be duplicated across EW peers.
3. **Permanent or while-inside?** Is the imbue permanent, or does it revert when the projectile leaves?
4. **Stacking.** What happens with several fields, the same field crossed twice, or the same modifier twice?
5. **Vanilla self-effects.** Keep the vanilla behaviours (homing or gravity circles that move, Larpa or Matter Eater capping a field's lifetime), or neutralise them?
6. **Material circles.** Should Circle of Fire/Acid/Oil/Water become real fields?
7. **Name. DECIDED:** published as *Field Imbue* (mod id `field_imbue`, repo `noita-field-imbue`).

---

## 8. Key references

**Vanilla** (paths inside `data.wak`):
- `data/scripts/gun/gun.lua` (shot pipeline, `draw_shot` 154-165, `add_projectile` 325-333, triggers 335-372)
- `data/scripts/gun/gun_actions.lua` (`BERSERK_FIELD` 6476, `FIRE_TRAIL` 8313, `BURN_TRAIL` 8333, `FREEZE` 7042, `CIRCLE_FIRE` 3118)
- `data/scripts/gun/gunaction_generated.lua`, `gun_collect_metadata.lua`
- `data/entities/projectiles/deck/base_field.xml`, `berserk_field.xml`, `freeze_field.xml`, `electrocution_field.xml`, `projectile_*_field.xml`
- `data/scripts/projectiles/projectile_{transmutation,thunder,gravity}.lua`, `chain_shot_launch.lua`, `nolla.lua`, `curse_init.lua`
- `data/entities/misc/burn.xml`, `effect_apply_on_fire.xml`, `homing.xml`, `area_damage.xml`
- `Noita/tools_modding/lua_api_documentation.txt`, `component_documentation.txt` (GameAreaEffectComponent 981-990, ProjectileComponent ~2200-2280)

**EW** (`Noita/mods/quant.ew`):
- `init.lua` (shot replay 177-338)
- `files/resource/append/gun.lua`, `action_fix.lua`
- `files/core/net_handling.lua:176-248`
- `files/system/entity_sync_helper/entity_sync_helper.lua:125-142`
- `files/api/{ew_api,ew_crosscalls,extra_modules}.lua`
- `files/system/spell_patches/spell_patches.lua`
- upstream `ew_api_example/`, `docs/hooks.md`, `contributing.md`

**Prior art:**
- The Focus: `files/actions/modifier_field/*`, `files/utils/proj_cfg_utils.lua`, `virtual_tag.lua`
- Windows of Opportunity: `files/window_common.lua`
- Potent Potions: `init.lua:77-172`, `files/scripts/enemy_handler.lua`
- Apotheosis: `spell_worm_shoot.lua`, `entangled_alt_fire_fix.lua`

**Wiki:** [Circle of Fervour](https://noita.wiki.gg/wiki/Circle_of_Fervour), [Circle of Stillness](https://noita.wiki.gg/wiki/Circle_of_Stillness), [Projectile modifier](https://noita.wiki.gg/wiki/Projectile_modifier), [Modding: Tags System](https://noita.wiki.gg/wiki/Modding:_Tags_System)
