#!/bin/sh
# Build the Steam Workshop client helper.
#
# Requires gcc and a Steam client install - libsteam_api.so ships with Steam
# itself, so no Steamworks SDK download is needed.
#
# The helper attaches to the *running* Steam client's session, so it must be
# built on (or for) a machine that has the client installed.
set -e

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STEAM_LIBDIR="${STEAM_LIBDIR:-$HOME/.local/share/Steam/steamrt64}"

if [ ! -f "$STEAM_LIBDIR/libsteam_api.so" ]; then
    echo "libsteam_api.so not found in $STEAM_LIBDIR" >&2
    echo "set STEAM_LIBDIR to your Steam client's steamrt64 directory" >&2
    exit 1
fi

printf '431960\n' > "$DIR/steam_appid.txt"

gcc -O2 -o "$DIR/dcent-steam-workshop" "$DIR/dcent-steam-workshop.c" \
    -L"$STEAM_LIBDIR" -lsteam_api -Wl,-rpath,"$STEAM_LIBDIR"

echo "built $DIR/dcent-steam-workshop"
