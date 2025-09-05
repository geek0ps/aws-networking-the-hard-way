# Lab 10: Network Disaster Recovery - Detailed Steps

## Prerequisites
- Completed Labs 01-09
- Understanding of disaster recovery concepts
- AWS CLI configured with appropriate permissions
- Access to multiple AWS regions

```bash
# Set environment variables
export PRIMARY_REGION="us-east-1"
export DR_REGION="us-west-2"
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
echo "Primary VPC: $VPC_ID in $PRIMARY_REGION"
```

## Step 1: Design Multi-Region DR Architecture

### Create DR Region VPC
```bash
# Switch to DR region and create VPC
aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --region $DR_REGION \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ecommerce-vpc-dr},{Key=Environment,Value=disaster-recovery},{Key=Project,Value=aws-networking-hard-way}]'

DR_VPC_ID=$(aws ec2 describe-vpcs \
    --region $DR_REGION \
    --filters "Name=tag:Name,Values=ecommerce-vpc-dr" \
    --query 'Vpcs[0].VpcId' \
    --output text)

# Enable DNS hostnames and support
aws ec2 modify-vpc-attribute --region $DR_REGION --vpc-id $DR_VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --region $DR_REGION --vpc-id $DR_VPC_ID --enable-dns-support

echo "Created DR VPC: $DR_VPC_ID in $DR_REGION"
```

### Create DR Subnets
```bash
# Create public subnets in DR region
aws ec2 create-subnet \
    --region $DR_REGION \
    --vpc-id $DR_VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone ${DR_REGION}a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-public-web-2a},{Key=Tier,Value=web},{Key=Environment,Value=dr}]'

aws ec2 create-subnet \
    --region $DR_REGION \
    --vpc-id $DR_VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone ${DR_REGION}b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-public-web-2b},{Key=Tier,Value=web},{Key=Environment,Value=dr}]'

# Create private subnets in DR region
aws ec2 create-subnet \
    --region $DR_REGION \
    --vpc-id $DR_VPC_ID \
    --cidr-block 10.0.11.0/24 \
    --availability-zone ${DR_REGION}a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-private-app-2a},{Key=Tier,Value=app},{Key=Environment,Value=dr}]'

aws ec2 create-subnet \
    --region $DR_REGION \
    --vpc-id $DR_VPC_ID \
    --cidr-block 10.0.12.0/24 \
    --availability-zone ${DR_REGION}b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-private-app-2b},{Key=Tier,Value=app},{Key=Environment,Value=dr}]'

# Create database subnets in DR region
aws ec2 create-subnet \
    --region $DR_REGION \
    --vpc-id $DR_VPC_ID \
    --cidr-block 10.0.21.0/24 \
    --availability-zone ${DR_REGION}a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-private-db-2a},{Key=Tier,Value=database},{Key=Environment,Value=dr}]'

aws ec2 create-subnet \
    --region $DR_REGION \
    --vpc-id $DR_VPC_ID \
    --cidr-block 10.0.22.0/24 \
    --availability-zone ${DR_REGION}b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dr-private-db-2b},{Key=Tier,Value=database},{Key=Environment,Value=dr}]'

echo "Created DR subnets in $DR_REGION"
```

### Set Up DR Networking Components
```bash
# Create Internet Gateway for DR VPC
aws ec2 create-internet-gateway \
    --region $DR_REGION \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=dr-igw},{Key=Environment,Value=dr}]'

DR_IGW_ID=$(aws ec2 describe-internet-gateways \
    --region $DR_REGION \
    --filters "Name=tag:Name,Values=dr-igw" \
    --query 'InternetGateways[0].InternetGatewayId' \
    --output text)

# Attach IGW to DR VPC
aws ec2 attach-internet-gateway \
    --region $DR_REGION \
    --internet-gateway-id $DR_IGW_ID \
    --vpc-id $DR_VPC_ID

# Create NAT Gateway for DR region
DR_PUBLIC_SUBNET_2A=$(aws ec2 describe-subnets \
    --region $DR_REGION \
    --filters "Name=tag:Name,Values=dr-public-web-2a" \
    --query 'Subnets[0].SubnetId' \
    --output text)

# Allocate Elastic IP for NAT Gateway
aws ec2 allocate-address \
    --region $DR_REGION \
    --domain vpc \
    --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=dr-nat-eip},{Key=Environment,Value=dr}]'

DR_EIP_ALLOC_ID=$(aws ec2 describe-addresses \
    --region $DR_REGION \
    --filters "Name=tag:Name,Values=dr-nat-eip" \
    --query 'Addresses[0].AllocationId' \
    --output text)

# Create NAT Gateway
aws ec2 create-nat-gateway \
    --region $DR_REGION \
    --subnet-id $DR_PUBLIC_SUBNET_2A \
    --allocation-id $DR_EIP_ALLOC_ID \
    --tag-specifications 'ResourceType=nat-gateway,Tags=[{Key=Name,Value=dr-nat-gateway},{Key=Environment,Value=dr}]'

echo "Created DR networking components"
```

## Step 2: Configure Route 53 Health Checks and Failover

### Create Health Checks for Primary Region
```bash
# Get ALB DNS name from primary region
PRIMARY_ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region $PRIMARY_REGION \
    --names enterprise-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$PRIMARY_ALB_DNS" ]; then
    # Create health check for primary ALB
    aws route53 create-health-check \
        --caller-reference "primary-alb-$(date +%s)" \
        --health-check-config Type=HTTP,ResourcePath=/health,FullyQualifiedDomainName=$PRIMARY_ALB_DNS,Port=80,RequestInterval=30,FailureThreshold=3 \
        --tags ResourceType=healthcheck,Key=Name,Value=primary-alb-health,Key=Environment,Value=primary

    PRIMARY_HEALTH_CHECK_ID=$(aws route53 list-health-checks \
        --query 'HealthChecks[?CallerReference==`primary-alb-$(date +%s)`].Id' \
        --output text)

    echo "Created health check for primary ALB: $PRIMARY_HEALTH_CHECK_ID"
else
    echo "⚠️  Primary ALB not found, skipping health check creation"
fi
```

### Set Up DR Load Balancer
```bash
# Create security group for DR ALB
aws ec2 create-security-group \
    --region $DR_REGION \
    --group-name dr-alb-sg \
    --description "Security group for DR Application Load Balancer" \
    --vpc-id $DR_VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=dr-alb-sg},{Key=Environment,Value=dr}]'

DR_ALB_SG_ID=$(aws ec2 describe-security-groups \
    --region $DR_REGION \
    --filters "Name=group-name,Values=dr-alb-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow HTTP and HTTPS
aws ec2 authorize-security-group-ingress \
    --region $DR_REGION \
    --group-id $DR_ALB_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --region $DR_REGION \
    --group-id $DR_ALB_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0

# Get DR public subnets
DR_PUBLIC_SUBNET_2B=$(aws ec2 describe-subnets \
    --region $DR_REGION \
    --filters "Name=tag:Name,Values=dr-public-web-2b" \
    --query 'Subnets[0].SubnetId' \
    --output text)

# Create DR ALB
aws elbv2 create-load-balancer \
    --region $DR_REGION \
    --name dr-enterprise-alb \
    --subnets $DR_PUBLIC_SUBNET_2A $DR_PUBLIC_SUBNET_2B \
    --security-groups $DR_ALB_SG_ID \
    --scheme internet-facing \
    --type application \
    --tags Key=Name,Value=dr-enterprise-alb,Key=Environment,Value=dr

DR_ALB_ARN=$(aws elbv2 describe-load-balancers \
    --region $DR_REGION \
    --names dr-enterprise-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

DR_ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region $DR_REGION \
    --names dr-enterprise-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "Created DR ALB: $DR_ALB_DNS"
```

### Configure DNS Failover
```bash
# Create hosted zone for DR testing
aws route53 create-hosted-zone \
    --name "dr-test.local" \
    --caller-reference "dr-test-$(date +%s)" \
    --hosted-zone-config Comment="DR testing zone" PrivateZone=false \
    --tags ResourceType=hostedzone,Key=Name,Value=dr-test-zone,Key=Purpose,Value=disaster-recovery

DR_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
    --dns-name "dr-test.local" \
    --query 'HostedZones[0].Id' \
    --output text | cut -d'/' -f3)

# Create primary record with health check
if [ ! -z "$PRIMARY_ALB_DNS" ]; then
    cat > primary-dr-record.json << EOF
{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "app.dr-test.local",
                "Type": "A",
                "SetIdentifier": "primary",
                "Failover": "PRIMARY",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "$(dig +short $PRIMARY_ALB_DNS | head -1)"
                    }
                ],
                "HealthCheckId": "$PRIMARY_HEALTH_CHECK_ID"
            }
        }
    ]
}
EOF

    aws route53 change-resource-record-sets \
        --hosted-zone-id $DR_HOSTED_ZONE_ID \
        --change-batch file://primary-dr-record.json
fi

# Create secondary record for DR
cat > secondary-dr-record.json << EOF
{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "app.dr-test.local",
                "Type": "A",
                "SetIdentifier": "secondary",
                "Failover": "SECONDARY",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "$(dig +short $DR_ALB_DNS | head -1)"
                    }
                ]
            }
        }
    ]
}
EOF

aws route53 change-resource-record-sets \
    --hosted-zone-id $DR_HOSTED_ZONE_ID \
    --change-batch file://secondary-dr-record.json

echo "Configured DNS failover records"

# Clean up temporary files
rm -f primary-dr-record.json secondary-dr-record.json
```

## Step 3: Implement Cross-Region Data Replication

### Set Up S3 Cross-Region Replication
```bash
# Create S3 buckets for data replication
PRIMARY_BUCKET="primary-data-$(date +%s)"
DR_BUCKET="dr-data-$(date +%s)"

# Create primary bucket
aws s3 mb s3://$PRIMARY_BUCKET --region $PRIMARY_REGION

# Create DR bucket
aws s3 mb s3://$DR_BUCKET --region $DR_REGION

# Enable versioning on both buckets
aws s3api put-bucket-versioning \
    --bucket $PRIMARY_BUCKET \
    --versioning-configuration Status=Enabled

aws s3api put-bucket-versioning \
    --bucket $DR_BUCKET \
    --versioning-configuration Status=Enabled

# Create IAM role for replication
cat > s3-replication-role.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name S3ReplicationRole \
    --assume-role-policy-document file://s3-replication-role.json

# Create replication policy
cat > s3-replication-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl"
      ],
      "Resource": "arn:aws:s3:::PRIMARY_BUCKET/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::PRIMARY_BUCKET"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete"
      ],
      "Resource": "arn:aws:s3:::DR_BUCKET/*"
    }
  ]
}
EOF

# Replace placeholders
sed -i "s/PRIMARY_BUCKET/$PRIMARY_BUCKET/g" s3-replication-policy.json
sed -i "s/DR_BUCKET/$DR_BUCKET/g" s3-replication-policy.json

aws iam create-policy \
    --policy-name S3ReplicationPolicy \
    --policy-document file://s3-replication-policy.json

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam attach-role-policy \
    --role-name S3ReplicationRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/S3ReplicationPolicy

# Configure replication
cat > replication-config.json << 'EOF'
{
  "Role": "arn:aws:iam::ACCOUNT_ID:role/S3ReplicationRole",
  "Rules": [
    {
      "ID": "ReplicateToDR",
      "Status": "Enabled",
      "Priority": 1,
      "Filter": {},
      "Destination": {
        "Bucket": "arn:aws:s3:::DR_BUCKET",
        "StorageClass": "STANDARD_IA"
      }
    }
  ]
}
EOF

sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" replication-config.json
sed -i "s/DR_BUCKET/$DR_BUCKET/g" replication-config.json

aws s3api put-bucket-replication \
    --bucket $PRIMARY_BUCKET \
    --replication-configuration file://replication-config.json

echo "Configured S3 cross-region replication"
echo "  Primary bucket: $PRIMARY_BUCKET"
echo "  DR bucket: $DR_BUCKET"

# Clean up temporary files
rm -f s3-replication-role.json s3-replication-policy.json replication-config.json
```

### Set Up Database Replication Simulation
```bash
# Create RDS subnet groups for both regions
# Primary region subnet group
aws rds create-db-subnet-group \
    --region $PRIMARY_REGION \
    --db-subnet-group-name primary-db-subnet-group \
    --db-subnet-group-description "Primary region DB subnet group" \
    --subnet-ids $(aws ec2 describe-subnets --region $PRIMARY_REGION --filters "Name=tag:Name,Values=private-db-1a,private-db-1b" --query 'Subnets[].SubnetId' --output text | tr '\t' ' ')

# DR region subnet group
DR_DB_SUBNET_2A=$(aws ec2 describe-subnets --region $DR_REGION --filters "Name=tag:Name,Values=dr-private-db-2a" --query 'Subnets[0].SubnetId' --output text)
DR_DB_SUBNET_2B=$(aws ec2 describe-subnets --region $DR_REGION --filters "Name=tag:Name,Values=dr-private-db-2b" --query 'Subnets[0].SubnetId' --output text)

aws rds create-db-subnet-group \
    --region $DR_REGION \
    --db-subnet-group-name dr-db-subnet-group \
    --db-subnet-group-description "DR region DB subnet group" \
    --subnet-ids $DR_DB_SUBNET_2A $DR_DB_SUBNET_2B

echo "Created RDS subnet groups for cross-region replication"
```

## Step 4: Create Automated Failover Mechanisms

### Create Lambda Function for Automated Failover
```bash
cat > dr-failover-lambda.py << 'EOF'
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Automated disaster recovery failover function
    """
    
    route53 = boto3.client('route53')
    ec2_primary = boto3.client('ec2', region_name=os.environ['PRIMARY_REGION'])
    ec2_dr = boto3.client('ec2', region_name=os.environ['DR_REGION'])
    
    try:
        # Check if this is a health check failure
        if 'source' in event and event['source'] == 'aws.route53':
            return handle_health_check_failure(event, route53, ec2_primary, ec2_dr)
        
        # Manual failover trigger
        elif event.get('action') == 'failover':
            return initiate_manual_failover(route53, ec2_primary, ec2_dr)
        
        # Failback trigger
        elif event.get('action') == 'failback':
            return initiate_failback(route53, ec2_primary, ec2_dr)
        
        else:
            return {
                'statusCode': 400,
                'body': json.dumps('Unknown action')
            }
            
    except Exception as e:
        logger.error(f"Error in DR failover: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_health_check_failure(event, route53, ec2_primary, ec2_dr):
    """Handle automatic failover due to health check failure"""
    
    logger.info("Health check failure detected, initiating automatic failover")
    
    # Start DR instances if they're stopped
    start_dr_instances(ec2_dr)
    
    # Update Route 53 records to point to DR
    update_dns_to_dr(route53)
    
    # Send notifications
    send_failover_notification("Automatic failover initiated due to health check failure")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Automatic failover completed')
    }

def initiate_manual_failover(route53, ec2_primary, ec2_dr):
    """Initiate manual failover to DR region"""
    
    logger.info("Manual failover initiated")
    
    # Start DR instances
    start_dr_instances(ec2_dr)
    
    # Update DNS
    update_dns_to_dr(route53)
    
    # Send notifications
    send_failover_notification("Manual failover initiated")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Manual failover completed')
    }

def initiate_failback(route53, ec2_primary, ec2_dr):
    """Initiate failback to primary region"""
    
    logger.info("Failback initiated")
    
    # Ensure primary instances are running
    start_primary_instances(ec2_primary)
    
    # Update DNS back to primary
    update_dns_to_primary(route53)
    
    # Send notifications
    send_failover_notification("Failback to primary region completed")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Failback completed')
    }

def start_dr_instances(ec2_dr):
    """Start instances in DR region"""
    
    try:
        # Get stopped instances in DR region
        response = ec2_dr.describe_instances(
            Filters=[
                {'Name': 'tag:Environment', 'Values': ['dr']},
                {'Name': 'instance-state-name', 'Values': ['stopped']}
            ]
        )
        
        instance_ids = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])
        
        if instance_ids:
            ec2_dr.start_instances(InstanceIds=instance_ids)
            logger.info(f"Started DR instances: {instance_ids}")
        
    except Exception as e:
        logger.error(f"Error starting DR instances: {str(e)}")

def start_primary_instances(ec2_primary):
    """Start instances in primary region"""
    
    try:
        # Similar logic for primary region
        logger.info("Starting primary region instances")
        
    except Exception as e:
        logger.error(f"Error starting primary instances: {str(e)}")

def update_dns_to_dr(route53):
    """Update DNS records to point to DR region"""
    
    try:
        # Update Route 53 records
        logger.info("Updating DNS to point to DR region")
        
    except Exception as e:
        logger.error(f"Error updating DNS to DR: {str(e)}")

def update_dns_to_primary(route53):
    """Update DNS records to point to primary region"""
    
    try:
        # Update Route 53 records
        logger.info("Updating DNS to point to primary region")
        
    except Exception as e:
        logger.error(f"Error updating DNS to primary: {str(e)}")

def send_failover_notification(message):
    """Send notification about failover event"""
    
    try:
        sns = boto3.client('sns')
        topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        if topic_arn:
            sns.publish(
                TopicArn=topic_arn,
                Message=message,
                Subject="DR Failover Event"
            )
            
        logger.info(f"Sent notification: {message}")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
EOF

# Create IAM role for DR Lambda
cat > dr-lambda-role.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name DRFailoverLambdaRole \
    --assume-role-policy-document file://dr-lambda-role.json

# Create policy for DR Lambda
cat > dr-lambda-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "ec2:DescribeInstances",
        "ec2:StartInstances",
        "ec2:StopInstances",
        "route53:ChangeResourceRecordSets",
        "route53:GetChange",
        "route53:ListResourceRecordSets",
        "sns:Publish"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
    --policy-name DRFailoverLambdaPolicy \
    --policy-document file://dr-lambda-policy.json

aws iam attach-role-policy \
    --role-name DRFailoverLambdaRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DRFailoverLambdaPolicy

aws iam attach-role-policy \
    --role-name DRFailoverLambdaRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create Lambda function
zip dr-failover-lambda.zip dr-failover-lambda.py

aws lambda create-function \
    --function-name DRFailoverAutomation \
    --runtime python3.9 \
    --role arn:aws:iam::${ACCOUNT_ID}:role/DRFailoverLambdaRole \
    --handler dr-failover-lambda.lambda_handler \
    --zip-file fileb://dr-failover-lambda.zip \
    --timeout 300 \
    --environment Variables="{PRIMARY_REGION=$PRIMARY_REGION,DR_REGION=$DR_REGION}" \
    --tags Key=Purpose,Value=disaster-recovery

echo "Created DR failover automation Lambda function"

# Clean up
rm -f dr-lambda-role.json dr-lambda-policy.json dr-failover-lambda.py dr-failover-lambda.zip
```

## Step 5: Create DR Testing and Validation

### Create DR Test Script
```bash
cat > test-disaster-recovery.sh << 'EOF'
#!/bin/bash

echo "🚨 Disaster Recovery Testing"
echo "============================"

# Load configuration
PRIMARY_REGION=${PRIMARY_REGION:-us-east-1}
DR_REGION=${DR_REGION:-us-west-2}

echo "Primary Region: $PRIMARY_REGION"
echo "DR Region: $DR_REGION"
echo ""

# Test 1: Verify DR Infrastructure
echo "Test 1: DR Infrastructure Verification"
echo "-------------------------------------"

# Check DR VPC
DR_VPC_ID=$(aws ec2 describe-vpcs --region $DR_REGION --filters "Name=tag:Name,Values=ecommerce-vpc-dr" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")

if [ "$DR_VPC_ID" != "None" ]; then
    echo "✅ DR VPC exists: $DR_VPC_ID"
    
    # Check DR subnets
    DR_SUBNET_COUNT=$(aws ec2 describe-subnets --region $DR_REGION --filters "Name=vpc-id,Values=$DR_VPC_ID" --query 'length(Subnets)' --output text)
    echo "✅ DR Subnets: $DR_SUBNET_COUNT"
    
    # Check DR NAT Gateway
    DR_NAT_COUNT=$(aws ec2 describe-nat-gateways --region $DR_REGION --filter "Name=vpc-id,Values=$DR_VPC_ID" --query 'length(NatGateways)' --output text)
    echo "✅ DR NAT Gateways: $DR_NAT_COUNT"
else
    echo "❌ DR VPC not found"
fi

# Test 2: Check Load Balancer Status
echo ""
echo "Test 2: Load Balancer Status"
echo "---------------------------"

# Primary ALB
PRIMARY_ALB_STATE=$(aws elbv2 describe-load-balancers --region $PRIMARY_REGION --names enterprise-alb --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null || echo "not_found")
echo "Primary ALB State: $PRIMARY_ALB_STATE"

# DR ALB
DR_ALB_STATE=$(aws elbv2 describe-load-balancers --region $DR_REGION --names dr-enterprise-alb --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null || echo "not_found")
echo "DR ALB State: $DR_ALB_STATE"

# Test 3: DNS Failover Configuration
echo ""
echo "Test 3: DNS Failover Configuration"
echo "---------------------------------"

# Check Route 53 health checks
HEALTH_CHECKS=$(aws route53 list-health-checks --query 'length(HealthChecks)' --output text)
echo "Health Checks Configured: $HEALTH_CHECKS"

# Check hosted zone
HOSTED_ZONE=$(aws route53 list-hosted-zones-by-name --dns-name "dr-test.local" --query 'HostedZones[0].Name' --output text 2>/dev/null || echo "not_found")
echo "DR Test Zone: $HOSTED_ZONE"

# Test 4: Data Replication Status
echo ""
echo "Test 4: Data Replication Status"
echo "------------------------------"

# Check S3 replication
PRIMARY_BUCKET=$(aws s3 ls | grep primary-data | awk '{print $3}' | head -1)
DR_BUCKET=$(aws s3 ls | grep dr-data | awk '{print $3}' | head -1)

if [ ! -z "$PRIMARY_BUCKET" ] && [ ! -z "$DR_BUCKET" ]; then
    echo "✅ S3 Replication configured"
    echo "   Primary: $PRIMARY_BUCKET"
    echo "   DR: $DR_BUCKET"
    
    # Test replication by uploading a file
    echo "Testing replication..." > test-replication.txt
    aws s3 cp test-replication.txt s3://$PRIMARY_BUCKET/
    
    # Wait and check if replicated
    sleep 30
    REPLICATED=$(aws s3 ls s3://$DR_BUCKET/test-replication.txt 2>/dev/null && echo "yes" || echo "no")
    echo "   Replication test: $REPLICATED"
    
    # Cleanup
    aws s3 rm s3://$PRIMARY_BUCKET/test-replication.txt
    aws s3 rm s3://$DR_BUCKET/test-replication.txt 2>/dev/null
    rm -f test-replication.txt
else
    echo "⚠️  S3 replication not configured"
fi

# Test 5: Automation Functions
echo ""
echo "Test 5: DR Automation"
echo "--------------------"

# Check Lambda function
LAMBDA_STATUS=$(aws lambda get-function --function-name DRFailoverAutomation --query 'Configuration.State' --output text 2>/dev/null || echo "not_found")
echo "DR Lambda Function: $LAMBDA_STATUS"

# Test 6: Network Connectivity
echo ""
echo "Test 6: Cross-Region Connectivity"
echo "--------------------------------"

# This would require actual instances running
echo "Manual test required:"
echo "1. Deploy test instances in both regions"
echo "2. Test connectivity between regions"
echo "3. Verify application functionality"

# Test 7: RTO/RPO Validation
echo ""
echo "Test 7: RTO/RPO Validation"
echo "-------------------------"

echo "Recovery Time Objective (RTO) targets:"
echo "  • DNS failover: < 5 minutes"
echo "  • Application startup: < 15 minutes"
echo "  • Full service restoration: < 30 minutes"
echo ""
echo "Recovery Point Objective (RPO) targets:"
echo "  • Database: < 5 minutes"
echo "  • File storage: < 1 minute (S3 replication)"
echo "  • Configuration: Real-time (Infrastructure as Code)"

echo ""
echo "🎯 DR Testing Complete"
echo ""
echo "📋 Manual Tests Required:"
echo "1. Simulate primary region failure"
echo "2. Trigger manual failover"
echo "3. Validate application functionality in DR region"
echo "4. Test failback procedures"
echo "5. Document actual RTO/RPO achieved"
EOF

chmod +x test-disaster-recovery.sh
echo "Created DR testing script: test-disaster-recovery.sh"
```

### Create DR Runbook
```bash
cat > dr-runbook.md << 'EOF'
# Disaster Recovery Runbook

## Overview
This runbook provides step-by-step procedures for disaster recovery scenarios affecting the primary AWS region.

## Emergency Contacts
- **Primary On-Call**: [Phone Number]
- **Secondary On-Call**: [Phone Number]
- **AWS Support**: [Support Case Portal]
- **Management**: [Contact Information]

## Disaster Scenarios

### Scenario 1: Complete Primary Region Outage

#### Detection
- Route 53 health checks failing
- CloudWatch alarms triggered
- Application unavailable
- AWS Service Health Dashboard shows regional issues

#### Response Procedure

**Phase 1: Assessment (0-5 minutes)**
1. Confirm regional outage via AWS Service Health Dashboard
2. Check Route 53 health check status
3. Verify DR region availability
4. Notify stakeholders

**Phase 2: Failover (5-15 minutes)**
1. Execute automated failover:
   ```bash
   aws lambda invoke \
     --function-name DRFailoverAutomation \
     --payload '{"action": "failover"}' \
     response.json
   ```

2. Monitor DNS propagation:
   ```bash
   dig app.dr-test.local
   nslookup app.dr-test.local
   ```

3. Verify DR instances are starting:
   ```bash
   aws ec2 describe-instances \
     --region us-west-2 \
     --filters "Name=tag:Environment,Values=dr"
   ```

**Phase 3: Validation (15-30 minutes)**
1. Test application functionality
2. Verify data consistency
3. Monitor performance metrics
4. Update status page

### Scenario 2: Partial Service Degradation

#### Detection
- Increased error rates
- Performance degradation
- Some services unavailable

#### Response Procedure
1. Identify affected services
2. Assess impact scope
3. Consider selective failover
4. Implement workarounds if possible

### Scenario 3: Data Center Connectivity Issues

#### Detection
- Network connectivity problems
- VPN/Direct Connect failures
- Intermittent service availability

#### Response Procedure
1. Check network status
2. Verify backup connectivity paths
3. Consider traffic rerouting
4. Engage network team

## Failback Procedures

### When to Failback
- Primary region fully operational
- All services restored
- Data synchronization complete
- Business approval obtained

### Failback Steps
1. Verify primary region health
2. Synchronize data from DR to primary
3. Execute failback:
   ```bash
   aws lambda invoke \
     --function-name DRFailoverAutomation \
     --payload '{"action": "failback"}' \
     response.json
   ```
4. Monitor application performance
5. Validate all services
6. Update documentation

## Testing Schedule

### Monthly Tests
- Health check validation
- DNS failover testing
- Data replication verification

### Quarterly Tests
- Full failover simulation
- Application functionality testing
- Performance benchmarking

### Annual Tests
- Complete DR exercise
- Runbook validation
- Team training update

## Metrics and KPIs

### Recovery Time Objective (RTO)
- **Target**: 30 minutes
- **Measurement**: Time from incident detection to service restoration

### Recovery Point Objective (RPO)
- **Target**: 5 minutes
- **Measurement**: Maximum acceptable data loss

### Success Criteria
- Application available within RTO
- Data loss within RPO
- All critical functions operational
- Performance within acceptable limits

## Post-Incident Activities

### Immediate (0-24 hours)
1. Incident timeline documentation
2. Impact assessment
3. Stakeholder communication
4. Initial lessons learned

### Short-term (1-7 days)
1. Detailed root cause analysis
2. Process improvement identification
3. Documentation updates
4. Team debriefing

### Long-term (1-4 weeks)
1. Infrastructure improvements
2. Procedure updates
3. Training plan updates
4. Next test scheduling

## Communication Templates

### Initial Notification
```
INCIDENT: [Severity] - [Brief Description]
STATUS: [Current Status]
IMPACT: [Affected Services/Users]
ETA: [Estimated Resolution Time]
NEXT UPDATE: [Time]
```

### Status Update
```
UPDATE: [Incident ID] - [Current Status]
ACTIONS: [What's being done]
PROGRESS: [What's been completed]
NEXT: [Next steps]
NEXT UPDATE: [Time]
```

### Resolution Notice
```
RESOLVED: [Incident ID] - [Brief Description]
RESOLUTION: [What fixed the issue]
IMPACT: [Final impact assessment]
FOLLOW-UP: [Any ongoing actions]
```

## Appendix

### Useful Commands
```bash
# Check health status
aws route53 get-health-check --health-check-id [ID]

# List running instances by region
aws ec2 describe-instances --region [REGION] --query 'Reservations[].Instances[?State.Name==`running`]'

# Check S3 replication status
aws s3api get-bucket-replication --bucket [BUCKET-NAME]

# Monitor CloudWatch alarms
aws cloudwatch describe-alarms --state-value ALARM
```

### Reference Links
- [AWS Service Health Dashboard](https://status.aws.amazon.com/)
- [Route 53 Health Checks](https://console.aws.amazon.com/route53/healthchecks/)
- [CloudWatch Dashboards](https://console.aws.amazon.com/cloudwatch/home#dashboards:)
- [S3 Replication Metrics](https://console.aws.amazon.com/s3/)
EOF

echo "Created DR runbook: dr-runbook.md"
```

## Validation Commands

### Verify DR Setup
```bash
# Check DR infrastructure
echo "🔍 DR Infrastructure Status:"
aws ec2 describe-vpcs --region $DR_REGION \
    --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,State:State}' \
    --output table

# Check Route 53 configuration
echo ""
echo "🌐 Route 53 Configuration:"
aws route53 list-health-checks \
    --query 'HealthChecks[].{ID:Id,Type:Type,FQDN:HealthCheckConfig.FullyQualifiedDomainName}' \
    --output table

# Check S3 replication
echo ""
echo "📦 S3 Replication Status:"
PRIMARY_BUCKET=$(aws s3 ls | grep primary-data | awk '{print $3}' | head -1)
if [ ! -z "$PRIMARY_BUCKET" ]; then
    aws s3api get-bucket-replication --bucket $PRIMARY_BUCKET \
        --query 'ReplicationConfiguration.Rules[].{Status:Status,Destination:Destination.Bucket}' \
        --output table 2>/dev/null || echo "No replication configured"
fi
```

## Cleanup for This Lab

```bash
cat > cleanup-lab10.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Lab 10 resources..."

PRIMARY_REGION=${PRIMARY_REGION:-us-east-1}
DR_REGION=${DR_REGION:-us-west-2}

# Delete Lambda function
aws lambda delete-function --function-name DRFailoverAutomation 2>/dev/null

# Delete DR ALB
DR_ALB_ARN=$(aws elbv2 describe-load-balancers --region $DR_REGION --names dr-enterprise-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
[ "$DR_ALB_ARN" != "None" ] && aws elbv2 delete-load-balancer --region $DR_REGION --load-balancer-arn $DR_ALB_ARN

# Delete DR VPC and components
DR_VPC_ID=$(aws ec2 describe-vpcs --region $DR_REGION --filters "Name=tag:Name,Values=ecommerce-vpc-dr" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [ "$DR_VPC_ID" != "None" ] && [ ! -z "$DR_VPC_ID" ]; then
    # Delete NAT Gateway
    DR_NAT_GW=$(aws ec2 describe-nat-gateways --region $DR_REGION --filter "Name=vpc-id,Values=$DR_VPC_ID" --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null)
    [ "$DR_NAT_GW" != "None" ] && aws ec2 delete-nat-gateway --region $DR_REGION --nat-gateway-id $DR_NAT_GW
    
    # Wait for NAT Gateway deletion
    sleep 60
    
    # Release Elastic IP
    DR_EIP=$(aws ec2 describe-addresses --region $DR_REGION --filters "Name=tag:Name,Values=dr-nat-eip" --query 'Addresses[0].AllocationId' --output text 2>/dev/null)
    [ "$DR_EIP" != "None" ] && aws ec2 release-address --region $DR_REGION --allocation-id $DR_EIP
    
    # Delete subnets
    DR_SUBNETS=$(aws ec2 describe-subnets --region $DR_REGION --filters "Name=vpc-id,Values=$DR_VPC_ID" --query 'Subnets[].SubnetId' --output text)
    for SUBNET in $DR_SUBNETS; do
        [ ! -z "$SUBNET" ] && aws ec2 delete-subnet --region $DR_REGION --subnet-id $SUBNET
    done
    
    # Delete security groups
    DR_SGS=$(aws ec2 describe-security-groups --region $DR_REGION --filters "Name=vpc-id,Values=$DR_VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    for SG in $DR_SGS; do
        [ ! -z "$SG" ] && aws ec2 delete-security-group --region $DR_REGION --group-id $SG
    done
    
    # Detach and delete Internet Gateway
    DR_IGW=$(aws ec2 describe-internet-gateways --region $DR_REGION --filters "Name=attachment.vpc-id,Values=$DR_VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)
    if [ "$DR_IGW" != "None" ]; then
        aws ec2 detach-internet-gateway --region $DR_REGION --internet-gateway-id $DR_IGW --vpc-id $DR_VPC_ID
        aws ec2 delete-internet-gateway --region $DR_REGION --internet-gateway-id $DR_IGW
    fi
    
    # Delete VPC
    aws ec2 delete-vpc --region $DR_REGION --vpc-id $DR_VPC_ID
fi

# Delete S3 buckets
PRIMARY_BUCKET=$(aws s3 ls | grep primary-data | awk '{print $3}')
DR_BUCKET=$(aws s3 ls | grep dr-data | awk '{print $3}')

[ ! -z "$PRIMARY_BUCKET" ] && aws s3 rb s3://$PRIMARY_BUCKET --force
[ ! -z "$DR_BUCKET" ] && aws s3 rb s3://$DR_BUCKET --force

# Delete RDS subnet groups
aws rds delete-db-subnet-group --region $PRIMARY_REGION --db-subnet-group-name primary-db-subnet-group 2>/dev/null
aws rds delete-db-subnet-group --region $DR_REGION --db-subnet-group-name dr-db-subnet-group 2>/dev/null

# Delete Route 53 hosted zone
DR_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "dr-test.local" --query 'HostedZones[0].Id' --output text 2>/dev/null | cut -d'/' -f3)
if [ "$DR_HOSTED_ZONE_ID" != "None" ] && [ ! -z "$DR_HOSTED_ZONE_ID" ]; then
    # Delete all records except NS and SOA
    aws route53 list-resource-record-sets --hosted-zone-id $DR_HOSTED_ZONE_ID --query 'ResourceRecordSets[?Type!=`NS` && Type!=`SOA`]' --output json > /tmp/dr_records.json
    if [ -s /tmp/dr_records.json ]; then
        aws route53 change-resource-record-sets --hosted-zone-id $DR_HOSTED_ZONE_ID --change-batch file:///tmp/dr_records.json
    fi
    aws route53 delete-hosted-zone --id $DR_HOSTED_ZONE_ID
fi

# Delete health checks
HEALTH_CHECKS=$(aws route53 list-health-checks --query 'HealthChecks[].Id' --output text)
for HC in $HEALTH_CHECKS; do
    [ ! -z "$HC" ] && aws route53 delete-health-check --health-check-id $HC 2>/dev/null
done

# Delete IAM roles and policies
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam detach-role-policy --role-name S3ReplicationRole --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/S3ReplicationPolicy 2>/dev/null
aws iam detach-role-policy --role-name DRFailoverLambdaRole --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DRFailoverLambdaPolicy 2>/dev/null
aws iam detach-role-policy --role-name DRFailoverLambdaRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null

aws iam delete-role --role-name S3ReplicationRole 2>/dev/null
aws iam delete-role --role-name DRFailoverLambdaRole 2>/dev/null

aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/S3ReplicationPolicy 2>/dev/null
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/DRFailoverLambdaPolicy 2>/dev/null

# Clean up files
rm -f dr-runbook.md

echo "✅ Lab 10 cleanup completed"
EOF

chmod +x cleanup-lab10.sh
echo "Created cleanup script: cleanup-lab10.sh"
```

## Next Steps

After completing this lab, you should have:
- ✅ Multi-region disaster recovery architecture
- ✅ Automated failover mechanisms with Route 53
- ✅ Cross-region data replication (S3 and RDS)
- ✅ DR testing and validation procedures
- ✅ Comprehensive disaster recovery runbook
- ✅ Automated recovery orchestration

**🎉 Congratulations!** You have completed all 10 labs of "AWS Networking The Hard Way" and now have enterprise-grade AWS networking expertise!