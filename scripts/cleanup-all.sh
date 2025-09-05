#!/bin/bash

# AWS Networking The Hard Way - Complete Cleanup Script
# This script removes all resources created during the labs
# WARNING: This will delete ALL resources with the specified tags

set -e

echo "🧹 AWS Networking The Hard Way - Complete Cleanup"
echo "=================================================="
echo ""
echo "⚠️  WARNING: This will delete ALL lab resources!"
echo "⚠️  Make sure you want to proceed before continuing."
echo ""
read -p "Are you sure you want to delete all lab resources? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "🔍 Discovering resources to cleanup..."

# Function to check if AWS CLI is configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS CLI not configured. Please run 'aws configure' first."
        exit 1
    fi
}

# Function to delete resources by tag
cleanup_by_tag() {
    local resource_type=$1
    local tag_key=$2
    local tag_value=$3
    
    echo "🗑️  Cleaning up $resource_type with tag $tag_key=$tag_value..."
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_id=$2
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Waiting for $resource_type $resource_id to be deleted..."
    
    while [ $attempt -le $max_attempts ]; do
        if ! aws ec2 describe-$resource_type --${resource_type}-ids $resource_id &> /dev/null; then
            echo "✅ $resource_type $resource_id deleted successfully"
            return 0
        fi
        
        echo "   Attempt $attempt/$max_attempts - still deleting..."
        sleep 10
        ((attempt++))
    done
    
    echo "⚠️  Timeout waiting for $resource_type $resource_id deletion"
    return 1
}

# Check prerequisites
check_aws_cli

echo "🎯 Current AWS Account: $(aws sts get-caller-identity --query Account --output text)"
echo "🌍 Current Region: $(aws configure get region)"
echo ""

# Get all VPCs with lab tags
echo "🔍 Finding lab VPCs..."
LAB_VPCS=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=aws-networking-hard-way" \
    --query 'Vpcs[].VpcId' \
    --output text)

if [ -z "$LAB_VPCS" ]; then
    echo "ℹ️  No lab VPCs found. Nothing to cleanup."
    exit 0
fi

echo "📋 Found VPCs to cleanup: $LAB_VPCS"
echo ""

# Cleanup each VPC
for VPC_ID in $LAB_VPCS; do
    echo "🧹 Cleaning up VPC: $VPC_ID"
    echo "================================"
    
    # 1. Delete EC2 instances
    echo "🖥️  Terminating EC2 instances..."
    INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
    
    if [ ! -z "$INSTANCES" ]; then
        aws ec2 terminate-instances --instance-ids $INSTANCES
        echo "   Terminated instances: $INSTANCES"
    fi
    
    # 2. Delete Load Balancers
    echo "⚖️  Deleting Load Balancers..."
    LOAD_BALANCERS=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
        --output text)
    
    for LB_ARN in $LOAD_BALANCERS; do
        if [ ! -z "$LB_ARN" ]; then
            aws elbv2 delete-load-balancer --load-balancer-arn $LB_ARN
            echo "   Deleted load balancer: $LB_ARN"
        fi
    done
    
    # 3. Delete NAT Gateways
    echo "🌐 Deleting NAT Gateways..."
    NAT_GATEWAYS=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
        --query 'NatGateways[].NatGatewayId' \
        --output text)
    
    for NAT_GW in $NAT_GATEWAYS; do
        if [ ! -z "$NAT_GW" ]; then
            aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW
            echo "   Deleted NAT Gateway: $NAT_GW"
        fi
    done
    
    # 4. Release Elastic IPs
    echo "📍 Releasing Elastic IPs..."
    ELASTIC_IPS=$(aws ec2 describe-addresses \
        --filters "Name=tag:Project,Values=aws-networking-hard-way" \
        --query 'Addresses[].AllocationId' \
        --output text)
    
    for EIP in $ELASTIC_IPS; do
        if [ ! -z "$EIP" ]; then
            aws ec2 release-address --allocation-id $EIP
            echo "   Released Elastic IP: $EIP"
        fi
    done
    
    # 5. Delete VPC Endpoints
    echo "🔗 Deleting VPC Endpoints..."
    VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'VpcEndpoints[].VpcEndpointId' \
        --output text)
    
    for ENDPOINT in $VPC_ENDPOINTS; do
        if [ ! -z "$ENDPOINT" ]; then
            aws ec2 delete-vpc-endpoint --vpc-endpoint-id $ENDPOINT
            echo "   Deleted VPC Endpoint: $ENDPOINT"
        fi
    done
    
    # 6. Delete VPC Peering Connections
    echo "🤝 Deleting VPC Peering Connections..."
    PEERING_CONNECTIONS=$(aws ec2 describe-vpc-peering-connections \
        --filters "Name=requester-vpc-info.vpc-id,Values=$VPC_ID" \
        --query 'VpcPeeringConnections[].VpcPeeringConnectionId' \
        --output text)
    
    for PEERING in $PEERING_CONNECTIONS; do
        if [ ! -z "$PEERING" ]; then
            aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $PEERING
            echo "   Deleted VPC Peering: $PEERING"
        fi
    done
    
    # Wait for NAT Gateways to be deleted before proceeding
    for NAT_GW in $NAT_GATEWAYS; do
        if [ ! -z "$NAT_GW" ]; then
            wait_for_deletion "nat-gateways" $NAT_GW
        fi
    done
    
    # 7. Delete Subnets
    echo "🏠 Deleting Subnets..."
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[].SubnetId' \
        --output text)
    
    for SUBNET in $SUBNETS; do
        if [ ! -z "$SUBNET" ]; then
            aws ec2 delete-subnet --subnet-id $SUBNET
            echo "   Deleted subnet: $SUBNET"
        fi
    done
    
    # 8. Delete Route Tables (except main)
    echo "🗺️  Deleting Route Tables..."
    ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
        --output text)
    
    for RT in $ROUTE_TABLES; do
        if [ ! -z "$RT" ]; then
            aws ec2 delete-route-table --route-table-id $RT
            echo "   Deleted route table: $RT"
        fi
    done
    
    # 9. Delete Security Groups (except default)
    echo "🔒 Deleting Security Groups..."
    SECURITY_GROUPS=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text)
    
    for SG in $SECURITY_GROUPS; do
        if [ ! -z "$SG" ]; then
            aws ec2 delete-security-group --group-id $SG
            echo "   Deleted security group: $SG"
        fi
    done
    
    # 10. Detach and Delete Internet Gateway
    echo "🌍 Deleting Internet Gateway..."
    IGW=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query 'InternetGateways[].InternetGatewayId' \
        --output text)
    
    if [ ! -z "$IGW" ]; then
        aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID
        aws ec2 delete-internet-gateway --internet-gateway-id $IGW
        echo "   Deleted Internet Gateway: $IGW"
    fi
    
    # 11. Delete VPC
    echo "🏢 Deleting VPC..."
    aws ec2 delete-vpc --vpc-id $VPC_ID
    echo "   Deleted VPC: $VPC_ID"
    
    echo ""
done

# Cleanup Transit Gateways
echo "🚇 Cleaning up Transit Gateways..."
TRANSIT_GATEWAYS=$(aws ec2 describe-transit-gateways \
    --filters "Name=tag:Project,Values=aws-networking-hard-way" \
    --query 'TransitGateways[].TransitGatewayId' \
    --output text)

for TGW in $TRANSIT_GATEWAYS; do
    if [ ! -z "$TGW" ]; then
        # Delete attachments first
        ATTACHMENTS=$(aws ec2 describe-transit-gateway-attachments \
            --filters "Name=transit-gateway-id,Values=$TGW" \
            --query 'TransitGatewayAttachments[].TransitGatewayAttachmentId' \
            --output text)
        
        for ATTACHMENT in $ATTACHMENTS; do
            if [ ! -z "$ATTACHMENT" ]; then
                aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id $ATTACHMENT
                echo "   Deleted TGW attachment: $ATTACHMENT"
            fi
        done
        
        # Wait for attachments to be deleted, then delete TGW
        sleep 30
        aws ec2 delete-transit-gateway --transit-gateway-id $TGW
        echo "   Deleted Transit Gateway: $TGW"
    fi
done

# Cleanup Route 53 resources
echo "🌐 Cleaning up Route 53 resources..."
HOSTED_ZONES=$(aws route53 list-hosted-zones-by-name \
    --query 'HostedZones[?Config.Comment==`aws-networking-hard-way`].Id' \
    --output text)

for ZONE in $HOSTED_ZONES; do
    if [ ! -z "$ZONE" ]; then
        # Delete all records except NS and SOA
        aws route53 list-resource-record-sets --hosted-zone-id $ZONE \
            --query 'ResourceRecordSets[?Type!=`NS` && Type!=`SOA`]' \
            --output json > /tmp/records.json
        
        if [ -s /tmp/records.json ]; then
            aws route53 change-resource-record-sets \
                --hosted-zone-id $ZONE \
                --change-batch file:///tmp/records.json
        fi
        
        aws route53 delete-hosted-zone --id $ZONE
        echo "   Deleted hosted zone: $ZONE"
    fi
done

echo ""
echo "✅ Cleanup completed successfully!"
echo ""
echo "💡 Note: Some resources may take a few minutes to fully delete."
echo "💡 Check the AWS console to verify all resources have been removed."
echo "💡 If you encounter any issues, check the AWS CloudTrail logs for details."