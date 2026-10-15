# Dev container image for the AWS labs of the cloud computing course.
# devcontainer.json adds Docker, kubectl, Helm, the GitHub CLI and the AWS
# CLI as dev container features on top of this image.
FROM mcr.microsoft.com/devcontainers/base:3-noble

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

# Versions of the tools that come from GitHub releases
ARG K3D_VERSION=v5.8.3
ARG PMTILES_VERSION=1.31.2
ARG TRIVY_VERSION=0.74.0
ARG TRIVY_SHA256_AMD64=2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a
ARG TRIVY_SHA256_ARM64=b94ce1976bbf3c15b514b605ee88be7c6d94a29be2302847ff01cb794d47aad5

# Ubuntu packages: Python 3.12, network diagnosis (T04), OpenStreetMap tools (T06),
# shell tools
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      python3 python3-pip gnupg \
      dnsutils iputils-ping netcat-openbsd tcpdump traceroute openssh-client openssl \
      osm2pgsql osmium-tool \
      jq zip unzip shellcheck \
 && rm --recursive --force /var/lib/apt/lists/*

# psql 18 (T06) from the package repository of PostgreSQL
# hadolint ignore=DL3008
RUN install --directory /usr/share/postgresql-common/pgdg \
 && curl --fail --silent --show-error --location --output /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc \
 && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc]" \
      "https://apt.postgresql.org/pub/repos/apt noble-pgdg main" >/etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install --yes --no-install-recommends postgresql-client-18 \
 && rm --recursive --force /var/lib/apt/lists/*

# OpenTofu from its Debian package repository
RUN curl --fail --silent --show-error --location --output /tmp/install-opentofu.sh https://get.opentofu.org/install-opentofu.sh \
 && sh /tmp/install-opentofu.sh --install-method deb \
 && rm --recursive --force /tmp/install-opentofu.sh /var/lib/apt/lists/*

# uv manages Python versions, virtual environments and packages
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /uvx /usr/local/bin/

# k3d runs a Kubernetes cluster in Docker; pmtiles cuts map tiles
RUN arch="$(dpkg --print-architecture)" \
 && curl --fail --silent --show-error --location --output /usr/local/bin/k3d \
      "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${arch}" \
 && chmod 755 /usr/local/bin/k3d \
 && if [ "$arch" = amd64 ]; then parch=x86_64; else parch="$arch"; fi \
 && curl --fail --silent --show-error --location "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_${parch}.tar.gz" \
    | tar --extract --gzip --directory /usr/local/bin pmtiles

# Trivy scans container images for vulnerabilities (T02). Pinned version with
# checksum: some releases and images were compromised in March 2026.
RUN case "$(dpkg --print-architecture)" in \
      amd64) tarch=64bit; sum="$TRIVY_SHA256_AMD64" ;; \
      arm64) tarch=ARM64; sum="$TRIVY_SHA256_ARM64" ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac \
 && curl --fail --silent --show-error --location --output /tmp/trivy.tar.gz \
      "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${tarch}.tar.gz" \
 && echo "$sum  /tmp/trivy.tar.gz" | sha256sum --check - \
 && tar --extract --gzip --file /tmp/trivy.tar.gz --directory /usr/local/bin trivy \
 && rm /tmp/trivy.tar.gz

# Mount points for the AWS login and the SSH keys of WSL (see devcontainer.json),
# owned by the container user, so that Docker does not create them as root
RUN install --directory --owner vscode --group vscode /home/vscode/.aws /home/vscode/.ssh /home/vscode/.config
