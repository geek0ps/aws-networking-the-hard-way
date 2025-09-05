# Lab 06: Load Balancing Strategies - Detailed Steps

## Prerequisites
- Completed Labs 01-05
- Understanding of load balancing concepts
- AWS CLI configured with appropriate permissions

```bash
# Set environment variables
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
echo "Working with VPC: $VPC_ID"
```

## Step 1: Deploy Application Load Balancer (ALB)

### Create Target Groups for ALB
```bash
# Create target group for web servers
aws elbv2 create-target-group \
    --name web-servers-tg \
    --protocol HTTP \
    --port 80 \
    --vpc-id $VPC_ID \
    --health-check-protocol HTTP \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --tags Key=Name,Value=web-servers-tg Key=Project,Value=aws-networking-hard-way

WEB_TG_ARN=$(aws elbv2 describe-target-groups \
    --names web-servers-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# Create target group for API servers
aws elbv2 create-target-group \
    --name api-servers-tg \
    --protocol HTTP \
    --port 8080 \
    --vpc-id $VPC_ID \
    --health-check-protocol HTTP \
    --health-check-path /api/health \
    --health-check-interval-seconds 15 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --tags Key=Name,Value=api-servers-tg Key=Project,Value=aws-networking-hard-way

API_TG_ARN=$(aws elbv2 describe-target-groups \
    --names api-servers-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

# Create target group for mobile API
aws elbv2 create-target-group \
    --name mobile-api-tg \
    --protocol HTTP \
    --port 8080 \
    --vpc-id $VPC_ID \
    --health-check-protocol HTTP \
    --health-check-path /mobile/health \
    --health-check-interval-seconds 10 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --tags Key=Name,Value=mobile-api-tg Key=Project,Value=aws-networking-hard-way

MOBILE_TG_ARN=$(aws elbv2 describe-target-groups \
    --names mobile-api-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

echo "Created target groups:"
echo "  Web Servers: $WEB_TG_ARN"
echo "  API Servers: $API_TG_ARN"
echo "  Mobile API: $MOBILE_TG_ARN"
```

### Create Security Group for ALB
```bash
# Create security group for Application Load Balancer
aws ec2 create-security-group \
    --group-name alb-sg \
    --description "Security group for Application Load Balancer" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=alb-sg},{Key=Purpose,Value=load-balancer}]'

ALB_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=alb-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow HTTP and HTTPS from internet
aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $ALB_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0

echo "Created ALB security group: $ALB_SG_ID"
```

### Create Application Load Balancer
```bash
# Get public subnet IDs
PUBLIC_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-web-1a" --query 'Subnets[0].SubnetId' --output text)
PUBLIC_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-web-1b" --query 'Subnets[0].SubnetId' --output text)

# Create Application Load Balancer
aws elbv2 create-load-balancer \
    --name enterprise-alb \
    --subnets $PUBLIC_SUBNET_1A $PUBLIC_SUBNET_1B \
    --security-groups $ALB_SG_ID \
    --scheme internet-facing \
    --type application \
    --ip-address-type ipv4 \
    --tags Key=Name,Value=enterprise-alb Key=Project,Value=aws-networking-hard-way

ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names enterprise-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names enterprise-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo "Created Application Load Balancer:"
echo "  ARN: $ALB_ARN"
echo "  DNS: $ALB_DNS"
```

### Configure ALB Listeners and Rules
```bash
# Create HTTP listener with path-based routing
aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$WEB_TG_ARN \
    --tags Key=Name,Value=alb-http-listener

HTTP_LISTENER_ARN=$(aws elbv2 describe-listeners \
    --load-balancer-arn $ALB_ARN \
    --query 'Listeners[?Port==`80`].ListenerArn' \
    --output text)

# Create rule for API path
aws elbv2 create-rule \
    --listener-arn $HTTP_LISTENER_ARN \
    --priority 100 \
    --conditions Field=path-pattern,Values="/api/*" \
    --actions Type=forward,TargetGroupArn=$API_TG_ARN \
    --tags Key=Name,Value=api-routing-rule

# Create rule for mobile API path
aws elbv2 create-rule \
    --listener-arn $HTTP_LISTENER_ARN \
    --priority 200 \
    --conditions Field=path-pattern,Values="/mobile/*" \
    --actions Type=forward,TargetGroupArn=$MOBILE_TG_ARN \
    --tags Key=Name,Value=mobile-routing-rule

# Create rule for host-based routing (if you have multiple domains)
aws elbv2 create-rule \
    --listener-arn $HTTP_LISTENER_ARN \
    --priority 300 \
    --conditions Field=host-header,Values="api.example.com" \
    --actions Type=forward,TargetGroupArn=$API_TG_ARN \
    --tags Key=Name,Value=host-based-rule

echo "Configured ALB listeners and routing rules"
```

## Step 2: Deploy Network Load Balancer (NLB)

### Create Target Group for NLB
```bash
# Create target group for TCP load balancing
aws elbv2 create-target-group \
    --name tcp-servers-tg \
    --protocol TCP \
    --port 3306 \
    --vpc-id $VPC_ID \
    --health-check-protocol TCP \
    --health-check-port 3306 \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --tags Key=Name,Value=tcp-servers-tg Key=Project,Value=aws-networking-hard-way

TCP_TG_ARN=$(aws elbv2 describe-target-groups \
    --names tcp-servers-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

echo "Created TCP target group: $TCP_TG_ARN"
```

### Create Network Load Balancer
```bash
# Create Network Load Balancer
aws elbv2 create-load-balancer \
    --name enterprise-nlb \
    --subnets $PUBLIC_SUBNET_1A $PUBLIC_SUBNET_1B \
    --scheme internet-facing \
    --type network \
    --ip-address-type ipv4 \
    --tags Key=Name,Value=enterprise-nlb Key=Project,Value=aws-networking-hard-way

NLB_ARN=$(aws elbv2 describe-load-balancers \
    --names enterprise-nlb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)

NLB_DNS=$(aws elbv2 describe-load-balancers \
    --names enterprise-nlb \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

# Create TCP listener
aws elbv2 create-listener \
    --load-balancer-arn $NLB_ARN \
    --protocol TCP \
    --port 3306 \
    --default-actions Type=forward,TargetGroupArn=$TCP_TG_ARN \
    --tags Key=Name,Value=nlb-tcp-listener

echo "Created Network Load Balancer:"
echo "  ARN: $NLB_ARN"
echo "  DNS: $NLB_DNS"
```

## Step 3: Deploy Backend Instances

### Create Security Groups for Backend Servers
```bash
# Create security group for web servers
aws ec2 create-security-group \
    --group-name web-servers-sg \
    --description "Security group for web servers behind ALB" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=web-servers-sg},{Key=Tier,Value=web}]'

WEB_SERVERS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=web-servers-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow HTTP from ALB only
aws ec2 authorize-security-group-ingress \
    --group-id $WEB_SERVERS_SG_ID \
    --protocol tcp \
    --port 80 \
    --source-group $ALB_SG_ID

# Create security group for API servers
aws ec2 create-security-group \
    --group-name api-servers-sg \
    --description "Security group for API servers behind ALB" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=api-servers-sg},{Key=Tier,Value=api}]'

API_SERVERS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=api-servers-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow port 8080 from ALB only
aws ec2 authorize-security-group-ingress \
    --group-id $API_SERVERS_SG_ID \
    --protocol tcp \
    --port 8080 \
    --source-group $ALB_SG_ID

# Create security group for database servers
aws ec2 create-security-group \
    --group-name db-servers-sg \
    --description "Security group for database servers behind NLB" \
    --vpc-id $VPC_ID \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=db-servers-sg},{Key=Tier,Value=database}]'

DB_SERVERS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=db-servers-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

# Allow MySQL from private subnets (NLB doesn't have security groups)
aws ec2 authorize-security-group-ingress \
    --group-id $DB_SERVERS_SG_ID \
    --protocol tcp \
    --port 3306 \
    --cidr 10.0.0.0/16

echo "Created security groups for backend servers"
```

### Deploy Web Servers
```bash
# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

# Create key pair for load balancer testing
aws ec2 create-key-pair \
    --key-name lb-test-key \
    --query 'KeyMaterial' \
    --output text > lb-test-key.pem 2>/dev/null || echo "Key pair already exists"

chmod 400 lb-test-key.pem 2>/dev/null

# Get private subnet IDs
PRIVATE_SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-app-1a" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=private-app-1b" --query 'Subnets[0].SubnetId' --output text)

# Deploy web server 1
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name lb-test-key \
    --subnet-id $PRIVATE_SUBNET_1A \
    --security-group-ids $WEB_SERVERS_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=web-server-1},{Key=Tier,Value=web},{Key=AZ,Value=1a}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# Create health check endpoint
echo "OK" > /var/www/html/health

# Create main page
cat > /var/www/html/index.html << EOF
<h1>Web Server 1</h1>
<p>Availability Zone: us-east-1a</p>
<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
<p>Local IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)</p>
<p>Timestamp: $(date)</p>
EOF

# Configure custom error page
cat > /var/www/html/error.html << EOF
<h1>Service Temporarily Unavailable</h1>
<p>Server: Web Server 1</p>
<p>Please try again later</p>
EOF'

# Deploy web server 2
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name lb-test-key \
    --subnet-id $PRIVATE_SUBNET_1B \
    --security-group-ids $WEB_SERVERS_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=web-server-2},{Key=Tier,Value=web},{Key=AZ,Value=1b}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# Create health check endpoint
echo "OK" > /var/www/html/health

# Create main page
cat > /var/www/html/index.html << EOF
<h1>Web Server 2</h1>
<p>Availability Zone: us-east-1b</p>
<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
<p>Local IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)</p>
<p>Timestamp: $(date)</p>
EOF

# Configure custom error page
cat > /var/www/html/error.html << EOF
<h1>Service Temporarily Unavailable</h1>
<p>Server: Web Server 2</p>
<p>Please try again later</p>
EOF'

echo "Deployed web servers"
```

### Deploy API Servers
```bash
# Deploy API server 1
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name lb-test-key \
    --subnet-id $PRIVATE_SUBNET_1A \
    --security-group-ids $API_SERVERS_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=api-server-1},{Key=Tier,Value=api},{Key=AZ,Value=1a}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y python3 python3-pip
pip3 install flask

mkdir -p /opt/api
cat > /opt/api/app.py << "EOF"
from flask import Flask, jsonify, request
import socket
import os
import time

app = Flask(__name__)

@app.route("/api/health")
def health():
    return jsonify({"status": "healthy", "server": "api-server-1"})

@app.route("/api/info")
def info():
    return jsonify({
        "server": "api-server-1",
        "hostname": socket.gethostname(),
        "instance_id": os.popen("curl -s http://169.254.169.254/latest/meta-data/instance-id").read().strip(),
        "availability_zone": "us-east-1a",
        "timestamp": time.time()
    })

@app.route("/mobile/health")
def mobile_health():
    return jsonify({"status": "healthy", "service": "mobile-api", "server": "api-server-1"})

@app.route("/mobile/info")
def mobile_info():
    return jsonify({
        "service": "mobile-api",
        "server": "api-server-1",
        "version": "1.0.0",
        "features": ["push_notifications", "offline_sync", "biometric_auth"]
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

cd /opt/api
nohup python3 app.py > /var/log/api.log 2>&1 &'

# Deploy API server 2
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t2.micro \
    --key-name lb-test-key \
    --subnet-id $PRIVATE_SUBNET_1B \
    --security-group-ids $API_SERVERS_SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=api-server-2},{Key=Tier,Value=api},{Key=AZ,Value=1b}]' \
    --user-data '#!/bin/bash
yum update -y
yum install -y python3 python3-pip
pip3 install flask

mkdir -p /opt/api
cat > /opt/api/app.py << "EOF"
from flask import Flask, jsonify, request
import socket
import os
import time

app = Flask(__name__)

@app.route("/api/health")
def health():
    return jsonify({"status": "healthy", "server": "api-server-2"})

@app.route("/api/info")
def info():
    return jsonify({
        "server": "api-server-2",
        "hostname": socket.gethostname(),
        "instance_id": os.popen("curl -s http://169.254.169.254/latest/meta-data/instance-id").read().strip(),
        "availability_zone": "us-east-1b",
        "timestamp": time.time()
    })

@app.route("/mobile/health")
def mobile_health():
    return jsonify({"status": "healthy", "service": "mobile-api", "server": "api-server-2"})

@app.route("/mobile/info")
def mobile_info():
    return jsonify({
        "service": "mobile-api",
        "server": "api-server-2",
        "version": "1.0.0",
        "features": ["push_notifications", "offline_sync", "biometric_auth"]
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

cd /opt/api
nohup python3 app.py > /var/log/api.log 2>&1 &'

echo "Deployed API servers"
```

### Register Targets with Load Balancers
```bash
# Wait for instances to be running
echo "Waiting for instances to be running..."
sleep 60

# Get instance IDs
WEB_SERVER_1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=web-server-1" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text)
WEB_SERVER_2_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=web-server-2" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text)
API_SERVER_1_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=api-server-1" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text)
API_SERVER_2_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=api-server-2" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text)

# Register web servers with web target group
aws elbv2 register-targets \
    --target-group-arn $WEB_TG_ARN \
    --targets Id=$WEB_SERVER_1_ID Id=$WEB_SERVER_2_ID

# Register API servers with API target group
aws elbv2 register-targets \
    --target-group-arn $API_TG_ARN \
    --targets Id=$API_SERVER_1_ID Id=$API_SERVER_2_ID

# Register API servers with mobile API target group
aws elbv2 register-targets \
    --target-group-arn $MOBILE_TG_ARN \
    --targets Id=$API_SERVER_1_ID Id=$API_SERVER_2_ID

echo "Registered targets with load balancers"
echo "Waiting for targets to become healthy..."
sleep 120
```

## Step 4: Configure Global Load Balancing with Route 53

### Create Route 53 Hosted Zone
```bash
# Create hosted zone for load balancer testing
aws route53 create-hosted-zone \
    --name "lb-test.local" \
    --caller-reference "lb-test-$(date +%s)" \
    --hosted-zone-config Comment="Load balancer testing zone" PrivateZone=false \
    --tags ResourceType=hostedzone,Key=Name,Value=lb-test-zone,Key=Project,Value=aws-networking-hard-way

HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
    --dns-name "lb-test.local" \
    --query 'HostedZones[0].Id' \
    --output text | cut -d'/' -f3)

echo "Created hosted zone: $HOSTED_ZONE_ID"
```

### Create Health Checks
```bash
# Create health check for ALB
aws route53 create-health-check \
    --caller-reference "alb-health-$(date +%s)" \
    --health-check-config Type=HTTPS_STR_MATCH,ResourcePath=/health,FullyQualifiedDomainName=$ALB_DNS,Port=80,RequestInterval=30,FailureThreshold=3,SearchString=OK \
    --tags ResourceType=healthcheck,Key=Name,Value=alb-health-check,Key=Project,Value=aws-networking-hard-way

ALB_HEALTH_CHECK_ID=$(aws route53 list-health-checks \
    --query 'HealthChecks[?CallerReference==`alb-health-$(date +%s)`].Id' \
    --output text)

echo "Created health check for ALB: $ALB_HEALTH_CHECK_ID"
```

### Configure DNS Records with Failover
```bash
# Create primary record pointing to ALB
cat > primary-record.json << EOF
{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "app.lb-test.local",
                "Type": "A",
                "SetIdentifier": "primary",
                "Failover": "PRIMARY",
                "AliasTarget": {
                    "DNSName": "$ALB_DNS",
                    "EvaluateTargetHealth": true,
                    "HostedZoneId": "$(aws elbv2 describe-load-balancers --names enterprise-alb --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text)"
                }
            }
        }
    ]
}
EOF

aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch file://primary-record.json

# Create secondary record pointing to NLB (for failover)
cat > secondary-record.json << EOF
{
    "Changes": [
        {
            "Action": "CREATE",
            "ResourceRecordSet": {
                "Name": "app.lb-test.local",
                "Type": "A",
                "SetIdentifier": "secondary",
                "Failover": "SECONDARY",
                "AliasTarget": {
                    "DNSName": "$NLB_DNS",
                    "EvaluateTargetHealth": true,
                    "HostedZoneId": "$(aws elbv2 describe-load-balancers --names enterprise-nlb --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text)"
                }
            }
        }
    ]
}
EOF

aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch file://secondary-record.json

# Clean up temporary files
rm -f primary-record.json secondary-record.json

echo "Configured DNS failover records"
```

## Step 5: Configure SSL/TLS Termination

### Request SSL Certificate
```bash
# Request SSL certificate from ACM
aws acm request-certificate \
    --domain-name "*.lb-test.local" \
    --subject-alternative-names "lb-test.local" \
    --validation-method DNS \
    --tags Key=Name,Value=lb-test-cert Key=Project,Value=aws-networking-hard-way

CERT_ARN=$(aws acm list-certificates \
    --query 'CertificateSummaryList[?DomainName==`*.lb-test.local`].CertificateArn' \
    --output text)

echo "Requested SSL certificate: $CERT_ARN"
echo "Note: Certificate validation required for production use"
```

### Add HTTPS Listener to ALB
```bash
# Create HTTPS listener (using self-signed cert for demo)
# In production, wait for certificate validation first
aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTPS \
    --port 443 \
    --certificates CertificateArn=$CERT_ARN \
    --ssl-policy ELBSecurityPolicy-TLS-1-2-2017-01 \
    --default-actions Type=forward,TargetGroupArn=$WEB_TG_ARN \
    --tags Key=Name,Value=alb-https-listener

echo "Added HTTPS listener to ALB"
```

## Step 6: Implement Sticky Sessions

### Configure Sticky Sessions on Target Group
```bash
# Enable sticky sessions on web target group
aws elbv2 modify-target-group-attributes \
    --target-group-arn $WEB_TG_ARN \
    --attributes Key=stickiness.enabled,Value=true Key=stickiness.type,Value=lb_cookie Key=stickiness.lb_cookie.duration_seconds,Value=86400

# Configure session affinity for API target group
aws elbv2 modify-target-group-attributes \
    --target-group-arn $API_TG_ARN \
    --attributes Key=stickiness.enabled,Value=true Key=stickiness.type,Value=app_cookie Key=stickiness.app_cookie.cookie_name,Value=JSESSIONID Key=stickiness.app_cookie.duration_seconds,Value=3600

echo "Configured sticky sessions"
```

## Step 7: Test Load Balancing Algorithms

### Create Load Balancing Test Script
```bash
cat > test-load-balancing.sh << 'EOF'
#!/bin/bash

echo "⚖️  Testing Load Balancing Algorithms"
echo "===================================="

# Get load balancer DNS names
ALB_DNS=$(aws elbv2 describe-load-balancers --names enterprise-alb --query 'LoadBalancers[0].DNSName' --output text)
NLB_DNS=$(aws elbv2 describe-load-balancers --names enterprise-nlb --query 'LoadBalancers[0].DNSName' --output text)

echo "Load Balancer Endpoints:"
echo "  ALB: $ALB_DNS"
echo "  NLB: $NLB_DNS"
echo ""

# Test 1: Round Robin Distribution
echo "Test 1: Round Robin Distribution"
echo "-------------------------------"
echo "Testing web servers (round robin):"

for i in {1..10}; do
    RESPONSE=$(curl -s http://$ALB_DNS | grep "Web Server" | head -1)
    echo "Request $i: $RESPONSE"
    sleep 1
done

# Test 2: Path-based Routing
echo ""
echo "Test 2: Path-based Routing"
echo "-------------------------"
echo "Testing API path routing:"

API_RESPONSE=$(curl -s http://$ALB_DNS/api/info | jq -r '.server' 2>/dev/null || echo "API not responding")
echo "API Server: $API_RESPONSE"

MOBILE_RESPONSE=$(curl -s http://$ALB_DNS/mobile/info | jq -r '.server' 2>/dev/null || echo "Mobile API not responding")
echo "Mobile API Server: $MOBILE_RESPONSE"

# Test 3: Health Check Behavior
echo ""
echo "Test 3: Health Check Status"
echo "--------------------------"

# Check target health
WEB_TG_ARN=$(aws elbv2 describe-target-groups --names web-servers-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
API_TG_ARN=$(aws elbv2 describe-target-groups --names api-servers-tg --query 'TargetGroups[0].TargetGroupArn' --output text)

echo "Web Servers Target Health:"
aws elbv2 describe-target-health --target-group-arn $WEB_TG_ARN --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' --output table

echo ""
echo "API Servers Target Health:"
aws elbv2 describe-target-health --target-group-arn $API_TG_ARN --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' --output table

# Test 4: Sticky Sessions
echo ""
echo "Test 4: Sticky Sessions"
echo "----------------------"
echo "Testing session persistence (look for Set-Cookie header):"

COOKIE_RESPONSE=$(curl -s -I http://$ALB_DNS | grep -i "set-cookie" || echo "No cookies set")
echo "Cookie Response: $COOKIE_RESPONSE"

# Test 5: SSL/TLS Configuration
echo ""
echo "Test 5: SSL/TLS Configuration"
echo "----------------------------"
echo "Testing HTTPS endpoint:"

HTTPS_RESPONSE=$(curl -s -k -I https://$ALB_DNS | head -1 || echo "HTTPS not available")
echo "HTTPS Response: $HTTPS_RESPONSE"

echo ""
echo "🎯 Load Balancing Test Complete"
EOF

chmod +x test-load-balancing.sh
echo "Created load balancing test script: test-load-balancing.sh"
```

### Create Performance Test Script
```bash
cat > test-load-balancer-performance.sh << 'EOF'
#!/bin/bash

echo "📊 Load Balancer Performance Testing"
echo "==================================="

ALB_DNS=$(aws elbv2 describe-load-balancers --names enterprise-alb --query 'LoadBalancers[0].DNSName' --output text)

# Test 1: Concurrent Connections
echo "Test 1: Concurrent Connection Test"
echo "---------------------------------"
echo "Running 100 concurrent requests..."

# Install apache bench if not available
if ! command -v ab &> /dev/null; then
    echo "Installing Apache Bench..."
    sudo yum install -y httpd-tools 2>/dev/null || sudo apt-get install -y apache2-utils 2>/dev/null || echo "Please install apache2-utils/httpd-tools"
fi

if command -v ab &> /dev/null; then
    ab -n 100 -c 10 http://$ALB_DNS/ > ab-results.txt 2>&1
    
    echo "Results:"
    grep "Requests per second" ab-results.txt || echo "Test failed"
    grep "Time per request" ab-results.txt || echo "Timing data not available"
    grep "Failed requests" ab-results.txt || echo "Failure data not available"
else
    echo "Apache Bench not available, skipping performance test"
fi

# Test 2: Response Time Distribution
echo ""
echo "Test 2: Response Time Analysis"
echo "-----------------------------"

TOTAL_TIME=0
REQUESTS=20

echo "Testing response times for $REQUESTS requests:"

for i in $(seq 1 $REQUESTS); do
    START_TIME=$(date +%s%N)
    curl -s http://$ALB_DNS/ > /dev/null
    END_TIME=$(date +%s%N)
    
    RESPONSE_TIME=$(( (END_TIME - START_TIME) / 1000000 ))
    echo "Request $i: ${RESPONSE_TIME}ms"
    TOTAL_TIME=$((TOTAL_TIME + RESPONSE_TIME))
done

AVERAGE_TIME=$((TOTAL_TIME / REQUESTS))
echo "Average response time: ${AVERAGE_TIME}ms"

# Test 3: Failover Testing
echo ""
echo "Test 3: Failover Simulation"
echo "---------------------------"
echo "To test failover:"
echo "1. Stop one of the backend servers"
echo "2. Monitor target health in AWS console"
echo "3. Verify traffic continues to healthy targets"
echo "4. Restart the server and verify it rejoins the pool"

echo ""
echo "🎯 Performance Testing Complete"
echo "Check ab-results.txt for detailed Apache Bench results"
EOF

chmod +x test-load-balancer-performance.sh
echo "Created performance test script: test-load-balancer-performance.sh"
```

## Validation Commands

### Verify Load Balancer Configuration
```bash
# Check load balancer status
echo "🔍 Load Balancer Status:"
aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[].{Name:LoadBalancerName,Type:Type,State:State.Code,DNS:DNSName}' \
    --output table

# Check target group health
echo ""
echo "🎯 Target Group Health:"
aws elbv2 describe-target-groups \
    --query 'TargetGroups[].{Name:TargetGroupName,Protocol:Protocol,Port:Port,HealthyCount:HealthyThresholdCount}' \
    --output table

# Check listeners
echo ""
echo "👂 Load Balancer Listeners:"
aws elbv2 describe-listeners \
    --load-balancer-arn $(aws elbv2 describe-load-balancers --names enterprise-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text) \
    --query 'Listeners[].{Protocol:Protocol,Port:Port,DefaultAction:DefaultActions[0].Type}' \
    --output table
```

## Cleanup for This Lab

```bash
cat > cleanup-lab06.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Lab 06 resources..."

# Terminate instances
echo "Terminating instances..."
INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:Tier,Values=web,api" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text)
if [ ! -z "$INSTANCES" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCES
    aws ec2 wait instance-terminated --instance-ids $INSTANCES
fi

# Delete load balancers
echo "Deleting load balancers..."
ALB_ARN=$(aws elbv2 describe-load-balancers --names enterprise-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
NLB_ARN=$(aws elbv2 describe-load-balancers --names enterprise-nlb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)

[ "$ALB_ARN" != "None" ] && aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
[ "$NLB_ARN" != "None" ] && aws elbv2 delete-load-balancer --load-balancer-arn $NLB_ARN

# Wait for load balancers to be deleted
sleep 60

# Delete target groups
echo "Deleting target groups..."
TARGET_GROUPS=$(aws elbv2 describe-target-groups --query 'TargetGroups[].TargetGroupArn' --output text)
for TG in $TARGET_GROUPS; do
    [ ! -z "$TG" ] && aws elbv2 delete-target-group --target-group-arn $TG 2>/dev/null
done

# Delete Route 53 hosted zone
echo "Deleting Route 53 hosted zone..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "lb-test.local" --query 'HostedZones[0].Id' --output text 2>/dev/null | cut -d'/' -f3)
if [ "$HOSTED_ZONE_ID" != "None" ] && [ ! -z "$HOSTED_ZONE_ID" ]; then
    # Delete all records except NS and SOA
    aws route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --query 'ResourceRecordSets[?Type!=`NS` && Type!=`SOA`]' --output json > /tmp/records.json
    if [ -s /tmp/records.json ]; then
        aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file:///tmp/records.json
    fi
    aws route53 delete-hosted-zone --id $HOSTED_ZONE_ID
fi

# Delete health checks
echo "Deleting health checks..."
HEALTH_CHECKS=$(aws route53 list-health-checks --query 'HealthChecks[].Id' --output text)
for HC in $HEALTH_CHECKS; do
    [ ! -z "$HC" ] && aws route53 delete-health-check --health-check-id $HC 2>/dev/null
done

# Delete SSL certificate
echo "Deleting SSL certificate..."
CERT_ARN=$(aws acm list-certificates --query 'CertificateSummaryList[?DomainName==`*.lb-test.local`].CertificateArn' --output text)
[ "$CERT_ARN" != "None" ] && aws acm delete-certificate --certificate-arn $CERT_ARN 2>/dev/null

# Delete security groups
echo "Deleting security groups..."
SECURITY_GROUPS="alb-sg web-servers-sg api-servers-sg db-servers-sg"
for SG_NAME in $SECURITY_GROUPS; do
    SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    [ "$SG_ID" != "None" ] && aws ec2 delete-security-group --group-id $SG_ID 2>/dev/null
done

# Delete key pair
aws ec2 delete-key-pair --key-name lb-test-key 2>/dev/null
rm -f lb-test-key.pem ab-results.txt

echo "✅ Lab 06 cleanup completed"
EOF

chmod +x cleanup-lab06.sh
echo "Created cleanup script: cleanup-lab06.sh"
```

## Next Steps

After completing this lab, you should have:
- ✅ Application Load Balancer with path-based routing
- ✅ Network Load Balancer for TCP traffic
- ✅ Global load balancing with Route 53
- ✅ SSL/TLS termination configuration
- ✅ Sticky sessions and health checks
- ✅ Performance testing and monitoring

**Continue to:** [Lab 07: Network Security](../07-network-security/README.md)