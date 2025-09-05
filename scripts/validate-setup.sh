#!/bin/bash

# AWS Networking The Hard Way - Setup Validation Script
# This script validates your AWS environment is ready for the labs

set -e

echo "🔍 AWS Networking The Hard Way - Environment Validation"
echo "======================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    local status=$1
    local message=$2
    
    if [ "$status" = "pass" ]; then
        echo -e "✅ ${GREEN}PASS${NC}: $message"
    elif [ "$status" = "fail" ]; then
        echo -e "❌ ${RED}FAIL${NC}: $message"
    elif [ "$status" = "warn" ]; then
        echo -e "⚠️  ${YELLOW}WARN${NC}: $message"
    else
        echo -e "ℹ️  INFO: $message"
    fi
}

# Function to check command exists
check_command() {
    local cmd=$1
    local name=$2
    
    if command -v $cmd &> /dev/null; then
        local version=$($cmd --version 2>&1 | head -n1)
        print_status "pass" "$name is installed: $version"
        return 0
    else
        print_status "fail" "$name is not installed"
        return 1
    fi
}

# Function to check AWS CLI configuration
check_aws_config() {
    if aws sts get-caller-identity &> /dev/null; then
        local account=$(aws sts get-caller-identity --query Account --output text)
        local user=$(aws sts get-caller-identity --query Arn --output text)
        local region=$(aws configure get region)
        
        print_status "pass" "AWS CLI is configured"
        echo "   Account: $account"
        echo "   User/Role: $user"
        echo "   Region: $region"
        return 0
    else
        print_status "fail" "AWS CLI is not configured or credentials are invalid"
        return 1
    fi
}

# Function to check AWS permissions
check_aws_permissions() {
    local permissions_ok=true
    
    echo ""
    echo "🔐 Checking AWS Permissions..."
    echo "=============================="
    
    # Test VPC permissions
    if aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        print_status "pass" "VPC read permissions"
    else
        print_status "fail" "VPC read permissions"
        permissions_ok=false
    fi
    
    # Test EC2 permissions
    if aws ec2 describe-instances --max-items 1 &> /dev/null; then
        print_status "pass" "EC2 read permissions"
    else
        print_status "fail" "EC2 read permissions"
        permissions_ok=false
    fi
    
    # Test Route 53 permissions
    if aws route53 list-hosted-zones --max-items 1 &> /dev/null; then
        print_status "pass" "Route 53 read permissions"
    else
        print_status "warn" "Route 53 read permissions (some labs may not work)"
    fi
    
    # Test CloudWatch permissions
    if aws logs describe-log-groups --max-items 1 &> /dev/null; then
        print_status "pass" "CloudWatch Logs read permissions"
    else
        print_status "warn" "CloudWatch Logs read permissions (monitoring labs may not work)"
    fi
    
    # Test IAM permissions (for advanced labs)
    if aws iam list-roles --max-items 1 &> /dev/null; then
        print_status "pass" "IAM read permissions"
    else
        print_status "warn" "IAM read permissions (some advanced labs may not work)"
    fi
    
    return $permissions_ok
}

# Function to check resource limits
check_resource_limits() {
    echo ""
    echo "📊 Checking Resource Limits..."
    echo "=============================="
    
    # Check VPC limit
    local vpc_count=$(aws ec2 describe-vpcs --query 'length(Vpcs)' --output text)
    local vpc_limit=$(aws ec2 describe-account-attributes --attribute-names supported-platforms --query 'AccountAttributes[0].AttributeValues[0].AttributeValue' --output text 2>/dev/null || echo "5")
    
    if [ "$vpc_count" -lt 5 ]; then
        print_status "pass" "VPC usage: $vpc_count/5 (sufficient for labs)"
    else
        print_status "warn" "VPC usage: $vpc_count/5 (may need cleanup before labs)"
    fi
    
    # Check Elastic IP limit
    local eip_count=$(aws ec2 describe-addresses --query 'length(Addresses)' --output text)
    
    if [ "$eip_count" -lt 3 ]; then
        print_status "pass" "Elastic IP usage: $eip_count/5 (sufficient for labs)"
    else
        print_status "warn" "Elastic IP usage: $eip_count/5 (may need cleanup before labs)"
    fi
    
    # Check Internet Gateway limit
    local igw_count=$(aws ec2 describe-internet-gateways --query 'length(InternetGateways)' --output text)
    
    if [ "$igw_count" -lt 3 ]; then
        print_status "pass" "Internet Gateway usage: $igw_count/5 (sufficient for labs)"
    else
        print_status "warn" "Internet Gateway usage: $igw_count/5 (may need cleanup before labs)"
    fi
}

# Function to estimate costs
estimate_costs() {
    echo ""
    echo "💰 Cost Estimation..."
    echo "===================="
    
    local region=$(aws configure get region)
    
    echo "Estimated costs for complete lab series in region $region:"
    echo ""
    echo "💡 Most resources are Free Tier eligible, but some charges apply:"
    echo "   • NAT Gateway: ~\$0.045/hour × 2 gateways × 40 hours = ~\$3.60"
    echo "   • Elastic IPs: ~\$0.005/hour when not attached = ~\$0.20"
    echo "   • Data Transfer: ~\$0.09/GB for cross-AZ = ~\$1.00"
    echo "   • Load Balancer: ~\$0.0225/hour × 20 hours = ~\$0.45"
    echo "   • VPC Endpoints: ~\$0.01/hour × 10 hours = ~\$0.10"
    echo ""
    echo "   📊 Total estimated cost: ~\$5-10 for complete series"
    echo ""
    print_status "info" "Set up billing alerts to monitor costs"
    print_status "info" "Always clean up resources after each lab"
}

# Function to check for existing resources
check_existing_resources() {
    echo ""
    echo "🔍 Checking for Existing Lab Resources..."
    echo "========================================"
    
    # Check for existing lab VPCs
    local lab_vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Project,Values=aws-networking-hard-way" \
        --query 'length(Vpcs)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$lab_vpcs" -gt 0 ]; then
        print_status "warn" "Found $lab_vpcs existing lab VPCs - consider cleanup before starting"
    else
        print_status "pass" "No existing lab resources found"
    fi
}

# Main validation
echo "🚀 Starting environment validation..."
echo ""

# Check prerequisites
echo "🛠️  Checking Prerequisites..."
echo "============================"

check_command "aws" "AWS CLI"
check_command "jq" "jq (JSON processor)" || print_status "warn" "jq not found - some scripts may not work optimally"
check_command "curl" "curl"
check_command "ssh" "SSH client"

echo ""

# Check AWS configuration
echo "☁️  Checking AWS Configuration..."
echo "================================"
check_aws_config

# Check permissions
check_aws_permissions

# Check resource limits
check_resource_limits

# Check existing resources
check_existing_resources

# Cost estimation
estimate_costs

echo ""
echo "📋 Validation Summary"
echo "===================="

# Final recommendations
echo ""
echo "📝 Recommendations:"
echo "• Review the prerequisites document if any checks failed"
echo "• Set up billing alerts in the AWS console"
echo "• Bookmark the troubleshooting guide for reference"
echo "• Start with Lab 01 if all critical checks passed"
echo ""

# Check if ready to proceed
if aws sts get-caller-identity &> /dev/null && aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
    print_status "pass" "Environment is ready for AWS Networking The Hard Way!"
    echo ""
    echo "🎯 Next steps:"
    echo "1. cd aws-networking-the-hard-way"
    echo "2. Read the README.md for overview"
    echo "3. Start with labs/01-foundation-vpc/README.md"
else
    print_status "fail" "Environment needs configuration before starting labs"
    echo ""
    echo "🔧 Required actions:"
    echo "1. Configure AWS CLI: aws configure"
    echo "2. Verify IAM permissions"
    echo "3. Run this script again"
fi

echo ""
echo "✨ Happy learning!"