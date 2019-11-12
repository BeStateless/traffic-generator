FROM debian:buster

RUN apt-get update \
 && apt-get install --yes \
      wget \
      python3-distutils \
      vim \
 && rm -rf /var/apt/lists/*

RUN cd tmp \
 && wget https://trex-tgn.cisco.com/trex/release/v2.65.tar.gz \
 && tar -xf v2.65.tar.gz \
 && rm v2.65.tar.gz \
 && mv v2.65 trex

COPY trex.yaml /etc/trex_cfg.yaml
COPY vlan_cfg.yaml /tmp/trex/cfg/vlan_cfg.yaml
COPY dns_customer_ip.yaml /tmp/trex/cap2/dns_customer_ip.yaml
COPY entry /usr/local/bin/entry
ENTRYPOINT ["entry"]
