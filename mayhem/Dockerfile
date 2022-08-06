# Build Stage
FROM ghcr.io/evanrichter/cargo-fuzz:latest as builder

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN echo building instrumented harnesses && \
    bash -c "pushd rs/crypto/internal/crypto_lib/threshold_sig/tecdsa/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    mv rs/crypto/internal/crypto_lib/threshold_sig/tecdsa/fuzz/target/x86_64-unknown-linux-gnu/release/fe /fe && \
    mv rs/crypto/internal/crypto_lib/threshold_sig/tecdsa/fuzz/target/x86_64-unknown-linux-gnu/release/scalar /scalar && \
    mv rs/crypto/internal/crypto_lib/threshold_sig/tecdsa/fuzz/target/x86_64-unknown-linux-gnu/release/sqrt_ratio /sqrt_ratio && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd rs/crypto/internal/crypto_lib/threshold_sig/tecdsa/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    mv rs/crypto/internal/crypto_lib/threshold_sig/tecdsa/fuzz/target/release/fe /fe_no_inst && \
    mv rs/crypto/internal/crypto_lib/threshold_sig/tecdsa/fuzz/target/release/scalar /scalar_no_inst && \
    mv rs/crypto/internal/crypto_lib/threshold_sig/tecdsa/fuzz/target/release/sqrt_ratio /sqrt_ratio_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /fe /fe_no_inst /
COPY --from=builder /scalar /scalar_no_inst /
COPY --from=builder /sqrt_ratio /sqrt_ratio_no_inst /
