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
   - Amazon Route 53
   - AWS Certificate Manager
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
# Create the ECS cluster first
aws ecs create-cluster --cluster-name dev-fleet-cluster --region us-east-1

# Make the script executable
chmod +x deploy-environment.sh

# Run the deployment script
./deploy-environment.sh
```

This creates an ECS cluster and registers the task definition for development environments. The script will:
1. Register the task definition for development environments
2. Automatically find a suitable subnet in your default VPC
3. Create or use an existing security group with SSH access
4. Provide a command to run a development environment
5. Offer to run a development environment task immediately

When prompted, you can choose to run a development environment task right away by typing 'y'.

### 5. Set Up Load Balancer and ECS Service

```bash
# Make the script executable
chmod +x setup-load-balancer.sh

# Run the load balancer setup script
./setup-load-balancer.sh
```

This creates a Network Load Balancer for SSH access and an ECS service with the load balancer attached.

### 6. Configure Custom Domain and TLS Certificate

```bash
# Make the script executable
chmod +x setup-custom-domain.sh

# Run the custom domain setup script
./setup-custom-domain.sh
```

This configures a custom domain (qdev.ngdegtm.com) for the load balancer and applies the existing wildcard certificate for secure SSH connections.

## Managing SSH Keys

Before developers can connect, you need to add their SSH public keys:

```bash
# Make the script executable
chmod +x ssh-key-management.sh

# Add a developer's SSH key
./ssh-key-management.sh add developer1 /path/to/developer1_key.pub

# List all managed keys
./ssh-key-management.sh list

# Remove a developer's SSH key
./ssh-key-management.sh remove developer1
```

## Connecting to a Development Environment

Once the setup is complete, developers can connect to the environment using:

```bash
ssh -i ~/.ssh/your_key developer@qdev.ngdegtm.com
```

## Security Features

- TLS encryption for SSH connections using the wildcard certificate
- Custom domain for easier access
- SSH key-based authentication only (no passwords)
- Network isolation with security groups
- Persistent storage with EFS

## Next Steps

After this initial POC is working:

1. Create a web portal for environment management
2. Implement user authentication and authorization
3. Add more development tools to the container image
4. Set up monitoring and cost optimization
5. Implement automatic scaling and environment lifecycle management
6. Create a key management system for SSH access
