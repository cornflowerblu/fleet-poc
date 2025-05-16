#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text --region ${AWS_REGION})
LB_NAME="dev-fleet-lb"
TG_NAME="dev-fleet-target-group"
CLUSTER_NAME="dev-fleet-cluster"
SERVICE_NAME="dev-fleet-service"

# Get subnet IDs
echo "Getting subnet IDs..."
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" \
  --output text \
  --region ${AWS_REGION})

# Convert to array
SUBNET_ARRAY=($SUBNET_IDS)
if [ ${#SUBNET_ARRAY[@]} -lt 2 ]; then
  echo "Error: Need at least 2 public subnets for ALB. Found: ${#SUBNET_ARRAY[@]}"
  exit 1
fi

# Create security group for load balancer
echo "Creating security group for load balancer..."
LB_SG_ID=$(aws ec2 create-security-group \
  --group-name ${LB_NAME}-sg \
  --description "Security group for Dev Fleet Load Balancer" \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --output text \
  --query 'GroupId')

# Allow SSH traffic from anywhere to the load balancer
echo "Configuring security group..."
aws ec2 authorize-security-group-ingress \
  --group-id ${LB_SG_ID} \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region ${AWS_REGION}

# Create security group for ECS tasks
echo "Creating security group for ECS tasks..."
TASK_SG_ID=$(aws ec2 create-security-group \
  --group-name ${SERVICE_NAME}-sg \
  --description "Security group for Dev Fleet ECS Tasks" \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --output text \
  --query 'GroupId')

# Allow SSH traffic from the load balancer to the tasks
echo "Configuring task security group..."
aws ec2 authorize-security-group-ingress \
  --group-id ${TASK_SG_ID} \
  --protocol tcp \
  --port 22 \
  --source-group ${LB_SG_ID} \
  --region ${AWS_REGION}

# Create target group
echo "Creating target group..."
TG_ARN=$(aws elbv2 create-target-group \
  --name ${TG_NAME} \
  --protocol TCP \
  --port 22 \
  --vpc-id ${VPC_ID} \
  --target-type ip \
  --region ${AWS_REGION} \
  --output text \
  --query 'TargetGroups[0].TargetGroupArn')

# Create Network Load Balancer (NLB for SSH)
echo "Creating Network Load Balancer..."
LB_ARN=$(aws elbv2 create-load-balancer \
  --name ${LB_NAME} \
  --type network \
  --subnets ${SUBNET_IDS} \
  --region ${AWS_REGION} \
  --output text \
  --query 'LoadBalancers[0].LoadBalancerArn')

# Create listener
echo "Creating listener..."
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn ${LB_ARN} \
  --protocol TCP \
  --port 22 \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
  --region ${AWS_REGION} \
  --output text \
  --query 'Listeners[0].ListenerArn')

# Create ECS service with load balancer
echo "Creating ECS service..."
aws ecs create-service \
  --cluster ${CLUSTER_NAME} \
  --service-name ${SERVICE_NAME} \
  --task-definition dev-environment:1 \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ARRAY[0]}],securityGroups=[${TASK_SG_ID}],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=${TG_ARN},containerName=dev-container,containerPort=22" \
  --region ${AWS_REGION}

# Get the DNS name of the load balancer
LB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LB_ARN} \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region ${AWS_REGION})

# Add a tag to the load balancer
aws elbv2 add-tags \
  --resource-arns ${LB_ARN} \
  --tags Key=Name,Value=${LB_NAME} \
  --region ${AWS_REGION}

# Create Route 53 hosted zone record
echo "Creating Route 53 record..."
aws route53 change-resource-record-sets \
  --hosted-zone-id Z06787101JUJT7PMVRO8D \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "qdev.ngdegtm.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z26RNL4JYFTOTI",
          "DNSName": "'${LB_DNS}'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }' \
  --region ${AWS_REGION}

echo "Load balancer setup complete!"
echo "Connect to development environments using: ssh -i ~/.ssh/your_key developer@${LB_DNS}"
