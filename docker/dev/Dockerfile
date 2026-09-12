FROM python:3.14-slim@sha256:cad9a2c871761c413caa6fdd6441c783451e740a48aaeba60ae62a8b53525ef6

COPY --from=ghcr.io/astral-sh/uv:latest@sha256:b485bd65cc2cf1c9a93b3554012c9c3778cf7b1b5fd3d3096ce9e1226c97e1e6 /uv /uvx /bin/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        shellcheck \
        git \
        build-essential \
        python3-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN uv pip install --system \
    yamllint \
    ansible-lint

WORKDIR /app

CMD ["bash"]
