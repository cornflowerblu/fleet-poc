#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
ECR_REPOSITORY_NAME="dev-fleet-containers"
IMAGE_TAG="base-dev-env:latest"

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
docker build -t ${ECR_REPOSITORY_NAME}:${IMAGE_TAG} .

# Tag the image for ECR
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}:${IMAGE_TAG}"
docker tag ${ECR_REPOSITORY_NAME}:${IMAGE_TAG} ${ECR_IMAGE_URI}

# Push the image to ECR
echo "Pushing image to ECR..."
docker push ${ECR_IMAGE_URI}

echo "Image successfully built and pushed to: ${ECR_IMAGE_URI}"
