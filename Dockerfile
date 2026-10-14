FROM node:22-bookworm

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV PNPM_HOME=/root/.local/share/pnpm
ENV CARGO_HOME=/root/.cargo
ENV RUSTUP_HOME=/root/.rustup
ENV PATH=/root/.local/share/pnpm:/root/.cargo/bin:$PATH

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

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain stable

RUN rustup toolchain install nightly \
    --profile minimal \
    --component rust-src \
    --target wasm32-unknown-unknown

RUN cargo install wasm-bindgen-cli \
    --version 0.2.105 \
    --locked

RUN cargo +stable install wasm-snip \
    --git https://github.com/r58playz/wasm-snip \
    --locked

RUN corepack enable
RUN corepack prepare pnpm@10.12.1 --activate

WORKDIR /app

COPY . .

# Docker/Render normally excludes .git. Provide the metadata expected by devserver.ts.
RUN git init \
    && git config user.email "build@localhost" \
    && git config user.name "Docker Build" \
    && git add -A \
    && git commit -m "Docker build snapshot" \
    && git rev-parse --short HEAD

RUN pnpm config set enable-pre-post-scripts true
RUN pnpm install --frozen-lockfile

RUN cd packages/scramjet/packages/core && pnpm rewriter:build

RUN pnpm build

ENV HOST=0.0.0.0
ENV PORT=10000

EXPOSE 10000

CMD ["pnpm", "dev"]
