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

# Check if ECS cluster exists
echo "Checking ECS cluster..."
CLUSTER_EXISTS=$(aws ecs describe-clusters --clusters ${CLUSTER_NAME} --region ${AWS_REGION} --query "clusters[?clusterName=='${CLUSTER_NAME}'].clusterName" --output text)

if [ -z "$CLUSTER_EXISTS" ]; then
  echo "ECS cluster does not exist. Please create it first with:"
  echo "aws ecs create-cluster --cluster-name ${CLUSTER_NAME} --region ${AWS_REGION}"
  exit 1
else
  echo "ECS cluster ${CLUSTER_NAME} exists, continuing..."
fi

# Create CloudWatch log group
echo "Creating CloudWatch log group..."
aws logs create-log-group --log-group-name /ecs/dev-environment --region ${AWS_REGION} || true

# Register task definition
echo "Registering task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json file://ecs-task-definition.json --region ${AWS_REGION} --query 'taskDefinition.taskDefinitionArn' --output text)

# Get default VPC ID
echo "Getting default VPC..."
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region ${AWS_REGION})

if [ -z "$DEFAULT_VPC_ID" ]; then
  echo "No default VPC found. Please specify a VPC ID manually."
  exit 1
fi

# Get first available subnet in the default VPC
echo "Getting subnet in default VPC..."
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" --query "Subnets[0].SubnetId" --output text --region ${AWS_REGION})

if [ -z "$SUBNET_ID" ]; then
  echo "No subnet found in the default VPC. Please specify a subnet ID manually."
  exit 1
fi

# Get or create security group for dev environment
echo "Getting or creating security group..."
SG_NAME="dev-fleet-sg"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${DEFAULT_VPC_ID}" --query "SecurityGroups[0].GroupId" --output text --region ${AWS_REGION})

if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
  echo "Creating security group ${SG_NAME}..."
  SG_ID=$(aws ec2 create-security-group --group-name ${SG_NAME} --description "Security group for development fleet" --vpc-id ${DEFAULT_VPC_ID} --region ${AWS_REGION} --query 'GroupId' --output text)
  
  # Add SSH inbound rule
  aws ec2 authorize-security-group-ingress --group-id ${SG_ID} --protocol tcp --port 22 --cidr 0.0.0.0/0 --region ${AWS_REGION}
  echo "Created security group ${SG_ID} with SSH access"
else
  echo "Using existing security group ${SG_ID}"
fi

echo "Task definition registered: ${TASK_DEF_ARN}"
echo "To run a development environment, use:"
echo "aws ecs run-task --cluster ${CLUSTER_NAME} --task-definition ${TASK_DEF_ARN##*/} --network-configuration \"awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}\" --launch-type FARGATE --region ${AWS_REGION}"

# Offer to run the task now
read -p "Do you want to run a development environment now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Running development environment task..."
  aws ecs run-task --cluster ${CLUSTER_NAME} --task-definition ${TASK_DEF_ARN##*/} --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" --launch-type FARGATE --region ${AWS_REGION}
  echo "Task started. You can check its status in the AWS ECS console."
fi
