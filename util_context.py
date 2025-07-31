"""
Context variables for Azure Functions message tracking.

This module provides context variables for tracking Kafka message metadata
across the execution context of Azure Functions.
"""

import contextvars
from dataclasses import dataclass
from typing import Optional


@dataclass
class KafkaMessageContext:
    """
    Structured context for Kafka message metadata.

    Attributes:
        message_id: Unique identifier for the message
        topic: Kafka topic name
        partition: Kafka partition number
        offset: Kafka offset position
        timestamp: Message timestamp
    """
    message_id: Optional[str] = None
    topic: Optional[str] = None
    partition: Optional[int] = None
    offset: Optional[int] = None
    timestamp: Optional[int] = None


# Context variable for Kafka message tracking
kafka_context: contextvars.ContextVar[Optional[KafkaMessageContext]] = (
    contextvars.ContextVar('kafka_context', default=None)
)
