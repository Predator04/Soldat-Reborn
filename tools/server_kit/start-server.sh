#!/bin/sh
# Tracerfall dedicated server (Linux). Run it from anywhere:
#   ./start-server.sh                 # uses server.cfg next to this script
#   ./start-server.sh --port 7800     # flags win over server.cfg
# First run: copies server.cfg.example to server.cfg. Stop with Ctrl+C.
# Run it as a service instead: sudo ./install-service.sh (see HOSTING.md).
cd "$(dirname "$0")" || exit 1
if [ ! -f server.cfg ]; then
	cp server.cfg.example server.cfg
	echo "Created server.cfg from server.cfg.example - edit it to name your server."
fi
chmod +x TracerfallServer.x86_64 2>/dev/null
exec ./TracerfallServer.x86_64 -- --config "$(pwd)/server.cfg" "$@"
