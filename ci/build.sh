#!/bin/bash

set -eu
set -o pipefail

# Tag is not always populated correctly by the docker-image resource (ie it defaults to latest)
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
        env:
        - name: SYSTEM
          value: ${ENV}.cld.gov.au
        ports:
        - name: http
          containerPort: 8080 # /metrics
EOF

cat deployment.yaml

mkdir -p $HOME/.ssh
cat <<EOF >> $HOME/.ssh/known_hosts
@cert-authority *.cld.gov.au $(cat ca/terraform/sshca-ca.pub)
EOF
echo "${JUMPBOX_SSH_KEY}" > $HOME/.ssh/key.pem
chmod 600 $HOME/.ssh/key.pem
ssh -i $HOME/.ssh/key.pem -p "${JUMPBOX_SSH_PORT}" ec2-user@${JUMPBOX_SSH_L_HOST} kubectl apply --record -f - < deployment.yaml
ssh -i $HOME/.ssh/key.pem -p "${JUMPBOX_SSH_PORT}" ec2-user@${JUMPBOX_SSH_L_HOST} kubectl rollout status deployment.apps/${ENV}cld-firehose-to-kinesis
