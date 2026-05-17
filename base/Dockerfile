# syntax=docker/dockerfile:1.7
# devbox-base — slim Linux dev container mirroring a macOS toolchain
#
# Build:  docker compose build   (from base/)
# Spec:   docs/superpowers/specs/2026-05-16-devbox-design.md

ARG DEBIAN_VERSION=bookworm
ARG NODE_VERSION=22
ARG GO_VERSION=1.23
ARG RUST_CHANNEL=stable
ARG UV_VERSION=0.5.11
ARG MISE_VERSION=v2025.1.0
ARG OP_VERSION=2.30.3
ARG JAVA_VERSION=17
ARG ANDROID_CMDLINE_TOOLS_VERSION=11076708
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

# =============================================================================
# Stage 1: system — apt packages (rarely changes; cached aggressively)
# =============================================================================
FROM debian:${DEBIAN_VERSION}-slim AS system

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg lsb-release \
        git openssh-server openssh-client sudo \
        zsh tmux less man-db locales \
        build-essential pkg-config libssl-dev \
        ripgrep fd-find bat jq \
        fzf direnv unzip xz-utils file procps iproute2 \
        python3 python3-venv python3-pip \
    && \
    # Debian ships `fd` as `fdfind` and `bat` as `batcat` — alias them
    ln -s /usr/bin/fdfind /usr/local/bin/fd && \
    ln -s /usr/bin/batcat /usr/local/bin/bat && \
    sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen

# gh (GitHub CLI), eza, delta, yq — not in bookworm's main repos at modern versions
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list >/dev/null && \
    # eza (modern ls replacement)
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
        | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
        > /etc/apt/sources.list.d/gierens.list && \
    chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends gh eza && \
    # delta (git-delta): binary from GitHub releases — not in Debian repos on all arches
    DELTA_VERSION="0.18.2" && \
    DELTA_ARCH=$(dpkg --print-architecture) && \
    curl -fsSL -o /tmp/delta.deb \
        "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${DELTA_ARCH}.deb" && \
    dpkg -i /tmp/delta.deb && \
    rm /tmp/delta.deb

# yq (mikefarah/yq, the Go one — fast, good)
ARG TARGETARCH
RUN curl -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH:-amd64}" && \
    chmod +x /usr/local/bin/yq

# starship — fast, lazy, cross-shell prompt (replaces oh-my-zsh themes)
RUN curl -sS https://starship.rs/install.sh \
        | sh -s -- -y -b /usr/local/bin

# zoxide — frecency-ranked `cd` replacement (ajeetdsouza/zoxide)
RUN ZOXIDE_VERSION="0.9.6" && \
    ARCH_ZOXIDE=$(case "${TARGETARCH:-amd64}" in amd64) echo "x86_64-unknown-linux-musl";; arm64) echo "aarch64-unknown-linux-musl";; esac) && \
    curl -fsSL -o /tmp/zoxide.tgz \
        "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-${ARCH_ZOXIDE}.tar.gz" && \
    tar -xzf /tmp/zoxide.tgz -C /usr/local/bin zoxide && \
    chmod +x /usr/local/bin/zoxide && \
    rm /tmp/zoxide.tgz

# atuin — sqlite-backed shell history with search + optional E2E sync (atuinsh/atuin)
RUN ATUIN_VERSION="18.4.0" && \
    ARCH_ATUIN=$(case "${TARGETARCH:-amd64}" in amd64) echo "x86_64-unknown-linux-gnu";; arm64) echo "aarch64-unknown-linux-gnu";; esac) && \
    curl -fsSL -o /tmp/atuin.tgz \
        "https://github.com/atuinsh/atuin/releases/download/v${ATUIN_VERSION}/atuin-${ARCH_ATUIN}.tar.gz" && \
    tar -xzf /tmp/atuin.tgz -C /tmp && \
    install -m 0755 "/tmp/atuin-${ARCH_ATUIN}/atuin" /usr/local/bin/atuin && \
    rm -rf /tmp/atuin.tgz "/tmp/atuin-${ARCH_ATUIN}"

# lazydocker — TUI for containers, images, volumes (jesseduffield/lazydocker)
RUN curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh \
        | DIR=/usr/local/bin bash

# dive — image-layer analyzer; directly supports the <2GB hard rule (wagoodman/dive)
RUN DIVE_VERSION="0.13.1" && \
    curl -fsSL -o /tmp/dive.deb \
        "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_${TARGETARCH:-amd64}.deb" && \
    dpkg -i /tmp/dive.deb && \
    rm /tmp/dive.deb

# ctop — top-style live container monitor (bcicen/ctop)
RUN curl -fsSL -o /usr/local/bin/ctop \
        "https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-${TARGETARCH:-amd64}" && \
    chmod +x /usr/local/bin/ctop

# hadolint — Dockerfile linter, shellcheck-aware (hadolint/hadolint)
RUN ARCH_HADOLINT=$(case "${TARGETARCH:-amd64}" in amd64) echo "x86_64";; arm64) echo "arm64";; esac) && \
    curl -fsSL -o /usr/local/bin/hadolint \
        "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-${ARCH_HADOLINT}" && \
    chmod +x /usr/local/bin/hadolint

# 1Password CLI
RUN ARCH="${TARGETARCH:-amd64}" && \
    curl -fsSL -o /tmp/op.zip \
        "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION:-2.30.3}/op_linux_${ARCH}_v${OP_VERSION:-2.30.3}.zip" && \
    unzip -d /usr/local/bin /tmp/op.zip op && \
    rm /tmp/op.zip

# Docker CLI only (the daemon stays on the host; we'll bind-mount /var/run/docker.sock)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
        > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin

# Java 17 (Temurin) — needed for Android/Gradle builds (React Native)
ARG JAVA_VERSION
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
        | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo $VERSION_CODENAME) main" \
        > /etc/apt/sources.list.d/adoptium.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends temurin-${JAVA_VERSION}-jdk && \
    # Symlink so JAVA_HOME doesn't need the arch suffix at ENV time
    ln -sf /usr/lib/jvm/temurin-${JAVA_VERSION}-jdk-* /usr/lib/jvm/temurin-jdk

ENV JAVA_HOME=/usr/lib/jvm/temurin-jdk

# Android SDK command-line tools + platform-tools (adb)
# NOTE: platform-tools (adb) are x86_64-only on Linux. On arm64 hosts
# (Apple Silicon via OrbStack/Docker Desktop), we add amd64 multiarch libs
# so Rosetta/QEMU translation works transparently.
ARG ANDROID_CMDLINE_TOOLS_VERSION
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    DPKG_ARCH=$(dpkg --print-architecture) && \
    if [ "$DPKG_ARCH" = "arm64" ]; then \
        dpkg --add-architecture amd64 && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            libc6:amd64 libstdc++6:amd64 zlib1g:amd64; \
    fi && \
    mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" && \
    unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools && \
    mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest && \
    rm /tmp/cmdline-tools.zip && \
    yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 || true && \
    ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager \
        "platform-tools" \
        "platforms;android-36" \
        "build-tools;36.0.0" && \
    chmod -R a+rX ${ANDROID_HOME}

ENV PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}

# Swift is installed as a separate sidecar image (Dockerfile.swift)
# to keep the base image lean. Use `docker compose --profile swift up`
# when you need to build ~/vault/ccode/AEON/main/ Swift code.

# =============================================================================
# Stage 2: user — non-root dev user, sudo, sshd config
# =============================================================================
FROM system AS user

ARG USERNAME
ARG USER_UID
ARG USER_GID

RUN groupadd --gid ${USER_GID} ${USERNAME} && \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /usr/bin/zsh ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# Allow the dev user into the docker group so it can talk to the mounted socket.
# We create the group with a placeholder GID; entrypoint.sh re-aligns it at runtime
# to match the host socket's GID so permissions actually work.
RUN groupadd -g 999 docker || true && \
    usermod -aG docker ${USERNAME}

# sshd: key-only, no root, no password
RUN mkdir -p /var/run/sshd && \
    sed -i \
        -e 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' \
        -e 's/^#*PermitRootLogin.*/PermitRootLogin no/' \
        -e 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
        -e 's/^#*X11Forwarding.*/X11Forwarding no/' \
        /etc/ssh/sshd_config && \
    install -d -m 0700 -o ${USERNAME} -g ${USERNAME} /home/${USERNAME}/.ssh

# =============================================================================
# Stage 3: languages — Rust, mise (manages Node + Go), uv (Python)
# Installed as the dev user so PATHs are right and caches go in $HOME.
# =============================================================================
FROM user AS languages

ARG USERNAME
ARG RUST_CHANNEL
ARG NODE_VERSION
ARG GO_VERSION
ARG UV_VERSION
ARG MISE_VERSION

USER ${USERNAME}
WORKDIR /home/${USERNAME}
ENV HOME=/home/${USERNAME} \
    PATH=/home/${USERNAME}/.local/bin:/home/${USERNAME}/.cargo/bin:/home/${USERNAME}/.local/share/mise/shims:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${JAVA_HOME}/bin:${PATH} \
    ANDROID_HOME=${ANDROID_HOME} \
    ANDROID_SDK_ROOT=${ANDROID_HOME} \
    JAVA_HOME=${JAVA_HOME} \
    GRADLE_USER_HOME=/home/${USERNAME}/.gradle

# Rust (rustup, stable channel, minimal profile + clippy + rustfmt)
RUN --mount=type=cache,target=/home/${USERNAME}/.cache/rust,uid=1000,gid=1000 \
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain ${RUST_CHANNEL} && \
    . "$HOME/.cargo/env" && \
    rustup component add clippy rustfmt

# mise (asdf-compatible polyglot version manager, replaces nvm/gvm/etc.)
RUN curl -fsSL https://mise.run | MISE_VERSION=${MISE_VERSION} sh && \
    mise use --global node@${NODE_VERSION} go@${GO_VERSION} && \
    mise reshim

# uv (modern Python installer/resolver)
RUN curl -LsSf https://astral.sh/uv/${UV_VERSION}/install.sh | sh

# =============================================================================
# Stage 4: cli-tools — AI agents (npm), oh-my-zsh, tmux plugins
# =============================================================================
FROM languages AS cli-tools

ARG USERNAME

# AI coding agents — install via npm using mise's node
RUN --mount=type=cache,target=/home/${USERNAME}/.npm,uid=1000,gid=1000 \
    npm install -g \
        @anthropic-ai/claude-code \
        @openai/codex \
        @google/gemini-cli

# oh-my-zsh + plugins
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc && \
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
        ${ZSH_CUSTOM:-/home/${USERNAME}/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
        ${ZSH_CUSTOM:-/home/${USERNAME}/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    git clone --depth=1 https://github.com/Aloxaf/fzf-tab \
        ${ZSH_CUSTOM:-/home/${USERNAME}/.oh-my-zsh/custom}/plugins/fzf-tab

# tmux plugin manager + resurrect + continuum (for session persistence)
RUN git clone --depth=1 https://github.com/tmux-plugins/tpm \
        /home/${USERNAME}/.tmux/plugins/tpm && \
    git clone --depth=1 https://github.com/tmux-plugins/tmux-resurrect \
        /home/${USERNAME}/.tmux/plugins/tmux-resurrect && \
    git clone --depth=1 https://github.com/tmux-plugins/tmux-continuum \
        /home/${USERNAME}/.tmux/plugins/tmux-continuum

# =============================================================================
# Stage 5: final — entrypoint, dotfiles bootstrap happens at runtime
# =============================================================================
FROM cli-tools AS final

ARG USERNAME

# Copy starter dotfiles into a template location. The entrypoint script either
# applies these (no DOTFILES_REPO set) or clones the user's repo on first boot.
COPY --chown=${USERNAME}:${USERNAME} dotfiles-sample/ /home/${USERNAME}/.dotfiles-sample/

USER root
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    printf 'PATH=/home/%s/.local/bin:/home/%s/.cargo/bin:/home/%s/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' \
        "${USERNAME}" "${USERNAME}" "${USERNAME}" >> /etc/environment

# SSH listens on 22 inside the container; compose maps it to 2222 on the host
EXPOSE 22

WORKDIR /home/${USERNAME}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sshd-foreground"]
