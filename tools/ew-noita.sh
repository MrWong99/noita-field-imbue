#!/usr/bin/env bash
# Runs one Entangled Worlds peer's Noita in its own Proton prefix (started by tools/ew-2p.sh). The CLI proxy does not
# launch the game itself, so this sets NP_NOITA_ADDR to the matching proxy port. Peer B runs from a shadow game
# folder (symlinks) so the two instances write separate logger.txt files.
set -euo pipefail
ROLE="$1"
STEAM="$HOME/.local/share/Steam"
DEV="$HOME/noita-dev"
PROTON="${PROTON:-/usr/share/steam/compatibilitytools.d/proton-cachyos-native/proton}"
case "$ROLE" in
A) PREFIX="$DEV/prefix-probe" GAME="$STEAM/steamapps/common/Noita" NP_NOITA_ADDR=127.0.0.1:21251 ;;
B) PREFIX="$DEV/prefix-probe-b" GAME="$DEV/noita-b" NP_NOITA_ADDR=127.0.0.1:21252 ;;
*)
	echo "usage: $0 A|B" >&2
	exit 2
	;;
esac
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM" STEAM_COMPAT_DATA_PATH="$PREFIX" SteamAppId=881100 SteamGameId=881100 NP_NOITA_ADDR
cd "$GAME"
exec "$PROTON" run "$GAME/noita.exe" -no_logo_splashes -gamemode 0 -gamemode_mod_name -gamemode_mod_workshop_item_id 0 -save_slot 0 -windowed
