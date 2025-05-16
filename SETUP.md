# Linux Development Fleet POC Setup Guide

This guide walks through setting up the initial Proof of Concept (POC) for the Linux Development Fleet project.

## Prerequisites

1. AWS CLI installed and configured with appropriate permissions
2. Docker installed locally
3. An AWS account with access to:
   - Amazon ECR
   - Amazon ECS/Fargate
   - Amazon EFS
   - Amazon ELB (Network Load Balancer)
   - IAM
   - CloudWatch Logs

## Setup Steps

### 1. Build and Push the Container Image

```bash
# Make the script executable
chmod +x build-and-push.sh

# Run the build script
./build-and-push.sh
```

This creates an ECR repository and pushes the base development container image to it.

### 2. Set Up Amazon EFS for Persistent Storage

```bash
# Make the script executable
chmod +x setup-efs.sh

# Run the EFS setup script
./setup-efs.sh
```

This creates an EFS file system and mount targets for persistent developer workspaces.

### 3. Create Required IAM Roles

```bash
# Make the script executable
chmod +x create-iam-roles.sh

# Run the IAM setup script
./create-iam-roles.sh
```

This creates the necessary IAM roles and policies for ECS tasks and EFS access.

### 4. Deploy the Environment

```bash
# Make the script executable
chmod +x deploy-environment.sh

# Run the deployment script
./deploy-environment.sh
```

This creates an ECS cluster and registers the task definition for development environments.

### 5. Set Up Load Balancer and ECS Service

```bash
# Make the script executable
chmod +x setup-load-balancer.sh

# Run the load balancer setup script
./setup-load-balancer.sh
```

This creates a Network Load Balancer for SSH access and an ECS service with the load balancer attached.

## Connecting to a Development Environment

Once the setup is complete, developers can connect to the environment using:

```bash
ssh -i ~/.ssh/your_key developer@<load-balancer-dns-name>
```

The load balancer DNS name is provided at the end of the load balancer setup script.

## Managing SSH Keys

Before developers can connect, you need to add their SSH public keys to the container:

1. Create a script to update the authorized_keys file in the EFS volume
2. Mount the EFS volume to an EC2 instance or use AWS Systems Manager to access it
3. Add developer SSH keys to the authorized_keys file in the EFS volume

## Next Steps

After this initial POC is working:

1. Create a web portal for environment management
2. Implement user authentication and authorization
3. Add more development tools to the container image
4. Set up monitoring and cost optimization
5. Implement automatic scaling and environment lifecycle management
6. Create a key management system for SSH access
