FROM node:22-bookworm AS build

ARG WITH_UI=false

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    g++ \
    gcc \
    git \
    make \
    pkg-config \
    python3 \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

RUN if [ "$WITH_UI" = "true" ]; then \
      scripts/build.sh --with-ui CC=gcc CXX=g++; \
    else \
      scripts/build.sh CC=gcc CXX=g++; \
    fi

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    libstdc++6 \
    socat \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/c/codebase-memory-mcp /usr/local/bin/amaze-mcp
RUN ln -sf /usr/local/bin/amaze-mcp /usr/local/bin/amaze \
    && ln -sf /usr/local/bin/amaze-mcp /usr/local/bin/codebase-memory-mcp

ENV AMAZE_CACHE_DIR=/Users/steve/.cache/amaze-mcp \
    CBM_CACHE_DIR=/Users/steve/.cache/amaze-mcp \
    CBM_LOG_LEVEL=info \
    HOME=/Users/steve

WORKDIR /Users/steve

ENTRYPOINT ["/usr/local/bin/amaze-mcp"]
