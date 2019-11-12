set -eux

sudo mkdir -p /var/run/netns
docker run -d --name sleeper --net none debian:buster sleep infinity
sudo ln -sfT /proc/$(docker inspect --format '{{.State.Pid}}' sleeper)/ns/net /var/run/netns/sleeper
sudo ln -sfT /proc/$(docker inspect --format '{{.State.Pid}}' trex)/ns/net /var/run/netns/trex

sudo ip link add veth1 type veth peer name veth2
sudo ip link set veth1 netns trex
sudo ip link set veth2 netns sleeper
sudo ip -n trex l set dev veth1 up
sudo ip -n sleeper l set dev veth2 up
sudo ip -n trex addr add 1.1.1.1/24 dev veth1
sudo ip -n sleeper addr add 1.1.1.2/24 dev veth2

sudo ip link add veth3 type veth peer name veth4
sudo ip link set veth3 netns trex
sudo ip link set veth4 netns sleeper
sudo ip -n trex l set dev veth3 up
sudo ip -n sleeper l set dev veth4 up
sudo ip -n trex addr add 1.1.1.3/24 dev veth3
sudo ip -n sleeper addr add 1.1.1.4/24 dev veth4

