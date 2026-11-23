#!/bin/bash
set -e

# Enable bridge traffic filtering
modprobe br_netfilter
sysctl -w net.bridge.bridge-nf-call-iptables=1

# Create our custom chain if it does not exist
iptables -w -N HW4-AGENT-EGRESS 2>/dev/null || true

# Clear previous course rules
iptables -w -F HW4-AGENT-EGRESS

# Send forwarded traffic through our course chain
iptables -w -C DOCKER-USER -j HW4-AGENT-EGRESS 2>/dev/null || \
iptables -w -I DOCKER-USER 1 -j HW4-AGENT-EGRESS

# 1. Allow established and related traffic
iptables -w -A HW4-AGENT-EGRESS \
-m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

# 2. Allow agent-node to reach web-lab on TCP 8000
iptables -w -A HW4-AGENT-EGRESS \
-s 172.30.0.10 -d 172.30.0.40 \
-p tcp --dport 8000 \
-m conntrack --ctstate NEW -j RETURN

# 3. Log new connections to mock-c2 on TCP 8080
iptables -w -A HW4-AGENT-EGRESS \
-s 172.30.0.10 -d 172.30.0.66 \
-p tcp --dport 8080 \
-m conntrack --ctstate NEW \
-j LOG --log-prefix "HW4-C2-DROP: "

# 4. Drop those connections
iptables -w -A HW4-AGENT-EGRESS \
-s 172.30.0.10 -d 172.30.0.66 \
-p tcp --dport 8080 \
-m conntrack --ctstate NEW -j DROP

# 5. Drop all other new forwarded connections from agent-node
iptables -w -A HW4-AGENT-EGRESS \
-s 172.30.0.10 \
-m conntrack --ctstate NEW -j DROP

# Leave unrelated traffic unchanged
iptables -w -A HW4-AGENT-EGRESS -j RETURN

echo "HW4 firewall rules successfully applied."
