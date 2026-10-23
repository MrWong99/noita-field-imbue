#!/usr/bin/env bash
# Two-peer Entangled Worlds run of the field_imbue probe (docs/RESEARCH.md §6 test 6) on this machine.
# Peer A = host (proxy on --host 5123, Noita at 127.0.0.1:21251), peer B = client (Steam disabled, 21252).
# Each peer gets its own Proton prefix, its own copy of the proxy binary/settings/state, and B a shadow game
# folder, so nothing is written to your normal prefix, saves, noita-proxy-linux folder or proxy.ron.
# Logs: Noita/logger.txt (A), ~/noita-dev/noita-b/logger.txt (B), ~/noita-dev/proxy-{a,b}/ for the proxies.
set -euo pipefail
STEAM="$HOME/.local/share/Steam"
NOITA="$STEAM/steamapps/common/Noita"
PROXY_SRC="${PROXY_SRC:-$HOME/Desktop/Games/noita-proxy-linux}"
PROTON="${PROTON:-/usr/share/steam/compatibilitytools.d/proton-cachyos-native/proton}"
DEV="$HOME/noita-dev"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
USER_SAVE="$STEAM/steamapps/compatdata/881100/pfx/drive_c/users/steamuser/AppData/LocalLow/Nolla_Games_Noita"
SAVE_REL="pfx/drive_c/users/steamuser/AppData/LocalLow/Nolla_Games_Noita"

ln -sfn "$REPO/probe" "$NOITA/mods/field_imbue_probe"
ln -sfn "$REPO" "$NOITA/mods/field_imbue"
echo ew >"$REPO/probe/suite.txt"

# shadow game folder for B: everything symlinked except logger.txt
mkdir -p "$DEV/noita-b"
for f in "$NOITA"/*; do
	n="$(basename "$f")"
	[ "$n" = logger.txt ] && continue
	ln -sfn "$f" "$DEV/noita-b/$n"
done

prepare_prefix() { # $1 = prefix dir
	local prefix="$1" base
	mkdir -p "$prefix"
	if [ ! -d "$prefix/pfx" ]; then
		STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM" STEAM_COMPAT_DATA_PATH="$prefix" SteamAppId=881100 SteamGameId=881100 \
			"$PROTON" run cmd.exe /c exit || true
	fi
	base="$prefix/$SAVE_REL"
	case "$base" in
	*/noita-dev/prefix-probe*) if [ -e "$base/save00" ]; then gio trash "$base/save00"; fi ;; # no "crashed? restore" dialog
	esac
	mkdir -p "$base/save00" "$base/save_shared"
	cp "$USER_SAVE/save_shared/config.xml" "$base/save_shared/config.xml" # skips first-run dialog, unsafe mods on
	sed -i -e 's/application_pause_when_unfocused="1"/application_pause_when_unfocused="0"/' -e 's/vsync="[0-9]"/vsync="0"/' \
		"$base/save_shared/config.xml"
	cat >"$base/save00/mod_config.xml" <<'XML'
<Mods>
  <Mod enabled="1" name="field_imbue" settings_fold_open="0" workshop_item_id="0" >
  </Mod>
  <Mod enabled="1" name="field_imbue_probe" settings_fold_open="0" workshop_item_id="0" >
  </Mod>
  <Mod enabled="1" name="quant.ew" settings_fold_open="0" workshop_item_id="0" >
  </Mod>
</Mods>
XML
}

prepare_proxy() { # $1 = name, $2 = noita exe, $3 = save dir
	local dir="$DEV/proxy-$1"
	mkdir -p "$dir"
	cp "$PROXY_SRC/noita_proxy.x86_64" "$PROXY_SRC/libsteam_api.so" "$dir/"
	sed -e "s|nickname:None|nickname:Some(\"probe-$1\")|" \
		-e "s|start_game_automatically:false|start_game_automatically:true|" \
		-e "s|noita_exe:Some(\"[^\"]*\")|noita_exe:Some(\"$2\")|" \
		-e "s|noita_save:Some(\"[^\"]*\")|noita_save:Some(\"$3\")|" \
		"$HOME/.config/entangledworlds/proxy.ron" >"$dir/proxy.ron"
}

prepare_prefix "$DEV/prefix-probe"
prepare_prefix "$DEV/prefix-probe-b"
prepare_proxy a "$NOITA/noita.exe" "$DEV/prefix-probe/$SAVE_REL"
prepare_proxy b "$DEV/noita-b/noita.exe" "$DEV/prefix-probe-b/$SAVE_REL"

# Sockets of a previous (killed) run can linger for a while: wait until the proxy ports are free.
for _ in $(seq 1 60); do
	ss -tanu | grep -qE ':(5123|21251|21252)\b' || break
	sleep 1
done

# CLI proxies are headless and only do networking (noita_proxy/src/cli.rs); with Steam disabled they need
# --exe-path. The games are started below, each pointed at its proxy through NP_NOITA_ADDR.
export NP_DISABLE_STEAM=1 NP_SKIP_MOD_CHECK=1 NP_ALLOW_REUSE_ADDR=1
(cd "$DEV/proxy-a" && NP_NOITA_ADDR=127.0.0.1:21251 exec ./noita_proxy.x86_64 \
	--host 5123 --exe-path "$NOITA/noita.exe" \
	--settings-path "$DEV/proxy-a/proxy.ron" --save-state-path "$DEV/proxy-a/state" >"$DEV/proxy-a/stdout.log" 2>&1) &
PROXY_A=$!
sleep 3
(cd "$DEV/proxy-b" && NP_NOITA_ADDR=127.0.0.1:21252 exec ./noita_proxy.x86_64 \
	--lobby 127.0.0.1:5123 --exe-path "$DEV/noita-b/noita.exe" \
	--settings-path "$DEV/proxy-b/proxy.ron" --save-state-path "$DEV/proxy-b/state" >"$DEV/proxy-b/stdout.log" 2>&1) &
PROXY_B=$!
sleep 3
for pid in "$PROXY_A" "$PROXY_B"; do
	if ! kill -0 "$pid" 2>/dev/null; then
		echo "a proxy died on startup, see $DEV/proxy-{a,b}/ew_log.txt" >&2
		kill "$PROXY_A" "$PROXY_B" 2>/dev/null || true
		exit 1
	fi
done
"$REPO/tools/ew-noita.sh" A >"$DEV/noita-a.out" 2>&1 &
sleep 20 # let A finish loading so it is the one that starts the run
"$REPO/tools/ew-noita.sh" B >"$DEV/noita-b.out" 2>&1 &
wait
