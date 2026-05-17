# Example project overlay — extends devbox-base with project-specific tools.
# Build devbox-base first (see base/), then this overlay layers on top.

FROM devbox-base:latest

USER root

# Project-specific apt packages — keep this list small.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-client redis-tools && \
    rm -rf /var/lib/apt/lists/*

USER dev

# Project-specific tool versions (overrides global mise config)
# COPY --chown=dev:dev mise.toml /home/dev/code/example-project/mise.toml
