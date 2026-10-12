# Dev container image for the AWS labs of the cloud computing course.
# devcontainer.json adds Docker, kubectl, Helm, the GitHub CLI and the AWS
# CLI as dev container features on top of this image.
FROM mcr.microsoft.com/devcontainers/base:3-noble

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

# Versions of the tools that come from GitHub releases
ARG K3D_VERSION=v5.8.3
ARG PMTILES_VERSION=1.31.2

# Ubuntu packages: Python 3.12, network diagnosis (T04), OpenStreetMap tools (T06),
# shell tools
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-pip gnupg \
      dnsutils iputils-ping netcat-openbsd tcpdump traceroute openssh-client openssl \
      osm2pgsql osmium-tool \
      jq zip unzip shellcheck \
 && rm -rf /var/lib/apt/lists/*

# psql 18 (T06) from the package repository of PostgreSQL
# hadolint ignore=DL3008
RUN install -d /usr/share/postgresql-common/pgdg \
 && curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc \
 && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc]" \
      "https://apt.postgresql.org/pub/repos/apt noble-pgdg main" >/etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends postgresql-client-18 \
 && rm -rf /var/lib/apt/lists/*

# OpenTofu from its Debian package repository
RUN curl -fsSL -o /tmp/install-opentofu.sh https://get.opentofu.org/install-opentofu.sh \
 && sh /tmp/install-opentofu.sh --install-method deb \
 && rm -rf /tmp/install-opentofu.sh /var/lib/apt/lists/*

# uv manages Python versions, virtual environments and packages
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /uvx /usr/local/bin/

# k3d runs a Kubernetes cluster in Docker; pmtiles cuts map tiles
RUN arch="$(dpkg --print-architecture)" \
 && curl -fsSL -o /usr/local/bin/k3d \
      "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${arch}" \
 && chmod 755 /usr/local/bin/k3d \
 && if [ "$arch" = amd64 ]; then parch=x86_64; else parch="$arch"; fi \
 && curl -fsSL "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_${parch}.tar.gz" \
    | tar -xz -C /usr/local/bin pmtiles

# Mount points for the AWS login and the SSH keys of WSL (see devcontainer.json),
# owned by the container user, so that Docker does not create them as root
RUN install -d -o vscode -g vscode /home/vscode/.aws /home/vscode/.ssh /home/vscode/.config
