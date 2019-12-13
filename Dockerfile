FROM statelesstestregistry.azurecr.io/stateless/base:9

# Install necessary Debian packages.
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      build-essential \
      ca-certificates \
      cmake \
      git \
      iproute2 \
      libmnl-dev \
      libnl-3-dev \
      libnl-route-3-dev \
      libnuma-dev \
      linux-headers-5.3.7 \
      pciutils \
      pkg-config \
      python3 \
      python3-distutils \
      supervisor \
      wget \
      zlib1g-dev \
    # Trex needs libzmq5, and python3-scapy which we don't have in the stateless apt repository yet. TODO add it into
    # the next version...
 && echo deb http://deb.debian.org/debian buster main >> /etc/apt/sources.list \
 && apt-get update \
 && apt-get install --yes \
      libzmq5 \
      python3-scapy \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# Build rdma-core 25.0 from source. We build rdma-core from source because the version that Trex has embedded in it has
# a bug that makes us unable to use our MLX5 cards.
RUN wget https://github.com/linux-rdma/rdma-core/releases/download/v25.0/rdma-core-25.0.tar.gz \
 && tar -xf rdma-core-*.tar.gz \
 && rm rdma-core-*.tar.gz \
 && mv rdma-core-* rdma-core \
 && cd rdma-core \
 && mkdir build \
 && cd build \
 && cmake ../ \
 && make -j$(( $(nproc) + 1 )) \
 && make install

# Build DPDK 19.11 from source. It might not be necessary to do a full build. What we really need are the rte_config.h
# and *_autoconf.h generated header files. The *_autoconf.h files aren't generated as part of "make config", so
# currently we do the full "make". A less long-running command may exist, but we haven't taken the time to find it yet.
# We don't install DPDK, we just need to rip some files out after the build.
#
# We don't _need_ any new functionality from DPDK 19.11, but when we tried to use just the new rdma-core build we got a
# bunch of build errors which are assumed to be due to an incompatability between DPDK 19.05 and rdma-core 25.0.
RUN wget https://fast.dpdk.org/rel/dpdk-19.11.tar.xz \
 && tar -xf dpdk-19.11.tar.xz \
 && rm dpdk-19.11.tar.xz \
 && mv dpdk-19.11 dpdk \
 && cd dpdk \
 && export RTE_KERNELDIR=/lib/modules/5.3.7/build \
 && make config T=x86_64-native-linuxapp-gcc \
 && cd build \
 && sed -i 's/CONFIG_RTE_LIBRTE_MLX4_PMD=n/CONFIG_RTE_LIBRTE_MLX4_PMD=y/' .config \
 && sed -i 's/CONFIG_RTE_LIBRTE_MLX5_PMD=n/CONFIG_RTE_LIBRTE_MLX5_PMD=y/' .config \
 && make EXTRA_CFLAGS="-I/tmp/rdma-core/build/include -L/tmp/rdma-core/build/lib" -j$(( $(nproc) + 1 ))

# Build Trex from source. Unfortunately, the transition from DPDK 19.05 to 19.11 was quite large, so quite a bit of code
# changes are required to do this. Here we have used sed commands and generate patches on the fly. It's a bit weird, but
# it _might_ be easier than maintaining a big patch set. In theory, when Trex moves to DPDK 19.11 or beyond we won't
# need to do this.
COPY assets/mlx5_flow.c.patch /tmp/
RUN wget https://github.com/cisco-system-traffic-generator/trex-core/archive/v2.71.tar.gz \
 && tar -xf v2.71.tar.gz \
 && rm v2.71.tar.gz \
 && mv trex-core-2.71 trex-core \
    # Get the source code for the DPDK version that Trex currently uses. We need this so we can generate a patch file
    # containing the differences between the DPDK code embedded in Trex and the mainline DPDK code. The Trex devs do not
    # provide this, which is something they _should_ provide so we don't have to to crazy workarounds like this. They
    # also don't copy _every_ DPDK lib, only some, so we need to be careful of that when generating the patch.
 && wget https://fast.dpdk.org/rel/dpdk-19.05.tar.xz \
 && tar -xf dpdk-19.05.tar.xz \
 && rm dpdk-19.05.tar.xz \
    # Make a directory called dpdk_libs which contains only the dpdk/libs directories that Trex uses.
 && mkdir dpdk_libs \
 && for DPDK_LIB in $(find dpdk-19.05/lib/* -maxdepth 1 -type d -name "lib*"); do \
      for TREX_LIB in $(find trex-core/src/dpdk/lib/* -maxdepth 1 -type d -name "lib*"); do \
        if [ "$(basename ${TREX_LIB})" = "$(basename ${DPDK_LIB})" ]; then \
          cp -r "${DPDK_LIB}" /tmp/dpdk_libs; \
        fi \
      done \
    done \
    # Stupidly, the DPDK code embedded in trex has _some_ .map and meson.build files, but not all of them. So we need to
    # remove all of those files from _both_ source trees in order for the diff to work appropriately. (Trex didn't make
    # any changes to these files, so they just get in the way.)
 && find dpdk_libs              -name "*.map" -or -name "*.build" -type f | xargs rm -f \
 && find trex-core/src/dpdk/lib -name "*.map" -or -name "*.build" -type f | xargs rm -f \
    # This file should _not_ be patched. It contains changes in Trex, but they are minor typing differences and the
    # transition from DPDK 19.05 to 19.11 makes the obsolete anyway.
 && rm trex-core/src/dpdk/lib/librte_net/rte_ip.h dpdk_libs/librte_net/rte_ip.h \
    # Generate the patch file. We will use this patch later to apply all of the Trex-specific changes on top of the new
    # DPDK 19.11 source.
 && diff -r --unified dpdk_libs trex-core/src/dpdk/lib > libs.patch || true \
 && rm -rf dpdk-19.05 \
 && cd trex-core/linux_dpdk \
    # Adjust the Trex WAF build script for our changes...
    # 1. Disable "-Werror" because the build hits some warnings on GCC8 that we do not want to be fatal.
 && sed -i "/-Werror/d" ws_main.py \
    # 2. Use DPDK 19.11 isntead of DPDK 19.05.
 && sed -i "s/dpdk1905/dpdk1911/g" ws_main.py \
    # 3. The "mlx5_flow_tcf.c" file was removed between DPDK 19.05 and DPDK 19.11.
 && sed -i "/mlx5_flow_tcf.c/d" ws_main.py \
    # 4. librte_cryptodev should be an include directory.
 && sed -i "/..\/src\/dpdk\/lib\/librte_compat\//a ..\/src\/dpdk\/lib\/librte_cryptodev\/" ws_main.py \
    # 5. librte_security should be an include directory.
 && sed -i "/..\/src\/dpdk\/lib\/librte_ring\//a ..\/src\/dpdk\/lib\/librte_security\/" ws_main.py \
    # 6. RTE_USE_FUNCTION_VERSIONING should be defined for DPDK to build.
 && sed -i "/-D__STDC_CONSTANT_MACROS/a '-DRTE_USE_FUNCTION_VERSIONING'," ws_main.py \
    # 7. rte_ether.c is a new file.
 && sed -i "/lib\/librte_mempool\/rte_mempool_ops_default.c/a 'lib\/librte_net\/rte_ether.c'," ws_main.py \
    # 8. eal_common_mcfg.c is a new file.
 && sed -i "/lib\/librte_eal\/common\/hotplug_mp.c/i 'lib\/librte_eal\/common\/eal_common_mcfg.c'," ws_main.py \
    # 9. rte_mbuf_dyn.c is a new file.
 && sed -i "/lib\/librte_mbuf\/rte_mbuf.c/a 'lib\/librte_mbuf\/rte_mbuf_dyn.c'," ws_main.py \
    # 10. enic_fm_flow.c is a new file.
 && sed -i "/drivers\/net\/enic\/enic_flow.c/a 'drivers\/net\/enic\/enic_fm_flow.c'," ws_main.py \
    # 11. rte_random.c is a new file.
 && sed -i "/lib\/librte_eal\/common\/rte_option.c/i 'lib\/librte_eal\/common\/rte_random.c'," ws_main.py \
    # 12. mlx5_flow_meter.c is a new file.
 && sed -i "/mlx5_flow_dv.c/a 'mlx5_flow_meter.c'," ws_main.py \
    # 13. mlx5_utils.c is a new file.
 && sed -i "/mlx5_txq.c/a 'mlx5_utils.c'," ws_main.py \
    # Put our newer rdma-core files in place.
 && cd ../external_libs/ibverbs/x86_64 \
 && rm -rf * \
 && mkdir include \
 && cp -r /tmp/rdma-core/build/include/infiniband include/ \
 && cp -L /tmp/rdma-core/build/lib/libibverbs.so \
          /tmp/rdma-core/build/lib/libmlx4.so \
          /tmp/rdma-core/build/lib/libmlx5.so \
          . \
    # Put our newer dpdk files in place.
 && cd ../../../src \
 && rm -rf dpdk \
 && mkdir dpdk \
 && cd dpdk \
 && cp -r /tmp/dpdk/drivers /tmp/dpdk/lib . \
    # Copy the special auto-generated headers in DPDK 19.11.
 && cp /tmp/dpdk/build/build/drivers/net/tap/tap_autoconf.h drivers/net/tap/ \
 && cp /tmp/dpdk/build/build/drivers/net/mlx4/mlx4_autoconf.h drivers/net/mlx4/ \
 && cp /tmp/dpdk/build/build/drivers/net/mlx5/mlx5_autoconf.h drivers/net/mlx5/ \
    # Take the differences between the stock rte_config.h and the Trex rte_config.h for DPDK 19.05. We'll apply this
    # diff over the rte_config.h for DPDK 19.11.
 && cd ../pal/linux_dpdk/dpdk1905_x86_64 \
 && diff --unified=2 rte_config_orig.h rte_config.h > /tmp/rte_config.h.patch || true \
 && mkdir ../dpdk1911_x86_64 \
 && cd ../dpdk1911_x86_64 \
 && cp /tmp/dpdk/build/include/rte_config.h . \
 && patch < /tmp/rte_config.h.patch \
    # Apply the DPDK Trex patch that we built earlier.
 && cd /tmp/trex-core/src/dpdk/lib \
 && patch -p1 < /tmp/libs.patch || true \
 && cd librte_mbuf \
 && patch rte_mbuf_core.h < rte_mbuf.h.rej \
 && cd ../../drivers/net/mlx5 \
 && patch < /tmp/mlx5_flow.c.patch \
 && cd ../../../../ \
    # A bunch of crap was renamed and moved. Deal with that using sed.
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i '/DEV_TX_OFFLOAD_MATCH_METADATA/d' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ETHER_ADDR_FMT_SIZE/RTE_ETHER_ADDR_FMT_SIZE/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ETHER_TYPE_ARP/RTE_ETHER_TYPE_ARP/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ETHER_TYPE_IPV4/RTE_ETHER_TYPE_IPV4/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ETHER_TYPE_IPV6/RTE_ETHER_TYPE_IPV6/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ETHER_TYPE_IPv4/RTE_ETHER_TYPE_IPV4/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ETHER_TYPE_IPv6/RTE_ETHER_TYPE_IPV6/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ETHER_TYPE_VLAN/RTE_ETHER_TYPE_VLAN/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ETHER_TYPE_QINQ/RTE_ETHER_TYPE_QINQ/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ ipv4_hdr / rte_ipv4_hdr /g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ ipv6_hdr / rte_ipv6_hdr /g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ tcp_hdr / rte_tcp_hdr /g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ udp_hdr / rte_udp_hdr /g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ ether_addr / rte_ether_addr /g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/eal_parse_pci_BDF/rte_pci_addr_parse/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/eal_parse_pci_DomBDF/rte_pci_addr_parse/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/rte_eth_dev_count(/rte_eth_dev_count_avail(/g' \
 && find . -path ./dpdk -prune -o -type f -print | xargs sed -i 's/ether_format_addr/rte_ether_format_addr/g' \
    # This static assertion triggers. The mbuf size must have changed.
 && sed -i '/size of MBUF must be 128/d' pal/linux_dpdk/mbuf.cpp \
 && cd ../linux_dpdk \
    # Actually build and install Trex.
 && ./b configure \
 && ./b build \
 && ./b install \
 && ldconfig

# Run supervisord as the entrypoint. We don't want to start trex immediately when the container starts because we might
# need to perform some interface initialization. The arguments to pass to trex are put in a file, because unfortunately
# there's no way for us to use supervisorctl to tell supervisord what arguments to use.
RUN echo "-i --no-ofed-check" > /tmp/trex-args
COPY assets/supervisord.conf /etc/supervisor/conf.d/
ENTRYPOINT [ "supervisord", "-c", "/etc/supervisor/supervisord.conf" ]
WORKDIR /tmp/trex-core/scripts
