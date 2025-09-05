# Lab 09: Network Monitoring and Troubleshooting - Detailed Steps

## Prerequisites
- Completed Labs 01-08
- Understanding of network monitoring concepts
- AWS CLI configured with appropriate permissions

```bash
# Set environment variables
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
echo "Working with VPC: $VPC_ID"
```

## Step 1: Configure Comprehensive VPC Flow Logs

### Enable Enhanced VPC Flow Logs
```bash
# Create S3 bucket for enhanced flow logs
FLOW_LOGS_BUCKET="enhanced-flow-logs-$(date +%s)"
aws s3 mb s3://$FLOW_LOGS_BUCKET

# Create IAM role for enhanced flow logs
cat > enhanced-flow-logs-role.json << 'EOF'
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
    --role-name EnhancedVPCFlowLogsRole \
    --assume-role-policy-document file://enhanced-flow-logs-role.json

# Create policy for enhanced flow logs
cat > enhanced-flow-logs-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::BUCKET_NAME",
        "arn:aws:s3:::BUCKET_NAME/*"
      ]
    }
  ]
}
EOF

sed -i "s/BUCKET_NAME/$FLOW_LOGS_BUCKET/g" enhanced-flow-logs-policy.json

aws iam create-policy \
    --policy-name EnhancedVPCFlowLogsPolicy \
    --policy-document file://enhanced-flow-logs-policy.json

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam attach-role-policy \
    --role-name EnhancedVPCFlowLogsRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/EnhancedVPCFlowLogsPolicy
```# E
nable enhanced VPC Flow Logs with custom format
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids $VPC_ID \
    --traffic-type ALL \
    --log-destination-type s3 \
    --log-destination arn:aws:s3:::$FLOW_LOGS_BUCKET/enhanced-flow-logs/ \
    --log-format '${version} ${account-id} ${interface-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${windowstart} ${windowend} ${action} ${flowlogstatus} ${vpc-id} ${subnet-id} ${instance-id} ${tcp-flags} ${type} ${pkt-srcaddr} ${pkt-dstaddr} ${region} ${az-id} ${sublocation-type} ${sublocation-id} ${pkt-src-aws-service} ${pkt-dst-aws-service} ${flow-direction} ${traffic-path}' \
    --deliver-logs-permission-arn arn:aws:iam::${ACCOUNT_ID}:role/EnhancedVPCFlowLogsRole \
    --tag-specifications 'ResourceType=vpc-flow-log,Tags=[{Key=Name,Value=enhanced-vpc-flow-logs},{Key=Purpose,Value=monitoring}]'

echo "Enabled enhanced VPC Flow Logs to S3: $FLOW_LOGS_BUCKET"

# Clean up temporary files
rm -f enhanced-flow-logs-role.json enhanced-flow-logs-policy.json
```

### Create CloudWatch Log Insights Queries
```bash
cat > create-log-insights-queries.sh << 'EOF'
#!/bin/bash

echo "📊 Creating CloudWatch Log Insights Queries"
echo "==========================================="

# Create saved queries for common network analysis

# Query 1: Top Talkers
aws logs put-query-definition \
    --name "VPC-TopTalkers" \
    --query-string 'fields @timestamp, srcaddr, dstaddr, bytes
| filter action = "ACCEPT"
| stats sum(bytes) as total_bytes by srcaddr, dstaddr
| sort total_bytes desc
| limit 20' \
    --log-group-names "/aws/vpc/flowlogs"

# Query 2: Rejected Traffic Analysis
aws logs put-query-definition \
    --name "VPC-RejectedTraffic" \
    --query-string 'fields @timestamp, srcaddr, dstaddr, srcport, dstport, protocol
| filter action = "REJECT"
| stats count() as reject_count by srcaddr, dstaddr, dstport
| sort reject_count desc
| limit 50' \
    --log-group-names "/aws/vpc/flowlogs"

# Query 3: Security Group Analysis
aws logs put-query-definition \
    --name "VPC-SecurityGroupBlocks" \
    --query-string 'fields @timestamp, srcaddr, dstaddr, srcport, dstport
| filter action = "REJECT" and flowlogstatus = "OK"
| stats count() as blocked_attempts by srcaddr, dstport
| sort blocked_attempts desc
| limit 30' \
    --log-group-names "/aws/vpc/flowlogs"

# Query 4: Bandwidth Usage by Instance
aws logs put-query-definition \
    --name "VPC-InstanceBandwidth" \
    --query-string 'fields @timestamp, instance_id, bytes
| filter instance_id != "-"
| stats sum(bytes) as total_bytes by instance_id
| sort total_bytes desc
| limit 25' \
    --log-group-names "/aws/vpc/flowlogs"

echo "Created CloudWatch Log Insights saved queries"
EOF

chmod +x create-log-insights-queries.sh
./create-log-insights-queries.sh
```

## Step 2: Set Up Advanced CloudWatch Monitoring

### Create Custom CloudWatch Metrics
```bash
# Create Lambda function for custom metrics
cat > network-metrics-lambda.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Generate custom network metrics from VPC Flow Logs
    """
    
    cloudwatch = boto3.client('cloudwatch')
    logs_client = boto3.client('logs')
    
    try:
        # Calculate metrics for the last 5 minutes
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=5)
        
        # Query VPC Flow Logs for rejected traffic
        query = """
        fields @timestamp, action
        | filter action = "REJECT"
        | stats count() as rejected_count
        """
        
        response = logs_client.start_query(
            logGroupName='/aws/vpc/flowlogs',
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        # Wait for query to complete (simplified for demo)
        import time
        time.sleep(10)
        
        results = logs_client.get_query_results(queryId=response['queryId'])
        
        rejected_count = 0
        if results['results']:
            for field in results['results'][0]:
                if field['field'] == 'rejected_count':
                    rejected_count = int(field['value'])
        
        # Put custom metric
        cloudwatch.put_metric_data(
            Namespace='Custom/VPC',
            MetricData=[
                {
                    'MetricName': 'RejectedConnections',
                    'Value': rejected_count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'VPC',
                            'Value': 'ecommerce-vpc'
                        }
                    ]
                }
            ]
        )
        
        logger.info(f"Published metric: RejectedConnections = {rejected_count}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Processed {rejected_count} rejected connections')
        }
        
    except Exception as e:
        logger.error(f"Error processing metrics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF

# Create IAM role for Lambda
cat > lambda-metrics-role.json << 'EOF'
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
    --role-name NetworkMetricsLambdaRole \
    --assume-role-policy-document file://lambda-metrics-role.json

# Create policy for Lambda
cat > lambda-metrics-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:StartQuery",
        "logs:GetQueryResults",
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
    --policy-name NetworkMetricsLambdaPolicy \
    --policy-document file://lambda-metrics-policy.json

aws iam attach-role-policy \
    --role-name NetworkMetricsLambdaRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/NetworkMetricsLambdaPolicy

aws iam attach-role-policy \
    --role-name NetworkMetricsLambdaRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create Lambda function
zip network-metrics-lambda.zip network-metrics-lambda.py

aws lambda create-function \
    --function-name NetworkMetricsProcessor \
    --runtime python3.9 \
    --role arn:aws:iam::${ACCOUNT_ID}:role/NetworkMetricsLambdaRole \
    --handler network-metrics-lambda.lambda_handler \
    --zip-file fileb://network-metrics-lambda.zip \
    --timeout 60 \
    --tags Key=Purpose,Value=network-monitoring

echo "Created network metrics Lambda function"

# Clean up
rm -f lambda-metrics-role.json lambda-metrics-policy.json network-metrics-lambda.py network-metrics-lambda.zip
```

### Create CloudWatch Alarms
```bash
# Create alarm for high rejected connections
aws cloudwatch put-metric-alarm \
    --alarm-name "HighRejectedConnections" \
    --alarm-description "Alert when rejected connections exceed threshold" \
    --metric-name RejectedConnections \
    --namespace Custom/VPC \
    --statistic Sum \
    --period 300 \
    --threshold 100 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions arn:aws:sns:us-east-1:${ACCOUNT_ID}:network-alerts \
    --dimensions Name=VPC,Value=ecommerce-vpc \
    --tags Key=Purpose,Value=network-monitoring

# Create alarm for NAT Gateway errors
aws cloudwatch put-metric-alarm \
    --alarm-name "NATGatewayErrors" \
    --alarm-description "Alert on NAT Gateway errors" \
    --metric-name ErrorPortAllocation \
    --namespace AWS/NatGateway \
    --statistic Sum \
    --period 300 \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions arn:aws:sns:us-east-1:${ACCOUNT_ID}:network-alerts \
    --tags Key=Purpose,Value=network-monitoring

# Create alarm for Transit Gateway packet drops
TGW_ID=$(aws ec2 describe-transit-gateways --filters "Name=tag:Name,Values=enterprise-central-tgw" --query 'TransitGateways[0].TransitGatewayId' --output text 2>/dev/null || echo "")

if [ ! -z "$TGW_ID" ] && [ "$TGW_ID" != "None" ]; then
    aws cloudwatch put-metric-alarm \
        --alarm-name "TransitGatewayPacketDrops" \
        --alarm-description "Alert on Transit Gateway packet drops" \
        --metric-name PacketDropCount \
        --namespace AWS/TransitGateway \
        --statistic Sum \
        --period 300 \
        --threshold 1000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions arn:aws:sns:us-east-1:${ACCOUNT_ID}:network-alerts \
        --dimensions Name=TransitGateway,Value=$TGW_ID \
        --tags Key=Purpose,Value=network-monitoring
fi

echo "Created CloudWatch alarms for network monitoring"
```

## Step 3: Implement Network Performance Monitoring

### Create Performance Monitoring Dashboard
```bash
cat > network-performance-dashboard.json << 'EOF'
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
                    [ "AWS/EC2", "NetworkIn", { "stat": "Average" } ],
                    [ ".", "NetworkOut", { "stat": "Average" } ],
                    [ ".", "NetworkPacketsIn", { "stat": "Average" } ],
                    [ ".", "NetworkPacketsOut", { "stat": "Average" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "EC2 Network Performance"
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
                    [ "Custom/VPC", "RejectedConnections", "VPC", "ecommerce-vpc" ],
                    [ "AWS/VPC", "PacketDropCount", { "stat": "Sum" } ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "Network Security Metrics"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/vpc/flowlogs' | fields @timestamp, srcaddr, dstaddr, bytes\n| filter action = \"ACCEPT\"\n| stats sum(bytes) as total_bytes by srcaddr\n| sort total_bytes desc\n| limit 10",
                "region": "us-east-1",
                "title": "Top Traffic Sources (Last Hour)"
            }
        }
    ]
}
EOF

aws cloudwatch put-dashboard \
    --dashboard-name "NetworkPerformance" \
    --dashboard-body file://network-performance-dashboard.json

echo "Created network performance dashboard"
rm -f network-performance-dashboard.json
```

### Set Up Automated Performance Reports
```bash
cat > create-performance-reports.sh << 'EOF'
#!/bin/bash

echo "📈 Creating Automated Performance Reports"
echo "========================================"

# Create Lambda function for performance reports
cat > performance-report-lambda.py << "LAMBDA_EOF"
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Generate weekly network performance report
    """
    
    cloudwatch = boto3.client('cloudwatch')
    logs_client = boto3.client('logs')
    ses = boto3.client('ses')
    
    try:
        # Calculate metrics for the last week
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=7)
        
        # Get network metrics
        network_in = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='NetworkIn',
            StartTime=start_time,
            EndTime=end_time,
            Period=3600,
            Statistics=['Average', 'Maximum']
        )
        
        # Generate report
        report = generate_report(network_in, start_time, end_time)
        
        # Send report via email (if SES is configured)
        # ses.send_email(...)
        
        logger.info("Performance report generated successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Performance report generated')
        }
        
    except Exception as e:
        logger.error(f"Error generating report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def generate_report(metrics, start_time, end_time):
    """Generate performance report content"""
    
    report = f"""
    Network Performance Report
    Period: {start_time.strftime('%Y-%m-%d')} to {end_time.strftime('%Y-%m-%d')}
    
    Summary:
    - Total data points: {len(metrics['Datapoints'])}
    - Average network in: {sum(dp['Average'] for dp in metrics['Datapoints']) / len(metrics['Datapoints']) if metrics['Datapoints'] else 0:.2f} bytes
    - Peak network in: {max(dp['Maximum'] for dp in metrics['Datapoints']) if metrics['Datapoints'] else 0:.2f} bytes
    
    Recommendations:
    - Monitor for unusual traffic patterns
    - Review security group rules for optimization
    - Consider bandwidth scaling if needed
    """
    
    return report
LAMBDA_EOF

# Create the Lambda function for reports
zip performance-report-lambda.zip performance-report-lambda.py

aws lambda create-function \
    --function-name NetworkPerformanceReports \
    --runtime python3.9 \
    --role arn:aws:iam::${ACCOUNT_ID}:role/NetworkMetricsLambdaRole \
    --handler performance-report-lambda.lambda_handler \
    --zip-file fileb://performance-report-lambda.zip \
    --timeout 300 \
    --tags Key=Purpose,Value=performance-reporting

# Schedule the function to run weekly
aws events put-rule \
    --name "WeeklyNetworkReport" \
    --schedule-expression "rate(7 days)" \
    --description "Generate weekly network performance report"

# Add Lambda as target
LAMBDA_ARN=$(aws lambda get-function --function-name NetworkPerformanceReports --query 'Configuration.FunctionArn' --output text)

aws events put-targets \
    --rule "WeeklyNetworkReport" \
    --targets "Id"="1","Arn"="$LAMBDA_ARN"

# Grant EventBridge permission to invoke Lambda
aws lambda add-permission \
    --function-name NetworkPerformanceReports \
    --statement-id "AllowEventBridge" \
    --action "lambda:InvokeFunction" \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:us-east-1:${ACCOUNT_ID}:rule/WeeklyNetworkReport

echo "Created automated performance reporting"

# Clean up
rm -f performance-report-lambda.py performance-report-lambda.zip
EOF

chmod +x create-performance-reports.sh
./create-performance-reports.sh
```

## Step 4: Build Network Troubleshooting Tools

### Create Network Diagnostic Script
```bash
cat > network-diagnostics.sh << 'EOF'
#!/bin/bash

echo "🔧 Network Diagnostics Tool"
echo "=========================="

# Function to check VPC configuration
check_vpc_config() {
    local vpc_id=$1
    echo "Checking VPC Configuration: $vpc_id"
    echo "-----------------------------------"
    
    # Check VPC exists and is available
    VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids $vpc_id --query 'Vpcs[0].State' --output text 2>/dev/null || echo "NOT_FOUND")
    echo "VPC State: $VPC_STATE"
    
    if [ "$VPC_STATE" != "available" ]; then
        echo "❌ VPC is not available"
        return 1
    fi
    
    # Check DNS settings
    DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute --vpc-id $vpc_id --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value' --output text)
    DNS_SUPPORT=$(aws ec2 describe-vpc-attribute --vpc-id $vpc_id --attribute enableDnsSupport --query 'EnableDnsSupport.Value' --output text)
    
    echo "DNS Hostnames: $DNS_HOSTNAMES"
    echo "DNS Support: $DNS_SUPPORT"
    
    if [ "$DNS_HOSTNAMES" = "false" ] || [ "$DNS_SUPPORT" = "false" ]; then
        echo "⚠️  DNS settings may cause resolution issues"
    fi
    
    # Check subnets
    SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'length(Subnets)' --output text)
    echo "Subnets: $SUBNET_COUNT"
    
    # Check route tables
    RT_COUNT=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'length(RouteTables)' --output text)
    echo "Route Tables: $RT_COUNT"
    
    echo "✅ VPC configuration check complete"
    echo ""
}

# Function to check connectivity
check_connectivity() {
    local source_ip=$1
    local dest_ip=$2
    local port=$3
    
    echo "Checking Connectivity: $source_ip -> $dest_ip:$port"
    echo "------------------------------------------------"
    
    # This would typically be run from the source instance
    echo "Manual test required:"
    echo "1. SSH to source instance: $source_ip"
    echo "2. Run: telnet $dest_ip $port"
    echo "3. Run: ping $dest_ip"
    echo "4. Run: traceroute $dest_ip"
    echo ""
}

# Function to analyze security groups
analyze_security_groups() {
    local instance_id=$1
    echo "Analyzing Security Groups for Instance: $instance_id"
    echo "================================================="
    
    # Get security groups for instance
    SECURITY_GROUPS=$(aws ec2 describe-instances --instance-ids $instance_id --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
    
    if [ -z "$SECURITY_GROUPS" ]; then
        echo "❌ Instance not found or no security groups"
        return 1
    fi
    
    echo "Security Groups: $SECURITY_GROUPS"
    
    for SG in $SECURITY_GROUPS; do
        echo ""
        echo "Security Group: $SG"
        echo "Inbound Rules:"
        aws ec2 describe-security-groups --group-ids $SG --query 'SecurityGroups[0].IpPermissions[].{Protocol:IpProtocol,Port:FromPort,Source:IpRanges[0].CidrIp}' --output table
        
        echo "Outbound Rules:"
        aws ec2 describe-security-groups --group-ids $SG --query 'SecurityGroups[0].IpPermissionsEgress[].{Protocol:IpProtocol,Port:FromPort,Dest:IpRanges[0].CidrIp}' --output table
    done
    
    echo "✅ Security group analysis complete"
    echo ""
}

# Function to check NAT Gateway health
check_nat_gateway() {
    local vpc_id=$1
    echo "Checking NAT Gateway Health for VPC: $vpc_id"
    echo "==========================================="
    
    # Get NAT Gateways in VPC
    NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" --query 'NatGateways[].{ID:NatGatewayId,State:State,SubnetId:SubnetId}' --output table)
    
    echo "NAT Gateways:"
    echo "$NAT_GATEWAYS"
    
    # Check NAT Gateway metrics
    NAT_GW_IDS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" --query 'NatGateways[].NatGatewayId' --output text)
    
    for NAT_ID in $NAT_GW_IDS; do
        echo ""
        echo "NAT Gateway Metrics: $NAT_ID"
        
        # Get error metrics from CloudWatch
        ERROR_COUNT=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/NatGateway \
            --metric-name ErrorPortAllocation \
            --dimensions Name=NatGatewayId,Value=$NAT_ID \
            --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
            --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
            --period 3600 \
            --statistics Sum \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "0")
        
        echo "Error Count (last hour): $ERROR_COUNT"
        
        if [ "$ERROR_COUNT" != "0" ] && [ "$ERROR_COUNT" != "None" ]; then
            echo "⚠️  NAT Gateway has errors - check capacity and configuration"
        fi
    done
    
    echo "✅ NAT Gateway health check complete"
    echo ""
}

# Main diagnostic function
run_diagnostics() {
    local vpc_id=${1:-$VPC_ID}
    
    if [ -z "$vpc_id" ]; then
        echo "❌ VPC ID required"
        echo "Usage: $0 <vpc-id>"
        exit 1
    fi
    
    echo "🔍 Starting Network Diagnostics for VPC: $vpc_id"
    echo "=============================================="
    echo ""
    
    check_vpc_config $vpc_id
    check_nat_gateway $vpc_id
    
    # Get a sample instance for security group analysis
    SAMPLE_INSTANCE=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$SAMPLE_INSTANCE" ] && [ "$SAMPLE_INSTANCE" != "None" ]; then
        analyze_security_groups $SAMPLE_INSTANCE
    else
        echo "ℹ️  No running instances found for security group analysis"
    fi
    
    echo "🎯 Network diagnostics complete"
    echo ""
    echo "📋 Common troubleshooting steps:"
    echo "1. Check security group rules"
    echo "2. Verify route table configurations"
    echo "3. Confirm NAT Gateway health"
    echo "4. Review VPC Flow Logs for blocked traffic"
    echo "5. Test connectivity from source instances"
}

# Run diagnostics if script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    run_diagnostics $1
fi
EOF

chmod +x network-diagnostics.sh
echo "Created network diagnostics tool: network-diagnostics.sh"
```

### Create Flow Logs Analysis Tool
```bash
cat > analyze-flow-logs.sh << 'EOF'
#!/bin/bash

echo "📊 VPC Flow Logs Analysis Tool"
echo "============================="

# Function to analyze rejected traffic
analyze_rejected_traffic() {
    local hours=${1:-1}
    echo "Analyzing rejected traffic (last $hours hours)..."
    
    # Create Athena table for flow logs (if using S3)
    FLOW_LOGS_BUCKET=$(aws s3 ls | grep enhanced-flow-logs | awk '{print $3}' | head -1)
    
    if [ ! -z "$FLOW_LOGS_BUCKET" ]; then
        echo "Flow logs bucket: $FLOW_LOGS_BUCKET"
        
        # Sample Athena query for rejected traffic
        cat > rejected_traffic_query.sql << SQL_EOF
SELECT 
    srcaddr,
    dstaddr,
    dstport,
    protocol,
    COUNT(*) as reject_count
FROM vpc_flow_logs 
WHERE action = 'REJECT' 
    AND start >= CURRENT_TIMESTAMP - INTERVAL '$hours' HOUR
GROUP BY srcaddr, dstaddr, dstport, protocol
ORDER BY reject_count DESC
LIMIT 20;
SQL_EOF
        
        echo "Created Athena query: rejected_traffic_query.sql"
        echo "Run this query in Athena console against your flow logs table"
    else
        echo "No flow logs bucket found"
    fi
}

# Function to analyze top talkers
analyze_top_talkers() {
    local hours=${1:-1}
    echo "Analyzing top talkers (last $hours hours)..."
    
    # CloudWatch Logs Insights query
    cat > top_talkers_query.txt << QUERY_EOF
fields @timestamp, srcaddr, dstaddr, bytes
| filter action = "ACCEPT"
| stats sum(bytes) as total_bytes by srcaddr, dstaddr
| sort total_bytes desc
| limit 20
QUERY_EOF
    
    echo "Created CloudWatch Logs Insights query: top_talkers_query.txt"
    echo "Use this query in CloudWatch Logs Insights"
}

# Function to check for security issues
check_security_issues() {
    echo "Checking for potential security issues..."
    
    # Query for unusual port activity
    cat > security_analysis_query.txt << QUERY_EOF
fields @timestamp, srcaddr, dstaddr, dstport, protocol
| filter action = "ACCEPT" and (dstport = 22 or dstport = 3389 or dstport = 1433 or dstport = 3306)
| stats count() as connection_count by srcaddr, dstport
| sort connection_count desc
| limit 50
QUERY_EOF
    
    echo "Created security analysis query: security_analysis_query.txt"
    echo "This query looks for connections to common administrative ports"
}

# Function to generate network summary
generate_network_summary() {
    local vpc_id=${1:-$VPC_ID}
    
    echo "Generating network summary for VPC: $vpc_id"
    echo "=========================================="
    
    # Get VPC information
    VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $vpc_id --query 'Vpcs[0].CidrBlock' --output text)
    SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'length(Subnets)' --output text)
    INSTANCE_COUNT=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$vpc_id" "Name=instance-state-name,Values=running" --query 'length(Reservations[].Instances[])' --output text)
    
    echo "VPC CIDR: $VPC_CIDR"
    echo "Subnets: $SUBNET_COUNT"
    echo "Running Instances: $INSTANCE_COUNT"
    
    # Get NAT Gateway information
    NAT_COUNT=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" --query 'length(NatGateways)' --output text)
    echo "NAT Gateways: $NAT_COUNT"
    
    # Get Internet Gateway information
    IGW_COUNT=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'length(InternetGateways)' --output text)
    echo "Internet Gateways: $IGW_COUNT"
    
    # Get VPC Endpoints
    ENDPOINT_COUNT=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc_id" --query 'length(VpcEndpoints)' --output text)
    echo "VPC Endpoints: $ENDPOINT_COUNT"
    
    echo ""
    echo "✅ Network summary complete"
}

# Main function
main() {
    local action=${1:-summary}
    local vpc_id=${2:-$VPC_ID}
    
    case $action in
        "rejected")
            analyze_rejected_traffic ${3:-1}
            ;;
        "talkers")
            analyze_top_talkers ${3:-1}
            ;;
        "security")
            check_security_issues
            ;;
        "summary")
            generate_network_summary $vpc_id
            ;;
        *)
            echo "Usage: $0 [rejected|talkers|security|summary] [vpc-id] [hours]"
            echo ""
            echo "Commands:"
            echo "  rejected - Analyze rejected traffic"
            echo "  talkers  - Find top bandwidth consumers"
            echo "  security - Check for security issues"
            echo "  summary  - Generate network summary (default)"
            ;;
    esac
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main $@
fi
EOF

chmod +x analyze-flow-logs.sh
echo "Created flow logs analysis tool: analyze-flow-logs.sh"
```

## Step 5: Create Automated Incident Response

### Set Up EventBridge Rules for Network Events
```bash
# Create EventBridge rule for VPC changes
aws events put-rule \
    --name "VPCConfigurationChanges" \
    --event-pattern '{"source":["aws.ec2"],"detail-type":["AWS API Call via CloudTrail"],"detail":{"eventSource":["ec2.amazonaws.com"],"eventName":["CreateVpc","DeleteVpc","CreateSubnet","DeleteSubnet","CreateRouteTable","DeleteRouteTable"]}}' \
    --description "Monitor VPC configuration changes"

# Create EventBridge rule for security group changes
aws events put-rule \
    --name "SecurityGroupChanges" \
    --event-pattern '{"source":["aws.ec2"],"detail-type":["AWS API Call via CloudTrail"],"detail":{"eventSource":["ec2.amazonaws.com"],"eventName":["AuthorizeSecurityGroupIngress","RevokeSecurityGroupIngress","AuthorizeSecurityGroupEgress","RevokeSecurityGroupEgress"]}}' \
    --description "Monitor security group changes"

echo "Created EventBridge rules for network monitoring"
```

## Validation Commands

### Test Monitoring Setup
```bash
# Check CloudWatch dashboards
echo "📊 CloudWatch Dashboards:"
aws cloudwatch list-dashboards \
    --query 'DashboardEntries[].{Name:DashboardName,LastModified:LastModified}' \
    --output table

# Check CloudWatch alarms
echo ""
echo "🚨 CloudWatch Alarms:"
aws cloudwatch describe-alarms \
    --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
    --output table

# Check Lambda functions
echo ""
echo "⚡ Lambda Functions:"
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `Network`)].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}' \
    --output table
```

## Cleanup for This Lab

```bash
cat > cleanup-lab09.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Lab 09 resources..."

# Delete Lambda functions
echo "Deleting Lambda functions..."
aws lambda delete-function --function-name NetworkMetricsProcessor 2>/dev/null
aws lambda delete-function --function-name NetworkPerformanceReports 2>/dev/null

# Delete EventBridge rules
echo "Deleting EventBridge rules..."
aws events remove-targets --rule VPCConfigurationChanges --ids 1 2>/dev/null
aws events remove-targets --rule SecurityGroupChanges --ids 1 2>/dev/null
aws events remove-targets --rule WeeklyNetworkReport --ids 1 2>/dev/null
aws events delete-rule --name VPCConfigurationChanges 2>/dev/null
aws events delete-rule --name SecurityGroupChanges 2>/dev/null
aws events delete-rule --name WeeklyNetworkReport 2>/dev/null

# Delete CloudWatch alarms
echo "Deleting CloudWatch alarms..."
aws cloudwatch delete-alarms --alarm-names HighRejectedConnections NATGatewayErrors TransitGatewayPacketDrops 2>/dev/null

# Delete CloudWatch dashboards
echo "Deleting CloudWatch dashboards..."
aws cloudwatch delete-dashboards --dashboard-names NetworkPerformance 2>/dev/null

# Delete IAM roles and policies
echo "Deleting IAM resources..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam detach-role-policy --role-name EnhancedVPCFlowLogsRole --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/EnhancedVPCFlowLogsPolicy 2>/dev/null
aws iam detach-role-policy --role-name NetworkMetricsLambdaRole --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/NetworkMetricsLambdaPolicy 2>/dev/null
aws iam detach-role-policy --role-name NetworkMetricsLambdaRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null

aws iam delete-role --role-name EnhancedVPCFlowLogsRole 2>/dev/null
aws iam delete-role --role-name NetworkMetricsLambdaRole 2>/dev/null

aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/EnhancedVPCFlowLogsPolicy 2>/dev/null
aws iam delete-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/NetworkMetricsLambdaPolicy 2>/dev/null

# Delete S3 bucket
echo "Deleting S3 bucket..."
FLOW_LOGS_BUCKET=$(aws s3 ls | grep enhanced-flow-logs | awk '{print $3}')
[ ! -z "$FLOW_LOGS_BUCKET" ] && aws s3 rb s3://$FLOW_LOGS_BUCKET --force 2>/dev/null

# Delete CloudWatch Log Insights queries
echo "Note: CloudWatch Log Insights saved queries need manual deletion"

# Clean up generated files
rm -f rejected_traffic_query.sql top_talkers_query.txt security_analysis_query.txt

echo "✅ Lab 09 cleanup completed"
EOF

chmod +x cleanup-lab09.sh
echo "Created cleanup script: cleanup-lab09.sh"
```

## Next Steps

After completing this lab, you should have:
- ✅ Comprehensive VPC Flow Logs with enhanced format
- ✅ Custom CloudWatch metrics and alarms
- ✅ Network performance monitoring dashboard
- ✅ Automated troubleshooting tools
- ✅ Flow logs analysis capabilities
- ✅ Incident response automation

**Continue to:** [Lab 10: Disaster Recovery](../10-disaster-recovery/README.md)