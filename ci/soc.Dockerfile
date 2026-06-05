# Full-SoC sim image: extends the sim image with the prebaked Didactic-SoC
# dependency checkouts (.bender) and vendored IPs (vendor_ips), plus colorama.
#
# These dependencies are normally fetched by `bender update && bender vendor
# init`, which needs network + the bender binary. The full-SoC Verilator job
# only *reads* the checkout files (it never invokes bender), so we bake a
# prebuilt snapshot in here. This keeps the constrained group5-runner host off
# the network per pipeline and avoids installing bender on it.
#
# The snapshot tarball (soc-deps.tar.gz) is produced from a working tree that
# has already run repository_init:
#   cd Didactic-SoC && tar czf soc-deps.tar.gz .bender vendor_ips
#
# Build on the runner (the build context must contain ci/soc-deps.tar.gz):
#   docker build -f ci/soc.Dockerfile -t group5-ci-soc:latest .
#
# Rebuild this image whenever Didactic-SoC/Bender.yml or the vendored IP
# revisions change (i.e. when the .bender checkout hashes referenced by
# verification/verilator/verilate.py MANUAL_FILES change).
FROM group5-ci-sim:latest

# colorama is imported by the SoC verilate runner scripts.
RUN pip3 install --no-cache-dir --break-system-packages colorama

# Prebaked SoC dependency snapshot (.bender checkouts + vendored IPs). The CI
# job copies these into the checked-out Didactic-SoC working tree before the
# Verilator build (verilate.py reads them via repo-relative paths).
COPY ci/soc-deps.tar.gz /tmp/soc-deps.tar.gz
RUN mkdir -p /opt/soc-deps \
    && tar xzf /tmp/soc-deps.tar.gz -C /opt/soc-deps \
    && rm -f /tmp/soc-deps.tar.gz
