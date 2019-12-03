#!/bin/bash -eux 

[[ ${EUID} -ne 0 ]] && echo "You must run this as root." && exit 1

mkdir -p /var/run/netns
docker run --detach --name sleeper --net none debian:buster sleep infinity
ln -sfT /proc/$(docker inspect --format '{{.State.Pid}}' sleeper)/ns/net /var/run/netns/sleeper
ln -sfT /proc/$(docker inspect --format '{{.State.Pid}}' trex)/ns/net /var/run/netns/trex

ip link add veth1 type veth peer name veth2
ip link set veth1 netns trex
ip link set veth2 netns sleeper
ip -n trex l set dev veth1 up
ip -n sleeper l set dev veth2 up
ip -n trex addr add 1.1.1.1/24 dev veth1
ip -n sleeper addr add 1.1.1.2/24 dev veth2
