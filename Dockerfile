FROM nvidia/cuda:12.8.1-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
# Allow pip to install into the system Python inside a Docker container.
# Ubuntu 24.04 enforces PEP 668 by default; this flag mirrors the old
# behaviour that python:3.12-slim had (no venv required in an image).
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# System deps. tmux is required by Cookbook for background downloads/serves.
# openssh-client is required for Cookbook remote server tests, setup, probes,
# downloads, and serves from Docker installs.
# git/cmake are required when Cookbook builds llama.cpp on first llama.cpp
# launch inside Docker.
# nodejs/npm provide npx for the optional built-in Browser MCP server.
# gosu lets the entrypoint drop privileges cleanly so signals still reach
# uvicorn directly (no extra shell layer like `su`/`sudo` would add).
# Python 3.12 is the default on Ubuntu 24.04; python3-dev and python3-pip
# add the headers and pip installer.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    curl \
    git \
    nodejs \
    npm \
    tmux \
    openssh-client \
    gosu \
    python3.12 \
    python3.12-dev \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Ensure `python` and `python3` resolve to 3.12.
RUN update-alternatives --install /usr/bin/python  python  /usr/bin/python3.12 1 \
 && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

WORKDIR /app

# Install Python deps first (layer cache). Optional extras (PyMuPDF AGPL, etc.)
# are opt-in so the default image stays MIT-core; see requirements-optional.txt.
ARG INSTALL_OPTIONAL=false
COPY requirements.txt requirements-optional.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && if [ "$INSTALL_OPTIONAL" = "true" ]; then pip install --no-cache-dir -r requirements-optional.txt; fi

# Copy app code
COPY . .

# Create data directory (mount a volume here for persistence)
RUN mkdir -p data logs services/cache/search

# Entrypoint that drops to PUID/PGID (default 1000:1000) and repairs
# ownership on the bind-mounted /app/data and /app/logs. Without this,
# the container runs as root and writes root-owned files into host
# bind mounts — any later non-root run (or a host user trying to
# update them) silently fails on EPERM, breaking skill extraction,
# prefs persistence, mail attachments, etc.
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 7000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7000"]
