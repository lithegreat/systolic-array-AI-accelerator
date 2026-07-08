# Sim image: Verilator base with the build toolchain and Python sim
# dependencies (cocotb, pytest, numpy, ...) preinstalled so CI 'sim' jobs
# don't apt/pip install on every run.
FROM verilator/verilator:latest

# System build dependencies needed by cocotb, the standalone Verilator flow, and formal verification.
# NOTE: z3 is intentionally NOT installed here via apt. The distro z3 package
# in this base image hung/blew up memory on control_unit_formal's SMT2 model
# under the runner's tight 892MB RAM (job died mid-solve: "Unexpected EOF
# response from solver" after 5+ minutes stuck on step 0 -- see the pipeline
# trace linked from control_unit_formal's job history). The same model solves
# in well under a second locally with a modern z3 (4.16.0). Instead, a modern
# prebuilt z3 binary comes from the `z3-solver` PyPI wheel (requirements/sim.txt,
# installed below) -- it lands at /usr/local/bin/z3, ahead of apt's /usr/bin on
# PATH.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-dev make g++ bash \
        yosys git \
    && rm -rf /var/lib/apt/lists/*

# Install SymbiYosys (sby) from source
RUN git clone --depth 1 https://github.com/YosysHQ/sby.git /tmp/sby \
    && cd /tmp/sby \
    && make install PREFIX=/usr/local \
    && rm -rf /tmp/sby

# Python simulation dependencies (also provides the z3 CLI binary, see above).
COPY requirements/sim.txt /tmp/sim.txt
RUN pip3 install --no-cache-dir --break-system-packages -r /tmp/sim.txt \
    && rm -f /tmp/sim.txt
RUN z3 --version

# The verilator image sets verilator as the entrypoint; reset it so GitLab CI
# can run arbitrary shell commands.
ENTRYPOINT []
WORKDIR /workspace
