#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
ECR_REPOSITORY_NAME="dev-fleet-containers"
IMAGE_TAG="base-dev-env"
DOMAIN_NAME="qdev.ngdegtm.com"
HOSTED_ZONE_NAME="ngdegtm.com"
ECS_CLUSTER_NAME="dev-fleet-cluster"
EFS_NAME="dev-fleet-persistent-storage"

# Check for wildcard certificate
echo "Checking for wildcard certificate..."
WILDCARD_CERT_ARN=$(aws acm list-certificates --region $AWS_REGION --query "CertificateSummaryList[?DomainName==\`*.$HOSTED_ZONE_NAME\`].CertificateArn" --output text)

if [ -n "$WILDCARD_CERT_ARN" ]; then
    echo "Found wildcard certificate: $WILDCARD_CERT_ARN"
    CERT_CONTEXT="--context wildcard_certificate_arn=$WILDCARD_CERT_ARN"
else
    echo "No wildcard certificate found. HTTPS features will be disabled."
    CERT_CONTEXT=""
fi

# Build and push container image
echo "Building and pushing container image..."
cd ..
./build-and-push.sh
cd cdk-implementation

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements.txt

# Bootstrap CDK (if needed)
echo "Bootstrapping CDK..."
cdk bootstrap

# Deploy the stack
echo "Deploying CDK stack..."
cdk deploy --require-approval never $CERT_CONTEXT \
    --context domain_name=$DOMAIN_NAME \
    --context hosted_zone_name=$HOSTED_ZONE_NAME \
    --context ecr_repository_name=$ECR_REPOSITORY_NAME \
    --context container_image_tag=$IMAGE_TAG \
    --context ecs_cluster_name=$ECS_CLUSTER_NAME \
    --context efs_name=$EFS_NAME

echo "Deployment complete!"
