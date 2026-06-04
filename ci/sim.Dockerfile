# Sim image: Verilator base with the build toolchain and Python sim
# dependencies (cocotb, pytest, numpy, ...) preinstalled so CI 'sim' jobs
# don't apt/pip install on every run.
FROM verilator/verilator:latest

# System build dependencies needed by cocotb and the standalone Verilator flow.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-dev make g++ bash \
    && rm -rf /var/lib/apt/lists/*

# Python simulation dependencies.
COPY requirements/sim.txt /tmp/sim.txt
RUN pip3 install --no-cache-dir --break-system-packages -r /tmp/sim.txt \
    && rm -f /tmp/sim.txt

# The verilator image sets verilator as the entrypoint; reset it so GitLab CI
# can run arbitrary shell commands.
ENTRYPOINT []
WORKDIR /workspace
