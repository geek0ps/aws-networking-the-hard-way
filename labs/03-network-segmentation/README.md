# Lab 03: Network Segmentation and Security Groups

## Objective
Implement enterprise-grade network segmentation using Security Groups, NACLs, and subnet isolation to create a defense-in-depth security model.

## Scenario
Your e-commerce platform handles sensitive customer data and payment information. You need to implement strict network segmentation following PCI DSS and SOC 2 compliance requirements.

## Architecture Overview
```
Security Zones:
├── DMZ (Public Subnets)
│   ├── Web Servers (Port 80/443 only)
│   └── Load Balancers
├── Application Zone (Private Subnets)
│   ├── App Servers (Internal communication)
│   └── API Gateways
├── Data Zone (Database Subnets)
│   ├── Primary Databases
│   └── Read Replicas
└── Management Zone
    ├── Bastion Hosts
    └── Monitoring Systems
```

## Enterprise Security Requirements
- Zero-trust network model
- Principle of least privilege
- Network traffic logging
- Compliance with security frameworks

## Tasks

### 1. Design Security Group Strategy
Create layered security groups for each tier.

### 2. Implement Network ACLs
Add subnet-level security controls.

### 3. Create Bastion Host Architecture
Secure administrative access pattern.

### 4. Configure VPC Flow Logs
Enable comprehensive network monitoring.

### 5. Test Security Boundaries
Validate isolation between tiers.

## Security Patterns Covered
- Micro-segmentation
- Jump box architecture
- Database security zones
- Web application firewalls

[Continue to detailed steps](./steps.md)