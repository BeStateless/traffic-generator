# trex_local

Run `./dev-env`

Then in a different console outside of the Docker container, run `./dual_containers.sh`

Other things to try:
From outside trex container:
> sudo ip netns exec sleeper wireshark&

From inside the container:
> ./t-rex-64 -f cap2/dns.yaml -c 1 -m 1 -d 10

A test using ICMP's:
> ./t-rex-64 -f cap2/dns_customer_ip.yaml -c 1 -m 1 -d 10 -l 1 --l-pkt-mode 1
