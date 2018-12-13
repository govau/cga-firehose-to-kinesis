package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"time"

	"github.com/cloudfoundry/noaa/consumer"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/sendgridlabs/go-kinesis"
	"github.com/sendgridlabs/go-kinesis/batchproducer"

	"github.com/cloudfoundry-community/go-cfenv"
	"github.com/govau/cf-common/env"
)

type config struct {
	CFURL            string
	CFClientID       string
	CFClientSecret   string
	CFSubscriptionID string
	CFPort           string
	CFInstanceID     string

	AWSStreamName   string
	AWSRegion       string
	AWSPartitions   string
	AWSAccessKey    string
	AWSAccessSecret string

	api *apiResp
}

type apiResp struct {
	Links struct {
		UAA struct {
			URL string `json:"href"`
		} `json:"uaa"`
		Logging struct {
			URL string `json:"href"`
		} `json:"logging"`
	} `json:"links"`
}

func fetchAPIResp(url string) (*apiResp, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, errors.New("bad status code from CF")
	}
	var serverConf apiResp
	err = json.NewDecoder(resp.Body).Decode(&serverConf)
	if err != nil {
		return nil, err
	}
	return &serverConf, nil
}

func (c *config) RefreshAuthToken() (string, error) {
	log.Println("refreshing access token...")
	resp, err := http.Post(c.api.Links.UAA.URL+"/oauth/token", "application/x-www-form-urlencoded", bytes.NewReader([]byte((url.Values{
		"client_id":     []string{c.CFClientID},
		"client_secret": []string{c.CFClientSecret},
		"grant_type":    []string{"client_credentials"},
	}).Encode())))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", errors.New("bad status code")
	}
	var og struct {
		AccessToken string `json:"access_token"`
	}
	err = json.NewDecoder(resp.Body).Decode(&og)
	if err != nil {
		return "", err
	}
	return og.AccessToken, nil
}

var (
	bufferSize = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "firehose_to_kinesis_buffer_size",
	}, []string{"instance"})
	errorCount = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "firehose_to_kinesis_errors_count",
	}, []string{"instance"})
	successCount = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "firehose_to_kinesis_sent_count",
	}, []string{"instance"})
	droppedCount = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "firehose_to_kinesis_dropped_count",
	}, []string{"instance"})
)

func init() {
	prometheus.MustRegister(bufferSize)
	prometheus.MustRegister(errorCount)
	prometheus.MustRegister(successCount)
	prometheus.MustRegister(droppedCount)
}

func (c *config) Receive(sb batchproducer.StatsBatch) {
	errorCount.WithLabelValues(c.CFInstanceID).Add(float64(sb.KinesisErrorsSinceLastStat))
	successCount.WithLabelValues(c.CFInstanceID).Add(float64(sb.RecordsSentSuccessfullySinceLastStat))
	droppedCount.WithLabelValues(c.CFInstanceID).Add(float64(sb.RecordsDroppedSinceLastStat))
	bufferSize.WithLabelValues(c.CFInstanceID).Set(float64(sb.BufferSize))
}

func (c *config) Printf(s string, v ...interface{}) {
	// noop
}

func (c *config) Run() error {
	totalParts, err := strconv.Atoi(c.AWSPartitions)
	if err != nil {
		return err
	}

	var kinAuth *kinesis.AuthCredentials
	if c.AWSAccessKey == "" {
		kinAuth, err = kinesis.NewAuthFromMetadata()
		if err != nil {
			return err
		}
	} else {
		kinAuth = kinesis.NewAuth(c.AWSAccessKey, c.AWSAccessSecret, "")
	}

	kinBP, err := batchproducer.New(kinesis.NewWithClient(c.AWSRegion, kinesis.NewClient(kinAuth)), c.AWSStreamName, batchproducer.Config{
		AddBlocksWhenBufferFull: true,
		BatchSize:               batchproducer.MaxKinesisBatchSize,
		BufferSize:              batchproducer.MaxKinesisBatchSize * 10,
		FlushInterval:           5 * time.Second,
		MaxAttemptsPerRecord:    5,
		Logger:                  c,
		StatInterval:            5 * time.Second,
		StatReceiver:            c,
	})
	if err != nil {
		return err
	}
	err = kinBP.Start()
	if err != nil {
		return err
	}
	defer kinBP.Flush(time.Second*10, true)

	c.api, err = fetchAPIResp(c.CFURL)
	if err != nil {
		return err
	}

	logConsumer := consumer.New(c.api.Links.Logging.URL, nil, nil)
	logConsumer.RefreshTokenFrom(c)

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt)
	go func() {
		<-sigChan
		log.Println("got signal, closing consumer...")
		logConsumer.Close()
	}()

	evts, errs := logConsumer.Firehose(c.CFSubscriptionID, "")
	go func() {
		for err := range errs {
			if err != nil {
				log.Println("received error: ", err)
			}
		}
	}()

	go func() {
		http.Handle("/metrics", promhttp.Handler())
		log.Fatal(http.ListenAndServe(":"+c.CFPort, nil))
	}()

	nextPart := 0
	for evt := range evts {
		eBytes, err := evt.Marshal()
		if err != nil {
			return err
		}
		err = kinBP.Add(eBytes, fmt.Sprintf("part-%d", nextPart))
		if err != nil {
			return err
		}
		nextPart++
		if nextPart >= totalParts {
			nextPart = 0
		}
	}

	return nil
}

func main() {
	e := env.NewVarSet()
	e.AppendSource(os.LookupEnv)
	app, err := cfenv.Current()
	if err == nil {
		e.AppendSource(env.NewLookupFromUPS(app, os.Getenv("UPS_NAME")))
	}
	err = (&config{
		CFURL:            e.MustString("CF_URL"),
		CFClientID:       e.MustString("CF_CLIENT_ID"),
		CFClientSecret:   e.MustString("CF_CLIENT_SECRET"),
		CFSubscriptionID: e.MustString("CF_SUBSCRIPTION_ID"),
		CFPort:           e.String("PORT", "8080"),
		CFInstanceID:     e.String("CF_INSTANCE_INDEX", "0"), // for prom metrics

		AWSStreamName:   e.MustString("AWS_KINESIS_DATA_STREAM"),
		AWSRegion:       e.MustString("AWS_REGION"),
		AWSPartitions:   e.MustString("AWS_PARTITIONS"),
		AWSAccessKey:    e.String("AWS_ACCESS_KEY_ID", ""),
		AWSAccessSecret: e.String("AWS_SECRET_ACCESS_KEY", ""),
	}).Run()
	if err != nil {
		log.Fatal(err)
	}
}
