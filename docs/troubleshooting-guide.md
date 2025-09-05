# Network Troubleshooting Guide

## Common Issues and Solutions

### 1. Connectivity Issues

#### Problem: Cannot reach EC2 instance from internet
**Symptoms:**
- Connection timeouts
- No response from public IP

**Troubleshooting Steps:**
```bash
# Check instance has public IP
aws ec2 describe-instances --instance-ids i-1234567890abcdef0

# Verify security group rules
aws ec2 describe-security-groups --group-ids sg-1234567890abcdef0

# Check route table associations
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-12345"

# Verify internet gateway attachment
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=vpc-12345"
```

**Common Causes:**
- Missing security group rules
- No public IP assigned
- Route table not associated with IGW
- NACL blocking traffic

#### Problem: Private instances cannot reach internet
**Symptoms:**
- Cannot download packages
- API calls fail
- No outbound connectivity

**Troubleshooting Steps:**
```bash
# Check NAT Gateway status
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=vpc-12345"

# Verify route table has NAT Gateway route
aws ec2 describe-route-tables --filters "Name=route.destination-cidr-block,Values=0.0.0.0/0"

# Check NAT Gateway subnet has IGW route
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-nat-12345"
```

### 2. DNS Resolution Issues

#### Problem: DNS queries not resolving
**Symptoms:**
- Cannot resolve domain names
- Application errors related to DNS

**Troubleshooting Steps:**
```bash
# Check VPC DNS settings
aws ec2 describe-vpc-attribute --vpc-id vpc-12345 --attribute enableDnsHostnames
aws ec2 describe-vpc-attribute --vpc-id vpc-12345 --attribute enableDnsSupport

# Test DNS resolution from instance
nslookup example.com
dig @169.254.169.253 example.com

# Check Route 53 resolver rules
aws route53resolver list-resolver-rules
```

### 3. Load Balancer Issues

#### Problem: Load balancer not distributing traffic
**Symptoms:**
- All traffic going to one target
- Targets showing unhealthy

**Troubleshooting Steps:**
```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...

# Verify security group rules for targets
aws ec2 describe-security-groups --group-ids sg-target-12345

# Check load balancer attributes
aws elbv2 describe-load-balancer-attributes --load-balancer-arn arn:aws:elasticloadbalancing:...
```

### 4. VPC Peering Issues

#### Problem: Cannot communicate across VPC peering connection
**Symptoms:**
- Timeouts between peered VPCs
- Route not working

**Troubleshooting Steps:**
```bash
# Check peering connection status
aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids pcx-12345

# Verify route tables have peering routes
aws ec2 describe-route-tables --filters "Name=route.vpc-peering-connection-id,Values=pcx-12345"

# Check security groups allow cross-VPC traffic
aws ec2 describe-security-groups --filters "Name=ip-permission.cidr,Values=10.1.0.0/16"
```

## Diagnostic Commands

### Network Connectivity Testing
```bash
# Test connectivity to specific port
telnet target-host 80
nc -zv target-host 80

# Trace network path
traceroute target-host
mtr target-host

# Test DNS resolution
nslookup domain.com
dig domain.com
host domain.com
```

### AWS CLI Diagnostics
```bash
# Check VPC configuration
aws ec2 describe-vpcs --vpc-ids vpc-12345

# List all subnets in VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-12345"

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-12345

# Verify route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-12345"

# Check NAT Gateways
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=vpc-12345"

# List internet gateways
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=vpc-12345"
```

### VPC Flow Logs Analysis
```bash
# Query flow logs with AWS CLI
aws logs filter-log-events \
    --log-group-name VPCFlowLogs \
    --start-time 1609459200000 \
    --filter-pattern "{ $.srcaddr = \"10.0.1.100\" }"

# Using Athena for complex queries
SELECT srcaddr, dstaddr, srcport, dstport, protocol, action, COUNT(*) as count
FROM vpc_flow_logs
WHERE day = '2023/12/01'
AND action = 'REJECT'
GROUP BY srcaddr, dstaddr, srcport, dstport, protocol, action
ORDER BY count DESC
LIMIT 10;
```

## Performance Troubleshooting

### Network Latency Issues
```bash
# Measure latency
ping -c 10 target-host

# Continuous monitoring
ping -i 0.2 target-host

# Check for packet loss
ping -c 100 target-host | grep "packet loss"
```

### Bandwidth Testing
```bash
# Install iperf3 on both ends
sudo yum install iperf3

# Server side
iperf3 -s

# Client side
iperf3 -c server-ip -t 30
```

### Application-Level Diagnostics
```bash
# HTTP response time testing
curl -w "@curl-format.txt" -o /dev/null -s "http://example.com"

# Where curl-format.txt contains:
#     time_namelookup:  %{time_namelookup}\n
#        time_connect:  %{time_connect}\n
#     time_appconnect:  %{time_appconnect}\n
#    time_pretransfer:  %{time_pretransfer}\n
#       time_redirect:  %{time_redirect}\n
#  time_starttransfer:  %{time_starttransfer}\n
#                     ----------\n
#          time_total:  %{time_total}\n
```

## Security Troubleshooting

### Security Group Analysis
```bash
# Find overly permissive rules
aws ec2 describe-security-groups \
    --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]]'

# Check for unused security groups
aws ec2 describe-security-groups \
    --query 'SecurityGroups[?length(IpPermissions)==`0` && length(IpPermissionsEgress)==`1`]'
```

### NACL Troubleshooting
```bash
# Check NACL rules
aws ec2 describe-network-acls --network-acl-ids acl-12345

# Find NACL associations
aws ec2 describe-network-acls \
    --filters "Name=association.subnet-id,Values=subnet-12345"
```

## Monitoring and Alerting

### CloudWatch Metrics to Monitor
```bash
# VPC Flow Logs metrics
aws logs put-metric-filter \
    --log-group-name VPCFlowLogs \
    --filter-name RejectTraffic \
    --filter-pattern "[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action=\"REJECT\", flowlogstatus]" \
    --metric-transformations \
        metricName=VPCFlowLogsRejectCount,metricNamespace=VPC/FlowLogs,metricValue=1
```

### Custom Monitoring Scripts
```bash
#!/bin/bash
# Monitor NAT Gateway connectivity
NAT_GW_ID="nat-12345"
INSTANCE_ID="i-12345"

# Check NAT Gateway status
STATUS=$(aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GW_ID --query 'NatGateways[0].State' --output text)

if [ "$STATUS" != "available" ]; then
    echo "NAT Gateway $NAT_GW_ID is not available: $STATUS"
    # Send alert
    aws sns publish --topic-arn arn:aws:sns:us-east-1:123456789012:alerts --message "NAT Gateway failure detected"
fi
```

## Escalation Procedures

### When to Contact AWS Support
- Regional service outages
- Suspected AWS infrastructure issues
- Direct Connect connectivity problems
- Unusual network behavior across multiple AZs

### Information to Gather
- VPC ID and region
- Affected resource IDs
- Timeline of the issue
- Error messages and logs
- Network topology diagram
- Recent changes made

### Emergency Contacts
- AWS Support (if you have a support plan)
- Internal network team
- Application team contacts
- Management escalation path

## Prevention Best Practices

### Design Principles
- Implement redundancy at every layer
- Use multiple AZs for critical components
- Design for failure scenarios
- Monitor everything
- Automate responses where possible

### Regular Maintenance
- Review security group rules monthly
- Audit NACL configurations
- Test disaster recovery procedures
- Update monitoring thresholds
- Review and update documentation