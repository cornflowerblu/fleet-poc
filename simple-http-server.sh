#!/bin/bash
# simple-http-server.sh - Simple HTTP server for health checks

# Install Python3 if not already installed
if ! command -v python3 &> /dev/null; then
  apt-get update && apt-get install -y python3
fi

# Create a simple index.html file
mkdir -p /var/www/html
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
  <title>Dev Container Health Check</title>
</head>
<body>
  <h1>Development Container is Healthy</h1>
  <p>Container ID: $(hostname)</p>
  <p>Timestamp: $(date)</p>
</body>
</html>
EOF

# Start a simple HTTP server in the background
cd /var/www/html
nohup python3 -m http.server 80 > /var/log/http-server.log 2>&1 &
echo "Simple HTTP server started on port 80"
