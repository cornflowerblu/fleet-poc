#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text --region ${AWS_REGION})
EFS_NAME="dev-fleet-persistent-storage"

# Create security group for EFS
echo "Creating security group for EFS..."
SG_ID=$(aws ec2 create-security-group \
    --group-name ${EFS_NAME}-sg \
    --description "Security group for Dev Fleet EFS" \
    --vpc-id ${VPC_ID} \
    --region ${AWS_REGION} \
    --output text \
    --query 'GroupId')

# Allow NFS traffic from within the VPC
echo "Configuring security group..."
aws ec2 authorize-security-group-ingress \
    --group-id ${SG_ID} \
    --protocol tcp \
    --port 2049 \
    --cidr $(aws ec2 describe-vpcs --vpc-ids ${VPC_ID} --query "Vpcs[0].CidrBlock" --output text) \
    --region ${AWS_REGION}

# Create EFS file system
echo "Creating EFS file system..."
EFS_ID=$(aws efs create-file-system \
    --creation-token ${EFS_NAME} \
    --encrypted \
    --performance-mode generalPurpose \
    --throughput-mode bursting \
    --tags Key=Name,Value=${EFS_NAME} \
    --region ${AWS_REGION} \
    --output text \
    --query 'FileSystemId')

echo "Waiting for EFS to become available..."
aws efs describe-file-systems --file-system-id ${EFS_ID} --region ${AWS_REGION} --query 'FileSystems[0].LifeCycleState' --output text
sleep 10

# Create mount targets in each subnet
echo "Creating mount targets..."
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[*].SubnetId" --output text --region ${AWS_REGION})

for SUBNET in ${SUBNETS}; do
    aws efs create-mount-target \
        --file-system-id ${EFS_ID} \
        --subnet-id ${SUBNET} \
        --security-groups ${SG_ID} \
        --region ${AWS_REGION}
    echo "Created mount target in subnet ${SUBNET}"
done

echo "EFS setup complete. File System ID: ${EFS_ID}"
echo "Security Group ID: ${SG_ID}"
