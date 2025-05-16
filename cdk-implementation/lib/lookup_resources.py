import boto3
import json
import os

def lookup_ecr_repositories():
    """
    Look up existing ECR repositories and export them as a CloudFormation output
    """
    ecr_client = boto3.client('ecr')
    repositories = []
    
    try:
        paginator = ecr_client.get_paginator('describe_repositories')
        for page in paginator.paginate():
            for repo in page['repositories']:
                repositories.append(repo['repositoryName'])
    except Exception as e:
        print(f"Error looking up ECR repositories: {e}")
    
    return repositories

def lookup_efs_filesystems():
    """
    Look up existing EFS file systems and export them as a CloudFormation output
    """
    efs_client = boto3.client('efs')
    file_systems = {}
    
    try:
        paginator = efs_client.get_paginator('describe_file_systems')
        for page in paginator.paginate():
            for fs in page['FileSystems']:
                if 'Name' in fs and fs['Name']:
                    file_systems[fs['Name']] = fs['FileSystemId']
    except Exception as e:
        print(f"Error looking up EFS file systems: {e}")
    
    return file_systems

def lookup_ecs_clusters():
    """
    Look up existing ECS clusters and export them as a CloudFormation output
    """
    ecs_client = boto3.client('ecs')
    clusters = []
    
    try:
        paginator = ecs_client.get_paginator('list_clusters')
        for page in paginator.paginate():
            for cluster_arn in page['clusterArns']:
                # Extract cluster name from ARN
                cluster_name = cluster_arn.split('/')[-1]
                clusters.append(cluster_name)
    except Exception as e:
        print(f"Error looking up ECS clusters: {e}")
    
    return clusters

def generate_exports():
    """
    Generate exports for CloudFormation to use
    """
    exports = {
        'ecr_repositories': lookup_ecr_repositories(),
        'efs_filesystems': lookup_efs_filesystems(),
        'ecs_clusters': lookup_ecs_clusters()
    }
    
    # Write to a file that can be imported by CDK
    with open('resource_exports.json', 'w') as f:
        json.dump(exports, f, indent=2)
    
    print("Resource exports generated successfully")

if __name__ == "__main__":
    generate_exports()
