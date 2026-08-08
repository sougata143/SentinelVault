# syntax=docker/dockerfile:1

### ---- Dependencies ----
# Standardizing on a modern pre-configured base environment to support Edition 2024 crates (like zeroize_derive 1.5.0+)
FROM rust:1.85-slim-bookworm AS rust-env
WORKDIR /app
RUN rustup target add wasm32-unknown-unknown

### ---- Build ----
# Build the native Rust crypto core to WebAssembly, then compile the Flutter web application using the stable version to support your app SDK requirements
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app

# Exposing build arguments to pass production base URLs at compile time
ARG AUTH_BASE_URL=http://localhost:3001
ARG SYNC_BASE_URL=http://localhost:3002
ARG SECURITY_BASE_URL=http://localhost:3003
ARG SHARING_BASE_URL=http://localhost:3004

# Transfer Cargo and Rustup dependencies from the rust environment
COPY --from=rust-env /usr/local/cargo /usr/local/cargo
COPY --from=rust-env /usr/local/rustup /usr/local/rustup

# Set explicit Rustup and Cargo environment variables so the toolchain is auto-resolved
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH="/usr/local/cargo/bin:${PATH}"

# Build native WebAssembly crypto binaries
COPY ./native/crypto_core ./native/crypto_core
WORKDIR /app/native/crypto_core
RUN cargo build --release --locked --target wasm32-unknown-unknown --features wasm

# Pull in core libraries and frontend client application
WORKDIR /app
COPY ./core ./core
COPY ./app ./app

# Resolve Flutter packages and bundle production-ready Web assets
WORKDIR /app/app
RUN flutter pub get
RUN flutter build web --release \
  --dart-define=AUTH_BASE_URL=$AUTH_BASE_URL \
  --dart-define=SYNC_BASE_URL=$SYNC_BASE_URL \
  --dart-define=SECURITY_BASE_URL=$SECURITY_BASE_URL \
  --dart-define=SHARING_BASE_URL=$SHARING_BASE_URL

### ---- Production ----
# Serves the compiled static frontend client via Nginx matching backend security configurations
FROM nginx:1.25-alpine AS production
WORKDIR /usr/share/nginx/html

ENV FRONTEND_PORT=8080

# Configure a low-privilege system user to avoid running the server as root
RUN addgroup -S sentinel && adduser -S sentinel -G sentinel

# Adjust directory permissions to allow the unprivileged sentinel user to run Nginx
RUN mkdir -p /var/cache/nginx /var/log/nginx /etc/nginx/conf.d && \
  chown -R sentinel:sentinel /var/cache/nginx /var/log/nginx /etc/nginx /usr/share/nginx/html && \
  touch /var/run/nginx.pid && \
  chown sentinel:sentinel /var/run/nginx.pid

COPY ./nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/app/build/web ./

USER sentinel
EXPOSE 8080

# Consistent shell healthcheck utilizing wget (native on Alpine)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:${FRONTEND_PORT:-8080}/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
