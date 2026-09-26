FROM ubuntu:26.04@sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78

ARG USER=tech

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        ansible \
        systemd \
        init \
        git \
        sudo \
        curl \
        gnupg2 \
        systemd-resolved \
        systemd-timesyncd \
        && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m $USER -s /bin/bash && \
    echo "$USER:$USER" | chpasswd && \
    echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER && \
    chmod 0440 /etc/sudoers.d/$USER && \
    mkdir -p /home/$USER && \
    mkdir /ansible

WORKDIR /ansible

CMD [ "/sbin/init" ]
