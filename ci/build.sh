#!/bin/bash

set -eu
set -x
set -o pipefail

ORIG_PWD="${PWD}"

# Create our own GOPATH
export GOPATH="${ORIG_PWD}/go"

# Symlink our source dir from inside of our own GOPATH
mkdir -p "${GOPATH}/src/github.com/govau"
ln -s "${ORIG_PWD}/src" "${GOPATH}/src/github.com/govau/cga-firehose-to-kinesis"

# Build it
go install github.com/govau/cga-firehose-to-kinesis

# Copy artefacts to output directory
cp "${ORIG_PWD}/src/Procfile" \
   "${ORIG_PWD}/build"

for ENV in a b;
do
    cat <<EOF > ${ORIG_PWD}/build/manifest-${ENV}.yml
applications:
- name: kinesis-${ENV}
  buildpack: binary_buildpack
  memory: 64MB
  disk_quota: 64MB
  services:
  - kinesis-ups
  instances: 1
  env:
    UPS_NAME: kinesis-ups
    SYSTEM: ${DOMAIN}
  domain: ${DOMAIN}
EOF
done

cp "${GOPATH}/bin/cga-firehose-to-kinesis" \
   "${ORIG_PWD}/build/cga-firehose-to-kinesis"

echo "Files in build:"
ls -l "${ORIG_PWD}/build"
