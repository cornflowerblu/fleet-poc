#!/bin/bash
# health-check-script.sh - Comprehensive health check for development containers

# Check if SSH service is running
if ! service ssh status > /dev/null 2>&1; then
  echo "ERROR: SSH service is not running"
  exit 1
fi

# Check if SSH is listening on port 22
if ! netstat -tulpn | grep -q ':22 '; then
  echo "ERROR: SSH is not listening on port 22"
  exit 1
fi

# Check if sshd process is running
if ! ps aux | grep -v grep | grep -q sshd; then
  echo "ERROR: sshd process is not running"
  exit 1
fi

# Check available disk space (fail if less than 10% free)
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_USAGE" -gt 90 ]; then
  echo "ERROR: Low disk space: ${DISK_USAGE}% used"
  exit 1
fi

# Check memory usage (fail if less than 10% free)
MEM_AVAILABLE=$(free | grep Mem | awk '{print $7/$2 * 100.0}')
MEM_AVAILABLE_INT=${MEM_AVAILABLE%.*}
if [ "$MEM_AVAILABLE_INT" -lt 10 ]; then
  echo "ERROR: Low memory: only ${MEM_AVAILABLE_INT}% available"
  exit 1
fi

# Check if we can access the workspace directory
if [ ! -d "/home/developer/workspace" ] || [ ! -w "/home/developer/workspace" ]; then
  echo "ERROR: Workspace directory is not accessible or writable"
  exit 1
fi

# All checks passed
echo "All health checks passed"
exit 0
