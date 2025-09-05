# Lab 02: Multi-AZ Architecture - Detailed Steps

## Prerequisites
- Completed Lab 01 (Foundation VPC)
- VPC ID from Lab 01 stored in environment variable

```bash
# Set VPC ID from Lab 01
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
echo "Working with VPC: $VPC_ID"
```

## Step 1: Deploy Second NAT Gateway for High Availability

### Create Elastic IP for Second NAT Gateway
```bash
# Allocate second Elastic IP
aws ec2 allocate-address \
    --domain vpc \
    --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=nat-eip-1b},{Key=Project,Value=aws-networking-hard-way}]'

# Get allocation ID
EIP_ALLOC_ID_1B=$(aws ec2 describe-addresses \
    --filters "Name=tag:Name,Values=nat-eip-1b" \
    --query 'Addresses[0].AllocationId' \
    --output text)

echo "Second EIP Allocation ID: $EIP_ALLOC_ID_1B"
```

### Create Second NAT Gateway
```bash
# Get public subnet in AZ-1b
PUBLIC_SUBNET_1B=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=public-web-1b" \
    --query 'Subnets[0].SubnetId' \
    --output text)

# Create NAT Gateway in second AZ
aws ec2 create-nat-gateway \
    --subnet-id $PUBLIC_SUBNET_1B \
    --allocation-id $EIP_ALLOC_ID_1B \
    --tag-specifications 'ResourceType=nat-gateway,Tags=[{Key=Name,Value=ecommerce-nat-1b},{Key=Project,Value=aws-networking-hard-way}]'

# Wait for NAT Gateway to be available
echo "Waiting for NAT Gateway to become available..."
NAT_GW_ID_1B=$(aws ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=ecommerce-nat-1b" \
    --query 'NatGateways[0].NatGatewayId' \
    --output text)

aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID_1B
echo "NAT Gateway $NAT_GW_ID_1B is now available"
```

## Step 2: Configure AZ-Specific Route Tables

### Create Separate Route Tables for Each AZ
```bash
# Create private route table for AZ-1a
aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=private-rt-1a},{Key=Project,Value=aws-networking-hard-way}]'

PRIVATE_RT_1A=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=private-rt-1a" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

# Create private route table for AZ-1b
aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=private-rt-1b},{Key=Project,Value=aws-networking-hard-way}]'

PRIVATE_RT_1B=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=private-rt-1b" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

echo "Created route tables: $PRIVATE_RT_1A (AZ-1a), $PRIVATE_RT_1B (AZ-1b)"
```

### Add Routes to Local NAT Gateways
```bash
# Get NAT Gateway IDs
NAT_GW_ID_1A=$(aws ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=ecommerce-nat" \
    --query 'NatGateways[0].NatGatewayId' \
    --output text)

# Add route to NAT Gateway 1a
aws ec2 create-route \
    --route-table-id $PRIVATE_RT_1A \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_GW_ID_1A

# Add route to NAT Gateway 1b
aws ec2 create-route \
    --route-table-id $PRIVATE_RT_1B \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_GW_ID_1B

echo "Added routes to respective NAT Gateways"
```

### Associate Subnets with AZ-Specific Route Tables
```bash
# Get subnet IDs
PRIVATE_SUBNET_1A=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=private-app-1a" \
    --query 'Subnets[0].SubnetId' \
    --output text)

PRIVATE_SUBNET_1B=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=private-app-1b" \
    --query 'Subnets[0].SubnetId' \
    --output text)

DB_SUBNET_1A=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=private-db-1a" \
    --query 'Subnets[0].SubnetId' \
    --output text)

DB_SUBNET_1B=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=private-db-1b" \
    --query 'Subnets[0].SubnetId' \
    --output text)

# Remove old associations (if any)
OLD_RT=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=private-rt" \
    --query 'RouteTables[0].RouteTableId' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$OLD_RT" ]; then
    # Disassociate old route table
    OLD_ASSOC_1A=$(aws ec2 describe-route-tables \
        --route-table-ids $OLD_RT \
        --query "RouteTables[0].Associations[?SubnetId=='$PRIVATE_SUBNET_1A'].RouteTableAssociationId" \
        --output text)
    
    OLD_ASSOC_1B=$(aws ec2 describe-route-tables \
        --route-table-ids $OLD_RT \
        --query "RouteTables[0].Associations[?SubnetId=='$PRIVATE_SUBNET_1B'].RouteTableAssociationId" \
        --output text)
    
    [ ! -z "$OLD_ASSOC_1A" ] && aws ec2 disassociate-route-table --association-id $OLD_ASSOC_1A
    [ ! -z "$OLD_ASSOC_1B" ] && aws ec2 disassociate-route-table --association-id $OLD_ASSOC_1B
fi

# Associate subnets with new AZ-specific route tables
aws ec2 associate-route-table --route-table-id $PRIVATE_RT_1A --subnet-id $PRIVATE_SUBNET_1A
aws ec2 associate-route-table --route-table-id $PRIVATE_RT_1A --subnet-id $DB_SUBNET_1A
aws ec2 associate-route-table --route-table-id $PRIVATE_RT_1B --subnet-id $PRIVATE_SUBNET_1B
aws ec2 associate-route-table --route-table-id $PRIVATE_RT_1B --subnet-id $DB_SUBNET_1B

echo "Associated subnets with AZ-specific route tables"
```

## Step 3: Deploy Test Instances for Validation

### Create Security Group for Test Instances
```bash
# Create security group for test instances
aws ec2 create-security-group \
    --group-name test-instances-sg \
    --description "Security group for test instances" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=test-instances-sg},{Key=Project,Value=aws-networking-hard-way}]'

TEST_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=test-instances-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow SSH access from anywhere (for testing only)
aws ec2 authorize-security-group-ingress \
    --group-id $TEST_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Allow ICMP for ping testing
aws ec2 authorize-security-group-ingress \
    --group-id $TEST_SG_ID \
    --protocol icmp \
    --port -1 \
    --cidr 10.0.0.0/16

echo "Created security group: $TEST_SG_ID"
```

### Launch Test Instances in Each AZ
```bash
# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

echo "Using AMI: $AMI_ID"

# Launch instance in AZ-1a
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --subnet-id $PRIVATE_SUBNET_1A \
    --security-group-ids $TEST_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-instance-1a},{Key=Project,Value=aws-networking-hard-way}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y tcpdump htop
echo "Instance in AZ-1a" > /home/ec2-user/az-info.txt'

# Launch instance in AZ-1b
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --subnet-id $PRIVATE_SUBNET_1B \
    --security-group-ids $TEST_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-instance-1b},{Key=Project,Value=aws-networking-hard-way}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y tcpdump htop
echo "Instance in AZ-1b" > /home/ec2-user/az-info.txt'

echo "Launched test instances in both AZs"
```

## Step 4: Test High Availability Scenarios

### Create Bastion Host for Testing
```bash
# Launch bastion host in public subnet
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --subnet-id $PUBLIC_SUBNET_1A \
    --security-group-ids $TEST_SG_ID \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bastion-host},{Key=Project,Value=aws-networking-hard-way}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y tcpdump htop nmap'

# Get bastion public IP
sleep 30
BASTION_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=bastion-host" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo "Bastion host public IP: $BASTION_IP"
```

### Test Connectivity from Each AZ
```bash
# Get private IPs of test instances
INSTANCE_1A_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=test-instance-1a" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

INSTANCE_1B_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=test-instance-1b" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)

echo "Test instance IPs:"
echo "  AZ-1a: $INSTANCE_1A_IP"
echo "  AZ-1b: $INSTANCE_1B_IP"

# Create test script for connectivity
cat > test-connectivity.sh << 'EOF'
#!/bin/bash
echo "Testing connectivity from both AZs..."

# Test from instance in AZ-1a
echo "Testing from AZ-1a instance:"
ssh -o StrictHostKeyChecking=no ec2-user@INSTANCE_1A_IP "curl -s http://checkip.amazonaws.com && echo ' (via NAT-1a)'"

# Test from instance in AZ-1b  
echo "Testing from AZ-1b instance:"
ssh -o StrictHostKeyChecking=no ec2-user@INSTANCE_1B_IP "curl -s http://checkip.amazonaws.com && echo ' (via NAT-1b)'"
EOF

# Replace placeholders
sed -i "s/INSTANCE_1A_IP/$INSTANCE_1A_IP/g" test-connectivity.sh
sed -i "s/INSTANCE_1B_IP/$INSTANCE_1B_IP/g" test-connectivity.sh

chmod +x test-connectivity.sh

echo "Created connectivity test script: test-connectivity.sh"
echo "Run this script from the bastion host to test HA setup"
```

## Step 5: Simulate NAT Gateway Failure

### Create Failure Simulation Script
```bash
cat > simulate-failure.sh << 'EOF'
#!/bin/bash

echo "🧪 Simulating NAT Gateway failure in AZ-1a..."

# Get NAT Gateway IDs
NAT_GW_1A=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=ecommerce-nat" --query 'NatGateways[0].NatGatewayId' --output text)
NAT_GW_1B=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=ecommerce-nat-1b" --query 'NatGateways[0].NatGatewayId' --output text)

echo "NAT Gateway 1A: $NAT_GW_1A"
echo "NAT Gateway 1B: $NAT_GW_1B"

# Test connectivity before failure
echo ""
echo "🔍 Testing connectivity before failure..."
INSTANCE_1A_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=test-instance-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
INSTANCE_1B_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=test-instance-1b" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

echo "Instance 1A can reach internet: $(timeout 5 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1A_IP 'curl -s --max-time 3 http://checkip.amazonaws.com' 2>/dev/null || echo 'FAILED')"
echo "Instance 1B can reach internet: $(timeout 5 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1B_IP 'curl -s --max-time 3 http://checkip.amazonaws.com' 2>/dev/null || echo 'FAILED')"

# Simulate failure by temporarily removing route
echo ""
echo "💥 Simulating NAT Gateway 1A failure (removing route)..."
PRIVATE_RT_1A=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt-1a" --query 'RouteTables[0].RouteTableId' --output text)

aws ec2 delete-route --route-table-id $PRIVATE_RT_1A --destination-cidr-block 0.0.0.0/0

echo "⏳ Waiting 30 seconds for route change to propagate..."
sleep 30

# Test connectivity after failure
echo ""
echo "🔍 Testing connectivity after simulated failure..."
echo "Instance 1A can reach internet: $(timeout 5 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1A_IP 'curl -s --max-time 3 http://checkip.amazonaws.com' 2>/dev/null || echo 'FAILED - Expected!')"
echo "Instance 1B can reach internet: $(timeout 5 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1B_IP 'curl -s --max-time 3 http://checkip.amazonaws.com' 2>/dev/null || echo 'FAILED')"

# Restore connectivity
echo ""
echo "🔧 Restoring connectivity..."
aws ec2 create-route --route-table-id $PRIVATE_RT_1A --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_1A

echo "⏳ Waiting 30 seconds for route restoration..."
sleep 30

# Test connectivity after restoration
echo ""
echo "🔍 Testing connectivity after restoration..."
echo "Instance 1A can reach internet: $(timeout 5 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1A_IP 'curl -s --max-time 3 http://checkip.amazonaws.com' 2>/dev/null || echo 'FAILED')"
echo "Instance 1B can reach internet: $(timeout 5 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1B_IP 'curl -s --max-time 3 http://checkip.amazonaws.com' 2>/dev/null || echo 'FAILED')"

echo ""
echo "✅ High availability test completed!"
EOF

chmod +x simulate-failure.sh
echo "Created failure simulation script: simulate-failure.sh"
```

## Step 6: Cost Analysis and Optimization

### Calculate Current Costs
```bash
cat > cost-analysis.sh << 'EOF'
#!/bin/bash

echo "💰 Multi-AZ Architecture Cost Analysis"
echo "====================================="

# Get current region
REGION=$(aws configure get region)
echo "Region: $REGION"

# NAT Gateway costs
echo ""
echo "🌐 NAT Gateway Costs:"
echo "  • 2 NAT Gateways × $0.045/hour = $0.09/hour"
echo "  • Monthly cost (730 hours): $65.70"
echo "  • Data processing: $0.045/GB processed"

# Elastic IP costs
echo ""
echo "📍 Elastic IP Costs:"
echo "  • 2 Elastic IPs (attached to NAT Gateways): $0.00/hour"
echo "  • If detached: $0.005/hour each"

# Data transfer costs
echo ""
echo "📊 Data Transfer Costs:"
echo "  • Cross-AZ traffic: $0.01/GB"
echo "  • Same-AZ traffic: Free"
echo "  • Internet egress: $0.09/GB (first 1GB free)"

# Alternative architectures
echo ""
echo "💡 Cost Optimization Options:"
echo ""
echo "1. Single NAT Gateway (Lower Cost, Lower Availability):"
echo "   • 1 NAT Gateway: $32.85/month"
echo "   • Savings: $32.85/month"
echo "   • Risk: Single point of failure"
echo ""
echo "2. NAT Instances (Lower Cost, More Management):"
echo "   • 2 t3.nano instances: ~$6.00/month"
echo "   • Savings: ~$59.70/month"
echo "   • Trade-off: Manual management, lower performance"
echo ""
echo "3. VPC Endpoints (For AWS Services):"
echo "   • $0.01/hour per endpoint"
echo "   • Eliminates NAT Gateway traffic for AWS services"
echo "   • Potential savings on data processing costs"

# Current month estimate
DAYS_IN_MONTH=$(date +%d)
ESTIMATED_COST=$(echo "scale=2; 0.09 * 24 * $DAYS_IN_MONTH" | bc 2>/dev/null || echo "~$2.16")

echo ""
echo "📈 Current Month Estimate (through day $DAYS_IN_MONTH):"
echo "  • NAT Gateway hours: ~$ESTIMATED_COST"
echo "  • Plus data processing charges"

echo ""
echo "🎯 Recommendations:"
echo "  • Monitor data transfer patterns"
echo "  • Consider VPC endpoints for AWS service traffic"
echo "  • Use CloudWatch to track NAT Gateway utilization"
echo "  • Implement cost alerts"
EOF

chmod +x cost-analysis.sh
echo "Created cost analysis script: cost-analysis.sh"
```

## Validation Commands

### Verify Multi-AZ Setup
```bash
# Check NAT Gateways in both AZs
echo "🔍 Verifying NAT Gateway deployment:"
aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$VPC_ID" \
    --query 'NatGateways[].{ID:NatGatewayId,AZ:AvailabilityZone,State:State,SubnetId:SubnetId}' \
    --output table

# Check route table associations
echo ""
echo "🗺️  Verifying route table associations:"
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[].{RouteTableId:RouteTableId,Name:Tags[?Key==`Name`].Value|[0],Associations:Associations[].SubnetId}' \
    --output table

# Check instance distribution
echo ""
echo "🖥️  Verifying instance distribution:"
aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],AZ:Placement.AvailabilityZone,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress}' \
    --output table
```

### Test Failover Capabilities
```bash
# Create comprehensive test
cat > comprehensive-test.sh << 'EOF'
#!/bin/bash

echo "🧪 Comprehensive Multi-AZ Test"
echo "=============================="

# Test 1: Verify independent NAT Gateway routing
echo ""
echo "Test 1: Independent NAT Gateway Routing"
echo "--------------------------------------"

# Get external IPs used by each instance
INSTANCE_1A_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=test-instance-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
INSTANCE_1B_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=test-instance-1b" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

EXT_IP_1A=$(timeout 10 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1A_IP 'curl -s --max-time 5 http://checkip.amazonaws.com' 2>/dev/null || echo "TIMEOUT")
EXT_IP_1B=$(timeout 10 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1B_IP 'curl -s --max-time 5 http://checkip.amazonaws.com' 2>/dev/null || echo "TIMEOUT")

echo "Instance 1A external IP: $EXT_IP_1A"
echo "Instance 1B external IP: $EXT_IP_1B"

if [ "$EXT_IP_1A" != "$EXT_IP_1B" ] && [ "$EXT_IP_1A" != "TIMEOUT" ] && [ "$EXT_IP_1B" != "TIMEOUT" ]; then
    echo "✅ PASS: Instances using different NAT Gateways"
else
    echo "❌ FAIL: Instances not using independent NAT Gateways"
fi

# Test 2: Cross-AZ communication
echo ""
echo "Test 2: Cross-AZ Communication"
echo "-----------------------------"

PING_RESULT=$(timeout 10 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1A_IP "ping -c 3 $INSTANCE_1B_IP" 2>/dev/null | grep "3 received" || echo "FAILED")

if [[ $PING_RESULT == *"3 received"* ]]; then
    echo "✅ PASS: Cross-AZ communication working"
else
    echo "❌ FAIL: Cross-AZ communication failed"
fi

# Test 3: Availability zone isolation
echo ""
echo "Test 3: Availability Zone Information"
echo "-----------------------------------"

AZ_1A=$(timeout 10 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1A_IP 'curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone' 2>/dev/null || echo "UNKNOWN")
AZ_1B=$(timeout 10 ssh -o StrictHostKeyChecking=no ec2-user@$INSTANCE_1B_IP 'curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone' 2>/dev/null || echo "UNKNOWN")

echo "Instance 1A AZ: $AZ_1A"
echo "Instance 1B AZ: $AZ_1B"

if [ "$AZ_1A" != "$AZ_1B" ] && [ "$AZ_1A" != "UNKNOWN" ] && [ "$AZ_1B" != "UNKNOWN" ]; then
    echo "✅ PASS: Instances in different availability zones"
else
    echo "❌ FAIL: Instances not properly distributed across AZs"
fi

echo ""
echo "🎯 Multi-AZ Architecture Test Complete"
EOF

chmod +x comprehensive-test.sh
echo "Created comprehensive test script: comprehensive-test.sh"
```

## Cleanup for This Lab

```bash
# Cleanup script for Lab 02 only
cat > cleanup-lab02.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Lab 02 resources..."

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)

# Terminate test instances
echo "Terminating test instances..."
INSTANCES=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text)
if [ ! -z "$INSTANCES" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCES
    aws ec2 wait instance-terminated --instance-ids $INSTANCES
fi

# Delete second NAT Gateway
echo "Deleting second NAT Gateway..."
NAT_GW_1B=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=ecommerce-nat-1b" --query 'NatGateways[0].NatGatewayId' --output text)
if [ "$NAT_GW_1B" != "None" ]; then
    aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW_1B
    aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT_GW_1B
fi

# Release second Elastic IP
echo "Releasing second Elastic IP..."
EIP_1B=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=nat-eip-1b" --query 'Addresses[0].AllocationId' --output text)
if [ "$EIP_1B" != "None" ]; then
    aws ec2 release-address --allocation-id $EIP_1B
fi

# Delete AZ-specific route tables
echo "Deleting AZ-specific route tables..."
RT_1A=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt-1a" --query 'RouteTables[0].RouteTableId' --output text)
RT_1B=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=private-rt-1b" --query 'RouteTables[0].RouteTableId' --output text)

[ "$RT_1A" != "None" ] && aws ec2 delete-route-table --route-table-id $RT_1A
[ "$RT_1B" != "None" ] && aws ec2 delete-route-table --route-table-id $RT_1B

# Delete security group
echo "Deleting test security group..."
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=test-instances-sg" --query 'SecurityGroups[0].GroupId' --output text)
[ "$SG_ID" != "None" ] && aws ec2 delete-security-group --group-id $SG_ID

echo "✅ Lab 02 cleanup completed"
EOF

chmod +x cleanup-lab02.sh
echo "Created cleanup script: cleanup-lab02.sh"
```

## Next Steps

After completing this lab, you should have:
- ✅ Redundant NAT Gateways in multiple AZs
- ✅ AZ-specific routing for optimal traffic flow
- ✅ Understanding of high availability trade-offs
- ✅ Cost analysis of different HA strategies

**Continue to:** [Lab 03: Network Segmentation](../03-network-segmentation/README.md)