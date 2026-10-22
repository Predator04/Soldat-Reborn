#!/bin/sh
# Update this Tracerfall server to the latest GitHub release (only if newer;
# the download must carry the game's release signature). Stop the server
# first, or restart it afterwards:  sudo systemctl restart tracerfall-server
#   ./update-server.sh            ./update-server.sh --check
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
	echo "update-server needs Python 3 (e.g. sudo apt install python3)." >&2
	exit 1
fi
exec python3 update_server.py "$@"
