# Eikon backend image: the SSH/rsync client tools used by scripts/ci_eikon_backend.sh,
# so the asic_* jobs don't `apk add` them on every run. Build on the runner host:
#   docker build -f ci/eikon.Dockerfile -t group5-ci-eikon:latest .
# then set the CI/CD variable EIKON_IMAGE=group5-ci-eikon:latest (the runner uses
# pull_policy = ["if-not-present"], like the other group5-ci-* images).
FROM alpine:3.19

RUN apk add --no-cache bash openssh-client rsync

WORKDIR /workspace
