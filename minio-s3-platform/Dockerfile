# MinIO S3 Platform - Multi-Stage Build from Source
# ==================================================
# This Dockerfile builds MinIO from the official source repository.
# It does NOT use the archived minio/minio Docker Hub image.
#
# Build modes:
#   OPTION A (default): Build from official MinIO source
#   OPTION B: Use Docker Hardened Image (dhi.io/minio) - see docker-compose.dhi.yml
#   OPTION C: Legacy minio/minio - NOT recommended, see docker-compose.legacy.yml
#
# Pinned Version: RELEASE.2024-10-02T17-50-41Z
# Source: https://github.com/minio/minio
# Commit: Tagged release for reproducibility

# ==================================================
# Stage 1: Build Stage
# ==================================================
FROM golang:1.22-alpine AS builder

# Build arguments for version pinning
ARG MINIO_VERSION=RELEASE.2024-10-02T17-50-41Z
ARG MINIO_REPO=https://github.com/minio/minio.git

# Install build dependencies
RUN apk add --no-cache \
    git \
    make \
    bash \
    ca-certificates \
    tzdata

# Create non-root build user
RUN adduser -D -u 1000 builder
WORKDIR /build

# Clone MinIO source at pinned version
RUN git clone --depth 1 --branch ${MINIO_VERSION} ${MINIO_REPO} .

# Build MinIO binary
# CGO_ENABLED=0 for static binary, fully portable
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath \
    -ldflags="-s -w -X github.com/minio/minio/cmd.Version=${MINIO_VERSION} -X github.com/minio/minio/cmd.ReleaseTag=${MINIO_VERSION}" \
    -o /build/minio ./

# Verify binary was built
RUN /build/minio --version

# ==================================================
# Stage 2: Runtime Stage
# ==================================================
FROM alpine:3.20 AS runtime

# OCI Image Labels
LABEL org.opencontainers.image.title="MinIO S3 Platform" \
      org.opencontainers.image.description="Production MinIO built from source" \
      org.opencontainers.image.version="RELEASE.2024-10-02T17-50-41Z" \
      org.opencontainers.image.source="https://github.com/minio/minio" \
      org.opencontainers.image.vendor="Self-Built" \
      org.opencontainers.image.licenses="AGPL-3.0"

# Install runtime dependencies only
RUN apk add --no-cache \
    ca-certificates \
    curl \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create minio user and group (non-root)
RUN addgroup -g 1000 minio && \
    adduser -D -u 1000 -G minio -h /home/minio minio

# Create data directory with correct permissions
RUN mkdir -p /data && chown -R minio:minio /data

# Copy MinIO binary from builder
COPY --from=builder /build/minio /usr/local/bin/minio

# Ensure binary is executable
RUN chmod +x /usr/local/bin/minio

# Switch to non-root user
USER minio

# Expose S3 API and Console ports
EXPOSE 9000 9001

# Data volume mount point
VOLUME ["/data"]

# Health check using MinIO's live endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:9000/minio/health/live || exit 1

# Default entrypoint
ENTRYPOINT ["minio"]

# Default command - can be overridden in docker-compose
CMD ["server", "/data", "--console-address", ":9001"]
