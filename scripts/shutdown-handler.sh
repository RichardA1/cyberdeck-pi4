#!/bin/bash
# CyberDeck — Shutdown HTTP handler
# Listens on port 8080 for shutdown requests from the web UI.
# Uses bash + netcat (no Python needed).
#
# Endpoints:
#   GET  /ping     → "pong" (health check)
#   POST /shutdown → initiates "shutdown -h now" after 3 second delay

LISTEN_PORT=8080

log() { logger -t "cyberdeck-shutdown" "$1"; echo "[shutdown-handler] $1"; }

log "Listening on port $LISTEN_PORT"

while true; do
    # Read the HTTP request via netcat
    RESPONSE=$(mktemp)

    # Use netcat to listen for one connection
    REQUEST=$(echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n" | \
        nc -l -p "$LISTEN_PORT" -q 1 2>/dev/null || \
        nc -l "$LISTEN_PORT" -q 1 2>/dev/null || \
        nc -l -p "$LISTEN_PORT" 2>/dev/null)

    rm -f "$RESPONSE"

    # Parse the request
    METHOD=$(echo "$REQUEST" | head -1 | awk '{print $1}')
    PATH_REQ=$(echo "$REQUEST" | head -1 | awk '{print $2}')

    if [ "$PATH_REQ" = "/ping" ]; then
        log "Health check ping"
        # Response already sent by netcat pipe above
        continue

    elif [ "$PATH_REQ" = "/shutdown" ] && [ "$METHOD" = "POST" ]; then
        log "SHUTDOWN REQUESTED via web UI"
        log "Shutting down in 3 seconds..."
        sleep 3
        shutdown -h now
        exit 0
    else
        log "Unknown request: $METHOD $PATH_REQ"
    fi
done
