#!/bin/bash
# entrypoint.sh - Start SSH server and HTTP server for health checks

# Start the HTTP server for health checks
python3 -m http.server 80 --directory /var/www/html &

# Start SSH server in the foreground
/usr/sbin/sshd -D
