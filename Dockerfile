# ==========================================
# Build Stage
# ==========================================
FROM docker.io/rocm/dev-ubuntu-24.04:7.2.4 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install math libraries and standard tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    git \
    libcurl4-openssl-dev \
    libomp-dev \
    libnuma-dev \
    hipblas-dev \
    rocblas-dev \
    && rm -rf /var/lib/apt/lists/*

ENV ROCM_PATH=/opt/rocm \
    HIP_PATH=/opt/rocm \
    PATH=/opt/rocm/bin:/opt/rocm/llvm/bin:$PATH

WORKDIR /opt/llama.cpp

# Clone the official upstream stable llama.cpp repository
RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp.git . \
    && git submodule update --init --recursive

# Compile clean and native for Strix Halo (gfx1151)
RUN cmake -S . -B build -G Ninja \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS=gfx1151 \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_HIP_UMA=ON \
    && cmake --build build --config Release \
    && cmake --install build --config Release


# ==========================================
# Runtime Stage (Clean, lightweight Ubuntu)
# ==========================================
FROM docker.io/ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install bare essentials + repository setup tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    libgomp1 \
    libnuma1 \
    sudo \
    procps \
    wget \
    gpg \
    && rm -rf /var/lib/apt/lists/*

# 2. Add the AMD ROCm repo so this stage can pull the runtime math libs
RUN wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2.4 noble main" | tee /etc/apt/sources.list.d/rocm.list

# 3. CRITICAL: Install ONLY the compiled runtime libraries (No heavy compiler tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
    hip-runtime-amd \
    hipblas \
    rocblas \
    && rm -rf /var/lib/apt/lists/*

# 4. Set up hardware groups for Strix Halo access
RUN groupadd -g 44 video || true \
    && groupadd -g 109 render || true

# 5. Bring over our custom compiled llama binaries
ENV PATH=/usr/local/bin:$PATH
COPY --from=builder /usr/local/ /usr/local/

# 6. Bind shared library paths so the system finds them instantly
RUN echo "/opt/rocm/lib" > /etc/ld.so.conf.d/rocm.conf \
    && echo "/opt/rocm/lib64" >> /etc/ld.so.conf.d/rocm.conf \
    && echo "/usr/local/lib"  >> /etc/ld.so.conf.d/local.conf \
    && echo "/usr/local/lib64" >> /etc/ld.so.conf.d/local.conf \
    && ldconfig

# Runtime Environment fallback declarations
ENV HOST=0.0.0.0 \
    PORT=8080 \
    CONTEXT_LENGTH=2048 \
    TEMPERATURE=0.7 \
    NGL=99 \
    FA=1 \
    MODEL_PATH=/models/model.gguf

CMD ["/bin/bash", "-c", "llama-server --host $HOST --port $PORT -c $CONTEXT_LENGTH --temp $TEMPERATURE --jinja --no-mmap -ngl $NGL -fa $FA -m $MODEL_PATH"]