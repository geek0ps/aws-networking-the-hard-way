# Lab 07: Network Security - Detailed Steps

## Prerequisites
- Completed Labs 01-06
- Understanding of network security concepts
- AWS CLI configured with appropriate permissions

```bash
# Set environment variables
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
export ALB_ARN=$(aws elbv2 describe-load-balancers --names enterprise-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")
echo "Working with VPC: $VPC_ID"
```

## Step 1: Configure AWS WAF

### Create Web ACL
```bash
# Create Web ACL for Application Load Balancer
aws wafv2 create-web-acl \
    --name "enterprise-web-acl" \
    --scope REGIONAL \
    --default-action Allow={} \
    --description "Enterprise Web Application Firewall" \
    --tags Key=Name,Value=enterprise-web-acl,Key=Project,Value=aws-networking-hard-way

WEB_ACL_ARN=$(aws wafv2 list-web-acls --scope REGIONAL \
    --query 'WebACLs[?Name==`enterprise-web-acl`].ARN' \
    --output text)

WEB_ACL_ID=$(aws wafv2 list-web-acls --scope REGIONAL \
    --query 'WebACLs[?Name==`enterprise-web-acl`].Id' \
    --output text)

echo "Created Web ACL: $WEB_ACL_ARN"
```

### Create WAF Rules

#### Rule 1: Rate Limiting
```bash
# Create rate limiting rule
aws wafv2 update-web-acl \
    --scope REGIONAL \
    --id $WEB_ACL_ID \
    --name "enterprise-web-acl" \
    --default-action Allow={} \
    --rules '[
        {
            "Name": "RateLimitRule",
            "Priority": 1,
            "Statement": {
                "RateBasedStatement": {
                    "Limit": 2000,
                    "AggregateKeyType": "IP"
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "RateLimitRule"
            }
        }
    ]'

echo "Added rate limiting rule (2000 requests per 5 minutes per IP)"
```

#### Rule 2: SQL Injection Protection
```bash
# Update Web ACL with SQL injection rule
aws wafv2 update-web-acl \
    --scope REGIONAL \
    --id $WEB_ACL_ID \
    --name "enterprise-web-acl" \
    --default-action Allow={} \
    --rules '[
        {
            "Name": "RateLimitRule",
            "Priority": 1,
            "Statement": {
                "RateBasedStatement": {
                    "Limit": 2000,
                    "AggregateKeyType": "IP"
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "RateLimitRule"
            }
        },
        {
            "Name": "SQLInjectionRule",
            "Priority": 2,
            "Statement": {
                "SqliMatchStatement": {
                    "FieldToMatch": {
                        "AllQueryArguments": {}
                    },
                    "TextTransformations": [
                        {
                            "Priority": 0,
                            "Type": "URL_DECODE"
                        },
                        {
                            "Priority": 1,
                            "Type": "HTML_ENTITY_DECODE"
                        }
                    ]
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "SQLInjectionRule"
            }
        }
    ]'

echo "Added SQL injection protection rule"
```

#### Rule 3: XSS Protection
```bash
# Update Web ACL with XSS protection rule
aws wafv2 update-web-acl \
    --scope REGIONAL \
    --id $WEB_ACL_ID \
    --name "enterprise-web-acl" \
    --default-action Allow={} \
    --rules '[
        {
            "Name": "RateLimitRule",
            "Priority": 1,
            "Statement": {
                "RateBasedStatement": {
                    "Limit": 2000,
                    "AggregateKeyType": "IP"
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "RateLimitRule"
            }
        },
        {
            "Name": "SQLInjectionRule",
            "Priority": 2,
            "Statement": {
                "SqliMatchStatement": {
                    "FieldToMatch": {
                        "AllQueryArguments": {}
                    },
                    "TextTransformations": [
                        {
                            "Priority": 0,
                            "Type": "URL_DECODE"
                        },
                        {
                            "Priority": 1,
                            "Type": "HTML_ENTITY_DECODE"
                        }
                    ]
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "SQLInjectionRule"
            }
        },
        {
            "Name": "XSSRule",
            "Priority": 3,
            "Statement": {
                "XssMatchStatement": {
                    "FieldToMatch": {
                        "AllQueryArguments": {}
                    },
                    "TextTransformations": [
                        {
                            "Priority": 0,
                            "Type": "URL_DECODE"
                        },
                        {
                            "Priority": 1,
                            "Type": "HTML_ENTITY_DECODE"
                        }
                    ]
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "XSSRule"
            }
        }
    ]'

echo "Added XSS protection rule"
```

#### Rule 4: Geographic Blocking
```bash
# Update Web ACL with geographic blocking
aws wafv2 update-web-acl \
    --scope REGIONAL \
    --id $WEB_ACL_ID \
    --name "enterprise-web-acl" \
    --default-action Allow={} \
    --rules '[
        {
            "Name": "RateLimitRule",
            "Priority": 1,
            "Statement": {
                "RateBasedStatement": {
                    "Limit": 2000,
                    "AggregateKeyType": "IP"
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "RateLimitRule"
            }
        },
        {
            "Name": "SQLInjectionRule",
            "Priority": 2,
            "Statement": {
                "SqliMatchStatement": {
                    "FieldToMatch": {
                        "AllQueryArguments": {}
                    },
                    "TextTransformations": [
                        {
                            "Priority": 0,
                            "Type": "URL_DECODE"
                        },
                        {
                            "Priority": 1,
                            "Type": "HTML_ENTITY_DECODE"
                        }
                    ]
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "SQLInjectionRule"
            }
        },
        {
            "Name": "XSSRule",
            "Priority": 3,
            "Statement": {
                "XssMatchStatement": {
                    "FieldToMatch": {
                        "AllQueryArguments": {}
                    },
                    "TextTransformations": [
                        {
                            "Priority": 0,
                            "Type": "URL_DECODE"
                        },
                        {
                            "Priority": 1,
                            "Type": "HTML_ENTITY_DECODE"
                        }
                    ]
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "XSSRule"
            }
        },
        {
            "Name": "GeoBlockRule",
            "Priority": 4,
            "Statement": {
                "GeoMatchStatement": {
                    "CountryCodes": ["CN", "RU", "KP"]
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "GeoBlockRule"
            }
        }
    ]'

echo "Added geographic blocking rule"
```

### Associate WAF with Load Balancer
```bash
# Associate Web ACL with ALB
if [ ! -z "$ALB_ARN" ]; then
    aws wafv2 associate-web-acl \
        --web-acl-arn $WEB_ACL_ARN \
        --resource-arn $ALB_ARN
    
    echo "Associated WAF with Application Load Balancer"
else
    echo "⚠️  ALB not found, skipping WAF association"
fi
```

## Step 2: Configure AWS Shield Advanced

### Enable Shield Advanced
```bash
# Note: Shield Advanced has a monthly cost ($3000/month)
# This is for demonstration - uncomment to actually enable

# aws shield subscribe-to-proactive-engagement \
#     --proactive-engagement-status ENABLED \
#     --emergency-contact-list EmailAddress=security@company.com,Name="Security Team",PhoneNumber="+1-555-123-4567"

# aws shield create-protection \
#     --name "ALB-Protection" \
#     --resource-arn $ALB_ARN

echo "ℹ️  Shield Advanced setup documented (requires subscription)"
echo "   Monthly cost: \$3000 + data transfer charges"
echo "   Provides: DDoS response team, cost protection, advanced metrics"
```

### Create DDoS Response Plan
```bash
cat > ddos-response-plan.md << 'EOF'
# DDoS Response Plan

## Immediate Response (0-15 minutes)
1. **Detection**
   - Monitor CloudWatch metrics for unusual traffic patterns
   - Check AWS Shield dashboard for DDoS alerts
   - Review WAF blocked requests metrics

2. **Assessment**
   - Determine attack type and scale
   - Identify affected resources
   - Check application availability

3. **Initial Mitigation**
   - Enable additional WAF rules if needed
   - Scale up infrastructure if possible
   - Contact AWS Support (if Shield Advanced subscriber)

## Short-term Response (15-60 minutes)
1. **Enhanced Monitoring**
   - Enable detailed CloudWatch metrics
   - Set up additional alarms
   - Monitor application performance

2. **Traffic Analysis**
   - Analyze VPC Flow Logs
   - Review WAF logs for attack patterns
   - Identify attack sources

3. **Additional Mitigation**
   - Implement custom WAF rules
   - Consider CloudFront for additional protection
   - Adjust rate limiting thresholds

## Long-term Response (1+ hours)
1. **Forensic Analysis**
   - Collect and analyze attack data
   - Document attack patterns
   - Update security policies

2. **Infrastructure Hardening**
   - Review and update WAF rules
   - Implement additional security controls
   - Consider architecture changes

3. **Communication**
   - Update stakeholders
   - Document lessons learned
   - Update response procedures

## Prevention Strategies
- Regular security assessments
- Proactive monitoring and alerting
- Infrastructure redundancy
- Regular DDoS simulation exercises
EOF

echo "Created DDoS response plan: ddos-response-plan.md"
```

## Step 3: Deploy GuardDuty for Threat Detection

### Enable GuardDuty
```bash
# Enable GuardDuty
aws guardduty create-detector \
    --enable \
    --finding-publishing-frequency FIFTEEN_MINUTES \
    --tags Key=Name,Value=enterprise-guardduty,Key=Project,Value=aws-networking-hard-way

DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)

echo "Enabled GuardDuty with detector ID: $DETECTOR_ID"
```

### Configure GuardDuty Threat Intelligence
```bash
# Create threat intelligence set (example malicious IPs)
cat > malicious-ips.txt << 'EOF'
192.0.2.1
198.51.100.1
203.0.113.1
EOF

# Upload to S3 bucket for GuardDuty
BUCKET_NAME="guardduty-threat-intel-$(date +%s)"
aws s3 mb s3://$BUCKET_NAME

aws s3 cp malicious-ips.txt s3://$BUCKET_NAME/malicious-ips.txt

# Create threat intelligence set
aws guardduty create-threat-intel-set \
    --detector-id $DETECTOR_ID \
    --name "MaliciousIPs" \
    --format TXT \
    --location s3://$BUCKET_NAME/malicious-ips.txt \
    --activate \
    --tags Key=Name,Value=malicious-ips-set

echo "Created threat intelligence set"
```

### Configure GuardDuty Findings
```bash
# Create SNS topic for GuardDuty alerts
aws sns create-topic \
    --name guardduty-alerts \
    --tags Key=Name,Value=guardduty-alerts,Key=Project,Value=aws-networking-hard-way

GUARDDUTY_TOPIC_ARN=$(aws sns list-topics \
    --query 'Topics[?contains(TopicArn, `guardduty-alerts`)].TopicArn' \
    --output text)

# Subscribe email to topic (replace with your email)
# aws sns subscribe \
#     --topic-arn $GUARDDUTY_TOPIC_ARN \
#     --protocol email \
#     --notification-endpoint your-email@example.com

echo "Created GuardDuty alerts topic: $GUARDDUTY_TOPIC_ARN"
```

## Step 4: Implement Network Monitoring

### Configure VPC Flow Logs with Enhanced Analysis
```bash
# Create S3 bucket for flow logs
FLOW_LOGS_BUCKET="vpc-flow-logs-$(date +%s)"
aws s3 mb s3://$FLOW_LOGS_BUCKET

# Create IAM role for flow logs to S3
cat > flow-logs-s3-trust-policy.json << 'EOF'
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
    --role-name VPCFlowLogsS3Role \
    --assume-role-policy-document file://flow-logs-s3-trust-policy.json

# Create policy for S3 access
cat > flow-logs-s3-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
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

sed -i "s/BUCKET_NAME/$FLOW_LOGS_BUCKET/g" flow-logs-s3-policy.json

aws iam create-policy \
    --policy-name VPCFlowLogsS3Policy \
    --policy-document file://flow-logs-s3-policy.json

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam attach-role-policy \
    --role-name VPCFlowLogsS3Role \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/VPCFlowLogsS3Policy

# Enable enhanced VPC Flow Logs to S3
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids $VPC_ID \
    --traffic-type ALL \
    --log-destination-type s3 \
    --log-destination arn:aws:s3:::$FLOW_LOGS_BUCKET \
    --log-format '${version} ${account-id} ${interface-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${windowstart} ${windowend} ${action} ${flowlogstatus} ${vpc-id} ${subnet-id} ${instance-id} ${tcp-flags} ${type} ${pkt-srcaddr} ${pkt-dstaddr} ${region} ${az-id}' \
    --deliver-logs-permission-arn arn:aws:iam::${ACCOUNT_ID}:role/VPCFlowLogsS3Role

echo "Configured enhanced VPC Flow Logs to S3: $FLOW_LOGS_BUCKET"

# Clean up temporary files
rm -f flow-logs-s3-trust-policy.json flow-logs-s3-policy.json
```

### Create Security Monitoring Dashboard
```bash
# Create CloudWatch dashboard for security monitoring
cat > security-dashboard.json << 'EOF'
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
                    [ "AWS/WAFV2", "BlockedRequests", "WebACL", "enterprise-web-acl", "Region", "us-east-1", "Rule", "ALL" ],
                    [ ".", "AllowedRequests", ".", ".", ".", ".", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "WAF Blocked vs Allowed Requests"
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
                    [ "AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/enterprise-alb" ],
                    [ ".", "RequestCount", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Application Load Balancer Metrics"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/wafv2/webacl/enterprise-web-acl' | fields @timestamp, action, clientIP, httpRequest.uri\n| filter action = \"BLOCK\"\n| stats count() by clientIP\n| sort count desc\n| limit 20",
                "region": "us-east-1",
                "title": "Top Blocked IPs (Last Hour)"
            }
        }
    ]
}
EOF

aws cloudwatch put-dashboard \
    --dashboard-name "NetworkSecurity" \
    --dashboard-body file://security-dashboard.json

echo "Created security monitoring dashboard"
rm -f security-dashboard.json
```

## Step 5: Create Security Automation

### Create Lambda Function for Automated Response
```bash
# Create IAM role for Lambda
cat > lambda-security-role.json << 'EOF'
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
    --role-name SecurityAutomationRole \
    --assume-role-policy-document file://lambda-security-role.json

# Attach policies
aws iam attach-role-policy \
    --role-name SecurityAutomationRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create custom policy for security actions
cat > security-automation-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "wafv2:UpdateWebAcl",
        "wafv2:GetWebAcl",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "sns:Publish",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
    --policy-name SecurityAutomationPolicy \
    --policy-document file://security-automation-policy.json

aws iam attach-role-policy \
    --role-name SecurityAutomationRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/SecurityAutomationPolicy

# Create Lambda function
cat > security-automation.py << 'EOF'
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Automated security response function
    Responds to GuardDuty findings and WAF alerts
    """
    
    wafv2 = boto3.client('wafv2')
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    try:
        # Parse the event
        if 'source' in event and event['source'] == 'aws.guardduty':
            handle_guardduty_finding(event, wafv2, ec2, sns)
        elif 'source' in event and event['source'] == 'aws.wafv2':
            handle_waf_alert(event, wafv2, sns)
        else:
            logger.info(f"Unhandled event type: {event}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Security automation executed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error in security automation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_guardduty_finding(event, wafv2, ec2, sns):
    """Handle GuardDuty findings"""
    detail = event['detail']
    finding_type = detail['type']
    severity = detail['severity']
    
    logger.info(f"Processing GuardDuty finding: {finding_type}, Severity: {severity}")
    
    # For high severity findings, take automated action
    if severity >= 7.0:
        # Extract malicious IP if available
        if 'remoteIpDetails' in detail['service']:
            malicious_ip = detail['service']['remoteIpDetails']['ipAddressV4']
            
            # Add IP to WAF block list
            block_ip_in_waf(malicious_ip, wafv2)
            
            # Send alert
            send_security_alert(f"High severity GuardDuty finding: {finding_type}. Blocked IP: {malicious_ip}", sns)

def handle_waf_alert(event, wafv2, sns):
    """Handle WAF alerts"""
    # Process WAF-specific alerts
    logger.info("Processing WAF alert")
    send_security_alert("WAF alert triggered", sns)

def block_ip_in_waf(ip_address, wafv2):
    """Add IP to WAF block list"""
    try:
        # This is a simplified example
        # In production, you'd update an IP set in WAF
        logger.info(f"Would block IP {ip_address} in WAF")
        
    except Exception as e:
        logger.error(f"Failed to block IP in WAF: {str(e)}")

def send_security_alert(message, sns):
    """Send security alert via SNS"""
    try:
        topic_arn = "TOPIC_ARN_PLACEHOLDER"
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject="Security Alert - Automated Response"
        )
        logger.info("Security alert sent")
        
    except Exception as e:
        logger.error(f"Failed to send alert: {str(e)}")
EOF

# Replace placeholder with actual topic ARN
sed -i "s/TOPIC_ARN_PLACEHOLDER/$GUARDDUTY_TOPIC_ARN/g" security-automation.py

# Create deployment package
zip security-automation.zip security-automation.py

# Create Lambda function
aws lambda create-function \
    --function-name SecurityAutomation \
    --runtime python3.9 \
    --role arn:aws:iam::${ACCOUNT_ID}:role/SecurityAutomationRole \
    --handler security-automation.lambda_handler \
    --zip-file fileb://security-automation.zip \
    --description "Automated security response function" \
    --timeout 60 \
    --tags Key=Name,Value=SecurityAutomation,Key=Project,Value=aws-networking-hard-way

echo "Created security automation Lambda function"

# Clean up
rm -f lambda-security-role.json security-automation-policy.json security-automation.py security-automation.zip
```

### Create EventBridge Rules for Automation
```bash
# Create EventBridge rule for GuardDuty findings
aws events put-rule \
    --name "GuardDutyFindings" \
    --event-pattern '{"source":["aws.guardduty"],"detail-type":["GuardDuty Finding"]}' \
    --description "Route GuardDuty findings to security automation"

# Add Lambda as target
LAMBDA_ARN=$(aws lambda get-function --function-name SecurityAutomation --query 'Configuration.FunctionArn' --output text)

aws events put-targets \
    --rule "GuardDutyFindings" \
    --targets "Id"="1","Arn"="$LAMBDA_ARN"

# Grant EventBridge permission to invoke Lambda
aws lambda add-permission \
    --function-name SecurityAutomation \
    --statement-id "AllowEventBridge" \
    --action "lambda:InvokeFunction" \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:us-east-1:${ACCOUNT_ID}:rule/GuardDutyFindings

echo "Configured EventBridge automation for GuardDuty findings"
```

## Step 6: Test Security Controls

### Create Security Testing Script
```bash
cat > test-security-controls.sh << 'EOF'
#!/bin/bash

echo "🔒 Testing Network Security Controls"
echo "=================================="

# Get load balancer DNS
ALB_DNS=$(aws elbv2 describe-load-balancers --names enterprise-alb --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "N/A")

if [ "$ALB_DNS" = "N/A" ]; then
    echo "⚠️  ALB not found, skipping web-based tests"
    ALB_DNS="example.com"
fi

echo "Testing against: $ALB_DNS"
echo ""

# Test 1: WAF Rate Limiting
echo "Test 1: WAF Rate Limiting"
echo "-------------------------"
echo "Sending rapid requests to test rate limiting..."

for i in {1..10}; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/ --max-time 5)
    echo "Request $i: HTTP $RESPONSE"
    sleep 0.1
done

# Test 2: SQL Injection Detection
echo ""
echo "Test 2: SQL Injection Detection"
echo "------------------------------"
echo "Testing SQL injection patterns..."

SQL_PAYLOADS=(
    "' OR '1'='1"
    "'; DROP TABLE users; --"
    "' UNION SELECT * FROM users --"
)

for payload in "${SQL_PAYLOADS[@]}"; do
    ENCODED_PAYLOAD=$(echo "$payload" | sed 's/ /%20/g' | sed "s/'/%27/g")
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS/?id=$ENCODED_PAYLOAD" --max-time 5)
    echo "SQL Injection test: HTTP $RESPONSE (should be 403 if blocked)"
done

# Test 3: XSS Detection
echo ""
echo "Test 3: XSS Detection"
echo "--------------------"
echo "Testing XSS patterns..."

XSS_PAYLOADS=(
    "<script>alert('xss')</script>"
    "<img src=x onerror=alert('xss')>"
    "javascript:alert('xss')"
)

for payload in "${XSS_PAYLOADS[@]}"; do
    ENCODED_PAYLOAD=$(echo "$payload" | sed 's/ /%20/g' | sed 's/</%3C/g' | sed 's/>/%3E/g')
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS/?search=$ENCODED_PAYLOAD" --max-time 5)
    echo "XSS test: HTTP $RESPONSE (should be 403 if blocked)"
done

# Test 4: Check WAF Metrics
echo ""
echo "Test 4: WAF Metrics"
echo "------------------"
echo "Checking WAF blocked requests..."

# Get WAF metrics from CloudWatch
BLOCKED_REQUESTS=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/WAFV2 \
    --metric-name BlockedRequests \
    --dimensions Name=WebACL,Value=enterprise-web-acl Name=Region,Value=us-east-1 Name=Rule,Value=ALL \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null || echo "0")

echo "Blocked requests in last hour: $BLOCKED_REQUESTS"

# Test 5: GuardDuty Status
echo ""
echo "Test 5: GuardDuty Status"
echo "-----------------------"
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null || echo "None")

if [ "$DETECTOR_ID" != "None" ]; then
    DETECTOR_STATUS=$(aws guardduty get-detector --detector-id $DETECTOR_ID --query 'Status' --output text)
    echo "GuardDuty Status: $DETECTOR_STATUS"
    
    # Check for recent findings
    FINDINGS_COUNT=$(aws guardduty list-findings --detector-id $DETECTOR_ID --query 'length(FindingIds)' --output text)
    echo "Recent findings: $FINDINGS_COUNT"
else
    echo "GuardDuty not enabled"
fi

# Test 6: VPC Flow Logs
echo ""
echo "Test 6: VPC Flow Logs"
echo "--------------------"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ecommerce-vpc" --query 'Vpcs[0].VpcId' --output text)
FLOW_LOGS=$(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC_ID" --query 'FlowLogs[0].FlowLogStatus' --output text 2>/dev/null || echo "None")

echo "VPC Flow Logs Status: $FLOW_LOGS"

echo ""
echo "🎯 Security Testing Complete"
echo ""
echo "📋 Security Recommendations:"
echo "1. Monitor WAF metrics regularly"
echo "2. Review GuardDuty findings daily"
echo "3. Analyze VPC Flow Logs for anomalies"
echo "4. Test security controls monthly"
echo "5. Update WAF rules based on attack patterns"
EOF

chmod +x test-security-controls.sh
echo "Created security testing script: test-security-controls.sh"
```

### Create Security Incident Response Playbook
```bash
cat > security-incident-playbook.md << 'EOF'
# Security Incident Response Playbook

## Phase 1: Detection and Analysis (0-30 minutes)

### Immediate Actions
1. **Confirm the Incident**
   - Review GuardDuty findings
   - Check WAF blocked requests
   - Analyze CloudWatch alarms
   - Verify with multiple data sources

2. **Initial Assessment**
   - Determine incident severity (Low/Medium/High/Critical)
   - Identify affected systems and data
   - Estimate potential impact
   - Document initial findings

3. **Notification**
   - Alert security team
   - Notify management (if High/Critical)
   - Contact AWS Support (if needed)
   - Update incident tracking system

## Phase 2: Containment (30-60 minutes)

### Short-term Containment
1. **Isolate Affected Systems**
   - Update security groups to block malicious traffic
   - Add IPs to WAF block lists
   - Disable compromised user accounts
   - Isolate affected instances

2. **Preserve Evidence**
   - Take EBS snapshots of affected instances
   - Export relevant logs
   - Document system state
   - Preserve network traffic captures

3. **Implement Temporary Fixes**
   - Apply emergency patches
   - Update WAF rules
   - Modify network ACLs
   - Enable additional monitoring

### Long-term Containment
1. **System Hardening**
   - Review and update security configurations
   - Implement additional security controls
   - Update access controls
   - Enhance monitoring

## Phase 3: Eradication and Recovery (1-4 hours)

### Eradication
1. **Remove Threats**
   - Delete malware/backdoors
   - Close security vulnerabilities
   - Update compromised credentials
   - Remove unauthorized access

2. **System Restoration**
   - Restore from clean backups
   - Rebuild compromised systems
   - Apply security patches
   - Update security configurations

### Recovery
1. **Gradual Service Restoration**
   - Test systems thoroughly
   - Monitor for recurring issues
   - Gradually restore normal operations
   - Validate security controls

2. **Enhanced Monitoring**
   - Implement additional logging
   - Set up specific alerts
   - Monitor for indicators of compromise
   - Conduct security scans

## Phase 4: Post-Incident Activities (1+ days)

### Documentation
1. **Incident Report**
   - Timeline of events
   - Root cause analysis
   - Impact assessment
   - Response effectiveness

2. **Lessons Learned**
   - What worked well
   - Areas for improvement
   - Process updates needed
   - Training requirements

### Improvement
1. **Update Procedures**
   - Revise incident response plan
   - Update security controls
   - Enhance monitoring
   - Improve automation

2. **Training and Awareness**
   - Conduct team debriefing
   - Update training materials
   - Share lessons learned
   - Practice scenarios

## Emergency Contacts

- **Security Team**: security@company.com
- **AWS Support**: [Support Case Portal]
- **Management**: management@company.com
- **Legal**: legal@company.com
- **PR/Communications**: pr@company.com

## Key Resources

- **AWS Security Hub**: [Console Link]
- **GuardDuty**: [Console Link]
- **WAF Dashboard**: [Console Link]
- **CloudTrail**: [Console Link]
- **VPC Flow Logs**: [S3 Bucket]

## Severity Definitions

- **Critical**: Active attack with data exfiltration
- **High**: Confirmed security breach
- **Medium**: Suspicious activity requiring investigation
- **Low**: Policy violation or minor security issue
EOF

echo "Created security incident response playbook: security-incident-playbook.md"
```

## Validation Commands

### Verify Security Configuration
```bash
# Check WAF status
echo "🔍 WAF Configuration:"
aws wafv2 list-web-acls --scope REGIONAL \
    --query 'WebACLs[].{Name:Name,Id:Id,Description:Description}' \
    --output table

# Check GuardDuty status
echo ""
echo "🛡️  GuardDuty Status:"
aws guardduty list-detectors \
    --query 'DetectorIds' \
    --output table

# Check VPC Flow Logs
echo ""
echo "📊 VPC Flow Logs:"
aws ec2 describe-flow-logs \
    --filter "Name=resource-id,Values=$VPC_ID" \
    --query 'FlowLogs[].{ID:FlowLogId,Status:FlowLogStatus,Destination:LogDestination}' \
    --output table

# Check security automation
echo ""
echo "🤖 Security Automation:"
aws lambda list-functions \
    --query 'Functions[?FunctionName==`SecurityAutomation`].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}' \
    --output table
```

## Cleanup for This Lab

```bash
cat > cleanup-lab07.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Lab 07 resources..."

# Disassociate WAF from ALB
ALB_ARN=$(aws elbv2 describe-load-balancers --names enterprise-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ "$ALB_ARN" != "None" ] && [ ! -z "$ALB_ARN" ]; then
    aws wafv2 disassociate-web-acl --resource-arn $ALB_ARN 2>/dev/null
fi

# Delete WAF Web ACL
WEB_ACL_ID=$(aws wafv2 list-web-acls --scope REGIONAL --query 'WebACLs[?Name==`enterprise-web-acl`].Id' --output text 2>/dev/null)
if [ "$WEB_ACL_ID" != "None" ] && [ ! -z "$WEB_ACL_ID" ]; then
    aws wafv2 delete-web-acl --scope REGIONAL --id $WEB_ACL_ID --lock-token $(aws wafv2 get-web-acl --scope REGIONAL --id $WEB_ACL_ID --query 'LockToken' --output text) 2>/dev/null
fi

# Delete GuardDuty detector
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null)
if [ "$DETECTOR_ID" != "None" ] && [ ! -z "$DETECTOR_ID" ]; then
    # Delete threat intelligence sets
    THREAT_SETS=$(aws guardduty list-threat-intel-sets --detector-id $DETECTOR_ID --query 'ThreatIntelSetIds' --output text 2>/dev/null)
    for SET_ID in $THREAT_SETS; do
        [ ! -z "$SET_ID" ] && aws guardduty delete-threat-intel-set --detector-id $DETECTOR_ID --threat-intel-set-id $SET_ID 2>/dev/null
    done
    
    aws guardduty delete-detector --detector-id $DETECTOR_ID 2>/dev/null
fi

# Delete Lambda function
aws lambda delete-function --function-name SecurityAutomation 2>/dev/null

# Delete EventBridge rule
aws events remove-targets --rule GuardDutyFindings --ids 1 2>/dev/null
aws events delete-rule --name GuardDutyFindings 2>/dev/null

# Delete IAM roles and policies
aws iam detach-role-policy --role-name SecurityAutomationRole --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/SecurityAutomationPolicy 2>/dev/null
aws iam detach-role-policy --role-name SecurityAutomationRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null
aws iam delete-role --role-name SecurityAutomationRole 2>/dev/null
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/SecurityAutomationPolicy 2>/dev/null

aws iam detach-role-policy --role-name VPCFlowLogsS3Role --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/VPCFlowLogsS3Policy 2>/dev/null
aws iam delete-role --role-name VPCFlowLogsS3Role 2>/dev/null
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/VPCFlowLogsS3Policy 2>/dev/null

# Delete S3 buckets
FLOW_LOGS_BUCKET=$(aws s3 ls | grep vpc-flow-logs | awk '{print $3}')
THREAT_INTEL_BUCKET=$(aws s3 ls | grep guardduty-threat-intel | awk '{print $3}')

[ ! -z "$FLOW_LOGS_BUCKET" ] && aws s3 rb s3://$FLOW_LOGS_BUCKET --force 2>/dev/null
[ ! -z "$THREAT_INTEL_BUCKET" ] && aws s3 rb s3://$THREAT_INTEL_BUCKET --force 2>/dev/null

# Delete SNS topic
TOPIC_ARN=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `guardduty-alerts`)].TopicArn' --output text)
[ ! -z "$TOPIC_ARN" ] && aws sns delete-topic --topic-arn $TOPIC_ARN 2>/dev/null

# Delete CloudWatch dashboard
aws cloudwatch delete-dashboards --dashboard-names NetworkSecurity 2>/dev/null

# Clean up files
rm -f malicious-ips.txt ddos-response-plan.md security-incident-playbook.md

echo "✅ Lab 07 cleanup completed"
EOF

chmod +x cleanup-lab07.sh
echo "Created cleanup script: cleanup-lab07.sh"
```

## Next Steps

After completing this lab, you should have:
- ✅ AWS WAF with comprehensive protection rules
- ✅ GuardDuty threat detection enabled
- ✅ Enhanced VPC Flow Logs monitoring
- ✅ Automated security response system
- ✅ Security incident response procedures
- ✅ Comprehensive security testing framework

**Continue to:** [Lab 08: Multi-Account Networking](../08-multi-account-networking/README.md)