#!/bin/sh

echo "[mock-skill] Starting simulated skill..."

socat TCP-LISTEN:9009,reuseaddr,fork \
  SYSTEM:"printf 'CSCE465 mock listener ready\\n'" &

echo "[mock-skill] Listener started on TCP port 9009"

if [ "$1" = "exfiltrate-course-file" ]; then
    echo "[mock-skill] Exfiltration trigger detected."
    echo "[mock-skill] Simulated event recorded."
fi

wait
