#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region ${AWS_REGION})
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

# Check if security group for load balancer already exists
echo "Checking if load balancer security group exists..."
LB_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${LB_NAME}-sg" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region ${AWS_REGION})

if [ "$LB_SG_ID" == "None" ] || [ -z "$LB_SG_ID" ]; then
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
else
  echo "Using existing load balancer security group: ${LB_SG_ID}"
fi

# Check if security group for ECS tasks already exists
echo "Checking if ECS tasks security group exists..."
TASK_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SERVICE_NAME}-sg" "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region ${AWS_REGION})

if [ "$TASK_SG_ID" == "None" ] || [ -z "$TASK_SG_ID" ]; then
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
else
  echo "Using existing ECS tasks security group: ${TASK_SG_ID}"
fi

# Check if target group already exists
echo "Checking if target group exists..."
TG_ARN=$(aws elbv2 describe-target-groups \
  --names ${TG_NAME} \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text \
  --region ${AWS_REGION} 2>/dev/null || echo "")

if [ -z "$TG_ARN" ]; then
  # Create target group with health check
  echo "Creating target group with health check..."
  TG_ARN=$(aws elbv2 create-target-group \
    --name ${TG_NAME} \
    --protocol TCP \
    --port 22 \
    --vpc-id ${VPC_ID} \
    --target-type ip \
    --health-check-protocol TCP \
    --health-check-port 22 \
    --health-check-enabled \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 3 \
    --unhealthy-threshold-count 3 \
    --region ${AWS_REGION} \
    --output text \
    --query 'TargetGroups[0].TargetGroupArn')
else
  echo "Using existing target group: ${TG_ARN}"
fi

# Check if load balancer already exists
echo "Checking if load balancer exists..."
LB_ARN=$(aws elbv2 describe-load-balancers \
  --names ${LB_NAME} \
  --query "LoadBalancers[0].LoadBalancerArn" \
  --output text \
  --region ${AWS_REGION} 2>/dev/null || echo "")

if [ -z "$LB_ARN" ]; then
  # Create Network Load Balancer (NLB for SSH)
  echo "Creating Network Load Balancer..."
  LB_ARN=$(aws elbv2 create-load-balancer \
    --name ${LB_NAME} \
    --type network \
    --subnets ${SUBNET_IDS} \
    --region ${AWS_REGION} \
    --output text \
    --query 'LoadBalancers[0].LoadBalancerArn')

  # Add a tag to the load balancer
  aws elbv2 add-tags \
    --resource-arns ${LB_ARN} \
    --tags Key=Name,Value=${LB_NAME} \
    --region ${AWS_REGION}
else
  echo "Using existing load balancer: ${LB_ARN}"
fi

# Check if listener already exists
echo "Checking if listener exists..."
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn ${LB_ARN} \
  --query "Listeners[?Port==\`22\`].ListenerArn" \
  --output text \
  --region ${AWS_REGION} 2>/dev/null || echo "")

if [ -z "$LISTENER_ARN" ]; then
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
else
  echo "Using existing listener: ${LISTENER_ARN}"
fi

# Check if ECS service already exists
echo "Checking if ECS service exists..."
SERVICE_EXISTS=$(aws ecs describe-services \
  --cluster ${CLUSTER_NAME} \
  --services ${SERVICE_NAME} \
  --query "services[?status=='ACTIVE'].serviceName" \
  --output text \
  --region ${AWS_REGION} 2>/dev/null || echo "")

# Get the latest task definition revision
LATEST_TASK_DEF=$(aws ecs list-task-definitions \
  --family-prefix dev-environment \
  --sort DESC \
  --query "taskDefinitionArns[0]" \
  --output text \
  --region ${AWS_REGION})

TASK_DEF_REVISION=${LATEST_TASK_DEF##*:}

if [ -z "$SERVICE_EXISTS" ]; then
  # Create ECS service with load balancer
  echo "Creating ECS service with task definition revision ${TASK_DEF_REVISION}..."
  aws ecs create-service \
    --cluster ${CLUSTER_NAME} \
    --service-name ${SERVICE_NAME} \
    --task-definition dev-environment:${TASK_DEF_REVISION} \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ARRAY[0]}],securityGroups=[${TASK_SG_ID}],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=${TG_ARN},containerName=dev-container,containerPort=22" \
    --region ${AWS_REGION}
else
  echo "ECS service ${SERVICE_NAME} already exists"
  
  # Update the service to use the latest task definition
  echo "Updating ECS service to use task definition revision ${TASK_DEF_REVISION}..."
  aws ecs update-service \
    --cluster ${CLUSTER_NAME} \
    --service ${SERVICE_NAME} \
    --task-definition dev-environment:${TASK_DEF_REVISION} \
    --region ${AWS_REGION} > /dev/null
fi

# Get the DNS name of the load balancer
LB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LB_ARN} \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region ${AWS_REGION})

# Check if Route 53 record already exists
echo "Checking if Route 53 record exists..."
HOSTED_ZONE_ID="Z06787101JUJT7PMVRO8D"  # Replace with your hosted zone ID
DOMAIN_NAME="qdev.ngdegtm.com"

RECORD_EXISTS=$(aws route53 list-resource-record-sets \
  --hosted-zone-id ${HOSTED_ZONE_ID} \
  --query "ResourceRecordSets[?Name=='${DOMAIN_NAME}.'].Name" \
  --output text \
  --region ${AWS_REGION})

if [ -z "$RECORD_EXISTS" ]; then
  # Create Route 53 hosted zone record
  echo "Creating Route 53 record..."
  aws route53 change-resource-record-sets \
    --hosted-zone-id ${HOSTED_ZONE_ID} \
    --change-batch '{
      "Changes": [{
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "'${DOMAIN_NAME}'",
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
else
  echo "Route 53 record for ${DOMAIN_NAME} already exists"
fi

echo "Load balancer setup complete!"
echo "Connect to development environments using: ssh -i ~/.ssh/your_key developer@${LB_DNS}"
echo "Or using the custom domain: ssh -i ~/.ssh/your_key developer@${DOMAIN_NAME}"
