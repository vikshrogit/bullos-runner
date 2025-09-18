ARG BASE_IMAGE=ubuntu:latest
ARG RUNNER_VERSION=2.328.0
ARG IMAGE_VERSION=latest

FROM ${BASE_IMAGE} as base

ARG RUNNER_VERSION
ARG IMAGE_VERSION
ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_USER=runner \
    RUNNER_HOME=/home/runner \
    RUNNER_WORKDIR=_work \
    RUNNER_VERSION=${RUNNER_VERSION} \
    IMAGE_VERSION=${IMAGE_VERSION} \
    TZ=UTC

# Minimal packages + common build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    git \
    jq \
    unzip \
    tar \
    zip \
    sudo \
    build-essential \
    gcc \
    g++ \
    make \
    python3 \
    python3-venv \
    python3-pip \
    locales \
    procps \
    iproute2 \
    iputils-ping \
    less \
    xvfb \
    vim \
    net-tools \
    apt-utils && \
    rm -rf /var/lib/apt/lists/*

# Set locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Install Docker CLI (for workflows that need to control dockerd on host)
RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

# Install helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Terraform (latest stable)
RUN set -eux; \
    # Fetch latest stable Terraform release
    TF_VER=$(curl -sSL https://api.github.com/repos/hashicorp/terraform/releases/latest | jq -r '.tag_name'); \
    TF_VER="${TF_VER#v}"; \
    echo "Installing Terraform $TF_VER"; \
    # Map architecture
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in \
        amd64) ARCH="amd64";; \
        arm64) ARCH="arm64";; \
        *) echo "Unsupported architecture: $ARCH"; exit 1;; \
    esac; \
    # Download and unzip
    curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_linux_${ARCH}.zip" -o /tmp/terraform.zip; \
    unzip /tmp/terraform.zip -d /usr/local/bin; \
    rm /tmp/terraform.zip


# Install AWS CLI v2
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in \
        amd64) AWS_ARCH="x86_64";; \
        arm64) AWS_ARCH="aarch64";; \
        *) echo "Unsupported architecture: $ARCH"; exit 1;; \
    esac; \
    echo "Installing AWS CLI v2 for $AWS_ARCH"; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip; \
    unzip /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli; \
    rm -rf /tmp/aws /tmp/awscliv2.zip


# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Go (latest stable)
RUN set -eux; \
    # Get latest Go version
    GO_VER=$(curl -sSL https://go.dev/VERSION?m=text); \
    GO_VER_CLEAN=${GO_VER#go}; \
    echo "Installing Go $GO_VER_CLEAN"; \
    # Detect architecture
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in \
        amd64) GO_ARCH="amd64";; \
        arm64) GO_ARCH="arm64";; \
        *) echo "Unsupported architecture: $ARCH"; exit 1;; \
    esac; \
    # Download Go tarball
    curl -fsSL "https://dl.google.com/go/${GO_VER_CLEAN}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz; \
    tar -C /usr/local -xzf /tmp/go.tar.gz; \
    rm /tmp/go.tar.gz; \
    ln -s /usr/local/go/bin/go /usr/local/bin/go


# Install rust (rustup) and set default toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    . $HOME/.cargo/env || true

ENV PATH=/root/.cargo/bin:${PATH}

# Create non-root user and group
RUN groupadd --gid 1000 ${RUNNER_USER} && \
    useradd --uid 1000 --gid ${RUNNER_USER} --create-home --shell /bin/bash ${RUNNER_USER} && \
    mkdir -p ${RUNNER_HOME}/${RUNNER_WORKDIR} && \
    chown -R ${RUNNER_USER}:${RUNNER_USER} ${RUNNER_HOME} && \
    usermod -aG docker ${RUNNER_USER}

# Add tini for proper signal handling
RUN apt-get update && apt-get install -y --no-install-recommends tini && rm -rf /var/lib/apt/lists/*

# Copy entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose a working directory as a volume (so host can mount and keep caches across restarts)
VOLUME ["${RUNNER_HOME}/${RUNNER_WORKDIR}"]

# Image metadata
LABEL org.opencontainers.image.title="bullos-gh-runner" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.authors="VIKSHRO INDIA" \
      org.opencontainers.image.description="Secure GitHub Actions self-hosted runner with common devops toolchain"

USER ${RUNNER_USER}
WORKDIR ${RUNNER_HOME}
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["run"]