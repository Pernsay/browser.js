FROM node:22-bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV PNPM_HOME=/root/.local/share/pnpm
ENV PATH=/root/.local/share/pnpm:/root/.cargo/bin:$PATH

RUN apt-get update && apt-get install -y \
    bash \
    build-essential \
    curl \
    git \
    pkg-config \
    libssl-dev \
    binaryen \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal

RUN rustup target add wasm32-unknown-unknown
RUN cargo install wasm-bindgen-cli --locked
RUN cargo install wasm-snip --git https://github.com/r58playz/wasm-snip --locked

RUN corepack enable
RUN corepack prepare pnpm@9.15.5 --activate

WORKDIR /app

COPY . .

RUN pnpm install --frozen-lockfile
RUN cd packages/scramjet/packages/core && pnpm rewriter:build
RUN pnpm build

EXPOSE 10000

CMD ["pnpm", "dev"]
