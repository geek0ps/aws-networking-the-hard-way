# Lab 08: Multi-Account Networking - Detailed Steps

## Prerequisites
- Completed Labs 01-07
- Understanding of AWS Organizations
- Multiple AWS accounts or ability to simulate multi-account setup
- AWS CLI configured with appropriate permissions

```bash
# Set environment variables
export MASTER_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Master Account ID: $MASTER_ACCOUNT_ID"
```

## Step 1: Set Up AWS Organizations Structure

### Create Organizational Units
```bash
# Note: This assumes you have AWS Organizations set up
# If not, you'll need to create an organization first

# Create organizational structure
cat > create-organization-structure.sh << 'EOF'
#!/bin/bash

echo "🏢 Setting up AWS Organizations Structure"
echo "========================================"

# Get organization ID
ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text 2>/dev/null || echo "None")

if [ "$ORG_ID" = "None" ]; then
    echo "Creating AWS Organization..."
    aws organizations create-organization --feature-set ALL
    ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text)
fi

echo "Organization ID: $ORG_ID"

# Get root ID
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
echo "Root ID: $ROOT_ID"

# Create Organizational Units
echo "Creating Organizational Units..."

# Core OU
aws organizations create-organizational-unit \
    --parent-id $ROOT_ID \
    --name "Core" \
    --tags Key=Purpose,Value=core-services

CORE_OU_ID=$(aws organizations list-organizational-units-for-parent \
    --parent-id $ROOT_ID \
    --query 'OrganizationalUnits[?Name==`Core`].Id' \
    --output text)

# Production OU
aws organizations create-organizational-unit \
    --parent-id $ROOT_ID \
    --name "Production" \
    --tags Key=Environment,Value=production

PROD_OU_ID=$(aws organizations list-organizational-units-for-parent \
    --parent-id $ROOT_ID \
    --query 'OrganizationalUnits[?Name==`Production`].Id' \
    --output text)

# Non-Production OU
aws organizations create-organizational-unit \
    --parent-id $ROOT_ID \
    --name "NonProduction" \
    --tags Key=Environment,Value=non-production

NONPROD_OU_ID=$(aws organizations list-organizational-units-for-parent \
    --parent-id $ROOT_ID \
    --query 'OrganizationalUnits[?Name==`NonProduction`].Id' \
    --output text)

# Security OU
aws organizations create-organizational-unit \
    --parent-id $ROOT_ID \
    --name "Security" \
    --tags Key=Purpose,Value=security-compliance

SECURITY_OU_ID=$(aws organizations list-organizational-units-for-parent \
    --parent-id $ROOT_ID \
    --query 'OrganizationalUnits[?Name==`Security`].Id' \
    --output text)

echo "Created Organizational Units:"
echo "  Core: $CORE_OU_ID"
echo "  Production: $PROD_OU_ID"
echo "  Non-Production: $NONPROD_OU_ID"
echo "  Security: $SECURITY_OU_ID"

# Save OUs to file for later use
cat > organization-structure.txt << STRUCT_EOF
ORG_ID=$ORG_ID
ROOT_ID=$ROOT_ID
CORE_OU_ID=$CORE_OU_ID
PROD_OU_ID=$PROD_OU_ID
NONPROD_OU_ID=$NONPROD_OU_ID
SECURITY_OU_ID=$SECURITY_OU_ID
STRUCT_EOF

echo "Organization structure saved to organization-structure.txt"
EOF

chmod +x create-organization-structure.sh
./create-organization-structure.sh
```

### Create Service Control Policies
```bash
# Create network security SCP
cat > network-security-scp.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyVPCDeletion",
      "Effect": "Deny",
      "Action": [
        "ec2:DeleteVpc",
        "ec2:DeleteSubnet",
        "ec2:DeleteRouteTable",
        "ec2:DeleteInternetGateway"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalArn": [
            "arn:aws:iam::*:role/NetworkAdminRole"
          ]
        }
      }
    },
    {
      "Sid": "RequireVPCFlowLogs",
      "Effect": "Deny",
      "Action": [
        "ec2:CreateVpc"
      ],
      "Resource": "*",
      "Condition": {
        "Bool": {
          "aws:RequestedRegion": "true"
        }
      }
    },
    {
      "Sid": "DenyPublicS3Buckets",
      "Effect": "Deny",
      "Action": [
        "s3:PutBucketPublicAccessBlock"
      ],
      "Resource": "*",
      "Condition": {
        "Bool": {
          "s3:PublicAccessBlockConfiguration": "false"
        }
      }
    }
  ]
}
EOF

# Create the SCP
aws organizations create-policy \
    --name "NetworkSecurityPolicy" \
    --description "Enforces network security standards across accounts" \
    --type SERVICE_CONTROL_POLICY \
    --content file://network-security-scp.json \
    --tags Key=Purpose,Value=network-security

NETWORK_SCP_ID=$(aws organizations list-policies \
    --filter SERVICE_CONTROL_POLICY \
    --query 'Policies[?Name==`NetworkSecurityPolicy`].Id' \
    --output text)

echo "Created Network Security SCP: $NETWORK_SCP_ID"

# Create production environment SCP
cat > production-scp.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInstanceTermination",
      "Effect": "Deny",
      "Action": [
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalArn": [
            "arn:aws:iam::*:role/ProductionAdminRole"
          ]
        }
      }
    },
    {
      "Sid": "RequireEncryption",
      "Effect": "Deny",
      "Action": [
        "ec2:CreateVolume",
        "rds:CreateDBInstance"
      ],
      "Resource": "*",
      "Condition": {
        "Bool": {
          "ec2:Encrypted": "false"
        }
      }
    }
  ]
}
EOF

aws organizations create-policy \
    --name "ProductionPolicy" \
    --description "Additional restrictions for production accounts" \
    --type SERVICE_CONTROL_POLICY \
    --content file://production-scp.json \
    --tags Key=Environment,Value=production

PROD_SCP_ID=$(aws organizations list-policies \
    --filter SERVICE_CONTROL_POLICY \
    --query 'Policies[?Name==`ProductionPolicy`].Id' \
    --output text)

echo "Created Production SCP: $PROD_SCP_ID"

# Clean up policy files
rm -f network-security-scp.json production-scp.json
```

## Step 2: Create Network Account Architecture

### Set Up Centralized Network Account
```bash
# Create network account setup script
cat > setup-network-account.sh << 'EOF'
#!/bin/bash

echo "🌐 Setting up Centralized Network Account"
echo "========================================"

# This script documents the setup for a dedicated network account
# In practice, you would run this in the network account

# Create Transit Gateway in network account
echo "Creating Transit Gateway..."
aws ec2 create-transit-gateway \
    --description "Enterprise Transit Gateway - Centralized" \
    --options AmazonSideAsn=64512,AutoAcceptSharedAttachments=enable,DefaultRouteTableAssociation=disable,DefaultRouteTablePropagation=disable \
    --tag-specifications 'ResourceType=transit-gateway,Tags=[{Key=Name,Value=enterprise-central-tgw},{Key=Purpose,Value=central-networking},{Key=Project,Value=aws-networking-hard-way}]'

CENTRAL_TGW_ID=$(aws ec2 describe-transit-gateways \
    --filters "Name=tag:Name,Values=enterprise-central-tgw" \
    --query 'TransitGateways[0].TransitGatewayId' \
    --output text)

echo "Central Transit Gateway ID: $CENTRAL_TGW_ID"

# Create route tables for different environments
echo "Creating Transit Gateway Route Tables..."

# Production route table
aws ec2 create-transit-gateway-route-table \
    --transit-gateway-id $CENTRAL_TGW_ID \
    --tag-specifications 'ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=production-rt},{Key=Environment,Value=production}]'

PROD_TGW_RT=$(aws ec2 describe-transit-gateway-route-tables \
    --filters "Name=tag:Name,Values=production-rt" \
    --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
    --output text)

# Non-production route table
aws ec2 create-transit-gateway-route-table \
    --transit-gateway-id $CENTRAL_TGW_ID \
    --tag-specifications 'ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=nonprod-rt},{Key=Environment,Value=non-production}]'

NONPROD_TGW_RT=$(aws ec2 describe-transit-gateway-route-tables \
    --filters "Name=tag:Name,Values=nonprod-rt" \
    --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
    --output text)

# Shared services route table
aws ec2 create-transit-gateway-route-table \
    --transit-gateway-id $CENTRAL_TGW_ID \
    --tag-specifications 'ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=shared-services-rt},{Key=Environment,Value=shared}]'

SHARED_TGW_RT=$(aws ec2 describe-transit-gateway-route-tables \
    --filters "Name=tag:Name,Values=shared-services-rt" \
    --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
    --output text)

echo "Created Transit Gateway Route Tables:"
echo "  Production: $PROD_TGW_RT"
echo "  Non-Production: $NONPROD_TGW_RT"
echo "  Shared Services: $SHARED_TGW_RT"

# Save network account configuration
cat > network-account-config.txt << NET_EOF
CENTRAL_TGW_ID=$CENTRAL_TGW_ID
PROD_TGW_RT=$PROD_TGW_RT
NONPROD_TGW_RT=$NONPROD_TGW_RT
SHARED_TGW_RT=$SHARED_TGW_RT
NET_EOF

echo "Network account configuration saved to network-account-config.txt"
EOF

chmod +x setup-network-account.sh
./setup-network-account.sh
```

### Create Cross-Account IAM Roles
```bash
# Create cross-account network management role
cat > network-cross-account-role.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::MASTER_ACCOUNT_ID:root"
        ]
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "network-management-2024"
        }
      }
    }
  ]
}
EOF

# Replace placeholder with actual account ID
sed -i "s/MASTER_ACCOUNT_ID/$MASTER_ACCOUNT_ID/g" network-cross-account-role.json

aws iam create-role \
    --role-name CrossAccountNetworkRole \
    --assume-role-policy-document file://network-cross-account-role.json \
    --description "Cross-account role for network management" \
    --tags Key=Purpose,Value=cross-account-networking

# Create policy for network management
cat > network-management-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeTransitGateways",
        "ec2:DescribeTransitGatewayAttachments",
        "ec2:DescribeTransitGatewayRouteTables",
        "ec2:CreateTransitGatewayVpcAttachment",
        "ec2:DeleteTransitGatewayVpcAttachment",
        "ec2:AssociateTransitGatewayRouteTable",
        "ec2:DisassociateTransitGatewayRouteTable",
        "ec2:PropagateTransitGatewayRouteTable",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeRouteTables"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ram:GetResourceShares",
        "ram:GetResourceShareAssociations",
        "ram:AcceptResourceShareInvitation"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
    --policy-name CrossAccountNetworkPolicy \
    --policy-document file://network-management-policy.json \
    --description "Policy for cross-account network management"

# Attach policy to role
aws iam attach-role-policy \
    --role-name CrossAccountNetworkRole \
    --policy-arn arn:aws:iam::${MASTER_ACCOUNT_ID}:policy/CrossAccountNetworkPolicy

echo "Created cross-account network management role"

# Clean up temporary files
rm -f network-cross-account-role.json network-management-policy.json
```

## Step 3: Implement Resource Sharing with RAM

### Share Transit Gateway via RAM
```bash
# Create resource share for Transit Gateway
CENTRAL_TGW_ID=$(grep CENTRAL_TGW_ID network-account-config.txt | cut -d'=' -f2)

aws ram create-resource-share \
    --name "CentralTransitGateway" \
    --resource-arns "arn:aws:ec2:us-east-1:${MASTER_ACCOUNT_ID}:transit-gateway/${CENTRAL_TGW_ID}" \
    --principals "$MASTER_ACCOUNT_ID" \
    --allow-external-principals \
    --tags Key=Name,Value=central-tgw-share,Key=Purpose,Value=multi-account-networking

TGW_SHARE_ARN=$(aws ram get-resource-shares \
    --resource-owner SELF \
    --name "CentralTransitGateway" \
    --query 'resourceShares[0].resourceShareArn' \
    --output text)

echo "Created Transit Gateway resource share: $TGW_SHARE_ARN"

# Create shared VPC for common services
aws ec2 create-vpc \
    --cidr-block 10.100.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=shared-services-vpc},{Key=Purpose,Value=shared-services},{Key=Project,Value=aws-networking-hard-way}]'

SHARED_VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=shared-services-vpc" \
    --query 'Vpcs[0].VpcId' \
    --output text)

# Enable DNS hostnames and support
aws ec2 modify-vpc-attribute --vpc-id $SHARED_VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $SHARED_VPC_ID --enable-dns-support

# Create subnets in shared VPC
aws ec2 create-subnet \
    --vpc-id $SHARED_VPC_ID \
    --cidr-block 10.100.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=shared-subnet-1a},{Key=Purpose,Value=shared-services}]'

aws ec2 create-subnet \
    --vpc-id $SHARED_VPC_ID \
    --cidr-block 10.100.2.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=shared-subnet-1b},{Key=Purpose,Value=shared-services}]'

# Share the VPC subnets
SHARED_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=shared-subnet-1a" --query 'Subnets[0].SubnetId' --output text)
SHARED_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=shared-subnet-1b" --query 'Subnets[0].SubnetId' --output text)

aws ram create-resource-share \
    --name "SharedVPCSubnets" \
    --resource-arns "arn:aws:ec2:us-east-1:${MASTER_ACCOUNT_ID}:subnet/${SHARED_SUBNET_1A}" "arn:aws:ec2:us-east-1:${MASTER_ACCOUNT_ID}:subnet/${SHARED_SUBNET_1B}" \
    --principals "$MASTER_ACCOUNT_ID" \
    --allow-external-principals \
    --tags Key=Name,Value=shared-vpc-subnets,Key=Purpose,Value=shared-services

echo "Created shared VPC and subnets:"
echo "  VPC: $SHARED_VPC_ID"
echo "  Subnet 1a: $SHARED_SUBNET_1A"
echo "  Subnet 1b: $SHARED_SUBNET_1B"
```

### Create DNS Resolution Strategy
```bash
# Create Route 53 Resolver for cross-account DNS
aws ec2 create-security-group \
    --group-name shared-dns-resolver-sg \
    --description "Security group for shared DNS resolver" \
    --vpc-id $SHARED_VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=shared-dns-resolver-sg},{Key=Purpose,Value=dns-resolution}]'

SHARED_DNS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=shared-dns-resolver-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow DNS traffic from all organization accounts
aws ec2 authorize-security-group-ingress \
    --group-id $SHARED_DNS_SG_ID \
    --protocol tcp \
    --port 53 \
    --cidr 10.0.0.0/8

aws ec2 authorize-security-group-ingress \
    --group-id $SHARED_DNS_SG_ID \
    --protocol udp \
    --port 53 \
    --cidr 10.0.0.0/8

# Create inbound resolver endpoint
aws route53resolver create-resolver-endpoint \
    --creator-request-id "shared-inbound-$(date +%s)" \
    --direction INBOUND \
    --ip-addresses SubnetId=$SHARED_SUBNET_1A,Ip=10.100.1.10 SubnetId=$SHARED_SUBNET_1B,Ip=10.100.2.10 \
    --security-group-ids $SHARED_DNS_SG_ID \
    --name "shared-inbound-resolver" \
    --tags Key=Name,Value=shared-inbound-resolver,Key=Purpose,Value=cross-account-dns

# Create outbound resolver endpoint
aws route53resolver create-resolver-endpoint \
    --creator-request-id "shared-outbound-$(date +%s)" \
    --direction OUTBOUND \
    --ip-addresses SubnetId=$SHARED_SUBNET_1A,Ip=10.100.1.20 SubnetId=$SHARED_SUBNET_1B,Ip=10.100.2.20 \
    --security-group-ids $SHARED_DNS_SG_ID \
    --name "shared-outbound-resolver" \
    --tags Key=Name,Value=shared-outbound-resolver,Key=Purpose,Value=cross-account-dns

echo "Created shared DNS resolver endpoints"
```

## Step 4: Configure Account-Specific Networking

### Create Production Account Network
```bash
cat > setup-production-account.sh << 'EOF'
#!/bin/bash

echo "🏭 Setting up Production Account Network"
echo "======================================"

# This script would be run in the production account
# For this lab, we'll simulate it in the current account with different CIDR

# Create production VPC
aws ec2 create-vpc \
    --cidr-block 10.10.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=production-vpc},{Key=Environment,Value=production},{Key=Account,Value=production},{Key=Project,Value=aws-networking-hard-way}]'

PROD_VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=production-vpc" \
    --query 'Vpcs[0].VpcId' \
    --output text)

# Enable DNS
aws ec2 modify-vpc-attribute --vpc-id $PROD_VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $PROD_VPC_ID --enable-dns-support

# Create production subnets
aws ec2 create-subnet \
    --vpc-id $PROD_VPC_ID \
    --cidr-block 10.10.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=prod-web-1a},{Key=Tier,Value=web},{Key=Environment,Value=production}]'

aws ec2 create-subnet \
    --vpc-id $PROD_VPC_ID \
    --cidr-block 10.10.2.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=prod-web-1b},{Key=Tier,Value=web},{Key=Environment,Value=production}]'

aws ec2 create-subnet \
    --vpc-id $PROD_VPC_ID \
    --cidr-block 10.10.11.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=prod-app-1a},{Key=Tier,Value=app},{Key=Environment,Value=production}]'

aws ec2 create-subnet \
    --vpc-id $PROD_VPC_ID \
    --cidr-block 10.10.12.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=prod-app-1b},{Key=Tier,Value=app},{Key=Environment,Value=production}]'

echo "Created Production VPC: $PROD_VPC_ID"

# Save production account config
cat > production-account-config.txt << PROD_EOF
PROD_VPC_ID=$PROD_VPC_ID
PROD_EOF

echo "Production account configuration saved"
EOF

chmod +x setup-production-account.sh
./setup-production-account.sh
```

### Create Development Account Network
```bash
cat > setup-development-account.sh << 'EOF'
#!/bin/bash

echo "🔧 Setting up Development Account Network"
echo "======================================="

# Create development VPC
aws ec2 create-vpc \
    --cidr-block 10.20.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=development-vpc},{Key=Environment,Value=development},{Key=Account,Value=development},{Key=Project,Value=aws-networking-hard-way}]'

DEV_VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=development-vpc" \
    --query 'Vpcs[0].VpcId' \
    --output text)

# Enable DNS
aws ec2 modify-vpc-attribute --vpc-id $DEV_VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $DEV_VPC_ID --enable-dns-support

# Create development subnets (simpler structure for dev)
aws ec2 create-subnet \
    --vpc-id $DEV_VPC_ID \
    --cidr-block 10.20.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dev-subnet-1a},{Key=Environment,Value=development}]'

aws ec2 create-subnet \
    --vpc-id $DEV_VPC_ID \
    --cidr-block 10.20.2.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=dev-subnet-1b},{Key=Environment,Value=development}]'

echo "Created Development VPC: $DEV_VPC_ID"

# Save development account config
cat > development-account-config.txt << DEV_EOF
DEV_VPC_ID=$DEV_VPC_ID
DEV_EOF

echo "Development account configuration saved"
EOF

chmod +x setup-development-account.sh
./setup-development-account.sh
```

## Step 5: Connect Accounts via Transit Gateway

### Attach VPCs to Central Transit Gateway
```bash
# Load configuration
source network-account-config.txt
source production-account-config.txt
source development-account-config.txt

# Attach production VPC to Transit Gateway
PROD_APP_SUBNET=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=prod-app-1a" --query 'Subnets[0].SubnetId' --output text)

aws ec2 create-transit-gateway-vpc-attachment \
    --transit-gateway-id $CENTRAL_TGW_ID \
    --vpc-id $PROD_VPC_ID \
    --subnet-ids $PROD_APP_SUBNET \
    --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=prod-tgw-attachment},{Key=Environment,Value=production}]'

# Attach development VPC to Transit Gateway
DEV_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=dev-subnet-1a" --query 'Subnets[0].SubnetId' --output text)

aws ec2 create-transit-gateway-vpc-attachment \
    --transit-gateway-id $CENTRAL_TGW_ID \
    --vpc-id $DEV_VPC_ID \
    --subnet-ids $DEV_SUBNET_1A \
    --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=dev-tgw-attachment},{Key=Environment,Value=development}]'

# Attach shared services VPC to Transit Gateway
aws ec2 create-transit-gateway-vpc-attachment \
    --transit-gateway-id $CENTRAL_TGW_ID \
    --vpc-id $SHARED_VPC_ID \
    --subnet-ids $SHARED_SUBNET_1A \
    --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=shared-tgw-attachment},{Key=Environment,Value=shared}]'

echo "Attached all VPCs to central Transit Gateway"

# Wait for attachments to be available
echo "Waiting for attachments to become available..."
sleep 60
```

### Configure Transit Gateway Route Tables
```bash
# Get attachment IDs
PROD_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments \
    --filters "Name=tag:Name,Values=prod-tgw-attachment" \
    --query 'TransitGatewayAttachments[0].TransitGatewayAttachmentId' \
    --output text)

DEV_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments \
    --filters "Name=tag:Name,Values=dev-tgw-attachment" \
    --query 'TransitGatewayAttachments[0].TransitGatewayAttachmentId' \
    --output text)

SHARED_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments \
    --filters "Name=tag:Name,Values=shared-tgw-attachment" \
    --query 'TransitGatewayAttachments[0].TransitGatewayAttachmentId' \
    --output text)

# Associate attachments with appropriate route tables
aws ec2 associate-transit-gateway-route-table \
    --transit-gateway-attachment-id $PROD_ATTACHMENT_ID \
    --transit-gateway-route-table-id $PROD_TGW_RT

aws ec2 associate-transit-gateway-route-table \
    --transit-gateway-attachment-id $DEV_ATTACHMENT_ID \
    --transit-gateway-route-table-id $NONPROD_TGW_RT

aws ec2 associate-transit-gateway-route-table \
    --transit-gateway-attachment-id $SHARED_ATTACHMENT_ID \
    --transit-gateway-route-table-id $SHARED_TGW_RT

# Configure route propagation
# Production can reach shared services
aws ec2 enable-transit-gateway-route-table-propagation \
    --transit-gateway-attachment-id $SHARED_ATTACHMENT_ID \
    --transit-gateway-route-table-id $PROD_TGW_RT

# Development can reach shared services
aws ec2 enable-transit-gateway-route-table-propagation \
    --transit-gateway-attachment-id $SHARED_ATTACHMENT_ID \
    --transit-gateway-route-table-id $NONPROD_TGW_RT

# Shared services can reach all environments
aws ec2 enable-transit-gateway-route-table-propagation \
    --transit-gateway-attachment-id $PROD_ATTACHMENT_ID \
    --transit-gateway-route-table-id $SHARED_TGW_RT

aws ec2 enable-transit-gateway-route-table-propagation \
    --transit-gateway-attachment-id $DEV_ATTACHMENT_ID \
    --transit-gateway-route-table-id $SHARED_TGW_RT

echo "Configured Transit Gateway routing"
```

### Update VPC Route Tables
```bash
# Update production VPC route tables
PROD_RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$PROD_VPC_ID" "Name=association.main,Values=true" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

# Add route to shared services via TGW
aws ec2 create-route \
    --route-table-id $PROD_RT_ID \
    --destination-cidr-block 10.100.0.0/16 \
    --transit-gateway-id $CENTRAL_TGW_ID

# Update development VPC route tables
DEV_RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$DEV_VPC_ID" "Name=association.main,Values=true" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

# Add route to shared services via TGW
aws ec2 create-route \
    --route-table-id $DEV_RT_ID \
    --destination-cidr-block 10.100.0.0/16 \
    --transit-gateway-id $CENTRAL_TGW_ID

# Update shared services VPC route tables
SHARED_RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$SHARED_VPC_ID" "Name=association.main,Values=true" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

# Add routes to production and development
aws ec2 create-route \
    --route-table-id $SHARED_RT_ID \
    --destination-cidr-block 10.10.0.0/16 \
    --transit-gateway-id $CENTRAL_TGW_ID

aws ec2 create-route \
    --route-table-id $SHARED_RT_ID \
    --destination-cidr-block 10.20.0.0/16 \
    --transit-gateway-id $CENTRAL_TGW_ID

echo "Updated VPC route tables for cross-account connectivity"
```

## Step 6: Implement Centralized Monitoring

### Create Cross-Account CloudWatch Dashboard
```bash
cat > multi-account-dashboard.json << 'EOF'
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/TransitGateway", "BytesIn", "TransitGateway", "CENTRAL_TGW_ID_PLACEHOLDER" ],
                    [ ".", "BytesOut", ".", "." ],
                    [ ".", "PacketDropCount", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "Transit Gateway Traffic"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/EC2", "NetworkIn", "VPC", "PROD_VPC_ID_PLACEHOLDER" ],
                    [ ".", "NetworkOut", ".", "." ],
                    [ ".", "NetworkIn", "VPC", "DEV_VPC_ID_PLACEHOLDER" ],
                    [ ".", "NetworkOut", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "VPC Network Traffic"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/transitgateway/flowlogs' | fields @timestamp, sourceVpc, targetVpc, bytes\n| filter bytes > 1000000\n| stats sum(bytes) by sourceVpc, targetVpc\n| sort sum desc\n| limit 20",
                "region": "us-east-1",
                "title": "Top VPC-to-VPC Traffic Flows"
            }
        }
    ]
}
EOF

# Replace placeholders
sed -i "s/CENTRAL_TGW_ID_PLACEHOLDER/$CENTRAL_TGW_ID/g" multi-account-dashboard.json
sed -i "s/PROD_VPC_ID_PLACEHOLDER/$PROD_VPC_ID/g" multi-account-dashboard.json
sed -i "s/DEV_VPC_ID_PLACEHOLDER/$DEV_VPC_ID/g" multi-account-dashboard.json

aws cloudwatch put-dashboard \
    --dashboard-name "MultiAccountNetworking" \
    --dashboard-body file://multi-account-dashboard.json

echo "Created multi-account networking dashboard"
rm -f multi-account-dashboard.json
```

### Set Up Cross-Account Logging
```bash
# Create S3 bucket for centralized logging
LOGGING_BUCKET="multi-account-logs-$(date +%s)"
aws s3 mb s3://$LOGGING_BUCKET

# Create bucket policy for cross-account access
cat > logging-bucket-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCrossAccountLogging",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": [
        "s3:PutObject",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::BUCKET_NAME",
        "arn:aws:s3:::BUCKET_NAME/*"
      ]
    }
  ]
}
EOF

sed -i "s/BUCKET_NAME/$LOGGING_BUCKET/g" logging-bucket-policy.json

aws s3api put-bucket-policy \
    --bucket $LOGGING_BUCKET \
    --policy file://logging-bucket-policy.json

# Enable VPC Flow Logs for all VPCs to centralized bucket
for VPC_ID in $PROD_VPC_ID $DEV_VPC_ID $SHARED_VPC_ID; do
    aws ec2 create-flow-logs \
        --resource-type VPC \
        --resource-ids $VPC_ID \
        --traffic-type ALL \
        --log-destination-type s3 \
        --log-destination arn:aws:s3:::$LOGGING_BUCKET/vpc-flow-logs/ \
        --log-format '${account-id} ${vpc-id} ${subnet-id} ${instance-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${windowstart} ${windowend} ${action} ${flowlogstatus}'
done

echo "Configured centralized VPC Flow Logs to: $LOGGING_BUCKET"

# Clean up
rm -f logging-bucket-policy.json
```

## Step 7: Test Multi-Account Connectivity

### Create Multi-Account Test Script
```bash
cat > test-multi-account-connectivity.sh << 'EOF'
#!/bin/bash

echo "🌐 Testing Multi-Account Connectivity"
echo "===================================="

# Load configuration
source network-account-config.txt 2>/dev/null || echo "Network config not found"
source production-account-config.txt 2>/dev/null || echo "Production config not found"
source development-account-config.txt 2>/dev/null || echo "Development config not found"

echo "Configuration:"
echo "  Central TGW: $CENTRAL_TGW_ID"
echo "  Production VPC: $PROD_VPC_ID"
echo "  Development VPC: $DEV_VPC_ID"
echo "  Shared Services VPC: $SHARED_VPC_ID"
echo ""

# Test 1: Transit Gateway Status
echo "Test 1: Transit Gateway Status"
echo "-----------------------------"
TGW_STATE=$(aws ec2 describe-transit-gateways --transit-gateway-ids $CENTRAL_TGW_ID --query 'TransitGateways[0].State' --output text 2>/dev/null || echo "Not found")
echo "Transit Gateway State: $TGW_STATE"

if [ "$TGW_STATE" = "available" ]; then
    echo "✅ PASS: Transit Gateway is available"
else
    echo "❌ FAIL: Transit Gateway not available"
fi

# Test 2: VPC Attachments
echo ""
echo "Test 2: VPC Attachments"
echo "----------------------"
echo "Transit Gateway Attachments:"
aws ec2 describe-transit-gateway-attachments \
    --filters "Name=transit-gateway-id,Values=$CENTRAL_TGW_ID" \
    --query 'TransitGatewayAttachments[].{VPC:ResourceId,State:State,Type:ResourceType}' \
    --output table

# Test 3: Route Table Associations
echo ""
echo "Test 3: Route Table Associations"
echo "-------------------------------"
echo "Production Route Table:"
aws ec2 describe-transit-gateway-route-tables \
    --transit-gateway-route-table-ids $PROD_TGW_RT \
    --query 'TransitGatewayRouteTables[0].Associations[].{AttachmentId:TransitGatewayAttachmentId,State:State}' \
    --output table 2>/dev/null || echo "No associations found"

echo ""
echo "Non-Production Route Table:"
aws ec2 describe-transit-gateway-route-tables \
    --transit-gateway-route-table-ids $NONPROD_TGW_RT \
    --query 'TransitGatewayRouteTables[0].Associations[].{AttachmentId:TransitGatewayAttachmentId,State:State}' \
    --output table 2>/dev/null || echo "No associations found"

# Test 4: Cross-Account Resource Sharing
echo ""
echo "Test 4: Resource Sharing Status"
echo "------------------------------"
RESOURCE_SHARES=$(aws ram get-resource-shares --resource-owner SELF --query 'resourceShares[].{Name:name,Status:status}' --output table)
echo "Resource Shares:"
echo "$RESOURCE_SHARES"

# Test 5: DNS Resolution
echo ""
echo "Test 5: DNS Resolution Setup"
echo "---------------------------"
RESOLVER_ENDPOINTS=$(aws route53resolver list-resolver-endpoints --query 'ResolverEndpoints[].{Name:Name,Direction:Direction,Status:Status}' --output table)
echo "Resolver Endpoints:"
echo "$RESOLVER_ENDPOINTS"

# Test 6: Security Group Rules
echo ""
echo "Test 6: Cross-Account Security"
echo "-----------------------------"
echo "Checking security groups allow cross-VPC communication..."

# Check if security groups exist and have appropriate rules
SHARED_SG_COUNT=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$SHARED_VPC_ID" --query 'length(SecurityGroups)' --output text 2>/dev/null || echo "0")
echo "Shared VPC Security Groups: $SHARED_SG_COUNT"

# Test 7: Monitoring Setup
echo ""
echo "Test 7: Monitoring Configuration"
echo "-------------------------------"
DASHBOARDS=$(aws cloudwatch list-dashboards --query 'DashboardEntries[?DashboardName==`MultiAccountNetworking`].DashboardName' --output text)
if [ ! -z "$DASHBOARDS" ]; then
    echo "✅ PASS: Multi-account dashboard exists"
else
    echo "❌ FAIL: Multi-account dashboard not found"
fi

# Test 8: Flow Logs
echo ""
echo "Test 8: Centralized Logging"
echo "--------------------------"
FLOW_LOGS_COUNT=0
for VPC in $PROD_VPC_ID $DEV_VPC_ID $SHARED_VPC_ID; do
    if [ ! -z "$VPC" ] && [ "$VPC" != "None" ]; then
        FL_STATUS=$(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC" --query 'FlowLogs[0].FlowLogStatus' --output text 2>/dev/null || echo "None")
        if [ "$FL_STATUS" = "ACTIVE" ]; then
            FLOW_LOGS_COUNT=$((FLOW_LOGS_COUNT + 1))
        fi
    fi
done

echo "Active VPC Flow Logs: $FLOW_LOGS_COUNT/3"

if [ $FLOW_LOGS_COUNT -eq 3 ]; then
    echo "✅ PASS: All VPCs have active flow logs"
else
    echo "⚠️  WARN: Not all VPCs have flow logs enabled"
fi

echo ""
echo "🎯 Multi-Account Connectivity Test Complete"
echo ""
echo "📋 Next Steps for Production:"
echo "1. Set up actual cross-account roles and permissions"
echo "2. Configure account-specific security policies"
echo "3. Implement automated compliance checking"
echo "4. Set up cross-account billing and cost allocation"
echo "5. Create disaster recovery procedures"
EOF

chmod +x test-multi-account-connectivity.sh
echo "Created multi-account connectivity test: test-multi-account-connectivity.sh"
```

## Validation Commands

### Verify Multi-Account Setup
```bash
# Check organization structure
echo "🏢 Organization Structure:"
aws organizations list-organizational-units-for-parent \
    --parent-id $(aws organizations list-roots --query 'Roots[0].Id' --output text) \
    --query 'OrganizationalUnits[].{Name:Name,Id:Id}' \
    --output table 2>/dev/null || echo "Organization not configured"

# Check Transit Gateway
echo ""
echo "🚇 Transit Gateway Status:"
aws ec2 describe-transit-gateways \
    --query 'TransitGateways[].{ID:TransitGatewayId,State:State,ASN:Options.AmazonSideAsn}' \
    --output table

# Check resource shares
echo ""
echo "🤝 Resource Shares:"
aws ram get-resource-shares \
    --resource-owner SELF \
    --query 'resourceShares[].{Name:name,Status:status,Resources:associatedEntities}' \
    --output table
```

## Cleanup for This Lab

```bash
cat > cleanup-lab08.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Lab 08 resources..."

# Load configuration files
source network-account-config.txt 2>/dev/null || echo "Network config not found"
source production-account-config.txt 2>/dev/null || echo "Production config not found"
source development-account-config.txt 2>/dev/null || echo "Development config not found"

# Delete Transit Gateway attachments
echo "Deleting Transit Gateway attachments..."
if [ ! -z "$CENTRAL_TGW_ID" ]; then
    ATTACHMENTS=$(aws ec2 describe-transit-gateway-attachments --filters "Name=transit-gateway-id,Values=$CENTRAL_TGW_ID" --query 'TransitGatewayAttachments[].TransitGatewayAttachmentId' --output text)
    for ATTACHMENT in $ATTACHMENTS; do
        [ ! -z "$ATTACHMENT" ] && aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id $ATTACHMENT
    done
    
    # Wait for attachments to be deleted
    sleep 60
    
    # Delete custom route tables
    for RT in $PROD_TGW_RT $NONPROD_TGW_RT $SHARED_TGW_RT; do
        [ ! -z "$RT" ] && aws ec2 delete-transit-gateway-route-table --transit-gateway-route-table-id $RT 2>/dev/null
    done
    
    # Delete Transit Gateway
    aws ec2 delete-transit-gateway --transit-gateway-id $CENTRAL_TGW_ID
fi

# Delete VPCs
echo "Deleting VPCs..."
for VPC_ID in $PROD_VPC_ID $DEV_VPC_ID $SHARED_VPC_ID; do
    if [ ! -z "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        # Delete subnets
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text)
        for SUBNET in $SUBNETS; do
            [ ! -z "$SUBNET" ] && aws ec2 delete-subnet --subnet-id $SUBNET 2>/dev/null
        done
        
        # Delete security groups
        SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
        for SG in $SECURITY_GROUPS; do
            [ ! -z "$SG" ] && aws ec2 delete-security-group --group-id $SG 2>/dev/null
        done
        
        # Delete VPC
        aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null
    fi
done

# Delete Route 53 Resolver endpoints
echo "Deleting Route 53 Resolver endpoints..."
RESOLVER_ENDPOINTS=$(aws route53resolver list-resolver-endpoints --query 'ResolverEndpoints[].Id' --output text)
for ENDPOINT in $RESOLVER_ENDPOINTS; do
    [ ! -z "$ENDPOINT" ] && aws route53resolver delete-resolver-endpoint --resolver-endpoint-id $ENDPOINT 2>/dev/null
done

# Delete resource shares
echo "Deleting resource shares..."
RESOURCE_SHARES=$(aws ram get-resource-shares --resource-owner SELF --query 'resourceShares[].resourceShareArn' --output text)
for SHARE in $RESOURCE_SHARES; do
    [ ! -z "$SHARE" ] && aws ram delete-resource-share --resource-share-arn $SHARE 2>/dev/null
done

# Delete IAM roles and policies
echo "Deleting IAM resources..."
aws iam detach-role-policy --role-name CrossAccountNetworkRole --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/CrossAccountNetworkPolicy 2>/dev/null
aws iam delete-role --role-name CrossAccountNetworkRole 2>/dev/null
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/CrossAccountNetworkPolicy 2>/dev/null

# Delete S3 logging bucket
echo "Deleting S3 logging bucket..."
LOGGING_BUCKET=$(aws s3 ls | grep multi-account-logs | awk '{print $3}')
[ ! -z "$LOGGING_BUCKET" ] && aws s3 rb s3://$LOGGING_BUCKET --force 2>/dev/null

# Delete CloudWatch dashboard
aws cloudwatch delete-dashboards --dashboard-names MultiAccountNetworking 2>/dev/null

# Delete SCPs (be careful with this in production)
echo "Note: Service Control Policies not deleted automatically"
echo "Delete manually if needed: NetworkSecurityPolicy, ProductionPolicy"

# Clean up configuration files
rm -f network-account-config.txt production-account-config.txt development-account-config.txt organization-structure.txt

echo "✅ Lab 08 cleanup completed"
echo "⚠️  Note: AWS Organizations structure and SCPs require manual cleanup"
EOF

chmod +x cleanup-lab08.sh
echo "Created cleanup script: cleanup-lab08.sh"
```

## Next Steps

After completing this lab, you should have:
- ✅ AWS Organizations structure with OUs and SCPs
- ✅ Centralized Transit Gateway for multi-account connectivity
- ✅ Resource sharing via AWS RAM
- ✅ Cross-account IAM roles and policies
- ✅ Centralized DNS resolution strategy
- ✅ Multi-account monitoring and logging
- ✅ Network governance and compliance controls

**Continue to:** [Lab 09: Monitoring & Troubleshooting](../09-monitoring-troubleshooting/README.md)