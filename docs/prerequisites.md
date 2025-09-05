# Prerequisites

## AWS Account Requirements

### Account Setup
- AWS account with administrative access
- AWS CLI v2 installed and configured
- Appropriate IAM permissions for networking services
- AWS Organizations access (for multi-account labs)

### Required Permissions
Your IAM user or role needs permissions for:
- EC2 (VPC, subnets, security groups, instances)
- Route 53 (DNS management)
- CloudFormation (infrastructure as code)
- CloudWatch (monitoring and logging)
- IAM (role creation and management)
- Organizations (multi-account setup)

### Cost Considerations
- Most labs use Free Tier eligible resources
- NAT Gateways incur hourly charges (~$0.045/hour)
- Data transfer charges may apply
- Estimated total cost: $10-20 for complete series

## Technical Prerequisites

### Networking Knowledge
- Understanding of TCP/IP, subnets, and CIDR notation
- Basic routing concepts
- DNS fundamentals
- Load balancing principles
- Network security concepts

### AWS Familiarity
- Basic AWS console navigation
- Understanding of regions and availability zones
- Familiarity with EC2 instances
- Basic knowledge of AWS services

### Tools Required
- AWS CLI v2
- Text editor (VS Code, vim, etc.)
- SSH client
- Web browser
- Optional: Terraform or CloudFormation experience

## Environment Setup

### AWS CLI Configuration
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure credentials
aws configure
```

### Verify Setup
```bash
# Test AWS access
aws sts get-caller-identity

# Check available regions
aws ec2 describe-regions --output table

# Verify permissions
aws ec2 describe-vpcs
```

### Optional Tools
- **jq**: JSON processing for CLI output
- **dig**: DNS troubleshooting
- **traceroute**: Network path analysis
- **nmap**: Network scanning and discovery

## Safety Guidelines

### Resource Management
- Always tag resources with lab identifiers
- Set up billing alerts
- Use resource naming conventions
- Clean up resources after each lab

### Security Best Practices
- Never use root account for labs
- Rotate access keys regularly
- Use least privilege principles
- Enable CloudTrail logging

### Cost Control
- Monitor AWS billing dashboard
- Set up cost alerts
- Use AWS Cost Explorer
- Delete resources when not needed

## Getting Help

### AWS Documentation
- [VPC User Guide](https://docs.aws.amazon.com/vpc/)
- [Route 53 Developer Guide](https://docs.aws.amazon.com/route53/)
- [CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)

### Community Resources
- AWS re:Post community
- AWS Architecture Center
- AWS Well-Architected Framework
- AWS Networking & Content Delivery Blog

### Troubleshooting
- Check AWS Service Health Dashboard
- Review CloudTrail logs for API errors
- Use AWS Support (if available)
- Consult lab-specific troubleshooting guides