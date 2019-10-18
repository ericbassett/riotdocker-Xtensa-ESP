#
# RIOT Dockerfile
#
# The resulting image will contain everything needed to build RIOT for all
# supported platforms. This is the largest build image, it takes about 1.5 GB in
# total.
#
# Setup:
# 1. Install docker, add yourself to docker group, enable docker, relogin
#
# Use prebuilt image:
# 1. Prebuilt image can be pulled from Docker Hub registry with:
#      # docker pull riot/riotbuild
# 
# Use own build image:
# 1. Build own image based on latest base OS image:
#      # docker build --pull -t riotbuild .
#
# Usage:
# 1. cd to riot root
# 2. # docker run -i -t -u $UID -v $(pwd):/data/riotbuild riotbuild ./dist/tools/compile_test/compile_test.py

FROM ubuntu:bionic

LABEL maintainer="Kaspar Schleiser <kaspar@riot-os.org>"

ENV DEBIAN_FRONTEND noninteractive

ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8

# The following package groups will be installed:
# - update the package index files to latest available version
# - native platform development and build system functionality (about 400 MB installed)
# All apt files will be deleted afterwards to reduce the size of the container image.
# The OS must not be updated by apt. Docker image should be build against the latest
#  updated base OS image. This can be forced with `--pull` flag.
# This is all done in a single RUN command to reduce the number of layers and to
# allow the cleanup to actually save space.
# Total size without cleaning is approximately 1.525 GB (2016-03-08)
# After adding the cleanup commands the size is approximately 1.497 GB
RUN \
    dpkg --add-architecture i386 >&2 && \
    echo 'Update the package index files to latest available versions' >&2 && \
    apt-get update \
    && echo 'Installing native toolchain and build system functionality' >&2 && \
    apt-get -y --no-install-recommends install \
        build-essential \
        ca-certificates \
        cmake \
        coccinelle \
        curl \
        cppcheck \
        doxygen \
        git \
        graphviz \
        less \
        pcregrep \
        protobuf-compiler \
        python \
        python3 \
        python3-dev \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        rsync \
        ssh-client \
        subversion \
        unzip \
        vera++ \
        vim-common \
        wget \
        xsltproc \
    && echo 'Cleaning up installation files' >&2 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# compile suid create_user binary
COPY create_user.c /tmp/create_user.c
RUN gcc -DHOMEDIR=\"/data/riotbuild\" -DUSERNAME=\"riotbuild\" /tmp/create_user.c -o /usr/local/bin/create_user \
    && chown root:root /usr/local/bin/create_user \
    && chmod u=rws,g=x,o=- /usr/local/bin/create_user \
    && rm /tmp/create_user.c

# Install complete ESP8266 toolchain in /opt/esp (139 MB after cleanup)
# remember https://github.com/RIOT-OS/RIOT/pull/10801 when updating
# NOTE: We install the toolchain for the RTOS SDK in parallel in the first
# step and remove the old version as soon as the RIOT port for the ESP8266
# RTOS SDK has been merged.
RUN echo 'Installing ESP8266 toolchain' >&2 && \
    mkdir -p /opt/esp && \
    cd /opt/esp && \
    git clone https://github.com/gschorcht/xtensa-esp8266-elf && \
    cd xtensa-esp8266-elf && \
    git checkout -q 696257c2b43e2a107d3108b2c1ca6d5df3fb1a6f && \
    rm -rf .git && \
    cd /opt/esp && \
    git clone https://github.com/gschorcht/RIOT-Xtensa-ESP8266-RTOS-SDK.git ESP8266_RTOS_SDK && \
    cd ESP8266_RTOS_SDK/ && \
    git checkout -q f074414c0705715a44b8e59d53b03d90b7630382 && \
    rm -rf .git* docs examples make tools && \
    cd components && \
    rm -rf app_update aws_iot bootloader cjson coap espos esp-tls freertos \
           jsmn libsodium log mdns mqtt newlib partition_table pthread \
           smartconfig_ack spiffs ssl tcpip_adapter vfs && \
    find . -name '*.[csS]' -exec rm {} \;

ENV PATH $PATH:/opt/esp/xtensa-esp8266-elf/bin
ENV ESP8266_RTOS_SDK_DIR /opt/esp/ESP8266_RTOS_SDK

# install required python packages from file
COPY requirements.txt /tmp/requirements.txt
RUN echo 'Installing python3 packages' >&2 \
    && pip3 install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Create working directory for mounting the RIOT sources
RUN mkdir -m 777 -p /data/riotbuild

# Set a global system-wide git user and email address
RUN git config --system user.name "riot" && \
    git config --system user.email "riot@example.com"

# Copy our entry point script (signal wrapper)
COPY run.sh /run.sh
ENTRYPOINT ["/bin/bash", "/run.sh"]

# By default, run a shell when no command is specified on the docker command line
CMD ["/bin/bash"]

WORKDIR /data/riotbuild
