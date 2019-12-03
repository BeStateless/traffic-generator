#!/bin/bash -eux 

[[ ${EUID} -ne 0 ]] && echo "You must run this as root." && exit 1

mkdir -p /var/run/netns
docker run --detach --name sleeper --net none debian:buster sleep infinity
ln -sfT /proc/$(docker inspect --format '{{.State.Pid}}' sleeper)/ns/net /var/run/netns/sleeper
ln -sfT /proc/$(docker inspect --format '{{.State.Pid}}' trex)/ns/net /var/run/netns/trex

ip link add veth1 type veth peer name veth2
ip link add link veth1 veth1.24 type vlan proto 802.1ad id 24
ip link add link veth2 veth2.12 type vlan proto 802.1ad id 12
ip link add link veth2 veth2.24 type vlan proto 802.1ad id 24
ip link set veth1.24 netns trex
ip link set veth2.24 netns sleeper
ip link set veth1 up
ip link set veth2 up
ip -n trex addr add 1.1.1.1/24 dev veth1.24
ip -n sleeper addr add 1.1.1.2/24 dev veth2.24
