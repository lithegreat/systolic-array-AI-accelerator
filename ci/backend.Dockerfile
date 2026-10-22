# The Azure runner only prepares source and connects to Eikon.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates git openssh-client tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
