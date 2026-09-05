FROM python:3.14-slim

COPY --from=ghcr.io/astral-sh/uv:latest@sha256:2bb3ebca0a796a155094a27773d290c4b074572e6107f171d88d086682fd2500 /uv /uvx /bin/

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
