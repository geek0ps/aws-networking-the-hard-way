# Lab 05: Hybrid Connectivity - Detailed Steps

## Prerequisites
- Completed Labs 01-04
- Understanding of VPN and BGP concepts
- AWS CLI configured with appropriate permissions

```bash
# Set environment variables
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
echo "Working with VPC: $VPC_ID"
```

## Step 1: Design Hybrid Network Architecture

### Create Customer Gateway (Simulated On-Premises)
```bash
# Get your public IP (simulating on-premises public IP)
YOUR_PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
echo "Your public IP (simulating on-premises): $YOUR_PUBLIC_IP"

# Create Customer Gateway
aws ec2 create-customer-gateway \
    --type ipsec.1 \
    --public-ip $YOUR_PUBLIC_IP \
    --bgp-asn 65000 \
    --tag-specifications 'ResourceType=customer-gateway,Tags=[{Key=Name,Value=on-premises-cgw},{Key=Project,Value=aws-networking-hard-way}]'

CGW_ID=$(aws ec2 describe-customer-gateways \
    --filters "Name=tag:Name,Values=on-premises-cgw" \
    --query 'CustomerGateways[0].CustomerGatewayId' \
    --output text)

echo "Created Customer Gateway: $CGW_ID"
```

### Create Virtual Private Gateway
```bash
# Create Virtual Private Gateway
aws ec2 create-vpn-gateway \
    --type ipsec.1 \
    --amazon-side-asn 64512 \
    --tag-specifications 'ResourceType=vpn-gateway,Tags=[{Key=Name,Value=aws-vpn-gateway},{Key=Project,Value=aws-networking-hard-way}]'

VGW_ID=$(aws ec2 describe-vpn-gateways \
    --filters "Name=tag:Name,Values=aws-vpn-gateway" \
    --query 'VpnGateways[0].VpnGatewayId' \
    --output text)

# Attach VGW to VPC
aws ec2 attach-vpn-gateway \
    --vpn-gateway-id $VGW_ID \
    --vpc-id $VPC_ID

# Wait for attachment
aws ec2 wait vpn-gateway-attached --vpn-gateway-ids $VGW_ID

echo "Created and attached Virtual Private Gateway: $VGW_ID"
```

## Step 2: Configure Site-to-Site VPN

### Create VPN Connection
```bash
# Create Site-to-Site VPN Connection
aws ec2 create-vpn-connection \
    --type ipsec.1 \
    --customer-gateway-id $CGW_ID \
    --vpn-gateway-id $VGW_ID \
    --options StaticRoutesOnly=false \
    --tag-specifications 'ResourceType=vpn-connection,Tags=[{Key=Name,Value=primary-vpn-connection},{Key=Project,Value=aws-networking-hard-way}]'

VPN_ID=$(aws ec2 describe-vpn-connections \
    --filters "Name=tag:Name,Values=primary-vpn-connection" \
    --query 'VpnConnections[0].VpnConnectionId' \
    --output text)

echo "Created VPN Connection: $VPN_ID"
echo "Waiting for VPN connection to be available..."

# Wait for VPN to be available
aws ec2 wait vpn-connection-available --vpn-connection-ids $VPN_ID

echo "VPN Connection is now available"
```

### Download VPN Configuration
```bash
# Get VPN configuration
aws ec2 describe-vpn-connections \
    --vpn-connection-ids $VPN_ID \
    --query 'VpnConnections[0].CustomerGatewayConfiguration' \
    --output text > vpn-config.xml

echo "Downloaded VPN configuration to vpn-config.xml"

# Extract tunnel information for reference
cat > extract-vpn-info.sh << 'EOF'
#!/bin/bash

echo "🔍 VPN Connection Details"
echo "========================"

VPN_ID=$(aws ec2 describe-vpn-connections --filters "Name=tag:Name,Values=primary-vpn-connection" --query 'VpnConnections[0].VpnConnectionId' --output text)

# Get tunnel information
aws ec2 describe-vpn-connections \
    --vpn-connection-ids $VPN_ID \
    --query 'VpnConnections[0].VgwTelemetry[].{TunnelIP:OutsideIpAddress,Status:Status,StatusMessage:StatusMessage}' \
    --output table

# Get BGP information
echo ""
echo "BGP Information:"
echo "---------------"
aws ec2 describe-vpn-connections \
    --vpn-connection-ids $VPN_ID \
    --query 'VpnConnections[0].Options.{BGPEnabled:StaticRoutesOnly,AmazonASN:TunnelOptions[0].TunnelInsideCidr}' \
    --output table

# Show route propagation status
echo ""
echo "Route Propagation:"
echo "-----------------"
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)" \
    --query 'RouteTables[].{RouteTableId:RouteTableId,PropagatingVgws:PropagatingVgws[].GatewayId}' \
    --output table
EOF

chmod +x extract-vpn-info.sh
./extract-vpn-info.sh
```

### Enable Route Propagation
```bash
# Get route table IDs
PRIVATE_RT_1A=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=private-rt-1a" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

PRIVATE_RT_1B=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=private-rt-1b" \
    --query 'RouteTables[0].RouteTableId' \
    --output text)

# Enable route propagation on private route tables
aws ec2 enable-vgw-route-propagation \
    --route-table-id $PRIVATE_RT_1A \
    --gateway-id $VGW_ID

aws ec2 enable-vgw-route-propagation \
    --route-table-id $PRIVATE_RT_1B \
    --gateway-id $VGW_ID

echo "Enabled route propagation on private route tables"
```

## Step 3: Simulate Direct Connect with Second VPN

### Create Second Customer Gateway (Simulating DX)
```bash
# Create second customer gateway (simulating Direct Connect backup)
aws ec2 create-customer-gateway \
    --type ipsec.1 \
    --public-ip $YOUR_PUBLIC_IP \
    --bgp-asn 65001 \
    --tag-specifications 'ResourceType=customer-gateway,Tags=[{Key=Name,Value=dx-backup-cgw},{Key=Purpose,Value=direct-connect-backup},{Key=Project,Value=aws-networking-hard-way}]'

DX_CGW_ID=$(aws ec2 describe-customer-gateways \
    --filters "Name=tag:Name,Values=dx-backup-cgw" \
    --query 'CustomerGateways[0].CustomerGatewayId' \
    --output text)

# Create second VPN connection (simulating DX backup)
aws ec2 create-vpn-connection \
    --type ipsec.1 \
    --customer-gateway-id $DX_CGW_ID \
    --vpn-gateway-id $VGW_ID \
    --options StaticRoutesOnly=false \
    --tag-specifications 'ResourceType=vpn-connection,Tags=[{Key=Name,Value=dx-backup-vpn},{Key=Purpose,Value=direct-connect-backup},{Key=Project,Value=aws-networking-hard-way}]'

DX_VPN_ID=$(aws ec2 describe-vpn-connections \
    --filters "Name=tag:Name,Values=dx-backup-vpn" \
    --query 'VpnConnections[0].VpnConnectionId' \
    --output text)

echo "Created backup VPN connection (simulating DX): $DX_VPN_ID"

# Wait for second VPN to be available
aws ec2 wait vpn-connection-available --vpn-connection-ids $DX_VPN_ID
```

### Configure BGP Path Preferences
```bash
# Create script to simulate BGP path manipulation
cat > configure-bgp-preferences.sh << 'EOF'
#!/bin/bash

echo "🛣️  Configuring BGP Path Preferences"
echo "===================================="

# In a real environment, you would configure these on your on-premises router
# This script documents the configuration that would be applied

echo "Primary VPN Connection (Lower preference for backup):"
echo "- Local Preference: 100"
echo "- AS Path Prepending: None"
echo "- MED: 100"
echo ""

echo "Backup VPN Connection (Higher preference for primary):"
echo "- Local Preference: 200"  
echo "- AS Path Prepending: 65001 65001 (make path longer)"
echo "- MED: 200"
echo ""

echo "Route Advertisement from On-Premises:"
echo "- Advertise 192.168.0.0/16 (simulated on-premises network)"
echo "- Advertise 172.16.0.0/16 (simulated branch offices)"
echo ""

echo "💡 In production, configure these on your BGP router:"
echo "router bgp 65000"
echo "  neighbor <tunnel1-ip> remote-as 64512"
echo "  neighbor <tunnel1-ip> local-preference 200"
echo "  neighbor <tunnel2-ip> remote-as 64512" 
echo "  neighbor <tunnel2-ip> local-preference 100"
echo "  network 192.168.0.0 mask 255.255.0.0"
echo "  network 172.16.0.0 mask 255.255.0.0"
EOF

chmod +x configure-bgp-preferences.sh
./configure-bgp-preferences.sh
```

## Step 4: Implement Hybrid DNS Resolution

### Create Route 53 Resolver Endpoints
```bash
# Create security group for DNS resolver
aws ec2 create-security-group \
    --group-name dns-resolver-sg \
    --description "Security group for Route 53 Resolver endpoints" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=dns-resolver-sg},{Key=Purpose,Value=hybrid-dns}]'

DNS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=dns-resolver-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow DNS traffic from on-premises networks
aws ec2 authorize-security-group-ingress \
    --group-id $DNS_SG_ID \
    --protocol tcp \
    --port 53 \
    --cidr 192.168.0.0/16

aws ec2 authorize-security-group-ingress \
    --group-id $DNS_SG_ID \
    --protocol udp \
    --port 53 \
    --cidr 192.168.0.0/16

aws ec2 authorize-security-group-ingress \
    --group-id $DNS_SG_ID \
    --protocol tcp \
    --port 53 \
    --cidr 172.16.0.0/16

aws ec2 authorize-security-group-ingress \
    --group-id $DNS_SG_ID \
    --protocol udp \
    --port 53 \
    --cidr 172.16.0.0/16

# Allow DNS from VPC
aws ec2 authorize-security-group-ingress \
    --group-id $DNS_SG_ID \
    --protocol tcp \
    --port 53 \
    --cidr 10.0.0.0/16

aws ec2 authorize-security-group-ingress \
    --group-id $DNS_SG_ID \
    --protocol udp \
    --port 53 \
    --cidr 10.0.0.0/16

echo "Created DNS resolver security group: $DNS_SG_ID"
```

### Create Resolver Endpoints
```bash
# Get subnet IDs for resolver endpoints
PRIVATE_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-app-1a" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-app-1b" --query 'Subnets[0].SubnetId' --output text)

# Create inbound resolver endpoint (for on-premises to query AWS DNS)
aws route53resolver create-resolver-endpoint \
    --creator-request-id "inbound-$(date +%s)" \
    --direction INBOUND \
    --ip-addresses SubnetId=$PRIVATE_SUBNET_1A,Ip=10.0.11.10 SubnetId=$PRIVATE_SUBNET_1B,Ip=10.0.12.10 \
    --security-group-ids $DNS_SG_ID \
    --name "aws-inbound-resolver" \
    --tags Key=Name,Value=aws-inbound-resolver Key=Project,Value=aws-networking-hard-way

# Create outbound resolver endpoint (for AWS to query on-premises DNS)
aws route53resolver create-resolver-endpoint \
    --creator-request-id "outbound-$(date +%s)" \
    --direction OUTBOUND \
    --ip-addresses SubnetId=$PRIVATE_SUBNET_1A,Ip=10.0.11.20 SubnetId=$PRIVATE_SUBNET_1B,Ip=10.0.12.20 \
    --security-group-ids $DNS_SG_ID \
    --name "aws-outbound-resolver" \
    --tags Key=Name,Value=aws-outbound-resolver Key=Project,Value=aws-networking-hard-way

echo "Created Route 53 Resolver endpoints"

# Wait for endpoints to be operational
echo "Waiting for resolver endpoints to become operational..."
sleep 60

# Get resolver endpoint IDs
INBOUND_RESOLVER_ID=$(aws route53resolver list-resolver-endpoints \
    --filters Name=Name,Values=aws-inbound-resolver \
    --query 'ResolverEndpoints[0].Id' \
    --output text)

OUTBOUND_RESOLVER_ID=$(aws route53resolver list-resolver-endpoints \
    --filters Name=Name,Values=aws-outbound-resolver \
    --query 'ResolverEndpoints[0].Id' \
    --output text)

echo "Inbound Resolver ID: $INBOUND_RESOLVER_ID"
echo "Outbound Resolver ID: $OUTBOUND_RESOLVER_ID"
```

### Create Resolver Rules
```bash
# Create resolver rule for on-premises domain
aws route53resolver create-resolver-rule \
    --creator-request-id "onprem-rule-$(date +%s)" \
    --domain-name "onprem.local" \
    --rule-type FORWARD \
    --resolver-endpoint-id $OUTBOUND_RESOLVER_ID \
    --target-ips Ip=192.168.1.10,Port=53 Ip=192.168.1.11,Port=53 \
    --name "onprem-dns-rule" \
    --tags Key=Name,Value=onprem-dns-rule Key=Project,Value=aws-networking-hard-way

# Create resolver rule for branch office domain
aws route53resolver create-resolver-rule \
    --creator-request-id "branch-rule-$(date +%s)" \
    --domain-name "branch.local" \
    --rule-type FORWARD \
    --resolver-endpoint-id $OUTBOUND_RESOLVER_ID \
    --target-ips Ip=172.16.1.10,Port=53 \
    --name "branch-dns-rule" \
    --tags Key=Name,Value=branch-dns-rule Key=Project,Value=aws-networking-hard-way

# Associate rules with VPC
ONPREM_RULE_ID=$(aws route53resolver list-resolver-rules \
    --filters Name=Name,Values=onprem-dns-rule \
    --query 'ResolverRules[0].Id' \
    --output text)

BRANCH_RULE_ID=$(aws route53resolver list-resolver-rules \
    --filters Name=Name,Values=branch-dns-rule \
    --query 'ResolverRules[0].Id' \
    --output text)

aws route53resolver associate-resolver-rule \
    --resolver-rule-id $ONPREM_RULE_ID \
    --vpc-id $VPC_ID \
    --name "onprem-rule-association"

aws route53resolver associate-resolver-rule \
    --resolver-rule-id $BRANCH_RULE_ID \
    --vpc-id $VPC_ID \
    --name "branch-rule-association"

echo "Created and associated DNS resolver rules"
```

## Step 5: Create Hybrid Test Environment

### Deploy On-Premises Simulation Instance
```bash
# Create security group for on-premises simulation
aws ec2 create-security-group \
    --group-name onprem-simulation-sg \
    --description "Security group for on-premises simulation" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=onprem-simulation-sg},{Key=Purpose,Value=hybrid-testing}]'

ONPREM_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=onprem-simulation-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow all traffic from VPC (simulating on-premises connectivity)
aws ec2 authorize-security-group-ingress \
    --group-id $ONPREM_SG_ID \
    --protocol -1 \
    --cidr 10.0.0.0/16

# Allow SSH from your IP
YOUR_IP=$(curl -s http://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
    --group-id $ONPREM_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr ${YOUR_IP}/32

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

# Create key pair for hybrid testing
aws ec2 create-key-pair \
    --key-name hybrid-test-key \
    --query 'KeyMaterial' \
    --output text > hybrid-test-key.pem 2>/dev/null || echo "Key pair already exists"

chmod 400 hybrid-test-key.pem 2>/dev/null

# Deploy on-premises simulation instance
PUBLIC_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-web-1a" --query 'Subnets[0].SubnetId' --output text)

aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name hybrid-test-key \
    --subnet-id $PUBLIC_SUBNET_1A \
    --security-group-ids $ONPREM_SG_ID \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=onprem-simulation},{Key=Environment,Value=on-premises},{Key=Project,Value=aws-networking-hard-way}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y bind-utils tcpdump traceroute nmap strongswan

# Configure as simulated on-premises server
echo "192.168.1.10 onprem-server.onprem.local" >> /etc/hosts
echo "172.16.1.10 branch-server.branch.local" >> /etc/hosts

# Create test DNS server simulation
cat > /home/ec2-user/test-dns.sh << "SCRIPT_EOF"
#!/bin/bash
echo "Simulated On-Premises DNS Server"
echo "================================"
echo "onprem-server.onprem.local -> 192.168.1.10"
echo "branch-server.branch.local -> 172.16.1.10"
echo "datacenter.onprem.local -> 192.168.1.100"
SCRIPT_EOF

chmod +x /home/ec2-user/test-dns.sh

# Install and configure simple HTTP server
cat > /var/www/html/index.html << "HTML_EOF"
<h1>On-Premises Simulation Server</h1>
<p>Environment: Simulated On-Premises</p>
<p>Network: 192.168.0.0/16</p>
<p>Services: DNS, DHCP, File Server</p>
<p>VPN Status: Connected to AWS</p>
HTML_EOF

systemctl start httpd
systemctl enable httpd'

echo "Deployed on-premises simulation instance"
```

### Create Hybrid Connectivity Test
```bash
cat > test-hybrid-connectivity.sh << 'EOF'
#!/bin/bash

echo "🌉 Testing Hybrid Connectivity"
echo "============================="

# Get instance IPs
ONPREM_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=onprem-simulation" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
ONPREM_PRIVATE_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=onprem-simulation" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
AWS_INSTANCE_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=app-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "N/A")

echo "Instance IPs:"
echo "  On-Premises Simulation: $ONPREM_IP (Public), $ONPREM_PRIVATE_IP (Private)"
echo "  AWS Instance: $AWS_INSTANCE_IP"
echo ""

# Test 1: VPN Connection Status
echo "Test 1: VPN Connection Status"
echo "-----------------------------"
VPN_ID=$(aws ec2 describe-vpn-connections --filters "Name=tag:Name,Values=primary-vpn-connection" --query 'VpnConnections[0].VpnConnectionId' --output text)
VPN_STATUS=$(aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_ID --query 'VpnConnections[0].State' --output text)

if [ "$VPN_STATUS" = "available" ]; then
    echo "✅ PASS: Primary VPN connection is available"
    
    # Check tunnel status
    TUNNEL_STATUS=$(aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_ID --query 'VpnConnections[0].VgwTelemetry[0].Status' --output text)
    echo "   Tunnel 1 Status: $TUNNEL_STATUS"
    
    TUNNEL2_STATUS=$(aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_ID --query 'VpnConnections[0].VgwTelemetry[1].Status' --output text)
    echo "   Tunnel 2 Status: $TUNNEL2_STATUS"
else
    echo "❌ FAIL: Primary VPN connection status: $VPN_STATUS"
fi

# Test 2: Route Propagation
echo ""
echo "Test 2: Route Propagation"
echo "------------------------"
VGW_ID=$(aws ec2 describe-vpn-gateways --filters "Name=tag:Name,Values=aws-vpn-gateway" --query 'VpnGateways[0].VpnGatewayId' --output text)
PROPAGATED_ROUTES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)" --query "RouteTables[?PropagatingVgws[?GatewayId=='$VGW_ID']]" --output text)

if [ ! -z "$PROPAGATED_ROUTES" ]; then
    echo "✅ PASS: Route propagation is enabled"
else
    echo "❌ FAIL: Route propagation is not enabled"
fi

# Test 3: DNS Resolution
echo ""
echo "Test 3: DNS Resolution"
echo "---------------------"
RESOLVER_STATUS=$(aws route53resolver list-resolver-endpoints --query 'ResolverEndpoints[0].Status' --output text 2>/dev/null || echo "NONE")

if [ "$RESOLVER_STATUS" = "OPERATIONAL" ]; then
    echo "✅ PASS: Route 53 Resolver endpoints are operational"
else
    echo "❌ FAIL: Route 53 Resolver endpoints status: $RESOLVER_STATUS"
fi

# Test 4: Connectivity Test (if instances are available)
echo ""
echo "Test 4: Cross-Network Connectivity"
echo "---------------------------------"

if [ "$ONPREM_IP" != "None" ] && [ "$AWS_INSTANCE_IP" != "N/A" ]; then
    echo "ℹ️  Manual test required:"
    echo "   1. SSH to on-premises simulation: ssh -i hybrid-test-key.pem ec2-user@$ONPREM_IP"
    echo "   2. Test connectivity to AWS: ping $AWS_INSTANCE_IP"
    echo "   3. Test DNS resolution: nslookup internal.aws.domain"
else
    echo "⚠️  SKIP: Instances not available for connectivity test"
fi

# Test 5: BGP Status (simulated)
echo ""
echo "Test 5: BGP Configuration"
echo "------------------------"
echo "ℹ️  BGP configuration would be verified on physical routers:"
echo "   - Check BGP neighbor status"
echo "   - Verify route advertisements"
echo "   - Confirm path preferences"
echo "   - Test failover scenarios"

echo ""
echo "🎯 Hybrid Connectivity Test Complete"
echo ""
echo "📋 Next Steps:"
echo "1. Configure physical routers with VPN settings from vpn-config.xml"
echo "2. Set up BGP routing with appropriate path preferences"
echo "3. Configure on-premises DNS to forward AWS queries to resolver endpoints"
echo "4. Test failover scenarios by disabling primary connection"
EOF

chmod +x test-hybrid-connectivity.sh
echo "Created hybrid connectivity test: test-hybrid-connectivity.sh"
```

## Step 6: Test Failover Scenarios

### Create Failover Test Script
```bash
cat > test-failover-scenarios.sh << 'EOF'
#!/bin/bash

echo "🔄 Testing Hybrid Failover Scenarios"
echo "===================================="

VPN_ID=$(aws ec2 describe-vpn-connections --filters "Name=tag:Name,Values=primary-vpn-connection" --query 'VpnConnections[0].VpnConnectionId' --output text)
BACKUP_VPN_ID=$(aws ec2 describe-vpn-connections --filters "Name=tag:Name,Values=dx-backup-vpn" --query 'VpnConnections[0].VpnConnectionId' --output text)

echo "Primary VPN: $VPN_ID"
echo "Backup VPN: $BACKUP_VPN_ID"
echo ""

# Test 1: Check current tunnel status
echo "Test 1: Current Tunnel Status"
echo "-----------------------------"

echo "Primary VPN Tunnels:"
aws ec2 describe-vpn-connections \
    --vpn-connection-ids $VPN_ID \
    --query 'VpnConnections[0].VgwTelemetry[].{Tunnel:OutsideIpAddress,Status:Status,LastStatusChange:LastStatusChange}' \
    --output table

echo ""
echo "Backup VPN Tunnels:"
aws ec2 describe-vpn-connections \
    --vpn-connection-ids $BACKUP_VPN_ID \
    --query 'VpnConnections[0].VgwTelemetry[].{Tunnel:OutsideIpAddress,Status:Status,LastStatusChange:LastStatusChange}' \
    --output table

# Test 2: Route table analysis
echo ""
echo "Test 2: Current Route Tables"
echo "---------------------------"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)

aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[].{RouteTable:RouteTableId,Routes:Routes[?State==`active`].{Dest:DestinationCidrBlock,Target:GatewayId}}' \
    --output json | jq -r '.[] | "Route Table: \(.RouteTable)", (.Routes[] | "  \(.Dest) -> \(.Target)"), ""'

# Test 3: Simulate failover monitoring
echo ""
echo "Test 3: Failover Monitoring Setup"
echo "---------------------------------"

cat > monitor-vpn-status.sh << 'MONITOR_EOF'
#!/bin/bash

# This script would run continuously to monitor VPN status
echo "VPN Monitoring Script"
echo "===================="

while true; do
    PRIMARY_STATUS=$(aws ec2 describe-vpn-connections --vpn-connection-ids VPN_ID_PLACEHOLDER --query 'VpnConnections[0].VgwTelemetry[0].Status' --output text)
    BACKUP_STATUS=$(aws ec2 describe-vpn-connections --vpn-connection-ids BACKUP_VPN_ID_PLACEHOLDER --query 'VpnConnections[0].VgwTelemetry[0].Status' --output text)
    
    echo "$(date): Primary=$PRIMARY_STATUS, Backup=$BACKUP_STATUS"
    
    if [ "$PRIMARY_STATUS" != "UP" ] && [ "$BACKUP_STATUS" = "UP" ]; then
        echo "ALERT: Primary VPN down, backup is active"
        # Send notification
        aws sns publish --topic-arn arn:aws:sns:region:account:vpn-alerts --message "VPN failover detected"
    fi
    
    sleep 60
done
MONITOR_EOF

sed -i "s/VPN_ID_PLACEHOLDER/$VPN_ID/g" monitor-vpn-status.sh
sed -i "s/BACKUP_VPN_ID_PLACEHOLDER/$BACKUP_VPN_ID/g" monitor-vpn-status.sh
chmod +x monitor-vpn-status.sh

echo "Created VPN monitoring script: monitor-vpn-status.sh"

# Test 4: Failover procedures
echo ""
echo "Test 4: Failover Procedures"
echo "--------------------------"
echo "In a production environment, failover would be handled by:"
echo "1. BGP route preferences (automatic)"
echo "2. Health checks and monitoring"
echo "3. Automated alerting systems"
echo "4. Network operations center procedures"
echo ""
echo "Manual failover testing:"
echo "1. Disable primary connection on customer gateway"
echo "2. Monitor route table changes"
echo "3. Verify traffic flows through backup connection"
echo "4. Test application connectivity"
echo "5. Re-enable primary and verify failback"

echo ""
echo "🎯 Failover Testing Complete"
EOF

chmod +x test-failover-scenarios.sh
echo "Created failover testing script: test-failover-scenarios.sh"
```

## Step 7: Performance Optimization

### Create Performance Testing Tools
```bash
cat > test-hybrid-performance.sh << 'EOF'
#!/bin/bash

echo "📊 Hybrid Network Performance Testing"
echo "===================================="

# Test 1: Latency measurements
echo "Test 1: Network Latency"
echo "----------------------"

ONPREM_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=onprem-simulation" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
AWS_INSTANCE_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=app-server-1a" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo "N/A")

if [ "$ONPREM_IP" != "None" ] && [ "$AWS_INSTANCE_IP" != "N/A" ]; then
    echo "Testing latency from on-premises to AWS..."
    echo "Command to run on on-premises server:"
    echo "  ping -c 10 $AWS_INSTANCE_IP"
    echo "  traceroute $AWS_INSTANCE_IP"
else
    echo "⚠️  Instances not available for latency testing"
fi

# Test 2: Bandwidth testing
echo ""
echo "Test 2: Bandwidth Testing"
echo "------------------------"
echo "For bandwidth testing, use iperf3:"
echo "1. On AWS instance: iperf3 -s"
echo "2. On on-premises: iperf3 -c $AWS_INSTANCE_IP -t 30"
echo ""
echo "Expected performance over VPN:"
echo "- Latency: 20-100ms (depending on distance)"
echo "- Bandwidth: Up to 1.25 Gbps per tunnel"
echo "- Packet loss: <0.1%"

# Test 3: DNS performance
echo ""
echo "Test 3: DNS Resolution Performance"
echo "---------------------------------"
echo "Test DNS resolution times:"
echo "1. AWS to on-premises: dig @10.0.11.10 onprem-server.onprem.local"
echo "2. On-premises to AWS: dig internal.aws.domain"
echo ""
echo "Expected DNS performance:"
echo "- Resolution time: <100ms"
echo "- Cache hit ratio: >90%"

# Test 4: Application performance
echo ""
echo "Test 4: Application Performance"
echo "------------------------------"
echo "Monitor application metrics:"
echo "- Database query response times"
echo "- File transfer speeds"
echo "- API call latencies"
echo "- User experience metrics"

# Test 5: Optimization recommendations
echo ""
echo "Test 5: Performance Optimization"
echo "-------------------------------"
echo "Optimization strategies:"
echo "1. Enable jumbo frames (9000 MTU) where supported"
echo "2. Use multiple VPN tunnels for increased bandwidth"
echo "3. Implement local caching for frequently accessed data"
echo "4. Optimize application protocols for WAN latency"
echo "5. Use compression for data transfers"
echo "6. Consider AWS Direct Connect for consistent performance"

echo ""
echo "🎯 Performance Testing Complete"
EOF

chmod +x test-hybrid-performance.sh
echo "Created performance testing script: test-hybrid-performance.sh"
```

## Validation Commands

### Verify Hybrid Setup
```bash
# Check VPN connections
echo "🔍 VPN Connections Status:"
aws ec2 describe-vpn-connections \
    --query 'VpnConnections[].{ID:VpnConnectionId,State:State,Type:Type,CustomerGateway:CustomerGatewayId}' \
    --output table

# Check Virtual Private Gateway
echo ""
echo "🚪 Virtual Private Gateway:"
aws ec2 describe-vpn-gateways \
    --query 'VpnGateways[].{ID:VpnGatewayId,State:State,Type:Type,Attachments:VpcAttachments[].VpcId}' \
    --output table

# Check Route 53 Resolver
echo ""
echo "🌐 Route 53 Resolver Endpoints:"
aws route53resolver list-resolver-endpoints \
    --query 'ResolverEndpoints[].{ID:Id,Direction:Direction,Status:Status,IpCount:IpAddressCount}' \
    --output table

# Check resolver rules
echo ""
echo "📋 Resolver Rules:"
aws route53resolver list-resolver-rules \
    --query 'ResolverRules[].{ID:Id,Domain:DomainName,Type:RuleType,Status:Status}' \
    --output table
```

## Cleanup for This Lab

```bash
cat > cleanup-lab05.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Lab 05 resources..."

# Terminate on-premises simulation instance
echo "Terminating on-premises simulation instance..."
ONPREM_INSTANCE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=onprem-simulation" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
if [ "$ONPREM_INSTANCE" != "None" ] && [ ! -z "$ONPREM_INSTANCE" ]; then
    aws ec2 terminate-instances --instance-ids $ONPREM_INSTANCE
    aws ec2 wait instance-terminated --instance-ids $ONPREM_INSTANCE
fi

# Delete resolver rule associations
echo "Deleting resolver rule associations..."
RULE_ASSOCIATIONS=$(aws route53resolver list-resolver-rule-associations --query 'ResolverRuleAssociations[].Id' --output text)
for ASSOC in $RULE_ASSOCIATIONS; do
    [ ! -z "$ASSOC" ] && aws route53resolver disassociate-resolver-rule --resolver-rule-association-id $ASSOC
done

# Delete resolver rules
echo "Deleting resolver rules..."
RESOLVER_RULES=$(aws route53resolver list-resolver-rules --query 'ResolverRules[?CreatorRequestId!=`Route 53 Resolver`].Id' --output text)
for RULE in $RESOLVER_RULES; do
    [ ! -z "$RULE" ] && aws route53resolver delete-resolver-rule --resolver-rule-id $RULE
done

# Delete resolver endpoints
echo "Deleting resolver endpoints..."
RESOLVER_ENDPOINTS=$(aws route53resolver list-resolver-endpoints --query 'ResolverEndpoints[].Id' --output text)
for ENDPOINT in $RESOLVER_ENDPOINTS; do
    [ ! -z "$ENDPOINT" ] && aws route53resolver delete-resolver-endpoint --resolver-endpoint-id $ENDPOINT
done

# Delete VPN connections
echo "Deleting VPN connections..."
VPN_CONNECTIONS=$(aws ec2 describe-vpn-connections --filters "Name=state,Values=available" --query 'VpnConnections[].VpnConnectionId' --output text)
for VPN in $VPN_CONNECTIONS; do
    [ ! -z "$VPN" ] && aws ec2 delete-vpn-connection --vpn-connection-id $VPN
done

# Wait for VPN connections to be deleted
sleep 60

# Detach and delete Virtual Private Gateway
echo "Deleting Virtual Private Gateway..."
VGW_ID=$(aws ec2 describe-vpn-gateways --filters "Name=tag:Name,Values=aws-vpn-gateway" --query 'VpnGateways[0].VpnGatewayId' --output text)
if [ "$VGW_ID" != "None" ]; then
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
    aws ec2 detach-vpn-gateway --vpn-gateway-id $VGW_ID --vpc-id $VPC_ID
    aws ec2 wait vpn-gateway-detached --vpn-gateway-ids $VGW_ID
    aws ec2 delete-vpn-gateway --vpn-gateway-id $VGW_ID
fi

# Delete Customer Gateways
echo "Deleting Customer Gateways..."
CUSTOMER_GATEWAYS=$(aws ec2 describe-customer-gateways --filters "Name=state,Values=available" --query 'CustomerGateways[].CustomerGatewayId' --output text)
for CGW in $CUSTOMER_GATEWAYS; do
    [ ! -z "$CGW" ] && aws ec2 delete-customer-gateway --customer-gateway-id $CGW
done

# Delete security groups
echo "Deleting security groups..."
DNS_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=dns-resolver-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
ONPREM_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=onprem-simulation-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

[ "$DNS_SG" != "None" ] && aws ec2 delete-security-group --group-id $DNS_SG 2>/dev/null
[ "$ONPREM_SG" != "None" ] && aws ec2 delete-security-group --group-id $ONPREM_SG 2>/dev/null

# Delete key pair
aws ec2 delete-key-pair --key-name hybrid-test-key 2>/dev/null
rm -f hybrid-test-key.pem vpn-config.xml

echo "✅ Lab 05 cleanup completed"
EOF

chmod +x cleanup-lab05.sh
echo "Created cleanup script: cleanup-lab05.sh"
```

## Next Steps

After completing this lab, you should have:
- ✅ Site-to-Site VPN connections with redundancy
- ✅ BGP routing configuration knowledge
- ✅ Hybrid DNS resolution with Route 53 Resolver
- ✅ Performance testing and optimization strategies
- ✅ Failover scenarios and monitoring

**Continue to:** [Lab 06: Load Balancing Strategies](../06-load-balancing-strategies/README.md)