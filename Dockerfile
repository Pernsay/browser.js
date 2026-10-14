FROM node:22-bookworm

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV PNPM_HOME=/root/.local/share/pnpm
ENV CARGO_HOME=/root/.cargo
ENV RUSTUP_HOME=/root/.rustup
ENV PATH=/root/.local/share/pnpm:/root/.cargo/bin:$PATH

# Scramjet's build script calls `cargo +nightly`.
# Pin nightly so it does not silently select a broken/current nightly.
ENV RUSTUP_TOOLCHAIN=nightly
ENV RUSTUP_AUTO_INSTALL=0
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    git \
    pkg-config \
    libssl-dev \
    binaryen \
    && rm -rf /var/lib/apt/lists/*

# Install Rust stable plus the exact nightly toolchain Scramjet needs.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain stable

RUN rustup toolchain install nightly \
    --profile minimal \
    --component rust-src \
    --target wasm32-unknown-unknown

# Scramjet checks for exactly this wasm-bindgen CLI version.
RUN cargo install wasm-bindgen-cli \
    --version 0.2.105 \
    --locked

# Scramjet requires this fork, not the original wasm-snip package.
RUN cargo install wasm-snip \
    --git https://github.com/r58playz/wasm-snip \
    --locked

# Use the pnpm version expected by Browser.js.
RUN corepack enable
RUN corepack prepare pnpm@10.12.1 --activate

WORKDIR /app

# Render has already checked out/synchronised the Git submodule.
COPY . .

# Install workspace dependencies and allow native dependency setup scripts.
RUN pnpm config set enable-pre-post-scripts true
RUN pnpm install --frozen-lockfile

# Build Scramjet's WebAssembly rewriter first.
RUN cd packages/scramjet/packages/core && pnpm rewriter:build

# Build Browser.js.
RUN pnpm build

# Render sends web traffic to the port in $PORT.
EXPOSE 10000

# Browser.js's existing dev server is the repository's documented server.
CMD ["pnpm", "dev"]
