#!/usr/bin/env bash
# Runs the field_imbue probe mod (probe/) in an isolated Proton prefix: own saves, own mod list (only the probe enabled).
# Your normal Noita prefix, saves and mod_config.xml are not touched. Note: Noita/logger.txt in the game folder is shared,
# so don't run this while another Noita instance is open.
set -euo pipefail
STEAM="$HOME/.local/share/Steam"
NOITA="$STEAM/steamapps/common/Noita"
PROTON="${PROTON:-/usr/share/steam/compatibilitytools.d/proton-cachyos-native/proton}"
PREFIX="${PREFIX:-$HOME/noita-dev/prefix-probe}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM" STEAM_COMPAT_DATA_PATH="$PREFIX" SteamAppId=881100 SteamGameId=881100

SUITE="${1:-research}" # research = §6 probes, prototype = mod checks, sweep [IDS] = every modifier (or only IDS)
mkdir -p "$PREFIX"
ln -sfn "$REPO/probe" "$NOITA/mods/field_imbue_probe"
ln -sfn "$REPO" "$NOITA/mods/field_imbue"
# line 2: sweep only these ids (comma-separated); line 3: field_imbue settings to force ("enemy", "destructive")
printf '%s\n%s\n%s\n' "$SUITE" "${2:-}" "${3:-}" >"$REPO/probe/suite.txt"
if [ ! -d "$PREFIX/pfx" ]; then
	"$PROTON" run cmd.exe /c exit || true
fi
SAVE="$PREFIX/pfx/drive_c/users/steamuser/AppData/LocalLow/Nolla_Games_Noita/save00"
# Start every probe run from an empty save00. Probe instances are killed, not quit, so a leftover autosave
# would otherwise trigger the "Looks like the game crashed? Restore" dialog. Only ever touches the probe prefix.
case "$SAVE" in
*/noita-dev/prefix-probe/*) if [ -e "$SAVE" ]; then gio trash "$SAVE"; fi ;;
esac
mkdir -p "$SAVE"
cat >"$SAVE/mod_config.xml" <<'XML'
<Mods>
  <Mod enabled="1" name="field_imbue" settings_fold_open="0" workshop_item_id="0" >
  </Mod>
  <Mod enabled="1" name="field_imbue_probe" settings_fold_open="0" workshop_item_id="0" >
  </Mod>
</Mods>
XML
# Copy your config once so a fresh profile skips the first-run release-notes dialog (it blocks -gamemode 0).
USER_CFG="$STEAM/steamapps/compatdata/881100/pfx/drive_c/users/steamuser/AppData/LocalLow/Nolla_Games_Noita/save_shared/config.xml"
if [ -f "$USER_CFG" ] && [ ! -f "$SAVE/../save_shared/config.xml" ]; then
	mkdir -p "$SAVE/../save_shared"
	cp "$USER_CFG" "$SAVE/../save_shared/config.xml"
fi
# keep simulating at full speed while the window is in the background (probe copy only): no pause on focus loss, and
# no vsync (a window hidden behind a fullscreen game gets no vblank and would crawl)
sed -i -e 's/application_pause_when_unfocused="1"/application_pause_when_unfocused="0"/' -e 's/vsync="[0-9]"/vsync="0"/' \
	"$SAVE/../save_shared/config.xml"
cd "$NOITA"
exec "$PROTON" run "$NOITA/noita.exe" -no_logo_splashes -gamemode 0 -gamemode_mod_name -gamemode_mod_workshop_item_id 0 -save_slot 0 -windowed
