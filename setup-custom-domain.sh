#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
DOMAIN_NAME="qdev.ngdegtm.com"
HOSTED_ZONE="ngdegtm.com"
LB_NAME="dev-fleet-lb"

# Get the load balancer ARN
echo "Getting load balancer ARN..."
LB_ARN=$(aws elbv2 describe-load-balancers \
  --names ${LB_NAME} \
  --region ${AWS_REGION} \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

if [ -z "$LB_ARN" ] || [ "$LB_ARN" == "None" ]; then
  echo "Error: Load balancer ${LB_NAME} not found"
  exit 1
fi

# Get the load balancer DNS name
LB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LB_ARN} \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region ${AWS_REGION})

# Get the hosted zone ID
echo "Getting hosted zone ID..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name ${HOSTED_ZONE} \
  --query 'HostedZones[0].Id' \
  --output text \
  --region ${AWS_REGION})

HOSTED_ZONE_ID=${HOSTED_ZONE_ID#/hostedzone/}

if [ -z "$HOSTED_ZONE_ID" ] || [ "$HOSTED_ZONE_ID" == "None" ]; then
  echo "Error: Hosted zone for ${HOSTED_ZONE} not found"
  exit 1
fi

# Get the load balancer hosted zone ID (needed for alias records)
LB_HOSTED_ZONE_ID=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns ${LB_ARN} \
  --query 'LoadBalancers[0].CanonicalHostedZoneId' \
  --output text \
  --region ${AWS_REGION})

# Check if Route53 record already exists
echo "Checking if Route53 record exists..."
RECORD_EXISTS=$(aws route53 list-resource-record-sets \
  --hosted-zone-id ${HOSTED_ZONE_ID} \
  --query "ResourceRecordSets[?Name=='${DOMAIN_NAME}.'].Name" \
  --output text \
  --region ${AWS_REGION})

if [ -z "$RECORD_EXISTS" ]; then
  # Create Route53 record set
  echo "Creating Route53 record..."
  aws route53 change-resource-record-sets \
    --hosted-zone-id ${HOSTED_ZONE_ID} \
    --change-batch '{
      "Changes": [
        {
          "Action": "UPSERT",
          "ResourceRecordSet": {
            "Name": "'${DOMAIN_NAME}'",
            "Type": "A",
            "AliasTarget": {
              "HostedZoneId": "'${LB_HOSTED_ZONE_ID}'",
              "DNSName": "'${LB_DNS}'",
              "EvaluateTargetHealth": true
            }
          }
        }
      ]
    }' \
    --region ${AWS_REGION}
else
  echo "Route53 record for ${DOMAIN_NAME} already exists"
fi

# Find existing certificate for *.ngdegtm.com
echo "Looking for existing certificate..."
CERT_ARN=$(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='*.ngdegtm.com'].CertificateArn" \
  --output text \
  --region ${AWS_REGION})

if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" == "None" ]; then
  echo "No existing certificate found for *.ngdegtm.com"
  echo "You'll need to request a certificate or use an existing one"
  exit 1
fi

echo "Found certificate: ${CERT_ARN}"

# Check if there's an existing listener
echo "Checking for existing listeners..."
LISTENERS=$(aws elbv2 describe-listeners \
  --load-balancer-arn ${LB_ARN} \
  --query 'Listeners[*].{ARN:ListenerArn,Protocol:Protocol}' \
  --output json \
  --region ${AWS_REGION})

# Parse the listeners to find TCP and TLS listeners
TCP_LISTENER_ARN=$(echo $LISTENERS | jq -r '.[] | select(.Protocol == "TCP") | .ARN')
TLS_LISTENER_ARN=$(echo $LISTENERS | jq -r '.[] | select(.Protocol == "TLS") | .ARN')

# Get the target group ARN from any existing listener
if [ ! -z "$TCP_LISTENER_ARN" ]; then
  TG_ARN=$(aws elbv2 describe-listeners \
    --listener-arns ${TCP_LISTENER_ARN} \
    --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
    --output text \
    --region ${AWS_REGION})
elif [ ! -z "$TLS_LISTENER_ARN" ]; then
  TG_ARN=$(aws elbv2 describe-listeners \
    --listener-arns ${TLS_LISTENER_ARN} \
    --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
    --output text \
    --region ${AWS_REGION})
else
  echo "Error: No listeners found on the load balancer"
  exit 1
fi

# If we have a TCP listener but no TLS listener, replace it
if [ ! -z "$TCP_LISTENER_ARN" ] && [ -z "$TLS_LISTENER_ARN" ]; then
  # Delete the existing TCP listener
  echo "Deleting existing TCP listener..."
  aws elbv2 delete-listener \
    --listener-arn ${TCP_LISTENER_ARN} \
    --region ${AWS_REGION}

  # Create a new TLS listener
  echo "Creating new TLS listener..."
  aws elbv2 create-listener \
    --load-balancer-arn ${LB_ARN} \
    --protocol TLS \
    --port 22 \
    --certificates CertificateArn=${CERT_ARN} \
    --ssl-policy ELBSecurityPolicy-TLS-1-2-2017-01 \
    --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
    --region ${AWS_REGION}
elif [ -z "$TLS_LISTENER_ARN" ]; then
  # Create a new TLS listener if none exists
  echo "Creating new TLS listener..."
  aws elbv2 create-listener \
    --load-balancer-arn ${LB_ARN} \
    --protocol TLS \
    --port 22 \
    --certificates CertificateArn=${CERT_ARN} \
    --ssl-policy ELBSecurityPolicy-TLS-1-2-2017-01 \
    --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
    --region ${AWS_REGION}
else
  echo "TLS listener already exists, no changes needed"
fi

echo "Setup complete!"
echo "Your development environment is now accessible at: ${DOMAIN_NAME}"
echo "Connect using: ssh -i ~/.ssh/your_key developer@${DOMAIN_NAME}"
