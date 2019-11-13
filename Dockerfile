FROM debian:buster

RUN apt-get update \
 && apt-get install --yes \
      wget \
      python3-distutils \
      python3-scapy \
      pciutils \
 && rm -rf /var/apt/lists/*

RUN cd tmp \
 && wget https://trex-tgn.cisco.com/trex/release/v2.65.tar.gz \
 && tar -xf v2.65.tar.gz \
 && rm v2.65.tar.gz \
 && mv v2.65 trex

COPY traffic-configurations/veth_cfg.yaml /etc/trex_cfg.yaml
COPY traffic-configurations/*.yaml /tmp/trex/cfg/
COPY traffic-patterns/dns_customer_ip.yaml /tmp/trex/cap2/dns_customer_ip.yaml

