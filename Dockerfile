ARG BASE_IMAGE=ubuntu:latest
ARG RUNNER_VERSION=2.328.0
ARG IMAGE_VERSION=latest


FROM ${BASE_IMAGE} AS base

ARG RUNNER_VERSION
ARG IMAGE_VERSION
ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_USER=runner \
    RUNNER_HOME=/home/runner \
    RUNNER_WORKDIR=_work \
    RUNNER_VERSION=${RUNNER_VERSION} \
    IMAGE_VERSION=${IMAGE_VERSION} \
    TZ=UTC

# ------------------------------
# Base system + tools
# ------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release apt-transport-https \
    software-properties-common git jq unzip tar zip sudo build-essential \
    gcc g++ make python3 python3-venv python3-pip locales procps iproute2 \
    iputils-ping less xvfb vim net-tools apt-utils dnsutils tini \
    && rm -rf /var/lib/apt/lists/*

# Locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# ------------------------------
# Extra DevOps tools
# ------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends docker.io && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Terraform
RUN set -eux; \
    TF_VER=$(curl -sSL https://api.github.com/repos/hashicorp/terraform/releases/latest | jq -r '.tag_name'); \
    TF_VER="${TF_VER#v}"; \
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in amd64) ARCH="amd64";; arm64) ARCH="arm64";; *) exit 1;; esac; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_linux_${ARCH}.zip" -o /tmp/terraform.zip; \
    unzip /tmp/terraform.zip -d /usr/local/bin; rm /tmp/terraform.zip

# AWS CLI
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in amd64) AWS_ARCH="x86_64";; arm64) AWS_ARCH="aarch64";; *) exit 1;; esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip; \
    unzip /tmp/awscliv2.zip -d /tmp; /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli; \
    rm -rf /tmp/aws /tmp/awscliv2.zip

# Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Go
RUN set -eux; \
    GO_VER=$(curl -sSL https://go.dev/VERSION?m=text | grep -oP '^go\d+\.\d+(\.\d+)?'); \
    GO_VER_CLEAN=${GO_VER#go}; \
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in amd64) GO_ARCH="amd64";; arm64) GO_ARCH="arm64";; *) exit 1;; esac; \
    curl -fsSL "https://go.dev/dl/go${GO_VER_CLEAN}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz; \
    tar -C /usr/local -xzf /tmp/go.tar.gz; rm /tmp/go.tar.gz; \
    ln -s /usr/local/go/bin/go /usr/local/bin/go

# Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH=/root/.cargo/bin:${PATH}

# ------------------------------
# Monitoring + Health
# ------------------------------
# Prometheus node-exporter
# Node Exporter
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in amd64) NE_ARCH="amd64";; arm64) NE_ARCH="arm64";; *) exit 1;; esac; \
    NE_VER=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | jq -r .tag_name); \
    curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/${NE_VER}/node_exporter-${NE_VER#v}.linux-${NE_ARCH}.tar.gz" -o /tmp/node_exporter.tar.gz; \
    mkdir -p /usr/local/bin/node_exporter; \
    tar -xzf /tmp/node_exporter.tar.gz --strip-components=1 -C /usr/local/bin/node_exporter; \
    rm -f /tmp/node_exporter.tar.gz
EXPOSE 9100

# OpenTelemetry Collector (optional tracing)
# OpenTelemetry Collector (auto latest, multi-arch)
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in \
        amd64) OTEL_ARCH="amd64";; \
        arm64) OTEL_ARCH="arm64";; \
        *) echo "Unsupported architecture: $ARCH"; exit 1;; \
    esac; \
    OTEL_VER=$(curl -s https://api.github.com/repos/open-telemetry/opentelemetry-collector-releases/releases/latest | jq -r .tag_name); \
    OTEL_VER_NO_V="${OTEL_VER#v}"; \
    curl -fsSL "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/${OTEL_VER}/otelcol-contrib_${OTEL_VER#v}_linux_${OTEL_ARCH}.tar.gz" -o /tmp/otelcol.tar.gz; \
    mkdir -p /usr/local/bin/otelcol; \
    tar -xzf /tmp/otelcol.tar.gz -C /usr/local/bin/otelcol; \
    rm -f /tmp/otelcol.tar.gz

# OpenTelemetry config
COPY configs/otelcol/config.yaml  /etc/otelcol/config.yaml
EXPOSE 4317 4318

# Healthcheck script
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh
HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD /usr/local/bin/healthcheck.sh

# ------------------------------
# Runner user + entrypoint
# ------------------------------
RUN set -eux; \
    # If the user exists, skip; else create with first available UID/GID >= 1000
    if ! id -u "${RUNNER_USER}" >/dev/null 2>&1; then \
        # Find available UID and GID starting at 1000
        UID=$(awk -F: 'BEGIN{uid=1000} {if($3>=uid){uid=$3+1}} END{print uid}' /etc/passwd); \
        GID=$(awk -F: 'BEGIN{gid=1000} {if($3>=gid){gid=$3+1}} END{print gid}' /etc/group); \
        groupadd -g "$GID" "${RUNNER_USER}"; \
        useradd --uid "$UID" --gid "$GID" --create-home --shell /bin/bash "${RUNNER_USER}"; \
    fi; \
    # Create workdir and set ownership
    mkdir -p "${RUNNER_HOME}/${RUNNER_WORKDIR}"; \
    chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"; \
    # Add to docker group if exists
    if getent group docker >/dev/null; then \
        usermod -aG docker "${RUNNER_USER}"; \
    fi; \
    # ✅ Allow passwordless sudo
    echo "${RUNNER_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${RUNNER_USER}; \
    chmod 0440 /etc/sudoers.d/${RUNNER_USER}

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["${RUNNER_HOME}/${RUNNER_WORKDIR}"]

LABEL org.opencontainers.image.title="bullos-gh-runner" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.authors="VIKSHRO" \
      org.opencontainers.image.description="Secure GitHub Actions self-hosted runner with metrics, tracing, healthcheck, autoscaling-ready"

USER ${RUNNER_USER}
WORKDIR ${RUNNER_HOME}

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["run"]
