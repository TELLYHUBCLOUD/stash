# Multi-stage Dockerfile for Stash

# Stage 1: Build Frontend UI
FROM node:24-alpine AS frontend
RUN apk add --no-cache make git
WORKDIR /stash

# Copy UI source and package files
COPY ./ui/v2.5/package.json ./ui/v2.5/pnpm-lock.yaml /stash/ui/v2.5/
COPY Makefile /stash/
COPY ./graphql /stash/graphql/
COPY ./ui /stash/ui/

# Install pnpm v10 (matching project's pnpm lockfile) and build UI
RUN npm install -g pnpm@10
RUN make pre-ui
RUN make generate-ui

ARG GITHASH="docker"
ARG STASH_VERSION="latest"
ARG BUILD_DATE=""
RUN if [ -z "$BUILD_DATE" ]; then BUILD_DATE=$(date +"%Y-%m-%d %H:%M:%S"); fi && \
    BUILD_DATE="$BUILD_DATE" make ui-only

# Stage 2: Build Backend Binary
FROM golang:1.25.9-alpine AS backend
RUN apk add --no-cache make alpine-sdk git
WORKDIR /stash

# Copy Go backend sources
COPY ./go* ./*.go Makefile gqlgen.yml .gqlgenc.yml /stash/
COPY ./graphql /stash/graphql/
COPY ./scripts /stash/scripts/
COPY ./pkg /stash/pkg/
COPY ./cmd /stash/cmd/
COPY ./internal /stash/internal/
COPY ./ui /stash/ui/

# Generate backend code and login locales
RUN make generate-backend generate-login-locale

# Copy built frontend assets from frontend stage
COPY --from=frontend /stash/ui/v2.5/build /stash/ui/v2.5/build

ARG GITHASH="docker"
ARG STASH_VERSION="latest"
ARG BUILD_DATE=""
RUN make flags-release flags-pie stash

# Stage 3: Final Production Image
FROM alpine:3.21

# Install runtime dependencies (FFmpeg, libvips, Python 3 for scrapers/plugins, etc.)
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    mailcap \
    vips \
    vips-tools \
    vips-heif \
    ffmpeg \
    python3 \
    py3-pip \
    py3-requests \
    py3-requests-toolbelt \
    py3-lxml \
    bash \
    curl \
    su-exec \
    && pip install --no-cache-dir --break-system-packages mechanicalsoup cloudscraper stashapp-tools

# Copy Stash binary from backend stage
COPY --from=backend /stash/stash /usr/bin/stash

# Copy entrypoint script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /usr/bin/stash /docker-entrypoint.sh

# Pre-create all required stash directories with full read/write permissions
RUN mkdir -p /root/.stash /data /metadata /cache /blobs /generated /config && \
    chmod -R 777 /root/.stash /data /metadata /cache /blobs /generated /config

# Default Environment Variables
ENV STASH_CONFIG_FILE=/root/.stash/config.yml \
    STASH_PORT=9999 \
    STASH_STASH=/data/ \
    STASH_GENERATED=/generated/ \
    STASH_METADATA=/metadata/ \
    STASH_CACHE=/cache/ \
    STASH_BLOBS=/blobs/

# Expose default port
EXPOSE 9999

# Volumes for persistent data
VOLUME ["/root/.stash", "/data", "/metadata", "/cache", "/blobs", "/generated"]

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -f http://127.0.0.1:${STASH_PORT:-9999}/healthz || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["stash"]
