# Lab 05: Hybrid Cloud Connectivity

## Objective
Establish secure, high-performance connections between on-premises infrastructure and AWS using VPN, Direct Connect, and hybrid DNS resolution.

## Scenario
Your enterprise has existing on-premises data centers that need to integrate with AWS workloads. You need to implement redundant connectivity with failover capabilities and seamless DNS resolution.

## Architecture Overview
```
Hybrid Connectivity:
├── On-Premises (192.168.0.0/16)
│   ├── Corporate Network
│   ├── Data Center
│   └── Branch Offices
├── AWS Direct Connect
│   ├── Primary Connection (1Gbps)
│   └── Backup Connection (500Mbps)
├── Site-to-Site VPN
│   ├── Primary Tunnel
│   └── Backup Tunnel
└── Hybrid DNS
    ├── Route 53 Resolver
    └── On-premises DNS
```

## Enterprise Requirements
- 99.99% connectivity uptime
- Sub-10ms latency for critical apps
- Seamless DNS resolution
- Disaster recovery capabilities
- Compliance with data residency

## Tasks

### 1. Design Network Architecture
Plan IP addressing and routing for hybrid setup.

### 2. Configure Site-to-Site VPN
Establish encrypted tunnels with redundancy.

### 3. Simulate Direct Connect
Use VPN to simulate DX connectivity patterns.

### 4. Implement Hybrid DNS
Set up Route 53 Resolver for cross-premises DNS.

### 5. Configure BGP Routing
Implement dynamic routing with path preferences.

### 6. Test Failover Scenarios
Validate connectivity during link failures.

## Advanced Topics
- ECMP (Equal Cost Multi-Path) routing
- BGP communities and path manipulation
- DNS forwarding rules
- Network performance optimization

[Continue to detailed steps](./steps.md)