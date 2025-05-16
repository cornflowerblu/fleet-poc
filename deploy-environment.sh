#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
CLUSTER_NAME="dev-fleet-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Update task definition with account ID and region
echo "Preparing task definition..."
sed -i "s/ACCOUNT_ID/${ACCOUNT_ID}/g" ecs-task-definition.json
sed -i "s/REGION/${AWS_REGION}/g" ecs-task-definition.json

# Get EFS ID and update task definition
EFS_ID=$(aws efs describe-file-systems --query "FileSystems[?Name=='dev-fleet-persistent-storage'].FileSystemId" --output text --region ${AWS_REGION})
sed -i "s/EFS_ID/${EFS_ID}/g" ecs-task-definition.json

# Create ECS cluster if it doesn't exist
echo "Creating ECS cluster..."
aws ecs describe-clusters --clusters ${CLUSTER_NAME} --region ${AWS_REGION} | grep ${CLUSTER_NAME} || \
aws ecs create-cluster --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION}

# Create CloudWatch log group
echo "Creating CloudWatch log group..."
aws logs create-log-group --log-group-name /ecs/dev-environment --region ${AWS_REGION} || true

# Register task definition
echo "Registering task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json --region ${AWS_REGION} --query 'taskDefinition.taskDefinitionArn' --output text)

echo "Task definition registered: ${TASK_DEF_ARN}"
echo "To run a development environment, use:"
echo "aws ecs run-task --cluster ${CLUSTER_NAME} --task-definition ${TASK_DEF_ARN##*/} --network-configuration \"awsvpcConfiguration={subnets=[subnet-id],securityGroups=[sg-id],assignPublicIp=ENABLED}\" --launch-type FARGATE --region ${AWS_REGION}"
