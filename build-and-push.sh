#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
ECR_REPOSITORY_NAME="dev-fleet-containers"
IMAGE_TAG="base-dev-env"

# Create ECR repository if it doesn't exist
echo "Checking if ECR repository exists..."
aws ecr describe-repositories --repository-names ${ECR_REPOSITORY_NAME} --region ${AWS_REGION} || \
    aws ecr create-repository --repository-name ${ECR_REPOSITORY_NAME} --region ${AWS_REGION}

# Get ECR login credentials
echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin \
    $(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com

# Build the Docker image
echo "Building Docker image..."
docker build -t ${ECR_REPOSITORY_NAME} .

# Tag the image for ECR with specific tag and latest
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}"
ECR_IMAGE_URI="${ECR_REPO_URI}:${IMAGE_TAG}"
ECR_LATEST_URI="${ECR_REPO_URI}:latest"

# Add timestamp to create a unique build ID
TIMESTAMP=$(date +%Y%m%d%H%M%S)
ECR_VERSIONED_URI="${ECR_REPO_URI}:${IMAGE_TAG}-${TIMESTAMP}"

echo "Tagging images..."
docker tag ${ECR_REPOSITORY_NAME} ${ECR_IMAGE_URI}
docker tag ${ECR_REPOSITORY_NAME} ${ECR_LATEST_URI}
docker tag ${ECR_REPOSITORY_NAME} ${ECR_VERSIONED_URI}

# Push the images to ECR
echo "Pushing images to ECR..."
docker push ${ECR_IMAGE_URI}
docker push ${ECR_LATEST_URI}
docker push ${ECR_VERSIONED_URI}

echo "Images successfully built and pushed:"
echo "- ${ECR_IMAGE_URI}"
echo "- ${ECR_LATEST_URI}"
echo "- ${ECR_VERSIONED_URI}"
