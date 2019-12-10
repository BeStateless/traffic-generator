#!/bin/bash -eux 

# Clean up any stale sleeper container.
docker rm -f sleeper      || true
rm /var/run/netns/sleeper || true

# Start a new container to receive packets from trex.
docker run --detach --name sleeper --net none debian:buster sleep infinity
ln -sfT /proc/$(docker inspect --format '{{.State.Pid}}' sleeper)/ns/net /var/run/netns/sleeper

# String a veth between the trex container and the sleeper container.
ip link add veth1 type veth peer name veth2
ip link set veth1 netns trex
ip link set veth2 netns sleeper
ip -n trex l set dev veth1 up
ip -n sleeper l set dev veth2 up
ip -n trex addr add 1.1.1.1/24 dev veth1
ip -n sleeper addr add 1.1.1.2/24 dev veth2
