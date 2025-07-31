# Azure Kafka Avro Handler

A complete development environment for Azure Functions that process Kafka messages with Avro schema compliance. This project includes a full containerized Kafka ecosystem, VS Code devcontainer setup, and production-ready Azure Function implementation.

## 🚀 Quick Start

### Prerequisites
- Docker Desktop
- VS Code with Dev Containers extension

### Development Setup

1. **Clone and open in devcontainer**:
   ```bash
   git clone <repository-url>
   cd azure-kafka-avro-handler
   code .
   # When prompted, click "Reopen in Container"
   ```

2. **Start Kafka infrastructure**:
   ```bash
   ./setup-infrastructure.sh start
   ```

3. **Run the Azure Function locally**:
   ```bash
   ./start-function.sh
   ```

4. **Test with sample messages**:
   ```bash
   ./publish-message.sh
   ```

## 🏗️ Architecture

### Development Environment
- **VS Code Devcontainer**: Fully configured development environment with Azure Functions Core Tools
- **Docker Compose**: Local Kafka ecosystem (Zookeeper, Kafka, Schema Registry, Kafka UI)
- **Management Scripts**: Automated setup and testing workflows

### Function Components
- **Kafka Trigger**: Processes messages from Kafka topics with retry policies
- **Avro Processing**: Deserializes and validates Avro messages against schemas
- **Response Producer**: Publishes processed results to response topics
- **Centralized Logging**: Structured logging with Azure Application Insights integration
- **Context Tracking**: Message correlation across the processing pipeline

## 📁 Project Structure

```
azure-kafka-avro-handler/
├── .devcontainer/
│   ├── devcontainer.json       # VS Code devcontainer configuration
│   └── Dockerfile              # Development environment setup
├── .vscode/
│   ├── settings.json           # VS Code workspace settings
│   └── tasks.json             # Build and run tasks
├── KafkaAvroHandler/
│   ├── __init__.py            # Main Azure Function implementation
│   └── function.json          # Function binding and trigger configuration
├── schemas/                    # Avro schema definitions
│   ├── incoming-topic-key.avsc
│   ├── incoming-topic-value.avsc
│   ├── response-topic-key.avsc
│   └── response-topic-value.avsc
├── avro_handler.py            # Avro message processing utilities
├── avro_producer.py           # Kafka message producer with Avro support
├── util_context.py            # Context variables for message tracking
├── util_log.py                # Centralized logging configuration
├── docker-compose.yml         # Kafka ecosystem infrastructure
├── setup-infrastructure.sh    # Infrastructure management script
├── start-function.sh          # Azure Function startup script
├── publish-message.sh         # Test message publishing script
├── test_function.py           # Unit tests and validation
├── host.json                  # Azure Functions host configuration
├── local.settings.json        # Local development settings
├── requirements.txt           # Production dependencies
└── requirements_dev.txt       # Development dependencies
```

## 🔧 Development Environment

### Devcontainer Features
- **Azure Functions Core Tools v4**: Local function runtime
- **Python 3.11**: Latest stable Python environment
- **Docker-in-Docker**: Run containers within the devcontainer
- **VS Code Extensions**: Pre-configured with Azure Functions, Python, and development tools

### Infrastructure Components
| Service | Port | Purpose |
|---------|------|---------|
| Zookeeper | 2181 | Kafka coordination |
| Kafka | 9092 | Message broker |
| Schema Registry | 8081 | Avro schema management |
| Kafka UI | 8080 | Web interface for Kafka |

### Management Scripts

#### `setup-infrastructure.sh`
Complete infrastructure management with these commands:
- `start` - Start all services and create topics/schemas
- `stop` - Stop all services
- `restart` - Restart all services
- `status` - Show service status
- `cleanup` - Remove all containers and volumes
- `connect` - Connect devcontainer to Kafka network

#### `start-function.sh`
Starts the Azure Function locally with proper environment configuration.

#### `publish-message.sh`
Sends test Avro messages to the incoming topic for testing.

### VS Code Tasks

The project includes pre-configured VS Code tasks for streamlined development workflow. Access these tasks via:
- **Windows**: `Ctrl+Shift+P` → "Tasks: Run Task" or `Ctrl+Shift+B`
- **Mac**: `Cmd+Shift+P` → "Tasks: Run Task" or `Cmd+Shift+B`

#### Infrastructure Management Tasks
| Task | Purpose |
|------|---------|
| **Infrastructure: Start All Services** | Start complete Kafka ecosystem |
| **Infrastructure: Stop All Services** | Stop all running services |
| **Infrastructure: Restart All Services** | Restart all services |
| **Infrastructure: Show Status** | Display current service status |
| **Infrastructure: Cleanup (Delete All Data)** | Remove all containers and volumes |

#### Monitoring Tasks
| Task | Purpose |
|------|---------|
| **Infrastructure: View All Logs** | Monitor all service logs (runs in background) |
| **Infrastructure: View Kafka Logs** | Monitor Kafka broker logs only (runs in background) |
| **Infrastructure: View Schema Registry Logs** | Monitor Schema Registry logs only (runs in background) |

#### Development Tasks
| Task | Purpose |
|------|---------|
| **Infrastructure: Create Kafka Topics** | Create required Kafka topics |
| **Infrastructure: Create Schema** | Register Avro schemas |
| **Kafka: Publish Sample Message** | Send test messages for development |
| **Azure Function: Start Function Host** | Start local function runtime (runs in background) |


## 🔄 Message Flow

1. **Incoming Messages**: JSON messages published to `incoming-topic`
2. **Function Trigger**: Azure Function triggered by Kafka messages
3. **Avro Processing**: Messages validated against Avro schemas
4. **Business Logic**: Custom processing with error handling
5. **Response Publishing**: Results published to `response-topic`
6. **Logging**: Full correlation tracking through Azure Application Insights

## 📋 Configuration

### Environment Variables

Set these in `local.settings.json` for local development:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "KAFKA_BROKER_LIST": "kafka:9092",
    "KAFKA_INCOMING_TOPIC": "incoming-topic",
    "KAFKA_RESPONSE_TOPIC": "response-topic",
    "KAFKA_CONSUMER_GROUP": "azure-function-group",
    "SCHEMA_REGISTRY_URL": "http://schema-registry:8081",
    "APPLICATIONINSIGHTS_CONNECTION_STRING": "InstrumentationKey=...;"
  }
}
```

### Avro Schemas

The function processes messages with these schema structures:

**Incoming Message Value**:
```json
{
  "type": "record",
  "name": "IncomingMessage",
  "fields": [
    {"name": "messageId", "type": "string"},
    {"name": "timestamp", "type": "long"},
    {"name": "payload", "type": "string"},
    {"name": "source", "type": "string"}
  ]
}
```

**Response Message Value**:
```json
{
  "type": "record",
  "name": "ResponseMessage",
  "fields": [
    {"name": "originalMessageId", "type": "string"},
    {"name": "processedAt", "type": "long"},
    {"name": "result", "type": "string"},
    {"name": "status", "type": "string"}
  ]
}
```

## 🧪 Testing

### Unit Tests
```bash
# Run all tests
python test_function.py

# Run with pytest for detailed output
pytest test_function.py -v
```

### Integration Testing
```bash
# Start infrastructure
./setup-infrastructure.sh start

# Start function
./start-function.sh &

# Send test messages
./publish-message.sh

# Check logs
func logs
```

### Manual Testing via Kafka UI
1. Open http://localhost:8080 in your browser
2. Navigate to Topics → incoming-topic
3. Publish test messages directly
4. Monitor processing in the response-topic

## 📊 Monitoring and Logging

### Context Tracking
- Each message gets a unique correlation ID
- Context variables track message flow across components
- All log entries include message correlation data

### Azure Application Insights Integration
- Structured logging with custom telemetry
- Automatic correlation with Azure Monitor
- Performance metrics and error tracking

### Log Format 
All the logs emitted contains the following fields in custom dimension:
- messageId
- topic
- partition
- offset
- timestamp

## 🚀 Deployment

### Azure Deployment
1. **Create Function App**:
   ```bash
   az functionapp create \
     --resource-group myResourceGroup \
     --consumption-plan-location westus \
     --runtime python \
     --runtime-version 3.11 \
     --functions-version 4 \
     --name myKafkaFunction \
     --storage-account mystorageaccount
   ```

2. **Configure App Settings**:
   ```bash
   az functionapp config appsettings set \
     --name myKafkaFunction \
     --resource-group myResourceGroup \
     --settings KAFKA_BROKER_LIST="your-kafka-broker:9093"
   ```

3. **Deploy Function**:
   ```bash
   func azure functionapp publish myKafkaFunction
   ```

### Production Configuration
- Configure managed identity for secure access
- Set up Key Vault for secrets management
- Configure Application Insights for monitoring
- Set up alerts and dashboards

## 🔍 Troubleshooting

### Common Issues

**Container Connection Issues**:
```bash
# Check network connectivity
./setup-infrastructure.sh status

# Reconnect devcontainer
./setup-infrastructure.sh connect
```

**Avro Schema Errors**:
- Verify schema compatibility in Schema Registry UI (http://localhost:8081)
- Check schema evolution compatibility settings
- Validate message format against schemas

**Function Trigger Issues**:
- Verify Kafka broker connectivity from function
- Check consumer group configuration
- Review retry policy settings in function.json

### Debugging Commands
```bash
# View service logs
docker-compose logs kafka
docker-compose logs schema-registry

# Check function logs
func logs

# Monitor message flow
./setup-infrastructure.sh status
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes in the devcontainer environment
4. Test with the local Kafka infrastructure
5. Submit a pull request

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For issues and questions:
- Check the troubleshooting section
- Review Azure Functions documentation
- Open an issue in the repository
