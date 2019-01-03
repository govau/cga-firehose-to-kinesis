FROM golang:alpine AS builder

COPY . /go/src/github.com/govau/cga-firehose-to-kinesis

# If we don't disable CGO, the binary won't work in the scratch image. Unsure why?
RUN CGO_ENABLED=0 go install github.com/govau/cga-firehose-to-kinesis

FROM scratch

COPY --from=builder /go/bin/cga-firehose-to-kinesis /go/bin/cga-firehose-to-kinesis
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

ENTRYPOINT ["/go/bin/cga-firehose-to-kinesis"]
