#!/bin/bash
# updated-health-check.sh - Simple HTTP health check for development containers

# Check if HTTP server is running on port 80
if curl -s http://localhost:80 > /dev/null; then
  echo "HTTP health check passed"
  exit 0
else
  echo "ERROR: HTTP health check failed"
  exit 1
fi
