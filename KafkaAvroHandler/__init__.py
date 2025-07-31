"""
Azure Function for handling Kafka messages with Avro schema compliance.
This function demonstrates:
- Kafka trigger with retry configuration
- Avro message deserialization
- Context variable usage for message tracking
- Centralized logging with App Insights integration
- One-time initialization of shared resources
"""

import json
import logging
import os
import time
import uuid
from typing import Dict, Tuple

from azure.functions import KafkaEvent
from avro_handler import AvroMessageHandler
from avro_producer import AvroMessageProducer, AvroMessageProducerConfig
from util_log import get_logger

# Get the configured logger (initialized once per app lifecycle)
logger = get_logger(__name__)
producer_config = AvroMessageProducerConfig(**(os.environ))
avro_message_handler = AvroMessageHandler(logger=logger)
avro_message_producer = AvroMessageProducer(
    config=producer_config, logger=logger
)


def main(kafka_event: KafkaEvent) -> None:
    """
    Main Azure Function entry point for Kafka message processing.

    Args:
        kafka_event: The Kafka event containing the message data
    """
    try:
        key, value = avro_message_handler.extract_from_kafka_event(kafka_event)
        logger.debug("Processing Kafka event... %s", kafka_event)
        logger.debug("Kafka event details: %s", kafka_event.metadata)
        logger.debug("Kafka event key: %s", kafka_event.key)
        logger.debug("Extracted key: %s, value: %s", key, value)

        response_key, response_value = process(key, value, logger)
        logger.debug("Generated response - Key: %s", response_key)
        logger.debug("Generated response - Value: %s", response_value)

        # Produce response message
        avro_message_producer.produce_message(
            key_data=response_key,
            value_data=response_value
        )

    except Exception as e:
        # Log error with context
        logger.error(
            "Error processing Kafka message: %s", str(e), exc_info=True
        )
        # Re-raise to trigger retry mechanism
        raise


def process(key: Dict, value: Dict,
            process_logger: logging.Logger) -> Tuple[Dict, Dict]:
    """
    Process the incoming message and generate response key/value pairs.

    Args:
        key: Incoming message key
        value: Incoming message value
        process_logger: Logger instance

    Returns:
        Tuple of (response_key, response_value)
    """
    # Extract correlation ID from incoming message
    correlation_id = key.get('correlationId', str(uuid.uuid4()))
    partition_key = key.get('partitionKey', 'default')
    try:
        # Simulate processing
        start_time = time.time()

        # Example processing logic
        processed_data = {
            "originalId": correlation_id,
            "processedAt": int(time.time() * 1000),
            "transformedData": str(value.get('data', '')).upper(),
            "source": value.get('source', 'unknown')
        }

        processing_time = int((time.time() - start_time) * 1000)

        # Create response key
        response_key = {
            "correlationId": correlation_id,
            "partitionKey": partition_key,
            "responseType": "PROCESSING_RESULT",
            "functionName": "KafkaAvroHandler"
        }

        # Create response value
        response_value = {
            "id": value.get('id', str(uuid.uuid4())),
            "correlationId": correlation_id,
            "timestamp": int(time.time() * 1000),
            "status": "SUCCESS",
            "result": {
                "processedData": json.dumps(processed_data),  # Convert to JSON
                "errorMessage": None,
                "errorCode": None,
                "processingTimeMs": processing_time,
                "retryCount": 0
            },
            "functionName": "KafkaAvroHandler",
            "executionId": str(uuid.uuid4()),
            "version": "1.0"
        }

        process_logger.info("Generated response - Key: %s", response_key)
        process_logger.info("Generated response - Value: %s", response_value)

        return response_key, response_value

    except Exception as e:
        # Create error response
        process_logger.error("Error in processing: %s", str(e))

        error_response_key = {
            "correlationId": correlation_id,
            "partitionKey": partition_key,
            "responseType": "ERROR_RESPONSE",
            "functionName": "KafkaAvroHandler"
        }

        error_response_value = {
            "id": value.get('id', str(uuid.uuid4())),
            "correlationId": correlation_id,
            "timestamp": int(time.time() * 1000),
            "status": "ERROR",
            "result": {
                "processedData": None,
                "errorMessage": str(e),
                "errorCode": "PROCESSING_ERROR",
                "processingTimeMs": 0,
                "retryCount": 0
            },
            "functionName": "KafkaAvroHandler",
            "executionId": str(uuid.uuid4()),
            "version": "1.0"
        }

        return error_response_key, error_response_value
