# Check image: lightweight Python environment with the convention/format
# tooling preinstalled so CI 'check' jobs don't pip install on every run.
FROM python:3.13-slim

# Install Python check dependencies (ruff, pre_commit) once at build time.
COPY requirements/check.txt /tmp/check.txt
RUN pip install --no-cache-dir -r /tmp/check.txt \
    && rm -f /tmp/check.txt

WORKDIR /workspace
