"""
Avro message producer for Kafka with Schema Registry integration.

This module provides utilities for producing Kafka messages with Avro
serialization using Confluent's Schema Registry client.
"""

import json
import logging
from typing import Any, Dict, Optional

from confluent_kafka import SerializingProducer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer


class AvroMessageProducerConfig:
    """Configuration class for AvroMessageProducer."""

    def __init__(self, **kwargs):
        """Initialize configuration with default values."""
        # Kafka settings
        self.bootstrap_servers = kwargs.get('bootstrap_servers', "kafka:9092")
        self.topic = kwargs.get('topic', "response-topic")
        self.kafka_username = kwargs.get('kafka_username', "kafka_user")
        self.kafka_password = kwargs.get('kafka_password', "kafka_password")
        self.security_protocol = kwargs.get('security_protocol', "PLAINTEXT")
        self.mechanism = kwargs.get('mechanism', 'PLAIN')

        # Schema Registry settings
        self.schema_registry_url = kwargs.get(
            'schema_registry_url', "http://host.docker.internal:8081"
        )
        self.schema_registry_username = kwargs.get(
            'schema_registry_username', "kafka_user"
        )
        self.schema_registry_password = kwargs.get(
            'schema_registry_password', "kafka_password"
        )

        # Schema files and subjects
        self.key_schema_file = kwargs.get(
            'key_schema_file', "./schemas/response-topic-key.avsc"
        )
        self.value_schema_file = kwargs.get(
            'value_schema_file', "./schemas/response-topic-value.avsc"
        )
        self.custom_key_subject = kwargs.get(
            'custom_key_subject', "response-topic-key"
        )
        self.custom_value_subject = kwargs.get(
            'custom_value_subject', "response-topic-value"
        )


class AvroMessageProducer:
    """Produces Kafka messages with Avro serialization."""

    def __init__(
        self,
        config: Optional[AvroMessageProducerConfig] = None,
        logger: Optional[logging.Logger] = None
    ):
        """
        Initialize the Avro message producer.

        Args:
            config: Configuration object with all settings
            logger: Logger instance (optional)
        """
        self._config = config or AvroMessageProducerConfig()
        self._logger = logger or logging.getLogger(__name__)
        self._topic = self._config.topic

        # Initialize Schema Registry client
        schema_registry_client = SchemaRegistryClient({
            'url': self._config.schema_registry_url,
            'basic.auth.user.info': (
                f"{self._config.schema_registry_username}:"
                f"{self._config.schema_registry_password}"
            )
        })

        # Load schemas
        key_schema = self._load_schema(self._config.key_schema_file)
        value_schema = self._load_schema(self._config.value_schema_file)

        # Create the Avro serializer for key.
        key_avro_serializer = AvroSerializer(
            schema_registry_client,
            schema_str=key_schema,
            conf={
                'auto.register.schemas': False,
                'subject.name.strategy': (
                    lambda _, __: (
                        self._config.custom_key_subject or
                        f"{self._topic}-key"
                    )
                )
            }
        )

        # Create the Avro serializer for value.
        value_avro_serializer = AvroSerializer(
            schema_registry_client,
            schema_str=value_schema,
            conf={
                'auto.register.schemas': False,
                'subject.name.strategy': (
                    lambda _, __: (
                        self._config.custom_value_subject or
                        f"{self._topic}-value"
                    )
                )
            }
        )

        # Create the underlying Kafka producer
        producer_conf = {
            'bootstrap.servers': self._config.bootstrap_servers,
            'value.serializer': value_avro_serializer,
            'key.serializer': key_avro_serializer,
            'sasl.mechanism': self._config.mechanism,
            'security.protocol': self._config.security_protocol,
            'sasl.username': self._config.kafka_username,
            'sasl.password': self._config.kafka_password
        }

        self._producer = SerializingProducer(producer_conf)

    def _load_schema(self, schema_file: str) -> str:
        """
        Load Avro schema from file.

        Args:
            schema_file: Path to schema file

        Returns:
            Schema as string
        """
        try:
            with open(schema_file, 'r', encoding='utf-8') as f:
                schema_dict = json.load(f)
            return json.dumps(schema_dict)
        except Exception as e:
            self._logger.error(
                "Failed to load schema from %s: %s", schema_file, e
            )
            raise

    def produce_message(
        self,
        key_data: Dict[str, Any],
        value_data: Dict[str, Any],
        partition: int = -1,
        headers: Optional[Dict[str, str]] = None
    ) -> None:
        """
        Produce a message to Kafka with Avro serialization.

        Args:
            key_data: Message key data
            value_data: Message value data
            partition: Specific partition (optional)
            headers: Message headers (optional)
        """
        try:
            # Produce message
            self._producer.produce(
                topic=self._config.topic,
                key=key_data,
                value=value_data,
                partition=partition,
                headers=headers,
                on_delivery=self.delivery_report
            )

            # Trigger delivery report callbacks
            self._producer.poll(0)

            self._logger.debug(
                "Message queued for production - Key: %s, Value ID: %s",
                key_data.get('partitionKey', 'unknown'),
                value_data.get('id', 'unknown')
            )

        except Exception as e:
            self._logger.error("Failed to produce message: %s", e)
            raise

    def flush(self, timeout: float = 10.0) -> int:
        """
        Flush pending messages.

        Args:
            timeout: Timeout in seconds

        Returns:
            Number of messages still in queue
        """
        return self._producer.flush(timeout)

    def close(self) -> None:
        """Close the producer and clean up resources."""
        if self._producer:
            self._logger.info("Flushing and closing producer...")
            remaining = self.flush()
            if remaining > 0:
                self._logger.warning(
                    "%d messages still in queue after flush", remaining
                )
            self._producer = None

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()

    @staticmethod
    def delivery_report(err, msg):
        """Handle delivery report callback from producer."""
        if err:
            print(f"Delivery failed for key {msg.key()}: {err}")
        else:
            print(
                f"Message delivered to {msg.topic()} [{msg.partition()}] "
                f"at offset {msg.offset()} with key {msg.key()}"
            )
