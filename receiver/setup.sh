#!/bin/bash
ip addr add 10.99.0.1/32 dev lo

ip route del default 2>/dev/null || true
r
ip route add 10.0.1.0/24 via 10.0.2.11 dev eth1

tcpdump -i eth0 -n -w /tmp/path2.pcap &
tcpdump -i eth1 -n -w /tmp/path1.pcap &

echo "=== Interfaces ==="
ip addr show
echo "=== Routes ==="
ip route show
echo "=== tcpdump started ==="
ps aux | grep tcpdump

sleep infinity
