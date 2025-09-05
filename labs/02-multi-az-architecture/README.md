# Lab 02: Multi-AZ High Availability Architecture

## Objective
Extend the foundation VPC to implement true high availability across multiple availability zones with redundant NAT Gateways and proper failover mechanisms.

## Scenario
The e-commerce platform is growing and requires 99.9% uptime. You need to eliminate single points of failure by implementing redundant network components across multiple AZs.

## Architecture Overview
```
Enhanced Multi-AZ Architecture:
├── AZ-1a Components
│   ├── Public Subnet: 10.0.1.0/24
│   ├── Private Subnet: 10.0.11.0/24
│   ├── DB Subnet: 10.0.21.0/24
│   └── NAT Gateway #1
└── AZ-1b Components
    ├── Public Subnet: 10.0.2.0/24
    ├── Private Subnet: 10.0.12.0/24
    ├── DB Subnet: 10.0.22.0/24
    └── NAT Gateway #2
```

## Enterprise Requirements
- No single point of failure
- Automatic failover capabilities
- Cost optimization strategies
- Monitoring and alerting

## Tasks

### 1. Deploy Second NAT Gateway
Create redundant NAT Gateway in second AZ.

### 2. Configure AZ-Specific Routing
Set up route tables for each AZ to use local NAT Gateway.

### 3. Implement Health Checks
Configure monitoring for network components.

### 4. Test Failover Scenarios
Validate high availability during component failures.

### 5. Cost Analysis
Compare costs of different HA strategies.

## Learning Outcomes
- Understanding AZ failure domains
- NAT Gateway redundancy patterns
- Route table design for HA
- Cost vs. availability trade-offs

[Continue to detailed steps](./steps.md)