#!/usr/bin/env python3
import os
from aws_cdk import App, Environment

from lib.dev_fleet_stack import DevFleetStack

app = App()

# Environment variables
account = os.environ.get('CDK_DEFAULT_ACCOUNT', os.environ.get('AWS_ACCOUNT_ID', ''))
region = os.environ.get('CDK_DEFAULT_REGION', os.environ.get('AWS_REGION', 'us-east-1'))

env = Environment(account=account, region=region)

# Create the stack
DevFleetStack(app, "DevFleetStack",
    domain_name="qdev.ngdegtm.com",
    hosted_zone_name="ngdegtm.com",
    ecr_repository_name="dev-fleet-containers",
    container_image_tag="base-dev-env",
    ecs_cluster_name="dev-fleet-cluster",
    efs_name="dev-fleet-persistent-storage",
    env=env
)

app.synth()
