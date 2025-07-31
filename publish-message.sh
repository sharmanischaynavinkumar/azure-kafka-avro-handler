#!/bin/bash

# Kafka Avro Console Producer Script
# This script publishes messages to the incoming-topic using Avro schemas

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Configuration
KAFKA_BOOTSTRAP_SERVER="kafka:9092"
SCHEMA_REGISTRY_URL="http://schema-registry:8081"
TOPIC_NAME="incoming-topic"
KEY_SUBJECT="incoming-topic-key"
VALUE_SUBJECT="incoming-topic-value"

# Function to check if services are running
check_services() {
    print_message $BLUE "Checking if required services are running..."
    
    # Check if Kafka is running
    if ! docker-compose ps kafka | grep -q "Up"; then
        print_message $RED "Error: Kafka is not running. Please start the infrastructure first."
        print_message $YELLOW "Run: ./setup-infrastructure.sh start"
        exit 1
    fi
    
    # Check if Schema Registry is running
    if ! docker-compose ps schema-registry | grep -q "Up"; then
        print_message $RED "Error: Schema Registry is not running. Please start the infrastructure first."
        print_message $YELLOW "Run: ./setup-infrastructure.sh start"
        exit 1
    fi
    
    print_message $GREEN "All required services are running!"
}

# Function to generate sample message key
generate_sample_key() {
    local event_type=${1:-"user.created"}
    local partition_key=${2:-"user-$(date +%s)"}
    local correlation_id=${3:-"corr-$(uuidgen 2>/dev/null || echo "$(date +%s)-$(( RANDOM % 1000 ))")"}
    
    cat << EOF
{
  "partitionKey": "$partition_key",
  "eventType": "$event_type",
  "correlationId": {"string": "$correlation_id"}
}
EOF
}

# Function to generate sample message value
generate_sample_value() {
    local event_type=${1:-"user.created"}
    local user_id=${2:-"user-$(date +%s)"}
    local message_id=${3:-"msg-$(uuidgen 2>/dev/null || echo "$(date +%s)-$(( RANDOM % 1000 ))")"}
    local timestamp=$(date +%s)000  # Current timestamp in milliseconds
    
    cat << EOF
{
  "id": "$message_id",
  "timestamp": $timestamp,
  "eventType": "$event_type",
  "payload": {
    "userId": {"string": "$user_id"},
    "data": "{\"name\": \"John Doe\", \"email\": \"john.doe@example.com\", \"age\": 30}",
    "metadata": {
      "source": "user-service",
      "region": "us-east-1",
      "environment": "development"
    }
  },
  "source": "user-management-system",
  "version": "1.0"
}
EOF
}

# Function to publish a single message with custom content
publish_custom_message() {
    local key_json="$1"
    local value_json="$2"
    
    print_message $BLUE "Publishing custom message to topic: $TOPIC_NAME"
    
    # Get schema IDs first (outside the container)
    local key_schema_id=$(get_schema_id "$KEY_SUBJECT")
    local value_schema_id=$(get_schema_id "$VALUE_SUBJECT")
    
    print_message $YELLOW "Using key schema ID: $key_schema_id"
    print_message $YELLOW "Using value schema ID: $value_schema_id"
    
    # Compact the JSON to single lines using jq
    local key_compact=$(echo "$key_json" | jq -c .)
    local value_compact=$(echo "$value_json" | jq -c .)
    
    # Create the message content using | as separator (safer than : which appears in JSON)
    local message_content="$key_compact|$value_compact"
    
    # Debug output
    print_message $BLUE "Message content:"
    echo "$message_content"
    
    # Publish using echo and pipe
    if echo "$message_content" | docker-compose exec -T schema-registry kafka-avro-console-producer \
        --broker-list "$KAFKA_BOOTSTRAP_SERVER" \
        --topic "$TOPIC_NAME" \
        --property schema.registry.url="$SCHEMA_REGISTRY_URL" \
        --property key.schema.id="$key_schema_id" \
        --property value.schema.id="$value_schema_id" \
        --property parse.key=true \
        --property auto.register.schemas=false \
        --property key.separator="|"; then

        print_message $GREEN "Message published successfully!"
    else
        print_message $RED "Failed to publish message"
        return 1
    fi
}

# Function to get schema ID from Schema Registry
get_schema_id() {
    local subject="$1"
    local schema_id=$(curl -s "http://host.docker.internal:8081/subjects/$subject/versions/latest" | grep -o '"id":[0-9]*' | cut -d':' -f2)
    echo "$schema_id"
}

# Function to publish a sample message
publish_sample_message() {
    local event_type=${1:-"user.created"}
    local user_id=${2:-"user-$(date +%s)"}
    
    print_message $BLUE "Publishing sample message to topic: $TOPIC_NAME"
    print_message $YELLOW "Event Type: $event_type"
    print_message $YELLOW "User ID: $user_id"
    
    local key_json=$(generate_sample_key "$event_type" "$user_id")
    local value_json=$(generate_sample_value "$event_type" "$user_id")
    
    print_message $BLUE "Generated Key:"
    echo "$key_json" | jq . 2>/dev/null || echo "$key_json"
    
    print_message $BLUE "Generated Value:"
    echo "$value_json" | jq . 2>/dev/null || echo "$value_json"
    
    publish_custom_message "$key_json" "$value_json"
}

# Function to publish multiple sample messages
publish_multiple_messages() {
    local count=${1:-5}
    
    print_message $BLUE "Publishing $count sample messages..."
    
    local event_types=("user.created" "user.updated" "user.deleted" "order.placed" "order.cancelled")
    
    for i in $(seq 1 "$count"); do
        local event_type=${event_types[$((i % ${#event_types[@]}))]}
        local user_id="user-$i-$(date +%s)"
        
        print_message $YELLOW "Publishing message $i/$count..."
        publish_sample_message "$event_type" "$user_id"
        
        # Small delay between messages
        sleep 1
    done
    
    print_message $GREEN "Published $count messages successfully!"
}

# Function to start interactive mode
interactive_mode() {
    print_message $BLUE "Starting interactive message publishing mode..."
    print_message $YELLOW "Enter JSON messages (key:value format) or 'quit' to exit"
    print_message $YELLOW "Example: {\"partitionKey\":\"test\",\"eventType\":\"test\",\"correlationId\":null}:{\"id\":\"test-123\",\"timestamp\":1234567890000,\"eventType\":\"test\",\"payload\":{\"userId\":\"test-user\",\"data\":\"{}\",\"metadata\":{}},\"source\":\"test\",\"version\":\"1.0\"}"
    
    while true; do
        echo -n "Enter message (key:value): "
        read -r input
        
        if [ "$input" = "quit" ] || [ "$input" = "exit" ]; then
            print_message $GREEN "Exiting interactive mode..."
            break
        fi
        
        if [[ "$input" == *":"* ]]; then
            local key_part="${input%%:*}"
            local value_part="${input#*:}"
            
            publish_custom_message "$key_part" "$value_part"
        else
            print_message $RED "Invalid format. Please use key:value format."
        fi
    done
}

# Function to show help
show_help() {
    echo "Kafka Avro Message Publisher Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  sample [event-type] [user-id]"
    echo "                    Publish a single sample message"
    echo "  multiple [count]  Publish multiple sample messages (default: 5)"
    echo "  interactive       Start interactive mode for custom messages"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 sample                           # Publish default sample message"
    echo "  $0 sample user.created user-123     # Publish specific event type and user"
    echo "  $0 multiple 10                      # Publish 10 sample messages"
    echo "  $0 interactive                      # Start interactive mode"
    echo ""
    echo "Configuration:"
    echo "  • Topic: $TOPIC_NAME"
    echo "  • Kafka Bootstrap: $KAFKA_BOOTSTRAP_SERVER"
    echo "  • Schema Registry: $SCHEMA_REGISTRY_URL"
    echo "  • Key Subject: $KEY_SUBJECT"
    echo "  • Value Subject: $VALUE_SUBJECT"
}

# Main script logic
main() {
    check_services
    
    case "${1:-help}" in
        "sample")
            publish_sample_message "$2" "$3"
            ;;
        "multiple")
            publish_multiple_messages "$2"
            ;;
        "interactive")
            interactive_mode
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Run the main function with all arguments
main "$@"
