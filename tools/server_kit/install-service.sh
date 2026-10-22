#!/bin/sh
# Install the Tracerfall server as a systemd service (starts at boot, restarts
# if it stops). Run with sudo from the server folder:
#   sudo ./install-service.sh                 # runs as the user who called sudo
#   sudo ./install-service.sh --user tf       # ... as another user
#   sudo ./install-service.sh --auto-update   # also update before every start
#   sudo ./install-service.sh --uninstall
# Afterwards: systemctl status tracerfall-server / journalctl -u tracerfall-server -f
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
UNIT=/etc/systemd/system/tracerfall-server.service
RUNAS=${SUDO_USER:-$(id -un)}
UPDATE="#"
while [ $# -gt 0 ]; do
	case "$1" in
		--user) RUNAS="$2"; shift;;
		--auto-update) UPDATE="";;
		--uninstall)
			systemctl disable --now tracerfall-server 2>/dev/null || true
			rm -f "$UNIT"
			systemctl daemon-reload
			echo "Removed tracerfall-server.service."
			exit 0;;
		*) echo "unknown option: $1" >&2; exit 2;;
	esac
	shift
done
if [ "$(id -u)" != 0 ]; then
	echo "Run with sudo: sudo $0 $*" >&2
	exit 1
fi
[ -f "$DIR/server.cfg" ] || cp "$DIR/server.cfg.example" "$DIR/server.cfg"
chown "$RUNAS" "$DIR/server.cfg" 2>/dev/null || true
chmod +x "$DIR/TracerfallServer.x86_64" "$DIR"/*.sh "$DIR"/*.py 2>/dev/null || true
sed -e "s|@DIR@|$DIR|g" -e "s|@USER@|$RUNAS|g" -e "s|^#@UPDATE@|$UPDATE|" "$DIR/tracerfall-server.service" > "$UNIT"
systemctl daemon-reload
systemctl enable --now tracerfall-server
echo "Installed $UNIT (user $RUNAS). It is running now and starts at boot."
echo "Log: journalctl -u tracerfall-server -f    Stop: sudo systemctl stop tracerfall-server"
echo "Open UDP ports 7777 and 7778 (or your port and port + 1) in your firewall."
