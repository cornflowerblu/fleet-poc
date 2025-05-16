#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"
S3_BUCKET="dev-fleet-keys-$(aws sts get-caller-identity --query Account --output text)"  # Unique bucket name with account ID
KEYS_DIR="/tmp/dev-fleet-keys"
AUTHORIZED_KEYS_FILE="${KEYS_DIR}/authorized_keys"

function check_bucket() {
  echo "Checking if S3 bucket exists..."
  if aws s3api head-bucket --bucket ${S3_BUCKET} --region ${AWS_REGION} 2>/dev/null; then
    echo "Bucket ${S3_BUCKET} exists"
    return 0
  else
    echo "Bucket ${S3_BUCKET} does not exist"
    return 1
  fi
}

function setup_bucket() {
  if check_bucket; then
    echo "Using existing bucket: ${S3_BUCKET}"
  else
    echo "Creating S3 bucket for key storage..."
    aws s3 mb s3://${S3_BUCKET} --region ${AWS_REGION}
    
    # Enable versioning for key history
    aws s3api put-bucket-versioning \
      --bucket ${S3_BUCKET} \
      --versioning-configuration Status=Enabled \
      --region ${AWS_REGION}
    
    # Set bucket policy to restrict access
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    aws s3api put-bucket-policy \
      --bucket ${S3_BUCKET} \
      --policy '{
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Principal": {
              "AWS": "arn:aws:iam::'${ACCOUNT_ID}':root"
            },
            "Action": "s3:*",
            "Resource": [
              "arn:aws:s3:::'${S3_BUCKET}'",
              "arn:aws:s3:::'${S3_BUCKET}'/*"
            ]
          }
        ]
      }' \
      --region ${AWS_REGION}
      
    echo "S3 bucket created and policy set"
  fi
  
  # Create directory structure
  mkdir -p ${KEYS_DIR}
  touch ${AUTHORIZED_KEYS_FILE}
  
  # Download existing authorized_keys if it exists
  aws s3 cp s3://${S3_BUCKET}/authorized_keys ${AUTHORIZED_KEYS_FILE} --region ${AWS_REGION} || true
}

function add_key() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Missing username or public key file"
    echo "Usage: $0 add <username> <public_key_file>"
    exit 1
  fi
  
  USERNAME=$1
  KEY_FILE=$2
  
  if [ ! -f "${KEY_FILE}" ]; then
    echo "Error: Public key file not found at ${KEY_FILE}"
    exit 1
  fi
  
  setup_bucket
  
  # Read the key content
  KEY_CONTENT=$(cat ${KEY_FILE})
  
  # Check if key already exists
  if grep -q "${KEY_CONTENT}" ${AUTHORIZED_KEYS_FILE}; then
    echo "Key already exists in authorized_keys"
  else
    # Add comment with username and date
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo "${KEY_CONTENT} # ${USERNAME} (added ${TIMESTAMP})" >> ${AUTHORIZED_KEYS_FILE}
    echo "Key added for user ${USERNAME}"
  fi
  
  # Upload updated authorized_keys file
  aws s3 cp ${AUTHORIZED_KEYS_FILE} s3://${S3_BUCKET}/authorized_keys --region ${AWS_REGION}
  
  # Also store individual key for reference
  aws s3 cp ${KEY_FILE} s3://${S3_BUCKET}/keys/${USERNAME}.pub --region ${AWS_REGION}
  
  echo "Key for ${USERNAME} has been added to authorized_keys and uploaded to S3"
  
  # Update ECS tasks with new keys
  update_ecs_tasks
}

function remove_key() {
  if [ -z "$1" ]; then
    echo "Error: Missing username"
    echo "Usage: $0 remove <username>"
    exit 1
  fi
  
  USERNAME=$1
  setup_bucket
  
  # Create a temporary file
  TEMP_FILE="${KEYS_DIR}/authorized_keys.tmp"
  
  # Filter out the user's key
  grep -v "# ${USERNAME} " ${AUTHORIZED_KEYS_FILE} > ${TEMP_FILE} || true
  
  # Check if any changes were made
  if cmp -s ${AUTHORIZED_KEYS_FILE} ${TEMP_FILE}; then
    echo "No keys found for user ${USERNAME}"
    rm ${TEMP_FILE}
    return
  fi
  
  # Replace the authorized_keys file
  mv ${TEMP_FILE} ${AUTHORIZED_KEYS_FILE}
  
  # Upload updated authorized_keys file
  aws s3 cp ${AUTHORIZED_KEYS_FILE} s3://${S3_BUCKET}/authorized_keys --region ${AWS_REGION}
  
  # Archive the removed key
  aws s3 mv s3://${S3_BUCKET}/keys/${USERNAME}.pub s3://${S3_BUCKET}/keys/archived/${USERNAME}.pub --region ${AWS_REGION} || true
  
  echo "Key for ${USERNAME} has been removed from authorized_keys"
  
  # Update ECS tasks with new keys
  update_ecs_tasks
}

function list_keys() {
  setup_bucket
  
  echo "Authorized SSH keys:"
  echo "-------------------"
  
  # Extract usernames and dates
  grep -o "# .* (added .*)" ${AUTHORIZED_KEYS_FILE} | while read -r line; do
    echo "${line}"
  done
  
  # If no keys found
  if [ ! -s ${AUTHORIZED_KEYS_FILE} ] || ! grep -q "#" ${AUTHORIZED_KEYS_FILE}; then
    echo "No keys found"
  fi
}

function update_ecs_tasks() {
  echo "Updating ECS tasks with new keys..."
  
  # Check if the ECS service exists
  CLUSTER_NAME="dev-fleet-cluster"
  SERVICE_NAME="dev-fleet-service"
  
  SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster ${CLUSTER_NAME} \
    --services ${SERVICE_NAME} \
    --query "services[?status=='ACTIVE'].serviceName" \
    --output text \
    --region ${AWS_REGION} 2>/dev/null || echo "")
  
  if [ -z "$SERVICE_EXISTS" ]; then
    echo "ECS service not found. Keys will be used for new tasks only."
    return
  fi
  
  # Force new deployment to update tasks with new keys
  aws ecs update-service \
    --cluster ${CLUSTER_NAME} \
    --service ${SERVICE_NAME} \
    --force-new-deployment \
    --region ${AWS_REGION} > /dev/null
  
  echo "ECS service updated. New tasks will use the updated keys."
}

function print_usage() {
  echo "Usage: $0 <command> [options]"
  echo "Commands:"
  echo "  setup                       - Create S3 bucket for key storage"
  echo "  add <username> <key_file>   - Add a user's public key"
  echo "  remove <username>           - Remove a user's public key"
  echo "  list                        - List all authorized keys"
  echo "  update                      - Update ECS tasks with current keys"
}

# Main execution
case "$1" in
  setup)
    setup_bucket
    ;;
  add)
    add_key "$2" "$3"
    ;;
  remove)
    remove_key "$2"
    ;;
  list)
    list_keys
    ;;
  update)
    update_ecs_tasks
    ;;
  *)
    print_usage
    exit 1
    ;;
esac

echo "Done!"