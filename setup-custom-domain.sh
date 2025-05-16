#!/bin/bash
set -e

# Configuration
AWS_REGION="us-east-1"  # Change to your preferred region
DOMAIN_NAME="dev-fleet.ngdegtm.com"
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

# Get the current listener ARN
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn ${LB_ARN} \
  --query 'Listeners[0].ListenerArn' \
  --output text \
  --region ${AWS_REGION})

# Get the target group ARN
TG_ARN=$(aws elbv2 describe-listeners \
  --listener-arns ${LISTENER_ARN} \
  --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
  --output text \
  --region ${AWS_REGION})

# Delete the existing listener
echo "Deleting existing TCP listener..."
aws elbv2 delete-listener \
  --listener-arn ${LISTENER_ARN} \
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

echo "Setup complete!"
echo "Your development environment is now accessible at: ${DOMAIN_NAME}"
echo "Connect using: ssh -i ~/.ssh/your_key developer@${DOMAIN_NAME}"
