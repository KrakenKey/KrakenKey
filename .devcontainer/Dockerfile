FROM mcr.microsoft.com/devcontainers/typescript-node:24-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-pip python3-venv python3-distutils \
    && rm -rf /var/lib/apt/lists/*

# ── Pre-built binaries (architecture-aware) ──────────────────────────────────
ARG GITLEAKS_VERSION=8.22.1
ARG HADOLINT_VERSION=2.12.0

# gitleaks: map arch → release suffix (x86_64→x64, aarch64→arm64)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in x86_64|amd64) GL_ARCH="x64" ;; aarch64|arm64) GL_ARCH="arm64" ;; *) exit 1 ;; esac && \
    curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" \
      | tar xz -C /usr/local/bin gitleaks

# hadolint: map arch → release suffix (x86_64→x86_64, aarch64→arm64)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in x86_64|amd64) HL_ARCH="x86_64" ;; aarch64|arm64) HL_ARCH="arm64" ;; *) exit 1 ;; esac && \
    curl -sSfL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${HL_ARCH}" \
      -o /usr/local/bin/hadolint && \
    chmod +x /usr/local/bin/hadolint
