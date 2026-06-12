FROM python:3.14-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

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
