#!/bin/bash
set -e

# Remove jumps to our custom chain
while iptables -w -C DOCKER-USER -j HW4-AGENT-EGRESS 2>/dev/null; do
    iptables -w -D DOCKER-USER -j HW4-AGENT-EGRESS
done

# Remove our custom chain
if iptables -w -nL HW4-AGENT-EGRESS >/dev/null 2>&1; then
    iptables -w -F HW4-AGENT-EGRESS
    iptables -w -X HW4-AGENT-EGRESS
fi

echo "HW4 firewall rules removed."
