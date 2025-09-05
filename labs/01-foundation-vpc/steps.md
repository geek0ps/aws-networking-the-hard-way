# Lab 01: Detailed Steps

## Step 1: Create the VPC

```bash
# Create VPC
aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ecommerce-vpc}]'

# Enable DNS hostnames
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)

aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames

aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-support
```

## Step 2: Create Subnets

### Public Subnets (Web Tier)
```bash
# Public subnet AZ-1a
aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-web-1a}]'

# Public subnet AZ-1b
aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-web-1b}]'
```

### Private Subnets (App Tier)
```bash
# Private subnet AZ-1a
aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.11.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-app-1a}]'

# Private subnet AZ-1b
aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.12.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-app-1b}]'
```

### Database Subnets
```bash
# Database subnet AZ-1a
aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.21.0/24 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-db-1a}]'

# Database subnet AZ-1b
aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.22.0/24 \
    --availability-zone us-east-1b \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-db-1b}]'
```

## Step 3: Create and Attach Internet Gateway

```bash
# Create Internet Gateway
aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=ecommerce-igw}]'

IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=ecommerce-igw" --query 'InternetGateways[0].InternetGatewayId' --output text)

# Attach to VPC
aws ec2 attach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID
```

## Step 4: Configure Route Tables

### Public Route Table
```bash
# Create public route table
aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=public-rt}]'

PUBLIC_RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=public-rt" --query 'RouteTables[0].RouteTableId' --output text)

# Add route to Internet Gateway
aws ec2 create-route \
    --route-table-id $PUBLIC_RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID

# Associate public subnets
PUBLIC_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-web-1a" --query 'Subnets[0].SubnetId' --output text)
PUBLIC_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-web-1b" --query 'Subnets[0].SubnetId' --output text)

aws ec2 associate-route-table --route-table-id $PUBLIC_RT_ID --subnet-id $PUBLIC_SUBNET_1A
aws ec2 associate-route-table --route-table-id $PUBLIC_RT_ID --subnet-id $PUBLIC_SUBNET_1B
```

## Step 5: Create NAT Gateway

```bash
# Allocate Elastic IP
aws ec2 allocate-address --domain vpc --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=nat-eip}]'

EIP_ALLOC_ID=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=nat-eip" --query 'Addresses[0].AllocationId' --output text)

# Create NAT Gateway in public subnet
aws ec2 create-nat-gateway \
    --subnet-id $PUBLIC_SUBNET_1A \
    --allocation-id $EIP_ALLOC_ID \
    --tag-specifications 'ResourceType=nat-gateway,Tags=[{Key=Name,Value=ecommerce-nat}]'

# Wait for NAT Gateway to be available
NAT_GW_ID=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=ecommerce-nat" --query 'NatGateways[0].NatGatewayId' --output text)

# Create private route table
aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=private-rt}]'

PRIVATE_RT_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt" --query 'RouteTables[0].RouteTableId' --output text)

# Add route to NAT Gateway
aws ec2 create-route \
    --route-table-id $PRIVATE_RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_GW_ID

# Associate private subnets
PRIVATE_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-app-1a" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-app-1b" --query 'Subnets[0].SubnetId' --output text)

aws ec2 associate-route-table --route-table-id $PRIVATE_RT_ID --subnet-id $PRIVATE_SUBNET_1A
aws ec2 associate-route-table --route-table-id $PRIVATE_RT_ID --subnet-id $PRIVATE_SUBNET_1B
```

## Validation Commands

```bash
# Verify VPC
aws ec2 describe-vpcs --vpc-ids $VPC_ID

# Verify subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID"

# Verify route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID"

# Verify NAT Gateway
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID"
```