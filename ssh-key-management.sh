#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
EFS_ID=$(aws efs describe-file-systems --query "FileSystems[?Name=='dev-fleet-persistent-storage'].FileSystemId" --output text --region ${AWS_REGION})
MOUNT_POINT="/mnt/efs"
KEY_DIR="${MOUNT_POINT}/ssh-keys"
AUTH_KEYS_PATH="${MOUNT_POINT}/home/developer/.ssh/authorized_keys"

# Check if EFS ID was found
if [ -z "$EFS_ID" ]; then
  echo "Error: Could not find EFS file system with name 'dev-fleet-persistent-storage'"
  exit 1
fi

# Create mount point if it doesn't exist
if [ ! -d "$MOUNT_POINT" ]; then
  echo "Creating mount point directory..."
  sudo mkdir -p "$MOUNT_POINT"
fi

# Check if EFS is already mounted
if mount | grep -q "$MOUNT_POINT"; then
  echo "EFS is already mounted at $MOUNT_POINT"
else
  # Install EFS utilities if needed
  if ! command -v amazon-efs-mount-helper &> /dev/null; then
    echo "Installing EFS utilities..."
    sudo yum install -y amazon-efs-utils || sudo apt-get install -y amazon-efs-utils
  fi

  # Mount EFS
  echo "Mounting EFS file system..."
  sudo mount -t efs -o tls $EFS_ID:/ $MOUNT_POINT
fi

# Create directories if they don't exist
echo "Creating necessary directories..."
sudo mkdir -p "$KEY_DIR"
sudo mkdir -p "$(dirname "$AUTH_KEYS_PATH")"
sudo touch "$AUTH_KEYS_PATH"

# Set proper permissions
sudo chmod 700 "$(dirname "$AUTH_KEYS_PATH")"
sudo chmod 600 "$AUTH_KEYS_PATH"

# Function to add a key
add_key() {
  local username=$1
  local key_file=$2
  
  if [ ! -f "$key_file" ]; then
    echo "Error: Key file $key_file does not exist"
    return 1
  fi
  
  # Copy key to key directory
  sudo cp "$key_file" "${KEY_DIR}/${username}.pub"
  
  # Add key to authorized_keys if not already there
  if ! sudo grep -q "$(cat "$key_file")" "$AUTH_KEYS_PATH"; then
    echo "Adding key for $username..."
    sudo bash -c "echo '# Key for $username' >> '$AUTH_KEYS_PATH'"
    sudo bash -c "cat '$key_file' >> '$AUTH_KEYS_PATH'"
    echo "Key added successfully"
  else
    echo "Key for $username already exists in authorized_keys"
  fi
}

# Function to remove a key
remove_key() {
  local username=$1
  
  if [ ! -f "${KEY_DIR}/${username}.pub" ]; then
    echo "Error: No key found for $username"
    return 1
  fi
  
  # Get the key content
  local key_content=$(cat "${KEY_DIR}/${username}.pub")
  
  # Remove the key and its comment from authorized_keys
  sudo sed -i "/# Key for $username/d" "$AUTH_KEYS_PATH"
  sudo sed -i "/$key_content/d" "$AUTH_KEYS_PATH"
  
  # Remove the key file
  sudo rm "${KEY_DIR}/${username}.pub"
  
  echo "Key for $username removed successfully"
}

# Function to list all keys
list_keys() {
  echo "Managed SSH keys:"
  for key_file in "$KEY_DIR"/*.pub; do
    if [ -f "$key_file" ]; then
      username=$(basename "$key_file" .pub)
      echo "- $username"
    fi
  done
}

# Parse command line arguments
case "$1" in
  add)
    if [ -z "$2" ] || [ -z "$3" ]; then
      echo "Usage: $0 add <username> <public-key-file>"
      exit 1
    fi
    add_key "$2" "$3"
    ;;
  remove)
    if [ -z "$2" ]; then
      echo "Usage: $0 remove <username>"
      exit 1
    fi
    remove_key "$2"
    ;;
  list)
    list_keys
    ;;
  *)
    echo "Usage: $0 {add|remove|list}"
    echo "  add <username> <public-key-file> - Add a user's SSH public key"
    echo "  remove <username> - Remove a user's SSH public key"
    echo "  list - List all managed SSH keys"
    exit 1
    ;;
esac

# Unmount EFS if we mounted it
if [ "$MOUNTED_BY_SCRIPT" = true ]; then
  echo "Unmounting EFS file system..."
  sudo umount "$MOUNT_POINT"
fi

echo "Done"
