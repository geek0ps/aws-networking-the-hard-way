# Lab 01: Foundation VPC Setup

## Objective
Build a production-ready VPC from scratch with proper CIDR planning, subnets, and basic routing.

## Scenario
You're tasked with creating the network foundation for a new e-commerce platform that needs to support web servers, application servers, and databases across multiple availability zones.

## Architecture Overview
```
VPC: 10.0.0.0/16
├── Public Subnets (Web Tier)
│   ├── us-east-1a: 10.0.1.0/24
│   └── us-east-1b: 10.0.2.0/24
├── Private Subnets (App Tier)
│   ├── us-east-1a: 10.0.11.0/24
│   └── us-east-1b: 10.0.12.0/24
└── Database Subnets
    ├── us-east-1a: 10.0.21.0/24
    └── us-east-1b: 10.0.22.0/24
```

## Tasks

### 1. Create the VPC
Create a VPC with proper DNS settings and CIDR block planning.

### 2. Create Subnets
Set up subnets following the three-tier architecture pattern.

### 3. Configure Internet Gateway
Enable internet access for public subnets.

### 4. Set Up Route Tables
Configure routing for public and private subnets.

### 5. Create NAT Gateway
Enable outbound internet access for private subnets.

## Step-by-Step Instructions

[Continue to detailed steps](./steps.md)

## Validation
- [ ] VPC created with correct CIDR
- [ ] All subnets created in correct AZs
- [ ] Internet Gateway attached
- [ ] Route tables configured properly
- [ ] NAT Gateway operational

## Troubleshooting
Common issues and solutions for this lab.

## Cleanup
Instructions to remove all resources created in this lab.

## Next Lab
[Lab 02: Multi-AZ Architecture](../02-multi-az-architecture/README.md)