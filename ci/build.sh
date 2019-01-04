#!/bin/bash

set -eu
set -o pipefail

# Tag is not alway populated correctly by the docker-image resource (ie it defaults to latest)
# so use the actual source for tag
TAG=$(cat src/.git/ref)
REPO=$(cat img/repository)

cat <<EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${ENV}cld-firehose-to-kinesis
spec:
  selector:
    matchLabels:
      app: ${ENV}cld-firehose-to-kinesis
  replicas: 2
  template:
    metadata:
      labels:
        app: ${ENV}cld-firehose-to-kinesis
    spec:
      containers:
      - name: ${ENV}cld-firehose-to-kinesis
        image: ${REPO}:${TAG}
        resources: {limits: {memory: "64Mi", cpu: "100m"}}
        envFrom:
        - secretRef: {name: ${ENV}cld-firehose-to-kinesis}
        - secretRef: {name: shared-firehose-to-kinesis}
EOF

cat deployment.yaml

mkdir -p $HOME/.ssh
cat <<EOF >> $HOME/.ssh/known_hosts
@cert-authority *.cld.gov.au $(cat ops.git/terraform/sshca-ca.pub)
EOF
echo "${JUMPBOX_SSH_KEY}" > $HOME/.ssh/key.pem
chmod 600 $HOME/.ssh/key.pem
ssh -i $HOME/.ssh/key.pem -p 32213 ec2-user@bosh-jumpbox.l.cld.gov.au kubectl apply --record -f - < deployment.yaml
ssh -i $HOME/.ssh/key.pem -p 32213 ec2-user@bosh-jumpbox.l.cld.gov.au kubectl rollout status deployment.apps/${ENV}cld-firehose-to-kinesis
