FROM rustlang/rust:nightly AS builder

RUN cargo install cargo-fuzz

ADD . /src
RUN printf '[toolchain]\nchannel = "nightly"\n' > /src/rust-toolchain.toml

WORKDIR /src/rs/crypto/internal/crypto_lib/threshold_sig/tecdsa/fuzz

RUN cargo fuzz build fe && \
    cargo fuzz build scalar && \
    cargo fuzz build sqrt_ratio && \
    mv target/x86_64-unknown-linux-gnu/release/fe /fe && \
    mv target/x86_64-unknown-linux-gnu/release/scalar /scalar && \
    mv target/x86_64-unknown-linux-gnu/release/sqrt_ratio /sqrt_ratio

RUN export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    cargo build --release && \
    mv target/release/fe /fe_no_inst && \
    mv target/release/scalar /scalar_no_inst && \
    mv target/release/sqrt_ratio /sqrt_ratio_no_inst

FROM rustlang/rust:nightly
COPY --from=builder /fe /fe_no_inst /
COPY --from=builder /scalar /scalar_no_inst /
COPY --from=builder /sqrt_ratio /sqrt_ratio_no_inst /
