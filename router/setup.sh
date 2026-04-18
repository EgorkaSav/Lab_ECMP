#!/bin/bash
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.fib_multipath_hash_policy=0

ip route del default 2>/dev/null || true

IF_PATH1=$(ip -o addr show | awk '/10.0.2.11/{print $2}')
IF_PATH2=$(ip -o addr show | awk '/10.0.3.11/{print $2}')

echo "=== Path1 interface: $IF_PATH1 ==="
echo "=== Path2 interface: $IF_PATH2 ==="

# ECMP маршрут к VIP ресивера
ip route add 10.99.0.1/32 \
    nexthop via 10.0.2.20 dev $IF_PATH1 weight 1 \
    nexthop via 10.0.3.20 dev $IF_PATH2 weight 1

echo "=== Route table ==="
ip route show

sleep infinity
