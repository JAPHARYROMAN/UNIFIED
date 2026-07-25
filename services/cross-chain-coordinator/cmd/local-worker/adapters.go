package main

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/segmentio/kafka-go"
	"github.com/unified-finance/unified/services/cross-chain-coordinator/provider"
	"golang.org/x/crypto/sha3"
)

const (
	evidenceBucket = "crosschain-evidence"
	outboxTopic    = "unified.crosschain.message-state.v1"
)

type httpTransport struct {
	id       string
	endpoint string
	client   *http.Client
}

func (transport *httpTransport) ID() string { return transport.id }

func (transport *httpTransport) Submit(
	ctx context.Context,
	delivery provider.Delivery,
) (provider.Receipt, error) {
	body, err := json.Marshal(struct {
		MessageID    string `json:"message_id"`
		Envelope     []byte `json:"envelope"`
		EnvelopeHash string `json:"envelope_hash"`
		SourceProof  []byte `json:"source_proof"`
		ProofHash    string `json:"proof_hash"`
	}{
		MessageID:    hex.EncodeToString(delivery.MessageID[:]),
		Envelope:     delivery.Envelope,
		EnvelopeHash: hex.EncodeToString(delivery.EnvelopeHash[:]),
		SourceProof:  delivery.SourceProof,
		ProofHash:    hex.EncodeToString(delivery.ProofHash[:]),
	})
	if err != nil {
		return provider.Receipt{}, err
	}
	request, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		transport.endpoint,
		bytes.NewReader(body),
	)
	if err != nil {
		return provider.Receipt{}, err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := transport.client.Do(request)
	if err != nil {
		return provider.Receipt{}, provider.Retryable(err)
	}
	defer func() { _ = response.Body.Close() }()
	receipt, err := io.ReadAll(io.LimitReader(response.Body, 64<<10))
	if err != nil {
		return provider.Receipt{}, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		failure := fmt.Errorf("transport status %d", response.StatusCode)
		if response.StatusCode == http.StatusRequestTimeout ||
			response.StatusCode == http.StatusTooManyRequests ||
			response.StatusCode >= http.StatusInternalServerError {
			return provider.Receipt{}, provider.Retryable(failure)
		}
		return provider.Receipt{}, failure
	}
	var accepted struct {
		Authority         string `json:"authority"`
		ContainsRealValue bool   `json:"contains_real_value"`
	}
	if err := json.Unmarshal(receipt, &accepted); err != nil {
		return provider.Receipt{}, errors.New("provider response is not canonical JSON")
	}
	if accepted.Authority != "TRANSPORT_ONLY" || accepted.ContainsRealValue {
		return provider.Receipt{}, errors.New("provider asserted forbidden authority or value")
	}
	return provider.Receipt{
		ProviderID: transport.id,
		Receipt:    receipt,
	}, nil
}

func newHTTPTransport(
	id, baseURL, path string,
	client *http.Client,
) (*httpTransport, error) {
	if id == "" || client == nil {
		return nil, errors.New("transport identity and client are required")
	}
	parsed, err := url.Parse(baseURL)
	if err != nil {
		return nil, err
	}
	parsed.Path = strings.TrimRight(parsed.Path, "/") + path
	if err := validateLoopbackHTTP(parsed.String()); err != nil {
		return nil, err
	}
	return &httpTransport{id: id, endpoint: parsed.String(), client: client}, nil
}

type immutableEvidenceStore interface {
	PutImmutable(context.Context, string, []byte, [32]byte) error
	GetImmutable(context.Context, string, [32]byte) ([]byte, error)
}

type minIOEvidenceStore struct {
	client *minio.Client
}

func newMinIOEvidenceStore(config configuration) (*minIOEvidenceStore, error) {
	parsed, err := url.Parse(config.objectURL)
	if err != nil {
		return nil, err
	}
	client, err := minio.New(parsed.Host, &minio.Options{
		Creds:  credentials.NewStaticV4(config.objectAccess, config.objectSecret, ""),
		Secure: false,
	})
	if err != nil {
		return nil, err
	}
	return &minIOEvidenceStore{client: client}, nil
}

func (store *minIOEvidenceStore) PutImmutable(
	ctx context.Context,
	key string,
	value []byte,
	hash [32]byte,
) error {
	if store == nil || store.client == nil {
		return errors.New("invalid immutable evidence object")
	}
	if err := validateEvidenceIdentity(key, value, hash); err != nil {
		return err
	}
	hashText := hex.EncodeToString(hash[:])
	exists, err := store.client.BucketExists(ctx, evidenceBucket)
	if err != nil {
		return fmt.Errorf("check evidence bucket: %w", err)
	}
	if !exists {
		// This resettable local smoke bucket is single-writer. The immutable
		// boundary is the content-addressed key plus the no-overwrite read below.
		if err := store.client.MakeBucket(ctx, evidenceBucket, minio.MakeBucketOptions{}); err != nil {
			return fmt.Errorf("create evidence bucket: %w", err)
		}
	}
	object, err := store.client.GetObject(ctx, evidenceBucket, key, minio.GetObjectOptions{})
	if err == nil {
		existing, readErr := io.ReadAll(io.LimitReader(object, int64(len(value))+1))
		closeErr := object.Close()
		if readErr == nil && closeErr == nil && bytes.Equal(existing, value) {
			return nil
		}
		if readErr == nil && closeErr == nil {
			return errors.New("immutable evidence object conflict")
		}
		var response minio.ErrorResponse
		if !errors.As(readErr, &response) || response.Code != "NoSuchKey" {
			return fmt.Errorf("read evidence object: %w", readErr)
		}
	}
	_, err = store.client.PutObject(
		ctx,
		evidenceBucket,
		key,
		bytes.NewReader(value),
		int64(len(value)),
		minio.PutObjectOptions{
			ContentType: "application/octet-stream",
			UserMetadata: map[string]string{
				"keccak-256": hashText,
				"immutable":  "true",
			},
		},
	)
	if err != nil {
		return fmt.Errorf("persist immutable evidence object: %w", err)
	}
	return nil
}

func (store *minIOEvidenceStore) GetImmutable(
	ctx context.Context,
	key string,
	hash [32]byte,
) ([]byte, error) {
	if store == nil || store.client == nil || key == "" || hash == ([32]byte{}) {
		return nil, errors.New("invalid immutable evidence object")
	}
	info, err := store.client.StatObject(
		ctx,
		evidenceBucket,
		key,
		minio.StatObjectOptions{},
	)
	if err != nil {
		return nil, fmt.Errorf("stat evidence object: %w", err)
	}
	const maximumEvidenceBytes = 8 << 20
	if info.Size <= 0 || info.Size > maximumEvidenceBytes {
		return nil, errors.New("immutable evidence object has invalid size")
	}
	object, err := store.client.GetObject(
		ctx,
		evidenceBucket,
		key,
		minio.GetObjectOptions{},
	)
	if err != nil {
		return nil, fmt.Errorf("open evidence object: %w", err)
	}
	value, readErr := io.ReadAll(io.LimitReader(object, info.Size+1))
	closeErr := object.Close()
	if readErr != nil {
		return nil, fmt.Errorf("read evidence object: %w", readErr)
	}
	if closeErr != nil {
		return nil, fmt.Errorf("close evidence object: %w", closeErr)
	}
	if int64(len(value)) != info.Size {
		return nil, errors.New("immutable evidence object size conflict")
	}
	if err := validateEvidenceIdentity(key, value, hash); err != nil {
		return nil, err
	}
	return value, nil
}

func validateEvidenceIdentity(key string, value []byte, hash [32]byte) error {
	if key == "" || len(value) == 0 || hash == ([32]byte{}) {
		return errors.New("invalid immutable evidence object")
	}
	hashText := hex.EncodeToString(hash[:])
	if keccak(value) != hash || !strings.Contains(key, "/"+hashText+".") {
		return errors.New("evidence key/hash/content identity conflict")
	}
	return nil
}

func keccak(value []byte) [32]byte {
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(value)
	var result [32]byte
	hasher.Sum(result[:0])
	return result
}

type brokerMessage struct {
	MessageID    [32]byte
	PartitionKey string
	Payload      []byte
	PayloadHash  [32]byte
	OutboxID     string
}

type consumedMessage struct {
	brokerMessage
	BrokerOffset string
}

type eventBroker interface {
	Publish(context.Context, brokerMessage) (string, error)
	Consume(context.Context, int) ([]consumedMessage, error)
	Close() error
}

type kafkaBroker struct {
	client          *kafka.Client
	transport       *kafka.Transport
	address         string
	producedOffsets []int64
	topicReady      bool
}

func newKafkaBroker(config configuration) *kafkaBroker {
	dialer := &net.Dialer{Timeout: 5 * time.Second}
	transport := &kafka.Transport{
		Dial: func(
			ctx context.Context,
			network string,
			_ string,
		) (net.Conn, error) {
			return dialer.DialContext(ctx, network, config.kafkaBroker)
		},
	}
	return &kafkaBroker{
		address:   config.kafkaBroker,
		transport: transport,
		client: &kafka.Client{
			Addr:      kafka.TCP(config.kafkaBroker),
			Timeout:   5 * time.Second,
			Transport: transport,
		},
	}
}

func (broker *kafkaBroker) Publish(
	ctx context.Context,
	event brokerMessage,
) (string, error) {
	if !broker.topicReady {
		connection, err := (&kafka.Dialer{Timeout: 5 * time.Second}).DialContext(
			ctx,
			"tcp",
			broker.address,
		)
		if err != nil {
			return "", fmt.Errorf("connect local outbox broker: %w", err)
		}
		createErr := connection.CreateTopics(kafka.TopicConfig{
			Topic:             outboxTopic,
			NumPartitions:     1,
			ReplicationFactor: 1,
		})
		closeErr := connection.Close()
		if createErr != nil && !errors.Is(createErr, kafka.TopicAlreadyExists) {
			return "", fmt.Errorf("create local outbox topic: %w", createErr)
		}
		if closeErr != nil {
			return "", fmt.Errorf("close local outbox broker connection: %w", closeErr)
		}
		broker.topicReady = true
	}
	headers := []kafka.Header{
		{Key: "message-id", Value: []byte(hex.EncodeToString(event.MessageID[:]))},
		{Key: "payload-hash", Value: []byte(hex.EncodeToString(event.PayloadHash[:]))},
		{Key: "outbox-id", Value: []byte(event.OutboxID)},
	}
	response, err := broker.client.Produce(ctx, &kafka.ProduceRequest{
		Topic:        outboxTopic,
		Partition:    0,
		RequiredAcks: kafka.RequireAll,
		Records: kafka.NewRecordReader(kafka.Record{
			Key:     kafka.NewBytes([]byte(event.PartitionKey)),
			Value:   kafka.NewBytes(append([]byte(nil), event.Payload...)),
			Headers: headers,
			Time:    time.Now().UTC(),
		}),
	})
	if err != nil {
		return "", fmt.Errorf("publish local outbox: %w", err)
	}
	if response == nil || response.Error != nil {
		if response != nil {
			err = response.Error
		}
		return "", fmt.Errorf("publish local outbox response: %w", err)
	}
	broker.producedOffsets = append(broker.producedOffsets, response.BaseOffset)
	return "0:" + strconv.FormatInt(response.BaseOffset, 10), nil
}

func (broker *kafkaBroker) Consume(
	ctx context.Context,
	count int,
) ([]consumedMessage, error) {
	if count < 0 || len(broker.producedOffsets) < count {
		return nil, errors.New("invalid local broker consume count")
	}
	result := make([]consumedMessage, 0, count)
	for _, expectedOffset := range broker.producedOffsets[:count] {
		response, err := broker.client.Fetch(ctx, &kafka.FetchRequest{
			Topic:     outboxTopic,
			Partition: 0,
			Offset:    expectedOffset,
			MinBytes:  1,
			MaxBytes:  1 << 20,
			MaxWait:   500 * time.Millisecond,
		})
		if err != nil {
			return nil, fmt.Errorf("consume local outbox: %w", err)
		}
		if response.Error != nil {
			return nil, fmt.Errorf("consume local outbox response: %w", response.Error)
		}
		raw, err := response.Records.ReadRecord()
		if err != nil {
			return nil, fmt.Errorf("read local outbox record: %w", err)
		}
		if raw.Offset != expectedOffset {
			return nil, errors.New("local broker returned an unexpected offset")
		}
		key, err := io.ReadAll(raw.Key)
		if err != nil {
			return nil, err
		}
		value, err := io.ReadAll(raw.Value)
		if err != nil {
			return nil, err
		}
		if err := errors.Join(raw.Key.Close(), raw.Value.Close()); err != nil {
			return nil, err
		}
		var messageID, payloadHash [32]byte
		var outboxID string
		for _, header := range raw.Headers {
			switch header.Key {
			case "message-id":
				value, decodeErr := hex.DecodeString(string(header.Value))
				if decodeErr != nil || len(value) != 32 {
					return nil, errors.New("invalid message-id broker header")
				}
				copy(messageID[:], value)
			case "payload-hash":
				value, decodeErr := hex.DecodeString(string(header.Value))
				if decodeErr != nil || len(value) != 32 {
					return nil, errors.New("invalid payload-hash broker header")
				}
				copy(payloadHash[:], value)
			case "outbox-id":
				outboxID = string(header.Value)
			}
		}
		if messageID == ([32]byte{}) || payloadHash == ([32]byte{}) || outboxID == "" {
			return nil, errors.New("required broker headers are missing")
		}
		result = append(result, consumedMessage{
			brokerMessage: brokerMessage{
				MessageID:    messageID,
				PartitionKey: string(key),
				Payload:      value,
				PayloadHash:  payloadHash,
				OutboxID:     outboxID,
			},
			BrokerOffset: "0:" + strconv.FormatInt(raw.Offset, 10),
		})
	}
	broker.producedOffsets = broker.producedOffsets[count:]
	return result, nil
}

func (broker *kafkaBroker) Close() error {
	if broker != nil && broker.transport != nil {
		broker.transport.CloseIdleConnections()
	}
	return nil
}
