# Lab 03: Network Segmentation - Detailed Steps

## Prerequisites
- Completed Lab 01 and Lab 02
- VPC with multi-AZ architecture in place

```bash
# Set environment variables
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
echo "Working with VPC: $VPC_ID"
```

## Step 1: Design Security Group Strategy

### Create Layered Security Groups

#### Web Tier Security Group
```bash
# Create web tier security group
aws ec2 create-security-group \
    --group-name web-tier-sg \
    --description "Security group for web tier - ALB and web servers" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=web-tier-sg},{Key=Tier,Value=web},{Key=Project,Value=aws-networking-hard-way}]'

WEB_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=web-tier-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow HTTP and HTTPS from internet
aws ec2 authorize-security-group-ingress \
    --group-id $WEB_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $WEB_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0

echo "Created Web Tier Security Group: $WEB_SG_ID"
```

#### Application Tier Security Group
```bash
# Create application tier security group
aws ec2 create-security-group \
    --group-name app-tier-sg \
    --description "Security group for application tier" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=app-tier-sg},{Key=Tier,Value=app},{Key=Project,Value=aws-networking-hard-way}]'

APP_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=app-tier-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow traffic from web tier only
aws ec2 authorize-security-group-ingress \
    --group-id $APP_SG_ID \
    --protocol tcp \
    --port 8080 \
    --source-group $WEB_SG_ID

# Allow internal app communication
aws ec2 authorize-security-group-ingress \
    --group-id $APP_SG_ID \
    --protocol tcp \
    --port 8080 \
    --source-group $APP_SG_ID

echo "Created Application Tier Security Group: $APP_SG_ID"
```

#### Database Tier Security Group
```bash
# Create database tier security group
aws ec2 create-security-group \
    --group-name db-tier-sg \
    --description "Security group for database tier" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=db-tier-sg},{Key=Tier,Value=db},{Key=Project,Value=aws-networking-hard-way}]'

DB_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=db-tier-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow MySQL/Aurora from app tier only
aws ec2 authorize-security-group-ingress \
    --group-id $DB_SG_ID \
    --protocol tcp \
    --port 3306 \
    --source-group $APP_SG_ID

# Allow PostgreSQL from app tier only
aws ec2 authorize-security-group-ingress \
    --group-id $DB_SG_ID \
    --protocol tcp \
    --port 5432 \
    --source-group $APP_SG_ID

# Allow database replication between DB instances
aws ec2 authorize-security-group-ingress \
    --group-id $DB_SG_ID \
    --protocol tcp \
    --port 3306 \
    --source-group $DB_SG_ID

echo "Created Database Tier Security Group: $DB_SG_ID"
```

#### Management Security Group
```bash
# Create management security group for bastion hosts and admin access
aws ec2 create-security-group \
    --group-name management-sg \
    --description "Security group for management and bastion hosts" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=management-sg},{Key=Tier,Value=management},{Key=Project,Value=aws-networking-hard-way}]'

MGMT_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=management-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow SSH from specific IP ranges (replace with your IP)
YOUR_IP=$(curl -s http://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
    --group-id $MGMT_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr ${YOUR_IP}/32

# Allow SSH to all tiers from management
aws ec2 authorize-security-group-ingress \
    --group-id $WEB_SG_ID \
    --protocol tcp \
    --port 22 \
    --source-group $MGMT_SG_ID

aws ec2 authorize-security-group-ingress \
    --group-id $APP_SG_ID \
    --protocol tcp \
    --port 22 \
    --source-group $MGMT_SG_ID

aws ec2 authorize-security-group-ingress \
    --group-id $DB_SG_ID \
    --protocol tcp \
    --port 22 \
    --source-group $MGMT_SG_ID

echo "Created Management Security Group: $MGMT_SG_ID"
echo "Allowed SSH access from your IP: $YOUR_IP"
```

## Step 2: Implement Network ACLs for Subnet-Level Security

### Create Custom Network ACLs

#### Web Tier NACL
```bash
# Create web tier NACL
aws ec2 create-network-acl \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=web-tier-nacl},{Key=Tier,Value=web},{Key=Project,Value=aws-networking-hard-way}]'

WEB_NACL_ID=$(aws ec2 describe-network-acls \
    --filters "Name=tag:Name,Values=web-tier-nacl" \
    --query 'NetworkAcls[0].NetworkAclId' \
    --output text)

# Allow inbound HTTP/HTTPS
aws ec2 create-network-acl-entry \
    --network-acl-id $WEB_NACL_ID \
    --rule-number 100 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=80,To=80 \
    --cidr-block 0.0.0.0/0

aws ec2 create-network-acl-entry \
    --network-acl-id $WEB_NACL_ID \
    --rule-number 110 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=443,To=443 \
    --cidr-block 0.0.0.0/0

# Allow ephemeral ports for return traffic
aws ec2 create-network-acl-entry \
    --network-acl-id $WEB_NACL_ID \
    --rule-number 120 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=1024,To=65535 \
    --cidr-block 0.0.0.0/0

# Allow SSH from management subnet
aws ec2 create-network-acl-entry \
    --network-acl-id $WEB_NACL_ID \
    --rule-number 130 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=22,To=22 \
    --cidr-block 10.0.1.0/24

# Allow outbound traffic to app tier
aws ec2 create-network-acl-entry \
    --network-acl-id $WEB_NACL_ID \
    --rule-number 100 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=8080,To=8080 \
    --cidr-block 10.0.0.0/16 \
    --egress

# Allow outbound HTTP/HTTPS for updates
aws ec2 create-network-acl-entry \
    --network-acl-id $WEB_NACL_ID \
    --rule-number 110 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=80,To=80 \
    --cidr-block 0.0.0.0/0 \
    --egress

aws ec2 create-network-acl-entry \
    --network-acl-id $WEB_NACL_ID \
    --rule-number 120 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=443,To=443 \
    --cidr-block 0.0.0.0/0 \
    --egress

# Allow ephemeral ports outbound
aws ec2 create-network-acl-entry \
    --network-acl-id $WEB_NACL_ID \
    --rule-number 130 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=1024,To=65535 \
    --cidr-block 0.0.0.0/0 \
    --egress

echo "Created Web Tier NACL: $WEB_NACL_ID"
```

#### Application Tier NACL
```bash
# Create application tier NACL
aws ec2 create-network-acl \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=app-tier-nacl},{Key=Tier,Value=app},{Key=Project,Value=aws-networking-hard-way}]'

APP_NACL_ID=$(aws ec2 describe-network-acls \
    --filters "Name=tag:Name,Values=app-tier-nacl" \
    --query 'NetworkAcls[0].NetworkAclId' \
    --output text)

# Allow inbound from web tier
aws ec2 create-network-acl-entry \
    --network-acl-id $APP_NACL_ID \
    --rule-number 100 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=8080,To=8080 \
    --cidr-block 10.0.1.0/24

aws ec2 create-network-acl-entry \
    --network-acl-id $APP_NACL_ID \
    --rule-number 110 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=8080,To=8080 \
    --cidr-block 10.0.2.0/24

# Allow SSH from management
aws ec2 create-network-acl-entry \
    --network-acl-id $APP_NACL_ID \
    --rule-number 120 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=22,To=22 \
    --cidr-block 10.0.1.0/24

# Allow ephemeral ports
aws ec2 create-network-acl-entry \
    --network-acl-id $APP_NACL_ID \
    --rule-number 130 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=1024,To=65535 \
    --cidr-block 0.0.0.0/0

# Allow outbound to database
aws ec2 create-network-acl-entry \
    --network-acl-id $APP_NACL_ID \
    --rule-number 100 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=3306,To=3306 \
    --cidr-block 10.0.21.0/24 \
    --egress

aws ec2 create-network-acl-entry \
    --network-acl-id $APP_NACL_ID \
    --rule-number 110 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=3306,To=3306 \
    --cidr-block 10.0.22.0/24 \
    --egress

# Allow outbound HTTP/HTTPS
aws ec2 create-network-acl-entry \
    --network-acl-id $APP_NACL_ID \
    --rule-number 120 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=80,To=80 \
    --cidr-block 0.0.0.0/0 \
    --egress

aws ec2 create-network-acl-entry \
    --network-acl-id $APP_NACL_ID \
    --rule-number 130 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=443,To=443 \
    --cidr-block 0.0.0.0/0 \
    --egress

# Allow ephemeral ports outbound
aws ec2 create-network-acl-entry \
    --network-acl-id $APP_NACL_ID \
    --rule-number 140 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=1024,To=65535 \
    --cidr-block 0.0.0.0/0 \
    --egress

echo "Created Application Tier NACL: $APP_NACL_ID"
```

#### Database Tier NACL
```bash
# Create database tier NACL
aws ec2 create-network-acl \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=db-tier-nacl},{Key=Tier,Value=db},{Key=Project,Value=aws-networking-hard-way}]'

DB_NACL_ID=$(aws ec2 describe-network-acls \
    --filters "Name=tag:Name,Values=db-tier-nacl" \
    --query 'NetworkAcls[0].NetworkAclId' \
    --output text)

# Allow inbound from app tier
aws ec2 create-network-acl-entry \
    --network-acl-id $DB_NACL_ID \
    --rule-number 100 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=3306,To=3306 \
    --cidr-block 10.0.11.0/24

aws ec2 create-network-acl-entry \
    --network-acl-id $DB_NACL_ID \
    --rule-number 110 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=3306,To=3306 \
    --cidr-block 10.0.12.0/24

# Allow database replication between AZs
aws ec2 create-network-acl-entry \
    --network-acl-id $DB_NACL_ID \
    --rule-number 120 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=3306,To=3306 \
    --cidr-block 10.0.21.0/24

aws ec2 create-network-acl-entry \
    --network-acl-id $DB_NACL_ID \
    --rule-number 130 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=3306,To=3306 \
    --cidr-block 10.0.22.0/24

# Allow SSH from management
aws ec2 create-network-acl-entry \
    --network-acl-id $DB_NACL_ID \
    --rule-number 140 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=22,To=22 \
    --cidr-block 10.0.1.0/24

# Allow ephemeral ports
aws ec2 create-network-acl-entry \
    --network-acl-id $DB_NACL_ID \
    --rule-number 150 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=1024,To=65535 \
    --cidr-block 0.0.0.0/0

# Allow outbound for updates (limited)
aws ec2 create-network-acl-entry \
    --network-acl-id $DB_NACL_ID \
    --rule-number 100 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=80,To=80 \
    --cidr-block 0.0.0.0/0 \
    --egress

aws ec2 create-network-acl-entry \
    --network-acl-id $DB_NACL_ID \
    --rule-number 110 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=443,To=443 \
    --cidr-block 0.0.0.0/0 \
    --egress

# Allow ephemeral ports outbound
aws ec2 create-network-acl-entry \
    --network-acl-id $DB_NACL_ID \
    --rule-number 120 \
    --protocol tcp \
    --rule-action allow \
    --port-range From=1024,To=65535 \
    --cidr-block 0.0.0.0/0 \
    --egress

echo "Created Database Tier NACL: $DB_NACL_ID"
```

### Associate NACLs with Subnets
```bash
# Get subnet IDs
PUBLIC_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-web-1a" --query 'Subnets[0].SubnetId' --output text)
PUBLIC_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-web-1b" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-app-1a" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-app-1b" --query 'Subnets[0].SubnetId' --output text)
DB_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-db-1a" --query 'Subnets[0].SubnetId' --output text)
DB_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-db-1b" --query 'Subnets[0].SubnetId' --output text)

# Associate web tier NACL with public subnets
aws ec2 replace-network-acl-association \
    --association-id $(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$PUBLIC_SUBNET_1A" --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text) \
    --network-acl-id $WEB_NACL_ID

aws ec2 replace-network-acl-association \
    --association-id $(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$PUBLIC_SUBNET_1B" --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text) \
    --network-acl-id $WEB_NACL_ID

# Associate app tier NACL with private subnets
aws ec2 replace-network-acl-association \
    --association-id $(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$PRIVATE_SUBNET_1A" --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text) \
    --network-acl-id $APP_NACL_ID

aws ec2 replace-network-acl-association \
    --association-id $(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$PRIVATE_SUBNET_1B" --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text) \
    --network-acl-id $APP_NACL_ID

# Associate database tier NACL with database subnets
aws ec2 replace-network-acl-association \
    --association-id $(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$DB_SUBNET_1A" --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text) \
    --network-acl-id $DB_NACL_ID

aws ec2 replace-network-acl-association \
    --association-id $(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$DB_SUBNET_1B" --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text) \
    --network-acl-id $DB_NACL_ID

echo "Associated NACLs with respective subnets"
```

## Step 3: Create Bastion Host Architecture

### Deploy Bastion Host
```bash
# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

# Create key pair for bastion access
aws ec2 create-key-pair \
    --key-name bastion-key \
    --query 'KeyMaterial' \
    --output text > bastion-key.pem

chmod 400 bastion-key.pem

# Launch bastion host
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name bastion-key \
    --subnet-id $PUBLIC_SUBNET_1A \
    --security-group-ids $MGMT_SG_ID \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bastion-host},{Key=Role,Value=management},{Key=Project,Value=aws-networking-hard-way}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y tcpdump nmap telnet nc htop
# Install session manager for secure access
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent'

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids $(aws ec2 describe-instances --filters "Name=tag:Name,Values=bastion-host" --query 'Reservations[0].Instances[0].InstanceId' --output text)

BASTION_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=bastion-host" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo "Bastion host deployed with public IP: $BASTION_IP"
```

### Deploy Test Instances in Each Tier
```bash
# Deploy web tier instance
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name bastion-key \
    --subnet-id $PUBLIC_SUBNET_1A \
    --security-group-ids $WEB_SG_ID \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=web-server-1a},{Key=Tier,Value=web},{Key=Project,Value=aws-networking-hard-way}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Web Server in AZ-1a</h1>" > /var/www/html/index.html
echo "<p>Tier: Web</p>" >> /var/www/html/index.html
echo "<p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html'

# Deploy app tier instance
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name bastion-key \
    --subnet-id $PRIVATE_SUBNET_1A \
    --security-group-ids $APP_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=app-server-1a},{Key=Tier,Value=app},{Key=Project,Value=aws-networking-hard-way}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y python3 python3-pip
pip3 install flask
mkdir /app
cat > /app/app.py << EOF
from flask import Flask, jsonify
import socket
import os

app = Flask(__name__)

@app.route("/")
def hello():
    return jsonify({
        "message": "Application Server Response",
        "tier": "application",
        "hostname": socket.gethostname(),
        "instance_id": os.popen("curl -s http://169.254.169.254/latest/meta-data/instance-id").read().strip()
    })

@app.route("/health")
def health():
    return jsonify({"status": "healthy"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

cd /app
nohup python3 app.py &'

# Deploy database tier instance (simulated)
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name bastion-key \
    --subnet-id $DB_SUBNET_1A \
    --security-group-ids $DB_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=db-server-1a},{Key=Tier,Value=database},{Key=Project,Value=aws-networking-hard-way}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y mariadb-server
systemctl start mariadb
systemctl enable mariadb
mysql -e "CREATE DATABASE ecommerce;"
mysql -e "CREATE USER \"appuser\"@\"%\" IDENTIFIED BY \"password123\";"
mysql -e "GRANT ALL PRIVILEGES ON ecommerce.* TO \"appuser\"@\"%\";"
mysql -e "FLUSH PRIVILEGES;"'

echo "Deployed test instances in all tiers"
```

## Step 4: Configure VPC Flow Logs

### Enable VPC Flow Logs
```bash
# Create CloudWatch log group for VPC Flow Logs
aws logs create-log-group \
    --log-group-name VPCFlowLogs \
    --tags Project=aws-networking-hard-way

# Create IAM role for VPC Flow Logs
cat > flow-logs-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name VPCFlowLogsRole \
    --assume-role-policy-document file://flow-logs-trust-policy.json \
    --tags Key=Project,Value=aws-networking-hard-way

# Create and attach policy
cat > flow-logs-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
    --policy-name VPCFlowLogsPolicy \
    --policy-document file://flow-logs-policy.json

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam attach-role-policy \
    --role-name VPCFlowLogsRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/VPCFlowLogsPolicy

# Enable VPC Flow Logs
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids $VPC_ID \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name VPCFlowLogs \
    --deliver-logs-permission-arn arn:aws:iam::${ACCOUNT_ID}:role/VPCFlowLogsRole \
    --tag-specifications 'ResourceType=vpc-flow-log,Tags=[{Key=Name,Value=ecommerce-vpc-flow-logs},{Key=Project,Value=aws-networking-hard-way}]'

echo "Enabled VPC Flow Logs for VPC: $VPC_ID"

# Clean up temporary files
rm -f flow-logs-trust-policy.json flow-logs-policy.json
```

## Step 5: Test Security Boundaries

### Create Security Testing Script
```bash
cat > test-security-boundaries.sh << 'EOF'
#!/bin/bash

echo "🔒 Testing Network Security Boundaries"
echo "====================================="

# Get instance IPs
BASTION_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=bastion-host" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
WEB_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=web-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
APP_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=app-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
DB_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=db-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

echo "Instance IPs:"
echo "  Bastion: $BASTION_IP"
echo "  Web: $WEB_IP"
echo "  App: $APP_IP"
echo "  DB: $DB_IP"
echo ""

# Test 1: Web tier accessibility
echo "Test 1: Web Tier Accessibility"
echo "------------------------------"
WEB_PUBLIC_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=web-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://$WEB_PUBLIC_IP || echo "TIMEOUT")
if [ "$HTTP_RESPONSE" = "200" ]; then
    echo "✅ PASS: Web server accessible from internet (HTTP 200)"
else
    echo "❌ FAIL: Web server not accessible from internet (HTTP $HTTP_RESPONSE)"
fi

# Test 2: Direct app tier access (should fail)
echo ""
echo "Test 2: Direct App Tier Access (Should Fail)"
echo "--------------------------------------------"
APP_RESPONSE=$(timeout 5 curl -s --max-time 3 http://$APP_IP:8080 2>/dev/null || echo "BLOCKED")
if [ "$APP_RESPONSE" = "BLOCKED" ]; then
    echo "✅ PASS: App tier blocked from direct internet access"
else
    echo "❌ FAIL: App tier accessible from internet (security issue!)"
fi

# Test 3: Database access from app tier (via bastion)
echo ""
echo "Test 3: Database Access Control"
echo "------------------------------"
# This test requires SSH access through bastion
echo "ℹ️  Manual test required: SSH to bastion, then to app server, then test DB connection"
echo "   Commands to run:"
echo "   ssh -i bastion-key.pem ec2-user@$BASTION_IP"
echo "   ssh ec2-user@$APP_IP"
echo "   mysql -h $DB_IP -u appuser -p"

# Test 4: Security group rules validation
echo ""
echo "Test 4: Security Group Rules Validation"
echo "--------------------------------------"

# Check web tier security group
WEB_SG_RULES=$(aws ec2 describe-security-groups --group-ids $WEB_SG_ID --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`].IpRanges[0].CidrIp' --output text)
if [ "$WEB_SG_RULES" = "0.0.0.0/0" ]; then
    echo "✅ PASS: Web tier allows HTTP from anywhere"
else
    echo "❌ FAIL: Web tier HTTP access misconfigured"
fi

# Check app tier security group
APP_SG_RULES=$(aws ec2 describe-security-groups --group-ids $APP_SG_ID --query 'SecurityGroups[0].IpPermissions[?FromPort==`8080`].UserIdGroupPairs[0].GroupId' --output text)
if [ "$APP_SG_RULES" = "$WEB_SG_ID" ]; then
    echo "✅ PASS: App tier only allows access from web tier"
else
    echo "❌ FAIL: App tier security group misconfigured"
fi

# Check database tier security group
DB_SG_RULES=$(aws ec2 describe-security-groups --group-ids $DB_SG_ID --query 'SecurityGroups[0].IpPermissions[?FromPort==`3306`].UserIdGroupPairs[0].GroupId' --output text)
if [ "$DB_SG_RULES" = "$APP_SG_ID" ]; then
    echo "✅ PASS: Database tier only allows access from app tier"
else
    echo "❌ FAIL: Database tier security group misconfigured"
fi

echo ""
echo "🎯 Security Boundary Test Complete"
echo ""
echo "📋 Manual Tests Required:"
echo "1. SSH through bastion to test tier-to-tier connectivity"
echo "2. Verify VPC Flow Logs are capturing traffic"
echo "3. Test NACL rules by temporarily blocking specific ports"
EOF

chmod +x test-security-boundaries.sh
echo "Created security testing script: test-security-boundaries.sh"
```

### Create Network Connectivity Test
```bash
cat > test-network-connectivity.sh << 'EOF'
#!/bin/bash

echo "🌐 Testing Network Connectivity Between Tiers"
echo "============================================="

# Get instance IPs
BASTION_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=bastion-host" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
WEB_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=web-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
APP_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=app-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
DB_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=db-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

# Create test script to run on bastion
cat > connectivity-test-remote.sh << 'REMOTE_EOF'
#!/bin/bash

echo "Testing from bastion host..."

# Test SSH connectivity to each tier
echo "Testing SSH connectivity:"
timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 ec2-user@WEB_IP "echo 'Web tier SSH: OK'" 2>/dev/null || echo "Web tier SSH: FAILED"
timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 ec2-user@APP_IP "echo 'App tier SSH: OK'" 2>/dev/null || echo "App tier SSH: FAILED"
timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 ec2-user@DB_IP "echo 'DB tier SSH: OK'" 2>/dev/null || echo "DB tier SSH: FAILED"

# Test application connectivity
echo ""
echo "Testing application connectivity:"
timeout 5 ssh -o StrictHostKeyChecking=no ec2-user@WEB_IP "curl -s --max-time 3 http://APP_IP:8080/health" 2>/dev/null || echo "Web to App: FAILED"

# Test database connectivity
echo ""
echo "Testing database connectivity:"
timeout 5 ssh -o StrictHostKeyChecking=no ec2-user@APP_IP "timeout 3 telnet DB_IP 3306" 2>/dev/null | grep "Connected" && echo "App to DB: OK" || echo "App to DB: FAILED"

REMOTE_EOF

# Replace placeholders
sed -i "s/WEB_IP/$WEB_IP/g" connectivity-test-remote.sh
sed -i "s/APP_IP/$APP_IP/g" connectivity-test-remote.sh
sed -i "s/DB_IP/$DB_IP/g" connectivity-test-remote.sh

# Copy and run on bastion
echo "Copying test script to bastion host..."
scp -i bastion-key.pem -o StrictHostKeyChecking=no connectivity-test-remote.sh ec2-user@$BASTION_IP:/tmp/

echo "Running connectivity tests from bastion host..."
ssh -i bastion-key.pem -o StrictHostKeyChecking=no ec2-user@$BASTION_IP "chmod +x /tmp/connectivity-test-remote.sh && /tmp/connectivity-test-remote.sh"

# Clean up
rm connectivity-test-remote.sh

echo ""
echo "✅ Network connectivity test completed"
EOF

chmod +x test-network-connectivity.sh
echo "Created network connectivity test: test-network-connectivity.sh"
```

## Step 6: Monitor VPC Flow Logs

### Create Flow Logs Analysis Script
```bash
cat > analyze-flow-logs.sh << 'EOF'
#!/bin/bash

echo "📊 Analyzing VPC Flow Logs"
echo "========================="

# Wait for some flow logs to be generated
echo "Waiting for flow logs to be generated (60 seconds)..."
sleep 60

# Query recent flow logs
echo ""
echo "Recent VPC Flow Logs (last 10 minutes):"
echo "---------------------------------------"

START_TIME=$(date -d '10 minutes ago' +%s)000
END_TIME=$(date +%s)000

aws logs filter-log-events \
    --log-group-name VPCFlowLogs \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --limit 20 \
    --query 'events[].message' \
    --output text | head -10

echo ""
echo "Flow Log Analysis:"
echo "-----------------"

# Count ACCEPT vs REJECT
ACCEPT_COUNT=$(aws logs filter-log-events \
    --log-group-name VPCFlowLogs \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --filter-pattern "ACCEPT" \
    --query 'length(events)' \
    --output text)

REJECT_COUNT=$(aws logs filter-log-events \
    --log-group-name VPCFlowLogs \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --filter-pattern "REJECT" \
    --query 'length(events)' \
    --output text)

echo "Accepted connections: $ACCEPT_COUNT"
echo "Rejected connections: $REJECT_COUNT"

# Show rejected traffic (potential security issues)
echo ""
echo "Recent Rejected Traffic:"
echo "-----------------------"
aws logs filter-log-events \
    --log-group-name VPCFlowLogs \
    --start-time $START_TIME \
    --end-time $END_TIME \
    --filter-pattern "REJECT" \
    --limit 5 \
    --query 'events[].message' \
    --output text

echo ""
echo "💡 Flow logs are now capturing all network traffic in your VPC"
echo "💡 Use CloudWatch Insights for more advanced analysis"
EOF

chmod +x analyze-flow-logs.sh
echo "Created flow logs analysis script: analyze-flow-logs.sh"
```

## Validation Commands

### Verify Security Configuration
```bash
# Verify security groups
echo "🔍 Security Groups Summary:"
aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[].{Name:GroupName,ID:GroupId,Rules:length(IpPermissions)}' \
    --output table

# Verify NACLs
echo ""
echo "🛡️  Network ACLs Summary:"
aws ec2 describe-network-acls \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkAcls[].{Name:Tags[?Key==`Name`].Value|[0],ID:NetworkAclId,Subnets:length(Associations)}' \
    --output table

# Verify VPC Flow Logs
echo ""
echo "📊 VPC Flow Logs Status:"
aws ec2 describe-flow-logs \
    --filter "Name=resource-id,Values=$VPC_ID" \
    --query 'FlowLogs[].{ID:FlowLogId,Status:FlowLogStatus,LogGroup:LogGroupName}' \
    --output table
```

## Cleanup for This Lab

```bash
cat > cleanup-lab03.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Lab 03 resources..."

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)

# Terminate instances
echo "Terminating instances..."
INSTANCES=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text)
if [ ! -z "$INSTANCES" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCES
    aws ec2 wait instance-terminated --instance-ids $INSTANCES
fi

# Delete key pair
aws ec2 delete-key-pair --key-name bastion-key 2>/dev/null
rm -f bastion-key.pem

# Delete VPC Flow Logs
FLOW_LOG_ID=$(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC_ID" --query 'FlowLogs[0].FlowLogId' --output text)
[ "$FLOW_LOG_ID" != "None" ] && aws ec2 delete-flow-logs --flow-log-ids $FLOW_LOG_ID

# Delete CloudWatch log group
aws logs delete-log-group --log-group-name VPCFlowLogs 2>/dev/null

# Delete IAM role and policy
aws iam detach-role-policy --role-name VPCFlowLogsRole --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/VPCFlowLogsPolicy 2>/dev/null
aws iam delete-role --role-name VPCFlowLogsRole 2>/dev/null
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/VPCFlowLogsPolicy 2>/dev/null

# Reset NACLs to default
DEFAULT_NACL=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" --query 'NetworkAcls[0].NetworkAclId' --output text)

# Get all subnets
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text)

# Reset subnet associations to default NACL
for SUBNET in $SUBNETS; do
    ASSOC_ID=$(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$SUBNET" --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text)
    [ "$ASSOC_ID" != "None" ] && aws ec2 replace-network-acl-association --association-id $ASSOC_ID --network-acl-id $DEFAULT_NACL 2>/dev/null
done

# Delete custom NACLs
CUSTOM_NACLS=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=false" --query 'NetworkAcls[].NetworkAclId' --output text)
for NACL in $CUSTOM_NACLS; do
    [ ! -z "$NACL" ] && aws ec2 delete-network-acl --network-acl-id $NACL 2>/dev/null
done

# Delete custom security groups
CUSTOM_SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
for SG in $CUSTOM_SGS; do
    [ ! -z "$SG" ] && aws ec2 delete-security-group --group-id $SG 2>/dev/null
done

echo "✅ Lab 03 cleanup completed"
EOF

chmod +x cleanup-lab03.sh
echo "Created cleanup script: cleanup-lab03.sh"
```

## Next Steps

After completing this lab, you should have:
- ✅ Layered security groups implementing least privilege
- ✅ Network ACLs providing subnet-level security
- ✅ Bastion host architecture for secure access
- ✅ VPC Flow Logs for network monitoring
- ✅ Understanding of defense-in-depth principles

**Continue to:** [Lab 04: Cross-VPC Communication](../04-cross-vpc-communication/README.md)