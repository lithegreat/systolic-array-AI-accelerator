# Sim image: Verilator base with the build toolchain and Python sim
# dependencies (cocotb, pytest, numpy, ...) preinstalled so CI 'sim' jobs
# don't apt/pip install on every run.
FROM verilator/verilator:latest

# System build dependencies needed by cocotb, the standalone Verilator flow, and formal verification.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-dev make g++ bash \
        yosys z3 git \
    && rm -rf /var/lib/apt/lists/*

# Install SymbiYosys (sby) from source
RUN git clone --depth 1 https://github.com/YosysHQ/sby.git /tmp/sby \
    && cd /tmp/sby \
    && make install PREFIX=/usr/local \
    && rm -rf /tmp/sby

# Python simulation dependencies.
COPY requirements/sim.txt /tmp/sim.txt
RUN pip3 install --no-cache-dir --break-system-packages -r /tmp/sim.txt \
    && rm -f /tmp/sim.txt

# The verilator image sets verilator as the entrypoint; reset it so GitLab CI
# can run arbitrary shell commands.
ENTRYPOINT []
WORKDIR /workspace
