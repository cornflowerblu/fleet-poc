#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
CLUSTER_NAME="dev-fleet-cluster"

# Check if task ID is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <task-id>"
  echo "Example: $0 1a2b3c4d5e6f7g8h9i0j"
  exit 1
fi

TASK_ID=$1

# Get the public IP of the task
echo "Getting task details..."
PUBLIC_IP=$(aws ecs describe-tasks \
  --cluster ${CLUSTER_NAME} \
  --tasks ${TASK_ID} \
  --region ${AWS_REGION} \
  --query 'tasks[0].attachments[0].details[?name==`publicIp`].value' \
  --output text)

if [ -z "$PUBLIC_IP" ]; then
  echo "Could not find public IP for task ${TASK_ID}"
  exit 1
fi

echo "Found public IP: ${PUBLIC_IP}"
echo "To connect to the development environment:"
echo "ssh -i ~/.ssh/your_key developer@${PUBLIC_IP}"

# Alternatively, use ECS Exec for direct access
echo ""
echo "Or use ECS Exec for direct access:"
echo "aws ecs execute-command --cluster ${CLUSTER_NAME} --task ${TASK_ID} --container dev-container --command \"/bin/bash\" --interactive --region ${AWS_REGION}"
