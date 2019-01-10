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
---
kind: Service
apiVersion: v1
metadata:
  name: ${ENV}cld-firehose-to-kinesis
  labels:
    monitor: me
spec:
  selector:
    app: ${ENV}cld-firehose-to-kinesis
  ports:
  - name: web
    port: 8080
EOF

cat deployment.yaml

echo $KUBECONFIG > k
export KUBECONFIG=k

kubectl apply --record -f - < deployment.yaml
kubectl rollout status deployment.apps/${ENV}cld-firehose-to-kinesis
