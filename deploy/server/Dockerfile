FROM rust:1-bookworm AS builder

WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
RUN cargo build --locked --release --package echoclip_server

FROM debian:bookworm-slim

RUN groupadd --system --gid 10001 echoclip \
    && useradd --system --uid 10001 --gid echoclip --home-dir /var/lib/echoclip --shell /usr/sbin/nologin echoclip \
    && install -d -o echoclip -g echoclip /etc/echoclip /var/lib/echoclip /var/lib/echoclip-secrets

COPY --from=builder /src/target/release/echoclip /usr/local/bin/echoclip
RUN chmod 0755 /usr/local/bin/echoclip

USER echoclip:echoclip
VOLUME ["/var/lib/echoclip", "/var/lib/echoclip-secrets"]
ENTRYPOINT ["/usr/local/bin/echoclip", "serve", "--config", "/etc/echoclip/server.toml"]
