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
                   ┌─────────────────────────────┐
                   │                             │
                   │  Network Load Balancer      │
                   │  (TLS + Custom Domain)      │
                   │  qdev.ngdegtm.com           │
                   │                             │
                   └─────────────────┬───────────┘
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

## Usage

See the `SETUP.md` file for detailed setup instructions.

## Next Steps

After this initial POC, the following steps will be implemented:

1. Create a web portal for environment management
2. Implement user authentication and authorization
3. Add more development tools to the container image
4. Set up monitoring and cost optimization
5. Implement automatic scaling and environment lifecycle management
