#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"
KEY_NAME="dev-fleet-key"
S3_BUCKET="dev-fleet-keys"  # You'll need to create this bucket first
KEY_PATH="/tmp/${KEY_NAME}"

function generate_key() {
  echo "Generating new SSH key pair..."
  ssh-keygen -t ed25519 -f ${KEY_PATH} -N "" -C "dev-fleet-shared-key"
  
  echo "Key pair generated at ${KEY_PATH}"
  echo "Public key: ${KEY_PATH}.pub"
  echo "Private key: ${KEY_PATH}"
}

function upload_public_key() {
  if [ ! -f "${KEY_PATH}.pub" ]; then
    echo "Error: Public key not found at ${KEY_PATH}.pub"
    exit 1
  fi
  
  echo "Uploading public key to S3..."
  aws s3 cp ${KEY_PATH}.pub s3://${S3_BUCKET}/authorized_keys --region ${AWS_REGION}
  
  echo "Public key uploaded to S3"
}

function distribute_private_key() {
  if [ ! -f "${KEY_PATH}" ]; then
    echo "Error: Private key not found at ${KEY_PATH}"
    exit 1
  }
  
  echo "Uploading private key to S3 (for admin access only)..."
  aws s3 cp ${KEY_PATH} s3://${S3_BUCKET}/admin/${KEY_NAME} --region ${AWS_REGION}
  
  echo "Private key uploaded to S3"
  echo "IMPORTANT: Share this key securely with developers"
  echo "Download command for developers: aws s3 cp s3://${S3_BUCKET}/admin/${KEY_NAME} ~/.ssh/${KEY_NAME}"
  echo "Don't forget to set permissions: chmod 600 ~/.ssh/${KEY_NAME}"
}

function setup_bucket() {
  echo "Creating S3 bucket for key storage..."
  aws s3 mb s3://${S3_BUCKET} --region ${AWS_REGION} || true
  
  # Set bucket policy to restrict access
  aws s3api put-bucket-policy \
    --bucket ${S3_BUCKET} \
    --policy '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "AWS": "arn:aws:iam::ACCOUNT_ID:role/DevFleetAdminRole"
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
}

function print_usage() {
  echo "Usage: $0 [command]"
  echo "Commands:"
  echo "  setup       - Create S3 bucket for key storage"
  echo "  generate    - Generate a new SSH key pair"
  echo "  upload      - Upload public key to S3"
  echo "  distribute  - Upload private key to S3 for admin access"
  echo "  all         - Run all commands in sequence"
}

# Main execution
case "$1" in
  setup)
    setup_bucket
    ;;
  generate)
    generate_key
    ;;
  upload)
    upload_public_key
    ;;
  distribute)
    distribute_private_key
    ;;
  all)
    setup_bucket
    generate_key
    upload_public_key
    distribute_private_key
    ;;
  *)
    print_usage
    exit 1
    ;;
esac

echo "Done!"