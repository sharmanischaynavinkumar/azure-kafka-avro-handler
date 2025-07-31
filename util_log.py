"""
Logging utilities for Azure Functions with Application Insights integration.

This module provides configured logger instances with Azure Application
Insights integration and custom dimensions for message tracking.
"""

import os
from logging import Filter, Logger, getLogger

from opencensus.ext.azure.log_exporter import AzureLogHandler

from util_context import kafka_context


def get_logger(name: str = __name__) -> Logger:
    """
    Create and configure a logger with Azure Application Insights integration.

    Args:
        name: The logger name, defaults to the current module name

    Returns:
        Logger: Configured logger instance with Azure handler and custom
                dimensions
    """
    appinsights_connection_string = os.getenv("APPINSIGHTS_CONNECTION_STRING")
    logging_level = os.getenv("LOGGING_LEVEL", "INFO").upper()

    logger = getLogger(name)
    logger.setLevel(logging_level)

    # Add Azure Application Insights Handler
    azure_handler = AzureLogHandler(
        connection_string=appinsights_connection_string
    )
    azure_handler.setLevel(logger.level)
    logger.addHandler(azure_handler)

    # pylint: disable=too-few-public-methods
    class CustomDimensionsFilter(Filter):
        """Filter to add custom dimensions to log records for tracking."""

        def filter(self, record):
            """
            Add custom dimensions to log record.

            Args:
                record: The log record to filter

            Returns:
                bool: Always returns True to allow the record through
            """
            if not hasattr(record, 'custom_dimensions'):
                record.custom_dimensions = {}

            # Add Kafka context information if available
            kafka_ctx = kafka_context.get()
            if kafka_ctx:
                record.custom_dimensions['messageId'] = kafka_ctx.message_id
                record.custom_dimensions['topic'] = kafka_ctx.topic
                record.custom_dimensions['partition'] = kafka_ctx.partition
                record.custom_dimensions['offset'] = kafka_ctx.offset
                record.custom_dimensions['timestamp'] = kafka_ctx.timestamp

            return True

    logger.addFilter(CustomDimensionsFilter())

    return logger
