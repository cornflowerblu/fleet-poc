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

# Deploy the CloudFormation stack
aws cloudformation deploy \
  --template-file dev-fleet-cloudformation.yaml \
  --stack-name dev-fleet-poc \
  --parameter-overrides \
    VpcId=$VPC_ID \
    PublicSubnets=$SUBNET_PARAM \
    DomainName=$DOMAIN_NAME \
    HostedZoneName=$HOSTED_ZONE \
    WildcardCertificateArn=$CERT_ARN \
  --capabilities CAPABILITY_NAMED_IAM

# Wait for stack to complete
echo "Waiting for stack creation to complete..."
aws cloudformation wait stack-create-complete --stack-name dev-fleet-poc || true

# Get ECR repository URI from stack outputs
ECR_REPO_URI=$(aws cloudformation describe-stacks \
  --stack-name dev-fleet-poc \
  --query "Stacks[0].Outputs[?OutputKey=='EcrRepositoryUri'].OutputValue" \
  --output text)

# Build and push container image
echo "Building and pushing container image to $ECR_REPO_URI..."
docker build -t $ECR_REPO_URI:base-dev-env .
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI
docker push $ECR_REPO_URI:base-dev-env

# Get connection information
CONNECTION_CMD=$(aws cloudformation describe-stacks \
  --stack-name dev-fleet-poc \
  --query "Stacks[0].Outputs[?OutputKey=='ConnectionCommand'].OutputValue" \
  --output text)

HTTPS_URL=$(aws cloudformation describe-stacks \
  --stack-name dev-fleet-poc \
  --query "Stacks[0].Outputs[?OutputKey=='HttpsUrl'].OutputValue" \
  --output text)

echo "Deployment complete!"
echo "To connect to your development environment: $CONNECTION_CMD"
echo "To check container health via HTTPS: $HTTPS_URL"
