# Development Fleet POC - CDK Implementation

This directory contains the AWS CDK implementation of the Linux Development Fleet project, focusing on container image creation and infrastructure setup.

## Overview

This CDK implementation replaces the CloudFormation template with a more robust, programmatic approach that:
1. Handles existing resources gracefully
2. Provides better error handling
3. Uses high-level constructs for easier maintenance
4. Supports conditional resource creation

## Prerequisites

- Python 3.6 or later
- AWS CDK v2
- AWS CLI configured with appropriate permissions
- Docker (for building container images)
- Boto3 (for resource lookup)

## Installation

```bash
# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap
```

## Usage

### Deploying the Stack

```bash
# Deploy the stack with default parameters
cdk deploy

# Deploy with a specific wildcard certificate ARN
cdk deploy --context wildcard_certificate_arn=arn:aws:acm:region:account:certificate/certificate-id
```

### Building and Pushing the Container Image

The container image needs to be built and pushed to ECR before deploying the CDK stack. You can use the existing `build-and-push.sh` script from the parent directory:

```bash
cd ..
./build-and-push.sh
```

### Accessing the Development Environment

After deployment, you can access your development environment using:

- **SSH Access**: `ssh -i ~/.ssh/your_key developer@qdev.ngdegtm.com`
- **Health Check**: `https://web-qdev.ngdegtm.com/` (requires wildcard certificate)

## Architecture

The CDK stack creates the following resources:

1. **ECR Repository** - For storing container images
2. **IAM Roles** - For ECS task execution and EFS access
3. **EFS File System** - For persistent developer workspaces
4. **ECS Cluster** - For running development containers
5. **Network Load Balancer** - For SSH access
6. **Application Load Balancer** - For HTTPS health checks (if certificate exists)
7. **Route53 Records** - For custom domain access

## Key Features

- **Idempotent Deployment**: Resources are checked for existence before creation using boto3 lookups
- **Conditional Resources**: HTTPS components are only created if a certificate exists
- **Resource Retention**: Critical resources like EFS and ECR repository are retained on stack deletion
- **Security Best Practices**: TLS encryption, key-based authentication, network isolation
- **No Fixed Resource Names**: Uses logical IDs to avoid name conflicts with existing resources

## Customization

You can customize the deployment by modifying the parameters in `app.py` or by providing context values during deployment:

```bash
cdk deploy --context domain_name=custom.example.com --context hosted_zone_name=example.com
```

## Troubleshooting

If you encounter issues with resource creation:

1. Check the logs for information about which resources are being reused vs. created
2. Verify that the boto3 resource lookup script ran successfully
3. For IAM role issues, you may need to manually delete conflicting roles
4. For load balancer name conflicts, the CDK will automatically generate unique names
