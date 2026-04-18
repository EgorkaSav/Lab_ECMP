#!/bin/bash

ip route del default 2>/dev/null || true
ip route add default via 10.0.1.11

for i in $(seq 3 15); do
    [ $i -eq 11 ] && continue
    ip addr add "10.0.1.${i}/24" dev eth0 2>/dev/null || true
done

echo "=== Aliases added ==="
ip addr show eth0

sleep infinity
