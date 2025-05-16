#!/usr/bin/env python3
import os
import json
import subprocess
from aws_cdk import App, Environment, CfnOutput

from lib.dev_fleet_stack import DevFleetStack

# Run the resource lookup script first
try:
    subprocess.run(["python", "lib/lookup_resources.py"], check=True)
    print("Successfully looked up existing resources")
except Exception as e:
    print(f"Warning: Could not look up existing resources: {e}")
    print("Proceeding with deployment without resource lookup")

app = App()

# Environment variables
account = os.environ.get('CDK_DEFAULT_ACCOUNT', os.environ.get('AWS_ACCOUNT_ID', ''))
region = os.environ.get('CDK_DEFAULT_REGION', os.environ.get('AWS_REGION', 'us-east-1'))

env = Environment(account=account, region=region)

# Load resource exports if available
resource_exports = {}
try:
    if os.path.exists('resource_exports.json'):
        with open('resource_exports.json', 'r') as f:
            resource_exports = json.load(f)
except Exception as e:
    print(f"Warning: Could not load resource exports: {e}")

# Define your certificate ARN here
wildcard_certificate_arn = "arn:aws:acm:us-east-1:510985353423:certificate/93474ca3-71c9-4c70-add6-9211e6c72b58"

# Create the stack
DevFleetStack(app, "DevFleetStack",
    domain_name="qdev.ngdegtm.com",
    hosted_zone_name="ngdegtm.com",
    ecr_repository_name="dev-fleet-containers",
    container_image_tag="base-dev-env",
    ecs_cluster_name="dev-fleet-cluster",
    efs_name="dev-fleet-persistent-storage",
    wildcard_certificate_arn=wildcard_certificate_arn,  # Pass the certificate ARN directly
    env=env,
    existing_resources=resource_exports
)

app.synth()
