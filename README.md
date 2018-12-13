# Firehose to Kinesis

Read from CloudFoundry firehose and write to Kinesis data stream.

Can be deployed as CloudFoundry app.

Exposes Prometheus metrics.

## Run

```bash
# Client needs authority: doppler.firehose
# IAM user needs permission to put records to Kinesis data stream
cf create-user-provided-service kinesis-ups -p @<(cat <<EOF
{
  "CF_URL": "https://api.system.example.com",
  "CF_CLIENT_SECRET": "xxx",
  "CF_CLIENT_ID": "xxx",
  "CF_SUBSCRIPTION_ID": "xxx",
  "AWS_REGION": "ap-southeast-2",
  "AWS_ACCESS_KEY_ID": "xxx",
  "AWS_SECRET_ACCESS_KEY": "xxx",
  "AWS_KINESIS_DATA_STREAM": "xxx",
  "AWS_PARTITIONS": "100"
}
EOF
)

go build .
cf push
curl https://kinesis.apps.example.com/metrics
```
