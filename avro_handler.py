"""
Avro message deserialization handler for Azure Functions.

This module provides utilities for deserializing Kafka messages with Avro
schemas, specifically handling both key and value deserialization using
the schemas defined in the schemas/ directory.
"""

import json
import logging
import os
from io import BytesIO
from typing import Any, Dict, Optional, Tuple

import avro.io
import avro.schema
from avro.schema import Schema
from azure.functions import KafkaEvent

from util_context import KafkaMessageContext, kafka_context


class AvroMessageHandler:
    """Handles Avro message deserialization for Kafka messages."""

    def __init__(
        self,
        schema_dir: str = "./schemas",
        logger: Optional[logging.Logger] = None
    ):
        """
        Initialize the Avro message handler.

        Args:
            schema_dir: Directory containing the Avro schema files
            logger: Logger instance to use for logging (optional)
        """
        self._schema_dir = schema_dir
        self._key_schema: Optional[Schema] = None
        self._value_schema: Optional[Schema] = None
        self._logger = logger or logging.getLogger(__name__)

        self._load_schemas()

    def _load_schemas(self) -> None:
        """Load Avro schemas from schema files."""
        def load(file_name: str) -> Schema:
            schema_path = os.path.join(self._schema_dir, file_name)
            with open(schema_path, 'r', encoding='utf-8') as f:
                schema_dict = json.load(f)
            return avro.schema.parse(json.dumps(schema_dict))

        try:
            # Load key schema
            self._key_schema = load("incoming-topic-key.avsc")

            # Load value schema
            self._value_schema = load("incoming-topic-value.avsc")

            self._logger.info("Avro schemas loaded successfully")

        except FileNotFoundError as e:
            self._logger.error("Schema file not found: %s", e)
            raise
        except json.JSONDecodeError as e:
            self._logger.error("Invalid JSON in schema file: %s", e)
            raise
        except Exception as e:
            self._logger.error("Failed to load Avro schemas: %s", e)
            raise

    def _deserialize_with_schema(
        self,
        raw_data: bytes,
        schema: Optional[Schema],
        data_type: str
    ) -> Dict[str, Any]:
        """
        Deserialize Avro-encoded data using the provided schema.
        Handles Confluent Schema Registry wire format by stripping the header.

        Args:
            raw_data: Raw bytes of the Avro-encoded data
                     (including Confluent header)
            schema: Avro schema to use for deserialization
            data_type: Type of data being deserialized (for logging)

        Returns:
            Dict containing the deserialized data

        Raises:
            ValueError: If schema is None
            Exception: If deserialization fails
        """
        if schema is None:
            raise ValueError(f"{data_type.capitalize()} schema not loaded")

        try:
            # Check if this is Confluent Schema Registry format
            if len(raw_data) >= 5 and raw_data[0] == 0:
                # Strip Confluent wire format header (5 bytes)
                # Byte 0: Magic byte (0x00)
                # Bytes 1-4: Schema ID
                avro_data = raw_data[5:]
                schema_id = int.from_bytes(raw_data[1:5], byteorder='big')
                self._logger.debug(
                    "Stripped Confluent header for %s, schema ID: %d",
                    data_type, schema_id
                )
            else:
                # Pure Avro binary data
                avro_data = raw_data

            bytes_reader = BytesIO(avro_data)
            decoder = avro.io.BinaryDecoder(bytes_reader)
            reader = avro.io.DatumReader(schema)
            data = reader.read(decoder)

            self._logger.debug(
                "Successfully deserialized %s: %s", data_type, data
            )
            return data

        except Exception as e:
            self._logger.error(
                "Failed to deserialize Avro %s: %s", data_type, e
            )
            raise

    def deserialize_message(
        self,
        raw_key: Optional[bytes] = None,
        raw_value: Optional[bytes] = None
    ) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
        """
        Deserialize both key and value from a Kafka message.

        Args:
            raw_key: Raw bytes of the Avro-encoded key (optional)
            raw_value: Raw bytes of the Avro-encoded value (optional)

        Returns:
            Tuple of (key_data, value_data) where either can be None
        """
        key_data = None
        value_data = None

        if raw_key:
            try:
                key_data = self._deserialize_with_schema(
                    raw_key, self._key_schema, "key"
                )
            except Exception as e:
                self._logger.warning("Failed to deserialize key: %s", e)

        if raw_value:
            try:
                value_data = self._deserialize_with_schema(
                    raw_value, self._value_schema, "value"
                )
            except Exception as e:
                self._logger.warning("Failed to deserialize value: %s", e)

        return key_data, value_data

    def extract_from_kafka_event(
        self,
        kafka_event: KafkaEvent,
    ) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
        """
        Process a complete Kafka message and set up context.

        Args:
            kafka_event: The KafkaEvent object containing the message data

        Returns:
            Tuple of (key_data, value_data)
        """
        # Extract raw bytes from Kafka event
        # Access key from metadata - it should be bytes
        raw_key = kafka_event.metadata['Key'].encode('latin-1')
        raw_value = kafka_event.get_body()  # Keep as bytes for Avro

        # Deserialize the message
        key_data, value_data = self.deserialize_message(raw_key, raw_value)

        # Extract message ID from value data if available
        message_id = None
        if value_data and 'id' in value_data:
            message_id = value_data['id']

        # Set up Kafka context
        context = KafkaMessageContext(
            message_id=message_id,
            topic=kafka_event.topic,
            partition=kafka_event.partition,
            offset=kafka_event.offset,
            timestamp=kafka_event.timestamp
        )
        kafka_context.set(context)

        return key_data, value_data

    def get_key_schema(self) -> Optional[Schema]:
        """Get the loaded key schema."""
        return self._key_schema

    def get_value_schema(self) -> Optional[Schema]:
        """Get the loaded value schema."""
        return self._value_schema
