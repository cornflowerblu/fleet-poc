# Development Fleet POC - Container Image Creation

This directory contains the initial Proof of Concept (POC) for the Linux Development Fleet project, focusing on container image creation and infrastructure setup.

## Overview

This POC implements the first stages of the implementation plan:
1. Creating a base development container image with necessary tools and SSH access capabilities
2. Setting up the infrastructure for a centrally managed Linux development environment fleet
3. Configuring load balancer access for developers with a custom domain and TLS certificate

## Components

### Container Image
- `Dockerfile`: Defines the base development container image with:
  - Ubuntu 22.04 base
  - Common development tools
  - SSH server for direct access
  - Non-root user with sudo privileges

- `build-and-push.sh`: Script to build the container image and push it to Amazon ECR

### Infrastructure
- `dev-fleet-cloudformation.yaml`: Complete CloudFormation template that provisions all required infrastructure
- `deploy-cloudformation.sh`: Script to deploy the CloudFormation stack with automatic parameter detection
- Individual scripts (used for manual deployment):
  - `setup-efs.sh`: Creates an EFS file system for persistent developer workspaces
  - `create-iam-roles.sh`: Sets up necessary IAM roles and policies
  - `ecs-task-definition.json`: Defines the ECS task for development environments
  - `deploy-environment.sh`: Deploys the ECS cluster and task definition
  - `setup-load-balancer.sh`: Creates a Network Load Balancer for SSH access
  - `setup-custom-domain.sh`: Configures a custom domain and TLS certificate

### Access Management
- `ssh-key-management.sh`: Tool for managing developer SSH keys
- `connect-to-container.sh`: Helper script for connecting to containers directly (for admin use)

## Architecture

```
                                 Users
                                   │
                                   ▼
┌─────────────────────────────┐   ┌─────────────────────────────┐
│                             │   │                             │
│  Network Load Balancer      │   │  Application Load Balancer  │
│  (TLS + Custom Domain)      │   │  (HTTPS + HTTP Redirect)    │
│  qdev.ngdegtm.com           │   │  web-qdev.ngdegtm.com       │
│  (SSH Access)               │   │  (Health Checks)            │
│                             │   │                             │
└─────────────────┬───────────┘   └─────────────────┬───────────┘
                  │                                 │
                  └────────────────┬────────────────┘
                                   │
                                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│                 │  │                 │  │                 │
│  ECS Fargate    │  │  ECS Fargate    │  │  ECS Fargate    │
│  Container      │  │  Container      │  │  Container      │
│                 │  │                 │  │                 │
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                    │
         └──────────┬─────────┴──────────┬─────────┘
                    │                    │
                    ▼                    ▼
         ┌─────────────────┐   ┌─────────────────┐
         │                 │   │                 │
         │  Amazon EFS     │   │  Amazon ECR     │
         │  (Persistent    │   │  (Container     │
         │   Storage)      │   │   Registry)     │
         │                 │   │                 │
         └─────────────────┘   └─────────────────┘
```

## Security Features

- TLS encryption for SSH connections using wildcard certificate
- Custom domain for easier access (qdev.ngdegtm.com)
- SSH password authentication is disabled
- Root login is disabled
- Key-based authentication only
- Persistent storage with EFS
- Network isolation with security groups
- Load balancer for controlled access
- HTTPS for web access with HTTP to HTTPS redirection
- Automatic health checks for container status

## Usage

### Deploying with CloudFormation (Recommended)

The easiest way to deploy the entire infrastructure is using the CloudFormation template:

```bash
# Make the deployment script executable
chmod +x deploy-cloudformation.sh

# Run the deployment script
./deploy-cloudformation.sh
```

This script will:
1. Automatically detect your VPC, subnets, and other parameters
2. Check for an existing wildcard certificate
3. Deploy the CloudFormation stack with all required resources
4. Build and push the container image to ECR
5. Output connection information when complete

### Accessing the Development Environment

After deployment, you can access your development environment using:

- **SSH Access**: `ssh -i ~/.ssh/your_key developer@qdev.ngdegtm.com`
- **Health Check**: `https://web-qdev.ngdegtm.com/` (requires wildcard certificate)

The health check endpoint automatically redirects HTTP requests to HTTPS for security.

### Manual Deployment

If you prefer to deploy components individually, see the `SETUP.md` file for detailed setup instructions.

## Health Checking

The development containers expose:
- Port 22 for SSH access
- Port 80 for HTTP health checks

The CloudFormation template sets up:
- Network Load Balancer for SSH access on port 22
- Application Load Balancer for health checks with:
  - HTTPS access on port 443 (web-qdev.ngdegtm.com)
  - Automatic redirection from HTTP to HTTPS
  - Health check endpoint that verifies container status

## Next Steps

After this initial POC, the following steps will be implemented:

1. Create a web portal for environment management
2. Implement user authentication and authorization
3. Add more development tools to the container image
4. Set up monitoring and cost optimization
5. Implement automatic scaling and environment lifecycle management
