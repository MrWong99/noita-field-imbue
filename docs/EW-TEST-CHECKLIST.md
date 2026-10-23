# field_imbue: two-player Entangled Worlds checklist

**A** = the host, who casts the fields. **B** = the second player.

## Setup (both players)
1. Both players install the same version: subscribe on the Steam Workshop, or extract the release zip from GitHub Releases into `Noita/mods/` (so it becomes `Noita/mods/field_imbue/`).
2. Mods menu:
   - enable **Field Imbue** and **Cheatgui** (A at least);
   - keep **quant.ew** enabled;
   - never enable `field_imbue_probe` (test-only);
   - Field Imbue's **mod settings** must match for both players (they apply from the next new run).
3. Start EW as usual (proxy, lobby, New Game). Leave EW friendly fire **off** for the first pass.

## Wands (A builds these with Cheatgui → spells; use non-shuffle wands)
| Wand | Cards, left to right | Mana per cast |
|---|---|---|
| **W1 freeze field** | Field resonance → Freeze charge → Circle of fervour | 65 |
| **W2 fire field** | Field resonance → Burning trail → Circle of fervour | 60 |
| **W3 control** | Freeze charge → Circle of fervour (no Field resonance) | 40 |
| **Bolt** | any wand with Spark bolt | – |

B only needs a Spark bolt wand; the starting wand is fine. A field lasts about 2 minutes. Circle of fervour also berserks enemies inside it, which is expected.

## Steps. Each step: both players report what they saw.
| # | Do | Expected on **both** screens |
|---|---|---|
| 1 | A casts W1 next to a few enemies (Mines entrance). | The same circle in the same spot. Enemies inside freeze, thaw, and re-freeze about once a second while they stay inside. |
| 2 | A fires Spark bolts **through** the W1 circle at an enemy beyond it. | The bolt gets frosty sparkles after crossing; the enemy it hits freezes. |
| 3 | B fires Spark bolts through **A's** circle. | Same as step 2, now for B's bolt (cross-peer imbue). |
| 4 | B stands inside A's W1 circle for ~10 s. A stands inside it too. | **Nobody freezes** (friendly fire off). |
| 5 | A casts W3 (control) and repeats steps 1–2. | Enemies freeze once when they enter, then stay thawed. Bolts through it are plain. |
| 6 | A casts W2 near enemies; both shoot through it. | Enemies inside catch fire within a few seconds (all of them, eventually). Bolts get a fire trail and set the target alight about half the time. |
| 7 | Watch an enemy projectile fly through a W1/W2 circle (optional). | Not imbued by default. With the setting **Imbue enemy projectiles** on, it is. |
| 8 | Note when the circles disappear. | At the same moment for both players. |

## 0.2.0: any modifier
- Try other modifiers in place of Freeze charge or Burning trail: Homing, Heavy shot, Explosive projectile, Water to poison and so on.
- Each projectile flying through gets the modifier. The circle itself shows no fire or snow at its centre and doesn't move.
- Nuke orbit and Chaos magic only work with the setting **Allow Nuke orbit and Chaos magic** on.

## Report back
- **Any mismatch between screens.** For example: frozen for A but not for B, a bolt imbued on only one screen, a circle that vanishes earlier for one player, or a fire that spreads differently.
- **Red error text or a crash.** If anything looks off, send both players' `Noita/logger.txt` (with EW's default settings it contains the Lua messages).
- **Feel.** Is it fun? Too strong? Should enemy shots be imbued?
