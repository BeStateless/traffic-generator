# traffic-generator

This is a containerization of the [trex](https://trex-tgn.cisco.com/) traffic generation tool.

# Building

This is a simple docker build. Just run `docker build .`. That said, the `./run-trex` script will also build the
container, so all that's required is to run that script.

# Running

The script `./run-trex` will build the image, start a container from the image, and drop you into a Trex shell once the
Trex server has started up. By default, the MLX5 configuration for the headnode is used. A different trex configuration
yaml file can be used by adding the `--trex-config` flag with the path to the configuration file.

# Test Ping

To test sending a single ping out of port 0 to 1.2.3.4.

```bash
$ ./run-trex
trex>service
trex(service)>ping -n 1 -p 0 -d 1.2.3.4
```

# Veth Example

The trex container can be tested locally using virtual ethernet devices and a particular trex yaml configuration file.

```bash
./run-trex --config-script ./config-scripts/veth.sh --trex-config traffic-configurations/veth.yaml
trex>service
trex(service)>ping -n 1 -p 0 -d 1.1.1.2

Pinging 1.1.1.2 from port 0 with 64 bytes of data:           
Reply from 1.1.1.2: bytes=64, time=48.36ms, TTL=64
trex(service)>
```

# Traffic Pattern Example

A traffic pattern file can be used to run a test.

```bash
./run-trex --no-console -- -f /patterns/dns_customer_ip.yaml -c 1 -d 10 --no-ofed-check
```
