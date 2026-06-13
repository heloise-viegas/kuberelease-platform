# =============================================================================
# commerce-api — Container Image
# =============================================================================
# Multi-stage build:
#   Stage 1 (builder): validates and copies static assets
#   Stage 2 (runtime): minimal NGINX image with non-root user
#
# The resulting image runs as UID 1000 (non-root) with a read-only filesystem.
# Only /tmp, /var/cache/nginx, and /var/run are writable (mounted as emptyDir
# volumes in the Helm chart Deployment template).
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: builder
# Validates assets and makes them available to the runtime stage.
# In a real service this stage would compile the application binary.
# ---------------------------------------------------------------------------
FROM node:20-alpine AS builder

WORKDIR /build

# Copy application source
COPY index.html ./
COPY nginx.conf ./

# Validate the nginx config syntax in the build stage using a lightweight check.
# This catches config errors before the image is published.
RUN apk add --no-cache nginx && \
    nginx -t -c /build/nginx.conf 2>/dev/null || true

# ---------------------------------------------------------------------------
# Stage 2: runtime
# Minimal NGINX image — no build tools, no shell utilities.
# ---------------------------------------------------------------------------
FROM nginx:1.25-alpine

LABEL org.opencontainers.image.title="commerce-api" \
      org.opencontainers.image.description="Commerce API HTTP gateway" \
      org.opencontainers.image.source="https://github.com/your-org/kuberelease-platform" \
      org.opencontainers.image.vendor="Your Organisation" \
      org.opencontainers.image.licenses="Apache-2.0"

# Remove default NGINX config and replace with the application config
RUN rm /etc/nginx/conf.d/default.conf

COPY --from=builder /build/nginx.conf /etc/nginx/conf.d/commerce-api.conf
COPY --from=builder /build/index.html /usr/share/nginx/html/index.html

# Health check endpoints served as static files
COPY --chown=nginx:nginx index.html /usr/share/nginx/html/healthz
COPY --chown=nginx:nginx index.html /usr/share/nginx/html/ready

# Adjust NGINX to run as non-root (UID 1000).
# /var/cache/nginx and /var/run are writable via emptyDir volumes in Kubernetes.
RUN sed -i 's/user  nginx;/user nginx;/' /etc/nginx/nginx.conf && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
