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
cp  "${ORIG_PWD}/manifest.yml" \
    "${ORIG_PWD}/Procfile" \
    "${ORIG_PWD}/build"

printf "\ndomain: $DOMAIN\n" >> ${ORIG_PWD}/build/manifest.yml

cp "${GOPATH}/bin/cga-firehose-to-kinesis" \
   "${ORIG_PWD}/build/cga-firehose-to-kinesis"

echo "Files in build:"
ls -l "${ORIG_PWD}/build"
