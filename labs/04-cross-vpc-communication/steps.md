# Lab 04: Cross-VPC Communication - Detailed Steps

## Prerequisites
- Completed Labs 01-03
- Understanding of VPC networking concepts
- AWS CLI configured with appropriate permissions

```bash
# Set environment variables from previous labs
export PROD_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
echo "Production VPC: $PROD_VPC_ID"
```

## Step 1: Create Multiple VPCs for Different Environments

### Create Staging VPC
```bash
# Create staging VPC
aws ec2 create-vpc \
    --cidr-block 10.1.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=staging-vpc},{Key=Environment,Value=staging},{Key=Project,Value=aws-networking-hard-way}]'

STAGING_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=staging-vpc" --query 'Vpcs[0].VpcId' --output text)

# Enable DNS hostnames and support
aws ec2 modify-vpc-attribute --vpc-id $STAGING_VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $STAGING_VPC_ID --enable-dns-support

echo "Created Staging VPC: $STAGING_VPC_ID"
```

### Create Shared Services VPC
```bash
# Create shared services VPC
aws ec2 create-vpc \
    --cidr-block 10.2.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=shared-services-vpc},{Key=Environment,Value=shared},{Key=Project,Value=aws-networking-hard-way}]'

SHARED_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=shared-services-vpc" --query 'Vpcs[0].VpcId' --output text)

# Enable DNS hostnames and support
aws ec2 modify-vpc-attribute --vpc-id $SHARED_VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $SHARED_VPC_ID --enable-dns-support

echo "Created Shared Services VPC: $SHARED_VPC_ID"
```

### Create Partner VPC
```bash
# Create partner VPC (simulating third-party integration)
aws ec2 create-vpc \
    --cidr-block 10.3.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=partner-vpc},{Key=Environment,Value=partner},{Key=Project,Value=aws-networking-hard-way}]'

PARTNER_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=partner-vpc" --query 'Vpcs[0].VpcId' --output text)

# Enable DNS hostnames and support
aws ec2 modify-vpc-attribute --vpc-id $PARTNER_VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $PARTNER_VPC_ID --enable-dns-support

echo "Created Partner VPC: $PARTNER_VPC_ID"
```

### Create Subnets in New VPCs
```bash
# Staging VPC subnets
aws ec2 create-subnet \
    --vpc-id $STAGING_VPC_ID \
    --cidr-block 10.1.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=staging-subnet-1a},{Key=Environment,Value=staging}]'

aws ec2 create-subnet \
    --vpc-id $STAGING_VPC_ID \
    --cidr-block 10.1.2.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=staging-subnet-1b},{Key=Environment,Value=staging}]'

# Shared Services VPC subnets
aws ec2 create-subnet \
    --vpc-id $SHARED_VPC_ID \
    --cidr-block 10.2.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=shared-subnet-1a},{Key=Environment,Value=shared}]'

aws ec2 create-subnet \
    --vpc-id $SHARED_VPC_ID \
    --cidr-block 10.2.2.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=shared-subnet-1b},{Key=Environment,Value=shared}]'

# Partner VPC subnets
aws ec2 create-subnet \
    --vpc-id $PARTNER_VPC_ID \
    --cidr-block 10.3.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=partner-subnet-1a},{Key=Environment,Value=partner}]'

echo "Created subnets in all VPCs"
```

## Step 2: Implement VPC Peering Connections

### Create VPC Peering Connections
```bash
# Production to Staging peering
aws ec2 create-vpc-peering-connection \
    --vpc-id $PROD_VPC_ID \
    --peer-vpc-id $STAGING_VPC_ID \
    --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=prod-to-staging-peering},{Key=Project,Value=aws-networking-hard-way}]'

PROD_STAGING_PEER_ID=$(aws ec2 describe-vpc-peering-connections \
    --filters "Name=tag:Name,Values=prod-to-staging-peering" \
    --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' \
    --output text)

# Accept the peering connection
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PROD_STAGING_PEER_ID

# Production to Shared Services peering
aws ec2 create-vpc-peering-connection \
    --vpc-id $PROD_VPC_ID \
    --peer-vpc-id $SHARED_VPC_ID \
    --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=prod-to-shared-peering},{Key=Project,Value=aws-networking-hard-way}]'

PROD_SHARED_PEER_ID=$(aws ec2 describe-vpc-peering-connections \
    --filters "Name=tag:Name,Values=prod-to-shared-peering" \
    --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' \
    --output text)

aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $PROD_SHARED_PEER_ID

# Staging to Shared Services peering
aws ec2 create-vpc-peering-connection \
    --vpc-id $STAGING_VPC_ID \
    --peer-vpc-id $SHARED_VPC_ID \
    --tag-specifications 'ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=staging-to-shared-peering},{Key=Project,Value=aws-networking-hard-way}]'

STAGING_SHARED_PEER_ID=$(aws ec2 describe-vpc-peering-connections \
    --filters "Name=tag:Name,Values=staging-to-shared-peering" \
    --query 'VpcPeeringConnections[0].VpcPeeringConnectionId' \
    --output text)

aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $STAGING_SHARED_PEER_ID

echo "Created and accepted VPC peering connections"
```

### Configure Route Tables for Peering
```bash
# Get route table IDs
PROD_RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$PROD_VPC_ID" "Name=tag:Name,Values=private-rt-1a" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

# Create route tables for new VPCs
aws ec2 create-route-table \
    --vpc-id $STAGING_VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=staging-rt},{Key=Environment,Value=staging}]'

STAGING_RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=staging-rt" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

aws ec2 create-route-table \
    --vpc-id $SHARED_VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=shared-rt},{Key=Environment,Value=shared}]'

SHARED_RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=shared-rt" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

# Add peering routes - Production VPC
aws ec2 create-route \
    --route-table-id $PROD_RT_ID \
    --destination-cidr-block 10.1.0.0/16 \
    --vpc-peering-connection-id $PROD_STAGING_PEER_ID

aws ec2 create-route \
    --route-table-id $PROD_RT_ID \
    --destination-cidr-block 10.2.0.0/16 \
    --vpc-peering-connection-id $PROD_SHARED_PEER_ID

# Add peering routes - Staging VPC
aws ec2 create-route \
    --route-table-id $STAGING_RT_ID \
    --destination-cidr-block 10.0.0.0/16 \
    --vpc-peering-connection-id $PROD_STAGING_PEER_ID

aws ec2 create-route \
    --route-table-id $STAGING_RT_ID \
    --destination-cidr-block 10.2.0.0/16 \
    --vpc-peering-connection-id $STAGING_SHARED_PEER_ID

# Add peering routes - Shared Services VPC
aws ec2 create-route \
    --route-table-id $SHARED_RT_ID \
    --destination-cidr-block 10.0.0.0/16 \
    --vpc-peering-connection-id $PROD_SHARED_PEER_ID

aws ec2 create-route \
    --route-table-id $SHARED_RT_ID \
    --destination-cidr-block 10.1.0.0/16 \
    --vpc-peering-connection-id $STAGING_SHARED_PEER_ID

# Associate route tables with subnets
STAGING_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=staging-subnet-1a" --query 'Subnets[0].SubnetId' --output text)
SHARED_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=shared-subnet-1a" --query 'Subnets[0].SubnetId' --output text)

aws ec2 associate-route-table --route-table-id $STAGING_RT_ID --subnet-id $STAGING_SUBNET_1A
aws ec2 associate-route-table --route-table-id $SHARED_RT_ID --subnet-id $SHARED_SUBNET_1A

echo "Configured routing for VPC peering"
```

## Step 3: Deploy Transit Gateway

### Create Transit Gateway
```bash
# Create Transit Gateway
aws ec2 create-transit-gateway \
    --description "Enterprise Transit Gateway for multi-VPC connectivity" \
    --options AmazonSideAsn=64512,AutoAcceptSharedAttachments=enable,DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable \
    --tag-specifications 'ResourceType=transit-gateway,Tags=[{Key=Name,Value=enterprise-tgw},{Key=Project,Value=aws-networking-hard-way}]'

# Wait for Transit Gateway to be available
TGW_ID=$(aws ec2 describe-transit-gateways \
    --filters "Name=tag:Name,Values=enterprise-tgw" \
    --query 'TransitGateways[0].TransitGatewayId' \
    --output text)

echo "Waiting for Transit Gateway to become available..."
aws ec2 wait transit-gateway-available --transit-gateway-ids $TGW_ID

echo "Created Transit Gateway: $TGW_ID"
```

### Create Transit Gateway Attachments
```bash
# Attach Production VPC
aws ec2 create-transit-gateway-vpc-attachment \
    --transit-gateway-id $TGW_ID \
    --vpc-id $PROD_VPC_ID \
    --subnet-ids $(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-app-1a" --query 'Subnets[0].SubnetId' --output text) \
    --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=prod-tgw-attachment},{Key=Environment,Value=production}]'

# Attach Staging VPC
aws ec2 create-transit-gateway-vpc-attachment \
    --transit-gateway-id $TGW_ID \
    --vpc-id $STAGING_VPC_ID \
    --subnet-ids $STAGING_SUBNET_1A \
    --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=staging-tgw-attachment},{Key=Environment,Value=staging}]'

# Attach Shared Services VPC
aws ec2 create-transit-gateway-vpc-attachment \
    --transit-gateway-id $TGW_ID \
    --vpc-id $SHARED_VPC_ID \
    --subnet-ids $SHARED_SUBNET_1A \
    --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=shared-tgw-attachment},{Key=Environment,Value=shared}]'

# Attach Partner VPC
aws ec2 create-transit-gateway-vpc-attachment \
    --transit-gateway-id $TGW_ID \
    --vpc-id $PARTNER_VPC_ID \
    --subnet-ids $(aws ec2 describe-subnets --filters "Name=tag:Name,Values=partner-subnet-1a" --query 'Subnets[0].SubnetId' --output text) \
    --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=partner-tgw-attachment},{Key=Environment,Value=partner}]'

echo "Created Transit Gateway attachments for all VPCs"

# Wait for attachments to be available
echo "Waiting for attachments to become available..."
sleep 60
```

### Configure Transit Gateway Route Tables
```bash
# Create custom route table for production isolation
aws ec2 create-transit-gateway-route-table \
    --transit-gateway-id $TGW_ID \
    --tag-specifications 'ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=production-tgw-rt},{Key=Environment,Value=production}]'

PROD_TGW_RT_ID=$(aws ec2 describe-transit-gateway-route-tables \
    --filters "Name=tag:Name,Values=production-tgw-rt" \
    --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
    --output text)

# Create route table for non-production environments
aws ec2 create-transit-gateway-route-table \
    --transit-gateway-id $TGW_ID \
    --tag-specifications 'ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=non-prod-tgw-rt},{Key=Environment,Value=non-production}]'

NON_PROD_TGW_RT_ID=$(aws ec2 describe-transit-gateway-route-tables \
    --filters "Name=tag:Name,Values=non-prod-tgw-rt" \
    --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
    --output text)

# Get attachment IDs
PROD_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments \
    --filters "Name=tag:Name,Values=prod-tgw-attachment" \
    --query 'TransitGatewayAttachments[0].TransitGatewayAttachmentId' \
    --output text)

STAGING_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments \
    --filters "Name=tag:Name,Values=staging-tgw-attachment" \
    --query 'TransitGatewayAttachments[0].TransitGatewayAttachmentId' \
    --output text)

SHARED_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments \
    --filters "Name=tag:Name,Values=shared-tgw-attachment" \
    --query 'TransitGatewayAttachments[0].TransitGatewayAttachmentId' \
    --output text)

PARTNER_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments \
    --filters "Name=tag:Name,Values=partner-tgw-attachment" \
    --query 'TransitGatewayAttachments[0].TransitGatewayAttachmentId' \
    --output text)

# Associate attachments with route tables
aws ec2 associate-transit-gateway-route-table \
    --transit-gateway-attachment-id $PROD_ATTACHMENT_ID \
    --transit-gateway-route-table-id $PROD_TGW_RT_ID

aws ec2 associate-transit-gateway-route-table \
    --transit-gateway-attachment-id $STAGING_ATTACHMENT_ID \
    --transit-gateway-route-table-id $NON_PROD_TGW_RT_ID

aws ec2 associate-transit-gateway-route-table \
    --transit-gateway-attachment-id $PARTNER_ATTACHMENT_ID \
    --transit-gateway-route-table-id $NON_PROD_TGW_RT_ID

# Shared services can communicate with all environments
aws ec2 associate-transit-gateway-route-table \
    --transit-gateway-attachment-id $SHARED_ATTACHMENT_ID \
    --transit-gateway-route-table-id $PROD_TGW_RT_ID

echo "Configured Transit Gateway route tables"
```

### Add Transit Gateway Routes to VPC Route Tables
```bash
# Add TGW routes to Production VPC
aws ec2 create-route \
    --route-table-id $PROD_RT_ID \
    --destination-cidr-block 10.2.0.0/16 \
    --transit-gateway-id $TGW_ID

# Add TGW routes to Staging VPC
aws ec2 create-route \
    --route-table-id $STAGING_RT_ID \
    --destination-cidr-block 10.2.0.0/16 \
    --transit-gateway-id $TGW_ID

aws ec2 create-route \
    --route-table-id $STAGING_RT_ID \
    --destination-cidr-block 10.3.0.0/16 \
    --transit-gateway-id $TGW_ID

# Add TGW routes to Shared Services VPC
aws ec2 create-route \
    --route-table-id $SHARED_RT_ID \
    --destination-cidr-block 10.0.0.0/16 \
    --transit-gateway-id $TGW_ID

aws ec2 create-route \
    --route-table-id $SHARED_RT_ID \
    --destination-cidr-block 10.1.0.0/16 \
    --transit-gateway-id $TGW_ID

aws ec2 create-route \
    --route-table-id $SHARED_RT_ID \
    --destination-cidr-block 10.3.0.0/16 \
    --transit-gateway-id $TGW_ID

# Create and configure Partner VPC route table
aws ec2 create-route-table \
    --vpc-id $PARTNER_VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=partner-rt},{Key=Environment,Value=partner}]'

PARTNER_RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=partner-rt" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

PARTNER_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=partner-subnet-1a" --query 'Subnets[0].SubnetId' --output text)

aws ec2 associate-route-table --route-table-id $PARTNER_RT_ID --subnet-id $PARTNER_SUBNET_1A

# Add TGW routes to Partner VPC (limited access)
aws ec2 create-route \
    --route-table-id $PARTNER_RT_ID \
    --destination-cidr-block 10.2.0.0/16 \
    --transit-gateway-id $TGW_ID

echo "Added Transit Gateway routes to VPC route tables"
```

## Step 4: Configure VPC Endpoints (PrivateLink)

### Create VPC Endpoint for S3
```bash
# Create S3 VPC Endpoint in Production VPC
aws ec2 create-vpc-endpoint \
    --vpc-id $PROD_VPC_ID \
    --service-name com.amazonaws.us-east-1.s3 \
    --vpc-endpoint-type Gateway \
    --route-table-ids $PROD_RT_ID \
    --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=prod-s3-endpoint},{Key=Service,Value=s3}]'

# Create S3 VPC Endpoint in Shared Services VPC
aws ec2 create-vpc-endpoint \
    --vpc-id $SHARED_VPC_ID \
    --service-name com.amazonaws.us-east-1.s3 \
    --vpc-endpoint-type Gateway \
    --route-table-ids $SHARED_RT_ID \
    --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=shared-s3-endpoint},{Key=Service,Value=s3}]'

echo "Created S3 VPC Endpoints"
```

### Create Interface VPC Endpoints
```bash
# Create security group for VPC endpoints
aws ec2 create-security-group \
    --group-name vpc-endpoint-sg \
    --description "Security group for VPC endpoints" \
    --vpc-id $SHARED_VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=vpc-endpoint-sg},{Key=Purpose,Value=endpoints}]'

ENDPOINT_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=vpc-endpoint-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow HTTPS from all VPCs
aws ec2 authorize-security-group-ingress \
    --group-id $ENDPOINT_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 10.0.0.0/8

# Create EC2 VPC Endpoint
aws ec2 create-vpc-endpoint \
    --vpc-id $SHARED_VPC_ID \
    --service-name com.amazonaws.us-east-1.ec2 \
    --vpc-endpoint-type Interface \
    --subnet-ids $SHARED_SUBNET_1A \
    --security-group-ids $ENDPOINT_SG_ID \
    --private-dns-enabled \
    --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=shared-ec2-endpoint},{Key=Service,Value=ec2}]'

# Create SSM VPC Endpoint for Session Manager
aws ec2 create-vpc-endpoint \
    --vpc-id $SHARED_VPC_ID \
    --service-name com.amazonaws.us-east-1.ssm \
    --vpc-endpoint-type Interface \
    --subnet-ids $SHARED_SUBNET_1A \
    --security-group-ids $ENDPOINT_SG_ID \
    --private-dns-enabled \
    --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=shared-ssm-endpoint},{Key=Service,Value=ssm}]'

echo "Created Interface VPC Endpoints"
```

## Step 5: Deploy Test Infrastructure

### Create Security Groups for Cross-VPC Communication
```bash
# Create security group for shared services
aws ec2 create-security-group \
    --group-name shared-services-sg \
    --description "Security group for shared services" \
    --vpc-id $SHARED_VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=shared-services-sg},{Key=Environment,Value=shared}]'

SHARED_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=shared-services-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow access from all connected VPCs
aws ec2 authorize-security-group-ingress \
    --group-id $SHARED_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 10.0.0.0/8

aws ec2 authorize-security-group-ingress \
    --group-id $SHARED_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 10.0.0.0/8

# Create security group for staging
aws ec2 create-security-group \
    --group-name staging-sg \
    --description "Security group for staging environment" \
    --vpc-id $STAGING_VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=staging-sg},{Key=Environment,Value=staging}]'

STAGING_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=staging-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

aws ec2 authorize-security-group-ingress \
    --group-id $STAGING_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 10.0.0.0/8

aws ec2 authorize-security-group-ingress \
    --group-id $STAGING_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 10.0.0.0/8

# Create security group for partner
aws ec2 create-security-group \
    --group-name partner-sg \
    --description "Security group for partner environment" \
    --vpc-id $PARTNER_VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=partner-sg},{Key=Environment,Value=partner}]'

PARTNER_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=partner-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

aws ec2 authorize-security-group-ingress \
    --group-id $PARTNER_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 10.2.0.0/16

aws ec2 authorize-security-group-ingress \
    --group-id $PARTNER_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 10.2.0.0/16

echo "Created security groups for cross-VPC communication"
```

### Deploy Test Instances
```bash
# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

# Create key pair if it doesn't exist
aws ec2 create-key-pair \
    --key-name cross-vpc-key \
    --query 'KeyMaterial' \
    --output text > cross-vpc-key.pem 2>/dev/null || echo "Key pair already exists"

chmod 400 cross-vpc-key.pem 2>/dev/null

# Deploy shared services instance (DNS, monitoring, etc.)
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name cross-vpc-key \
    --subnet-id $SHARED_SUBNET_1A \
    --security-group-ids $SHARED_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=shared-services-server},{Key=Environment,Value=shared},{Key=Role,Value=dns-monitoring}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y httpd bind-utils tcpdump
systemctl start httpd
systemctl enable httpd
echo "<h1>Shared Services Server</h1>" > /var/www/html/index.html
echo "<p>Environment: Shared Services</p>" >> /var/www/html/index.html
echo "<p>Services: DNS, Monitoring, Logging</p>" >> /var/www/html/index.html
echo "<p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html'

# Deploy staging instance
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name cross-vpc-key \
    --subnet-id $STAGING_SUBNET_1A \
    --security-group-ids $STAGING_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=staging-app-server},{Key=Environment,Value=staging},{Key=Role,Value=application}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y httpd bind-utils tcpdump
systemctl start httpd
systemctl enable httpd
echo "<h1>Staging Application Server</h1>" > /var/www/html/index.html
echo "<p>Environment: Staging</p>" >> /var/www/html/index.html
echo "<p>Role: Application Testing</p>" >> /var/www/html/index.html
echo "<p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html'

# Deploy partner instance
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name cross-vpc-key \
    --subnet-id $PARTNER_SUBNET_1A \
    --security-group-ids $PARTNER_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=partner-integration-server},{Key=Environment,Value=partner},{Key=Role,Value=integration}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y httpd bind-utils tcpdump
systemctl start httpd
systemctl enable httpd
echo "<h1>Partner Integration Server</h1>" > /var/www/html/index.html
echo "<p>Environment: Partner</p>" >> /var/www/html/index.html
echo "<p>Role: Third-party Integration</p>" >> /var/www/html/index.html
echo "<p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html'

echo "Deployed test instances in all VPCs"
```

## Step 6: Test Cross-VPC Communication

### Create Comprehensive Connectivity Test
```bash
cat > test-cross-vpc-connectivity.sh << 'EOF'
#!/bin/bash

echo "🌐 Testing Cross-VPC Communication"
echo "=================================="

# Get instance IPs
PROD_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=app-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "N/A")
STAGING_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=staging-app-server" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "N/A")
SHARED_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=shared-services-server" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "N/A")
PARTNER_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=partner-integration-server" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "N/A")

echo "Instance IPs:"
echo "  Production: $PROD_IP"
echo "  Staging: $STAGING_IP"
echo "  Shared Services: $SHARED_IP"
echo "  Partner: $PARTNER_IP"
echo ""

# Test 1: VPC Peering Connectivity
echo "Test 1: VPC Peering Connectivity"
echo "--------------------------------"

if [ "$PROD_IP" != "N/A" ] && [ "$STAGING_IP" != "N/A" ]; then
    # Test production to staging via peering
    PEERING_TEST=$(timeout 10 ssh -i cross-vpc-key.pem -o StrictHostKeyChecking=no ec2-user@$PROD_IP "curl -s --max-time 5 http://$STAGING_IP" 2>/dev/null | grep "Staging" || echo "FAILED")
    if [[ $PEERING_TEST == *"Staging"* ]]; then
        echo "✅ PASS: Production can reach Staging via VPC Peering"
    else
        echo "❌ FAIL: Production cannot reach Staging via VPC Peering"
    fi
else
    echo "⚠️  SKIP: Production or Staging instance not available"
fi

# Test 2: Transit Gateway Connectivity
echo ""
echo "Test 2: Transit Gateway Connectivity"
echo "-----------------------------------"

if [ "$STAGING_IP" != "N/A" ] && [ "$SHARED_IP" != "N/A" ]; then
    TGW_TEST=$(timeout 10 ssh -i cross-vpc-key.pem -o StrictHostKeyChecking=no ec2-user@$STAGING_IP "curl -s --max-time 5 http://$SHARED_IP" 2>/dev/null | grep "Shared Services" || echo "FAILED")
    if [[ $TGW_TEST == *"Shared Services"* ]]; then
        echo "✅ PASS: Staging can reach Shared Services via Transit Gateway"
    else
        echo "❌ FAIL: Staging cannot reach Shared Services via Transit Gateway"
    fi
else
    echo "⚠️  SKIP: Staging or Shared Services instance not available"
fi

# Test 3: Partner Access (Limited)
echo ""
echo "Test 3: Partner Access Control"
echo "-----------------------------"

if [ "$PARTNER_IP" != "N/A" ] && [ "$SHARED_IP" != "N/A" ]; then
    PARTNER_TEST=$(timeout 10 ssh -i cross-vpc-key.pem -o StrictHostKeyChecking=no ec2-user@$PARTNER_IP "curl -s --max-time 5 http://$SHARED_IP" 2>/dev/null | grep "Shared Services" || echo "FAILED")
    if [[ $PARTNER_TEST == *"Shared Services"* ]]; then
        echo "✅ PASS: Partner can reach Shared Services"
    else
        echo "❌ FAIL: Partner cannot reach Shared Services"
    fi
    
    # Test that partner cannot reach production directly
    if [ "$PROD_IP" != "N/A" ]; then
        PARTNER_PROD_TEST=$(timeout 5 ssh -i cross-vpc-key.pem -o StrictHostKeyChecking=no ec2-user@$PARTNER_IP "curl -s --max-time 3 http://$PROD_IP" 2>/dev/null || echo "BLOCKED")
        if [ "$PARTNER_PROD_TEST" = "BLOCKED" ]; then
            echo "✅ PASS: Partner correctly blocked from Production"
        else
            echo "❌ FAIL: Partner can access Production (security issue!)"
        fi
    fi
else
    echo "⚠️  SKIP: Partner or Shared Services instance not available"
fi

# Test 4: DNS Resolution
echo ""
echo "Test 4: DNS Resolution"
echo "---------------------"

if [ "$SHARED_IP" != "N/A" ]; then
    DNS_TEST=$(timeout 10 ssh -i cross-vpc-key.pem -o StrictHostKeyChecking=no ec2-user@$SHARED_IP "nslookup ec2.amazonaws.com" 2>/dev/null | grep "Address" || echo "FAILED")
    if [[ $DNS_TEST == *"Address"* ]]; then
        echo "✅ PASS: DNS resolution working via VPC endpoints"
    else
        echo "❌ FAIL: DNS resolution not working"
    fi
else
    echo "⚠️  SKIP: Shared Services instance not available"
fi

echo ""
echo "🎯 Cross-VPC Communication Test Complete"
EOF

chmod +x test-cross-vpc-connectivity.sh
echo "Created cross-VPC connectivity test: test-cross-vpc-connectivity.sh"
```

### Create Route Analysis Tool
```bash
cat > analyze-routes.sh << 'EOF'
#!/bin/bash

echo "🗺️  Cross-VPC Route Analysis"
echo "============================"

# Get VPC IDs
PROD_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
STAGING_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=staging-vpc" --query 'Vpcs[0].VpcId' --output text)
SHARED_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=shared-services-vpc" --query 'Vpcs[0].VpcId' --output text)
PARTNER_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=partner-vpc" --query 'Vpcs[0].VpcId' --output text)

echo "VPC Summary:"
echo "  Production: $PROD_VPC_ID (10.0.0.0/16)"
echo "  Staging: $STAGING_VPC_ID (10.1.0.0/16)"
echo "  Shared Services: $SHARED_VPC_ID (10.2.0.0/16)"
echo "  Partner: $PARTNER_VPC_ID (10.3.0.0/16)"
echo ""

# Analyze VPC Peering Connections
echo "VPC Peering Connections:"
echo "-----------------------"
aws ec2 describe-vpc-peering-connections \
    --filters "Name=status-code,Values=active" \
    --query 'VpcPeeringConnections[].{ID:VpcPeeringConnectionId,Requester:RequesterVpcInfo.CidrBlock,Accepter:AccepterVpcInfo.CidrBlock,Status:Status.Code}' \
    --output table

# Analyze Transit Gateway
echo ""
echo "Transit Gateway Attachments:"
echo "---------------------------"
TGW_ID=$(aws ec2 describe-transit-gateways --filters "Name=tag:Name,Values=enterprise-tgw" --query 'TransitGateways[0].TransitGatewayId' --output text)

if [ "$TGW_ID" != "None" ]; then
    aws ec2 describe-transit-gateway-attachments \
        --filters "Name=transit-gateway-id,Values=$TGW_ID" \
        --query 'TransitGatewayAttachments[].{VPC:ResourceId,State:State,Type:ResourceType}' \
        --output table
else
    echo "No Transit Gateway found"
fi

# Analyze VPC Endpoints
echo ""
echo "VPC Endpoints:"
echo "-------------"
aws ec2 describe-vpc-endpoints \
    --query 'VpcEndpoints[].{VPC:VpcId,Service:ServiceName,Type:VpcEndpointType,State:State}' \
    --output table

# Route Table Analysis
echo ""
echo "Route Table Analysis:"
echo "--------------------"

for VPC_ID in $PROD_VPC_ID $STAGING_VPC_ID $SHARED_VPC_ID $PARTNER_VPC_ID; do
    VPC_NAME=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text)
    echo ""
    echo "Routes in $VPC_NAME ($VPC_ID):"
    aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'RouteTables[].Routes[?State==`active`].{Destination:DestinationCidrBlock,Target:GatewayId,TGW:TransitGatewayId,Peering:VpcPeeringConnectionId}' \
        --output table | head -20
done

echo ""
echo "🎯 Route Analysis Complete"
EOF

chmod +x analyze-routes.sh
echo "Created route analysis tool: analyze-routes.sh"
```

## Validation Commands

### Verify Cross-VPC Setup
```bash
# Check VPC Peering Status
echo "🔍 VPC Peering Status:"
aws ec2 describe-vpc-peering-connections \
    --filters "Name=status-code,Values=active" \
    --query 'VpcPeeringConnections[].{ID:VpcPeeringConnectionId,Status:Status.Code,Requester:RequesterVpcInfo.CidrBlock,Accepter:AccepterVpcInfo.CidrBlock}' \
    --output table

# Check Transit Gateway Status
echo ""
echo "🚇 Transit Gateway Status:"
TGW_ID=$(aws ec2 describe-transit-gateways --filters "Name=tag:Name,Values=enterprise-tgw" --query 'TransitGateways[0].TransitGatewayId' --output text)
aws ec2 describe-transit-gateway-attachments \
    --filters "Name=transit-gateway-id,Values=$TGW_ID" \
    --query 'TransitGatewayAttachments[].{VPC:ResourceId,State:State,RouteTable:Association.TransitGatewayRouteTableId}' \
    --output table

# Check VPC Endpoints
echo ""
echo "🔗 VPC Endpoints Status:"
aws ec2 describe-vpc-endpoints \
    --query 'VpcEndpoints[].{Service:ServiceName,VPC:VpcId,Type:VpcEndpointType,State:State}' \
    --output table
```

## Cleanup for This Lab

```bash
cat > cleanup-lab04.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Lab 04 resources..."

# Terminate instances in new VPCs
echo "Terminating instances..."
for VPC_NAME in staging-vpc shared-services-vpc partner-vpc; do
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text)
    if [ "$VPC_ID" != "None" ]; then
        INSTANCES=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text)
        if [ ! -z "$INSTANCES" ]; then
            aws ec2 terminate-instances --instance-ids $INSTANCES
            aws ec2 wait instance-terminated --instance-ids $INSTANCES
        fi
    fi
done

# Delete Transit Gateway attachments
echo "Deleting Transit Gateway attachments..."
TGW_ID=$(aws ec2 describe-transit-gateways --filters "Name=tag:Name,Values=enterprise-tgw" --query 'TransitGateways[0].TransitGatewayId' --output text)
if [ "$TGW_ID" != "None" ]; then
    ATTACHMENTS=$(aws ec2 describe-transit-gateway-attachments --filters "Name=transit-gateway-id,Values=$TGW_ID" --query 'TransitGatewayAttachments[].TransitGatewayAttachmentId' --output text)
    for ATTACHMENT in $ATTACHMENTS; do
        aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id $ATTACHMENT
    done
    
    # Wait for attachments to be deleted
    sleep 60
    
    # Delete custom route tables
    CUSTOM_RTS=$(aws ec2 describe-transit-gateway-route-tables --filters "Name=transit-gateway-id,Values=$TGW_ID" --query 'TransitGatewayRouteTables[?DefaultAssociationRouteTable==`false`].TransitGatewayRouteTableId' --output text)
    for RT in $CUSTOM_RTS; do
        aws ec2 delete-transit-gateway-route-table --transit-gateway-route-table-id $RT
    done
    
    # Delete Transit Gateway
    aws ec2 delete-transit-gateway --transit-gateway-id $TGW_ID
fi

# Delete VPC Peering Connections
echo "Deleting VPC Peering connections..."
PEERING_CONNECTIONS=$(aws ec2 describe-vpc-peering-connections --filters "Name=status-code,Values=active" --query 'VpcPeeringConnections[].VpcPeeringConnectionId' --output text)
for PEERING in $PEERING_CONNECTIONS; do
    aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $PEERING
done

# Delete VPC Endpoints
echo "Deleting VPC Endpoints..."
ENDPOINTS=$(aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].VpcEndpointId' --output text)
for ENDPOINT in $ENDPOINTS; do
    aws ec2 delete-vpc-endpoint --vpc-endpoint-id $ENDPOINT
done

# Delete VPCs and their components
for VPC_NAME in staging-vpc shared-services-vpc partner-vpc; do
    echo "Deleting $VPC_NAME..."
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text)
    
    if [ "$VPC_ID" != "None" ]; then
        # Delete subnets
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text)
        for SUBNET in $SUBNETS; do
            aws ec2 delete-subnet --subnet-id $SUBNET
        done
        
        # Delete route tables
        ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
        for RT in $ROUTE_TABLES; do
            aws ec2 delete-route-table --route-table-id $RT
        done
        
        # Delete security groups
        SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
        for SG in $SECURITY_GROUPS; do
            aws ec2 delete-security-group --group-id $SG
        done
        
        # Delete VPC
        aws ec2 delete-vpc --vpc-id $VPC_ID
    fi
done

# Delete key pair
aws ec2 delete-key-pair --key-name cross-vpc-key 2>/dev/null
rm -f cross-vpc-key.pem

echo "✅ Lab 04 cleanup completed"
EOF

chmod +x cleanup-lab04.sh
echo "Created cleanup script: cleanup-lab04.sh"
```

## Next Steps

After completing this lab, you should have:
- ✅ Multiple VPCs representing different environments
- ✅ VPC Peering for selective connectivity
- ✅ Transit Gateway for centralized routing
- ✅ VPC Endpoints for AWS service access
- ✅ Understanding of enterprise networking patterns

**Continue to:** [Lab 05: Hybrid Connectivity](../05-hybrid-connectivity/README.md)