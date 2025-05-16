#!/bin/bash
set -e

# Configuration - automatically detect values like the original scripts
AWS_REGION="us-east-1"  # Change to your preferred region
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region ${AWS_REGION})
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" --output text --region ${AWS_REGION})
DOMAIN_NAME="qdev.ngdegtm.com"
HOSTED_ZONE="ngdegtm.com"
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name ${HOSTED_ZONE} --query 'HostedZones[0].Id' --output text --region ${AWS_REGION})
HOSTED_ZONE_ID=${HOSTED_ZONE_ID#/hostedzone/}
STACK_NAME="dev-fleet-poc"
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Look for existing wildcard certificate
CERT_ARN=$(aws acm list-certificates --query "CertificateSummaryList[?DomainName=='*.ngdegtm.com'].CertificateArn" --output text --region ${AWS_REGION})

# Format subnet IDs for CloudFormation parameter (comma-separated)
SUBNET_PARAM=$(echo $SUBNET_IDS | tr ' ' ',')

echo "Deploying CloudFormation stack with the following parameters:"
echo "VPC ID: $VPC_ID"
echo "Subnet IDs: $SUBNET_PARAM"
echo "Domain Name: $DOMAIN_NAME"
echo "Hosted Zone: $HOSTED_ZONE (ID: $HOSTED_ZONE_ID)"
echo "Certificate ARN: $CERT_ARN"

# Check if stack already exists
STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} 2>&1 || echo "STACK_NOT_FOUND")

if [[ "$STACK_EXISTS" == *"STACK_NOT_FOUND"* ]]; then
  echo "Creating new CloudFormation stack: ${STACK_NAME}"
  
  # Deploy the CloudFormation stack
  aws cloudformation deploy \
    --template-file dev-fleet-cloudformation.yaml \
    --stack-name ${STACK_NAME} \
    --parameter-overrides \
      VpcId=$VPC_ID \
      PublicSubnets=$SUBNET_PARAM \
      DomainName=$DOMAIN_NAME \
      HostedZoneName=$HOSTED_ZONE \
      WildcardCertificateArn=$CERT_ARN \
      EcrRepositoryName="dev-fleet-containers-${TIMESTAMP}" \
      EcsClusterName="dev-fleet-cluster-${TIMESTAMP}" \
      EfsName="dev-fleet-persistent-storage-${TIMESTAMP}" \
    --capabilities CAPABILITY_NAMED_IAM
else
  echo "Stack ${STACK_NAME} already exists. Updating..."
  
  # Update the CloudFormation stack
  aws cloudformation update-stack \
    --stack-name ${STACK_NAME} \
    --template-body file://dev-fleet-cloudformation.yaml \
    --parameters \
      ParameterKey=VpcId,ParameterValue=$VPC_ID \
      ParameterKey=PublicSubnets,ParameterValue=$SUBNET_PARAM \
      ParameterKey=DomainName,ParameterValue=$DOMAIN_NAME \
      ParameterKey=HostedZoneName,ParameterValue=$HOSTED_ZONE \
      ParameterKey=WildcardCertificateArn,ParameterValue=$CERT_ARN \
      ParameterKey=EcrRepositoryName,ParameterValue="dev-fleet-containers-${TIMESTAMP}" \
      ParameterKey=EcsClusterName,ParameterValue="dev-fleet-cluster-${TIMESTAMP}" \
      ParameterKey=EfsName,ParameterValue="dev-fleet-persistent-storage-${TIMESTAMP}" \
    --capabilities CAPABILITY_NAMED_IAM
fi

# Wait for stack to complete
echo "Waiting for stack operation to complete..."
if [[ "$STACK_EXISTS" == *"STACK_NOT_FOUND"* ]]; then
  aws cloudformation wait stack-create-complete --stack-name ${STACK_NAME} || true
else
  aws cloudformation wait stack-update-complete --stack-name ${STACK_NAME} || true
fi

# Get ECR repository URI from stack outputs
ECR_REPO_URI=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" \
  --output text)

# Build and push container image
echo "Building and pushing container image to $ECR_REPO_URI..."
docker build -t $ECR_REPO_URI:base-dev-env .
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI
docker push $ECR_REPO_URI:base-dev-env

# Get connection information
CONNECTION_CMD=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query "Stacks[0].Outputs[?OutputKey=='ConnectionCommand'].OutputValue" \
  --output text)

HTTPS_URL=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query "Stacks[0].Outputs[?OutputKey=='HttpsUrl'].OutputValue" \
  --output text || echo "No HTTPS URL available")

echo "Deployment complete!"
echo "To connect to your development environment: $CONNECTION_CMD"
if [[ "$HTTPS_URL" != "No HTTPS URL available" ]]; then
  echo "To check container health via HTTPS: $HTTPS_URL"
fi
