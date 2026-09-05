FROM ubuntu:26.04@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b

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
