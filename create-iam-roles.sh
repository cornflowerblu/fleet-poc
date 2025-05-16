#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region

# Create ECS task execution role if it doesn't exist
echo "Creating ECS task execution role..."
aws iam get-role --role-name ecsTaskExecutionRole 2>/dev/null || \
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'

# Attach the required policies to the task execution role
echo "Attaching policies to task execution role..."
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Create dev fleet task role
echo "Creating dev fleet task role..."
aws iam create-role \
  --role-name devFleetTaskRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'

# Create policy for EFS access
echo "Creating EFS access policy..."
aws iam create-policy \
  --policy-name devFleetEFSAccessPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ],
        "Resource": "*"
      }
    ]
  }'

# Attach EFS policy to task role
echo "Attaching EFS policy to task role..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam attach-role-policy \
  --role-name devFleetTaskRole \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/devFleetEFSAccessPolicy

echo "IAM roles and policies created successfully"
