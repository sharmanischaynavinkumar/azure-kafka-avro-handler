#!/bin/bash

# Kafka Infrastructure Setup Script
# This script manages the Docker containers for Kafka ecosystem

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

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        print_message $RED "Error: Docker is not running. Please start Docker and try again."
        exit 1
    fi
}

# Function to start the infrastructure
start_infrastructure() {
    print_message $BLUE "Starting Kafka infrastructure..."
    
    # Start all services
    docker-compose -f docker-compose.yml up -d

    print_message $GREEN "Infrastructure started successfully!"
    print_message $YELLOW "Services starting up. This may take a few minutes..."
    
    # Wait for services to be healthy
    print_message $BLUE "Waiting for services to be ready..."
    
    # Check Kafka health - wait for port to be available
    echo "Checking Kafka..."
    until docker-compose exec -T kafka kafka-broker-api-versions --bootstrap-server kafka:9092 >/dev/null 2>&1; do
        echo "Waiting for Kafka..."
        sleep 3
    done

    # Check Schema Registry health
    echo "Checking Schema Registry..."
    until curl -f host.docker.internal:8081/ >/dev/null 2>&1; do
        echo "Waiting for Schema Registry..."
        sleep 3
    done

    print_message $GREEN "All services are ready!"

    show_status

    create_topic incoming-topic
    create_topic response-topic

    create_schema "incoming-topic-value" "schemas/incoming-topic-value.avsc"
    create_schema "incoming-topic-key" "schemas/incoming-topic-key.avsc"
    create_schema "response-topic-key" "schemas/response-topic-key.avsc"
    create_schema "response-topic-value" "schemas/response-topic-value.avsc"

    docker network connect azure-kafka-avro-handler_default azure-kafka-avro-handler
}

# Function to stop the infrastructure
stop_infrastructure() {
    print_message $BLUE "Stopping Kafka infrastructure..."
    docker network disconnect azure-kafka-avro-handler_default azure-kafka-avro-handler
    docker-compose down
    print_message $GREEN "Infrastructure stopped successfully!"
}

# Function to restart the infrastructure
restart_infrastructure() {
    print_message $BLUE "Restarting Kafka infrastructure..."
    stop_infrastructure
    start_infrastructure
    print_message $GREEN "Infrastructure restarted successfully!"
}

# Function to show infrastructure status
show_status() {
    print_message $BLUE "Infrastructure Status:"
    echo ""
    docker-compose ps
    echo ""
    print_message $GREEN "Service URLs:"
    echo "  • Schema Registry: http://host.docker.internal:8081"
    echo "  • Kafka Broker:    kafka:9092"
    echo ""
    print_message $YELLOW "Connection strings for your Azure Function:"
    echo "  • Kafka Bootstrap: kafka:9092"
    echo "  • Schema Registry: http://host.docker.internal:8081"
}

# Function to clean up (remove containers and volumes)
cleanup() {
    print_message $YELLOW "Warning: This will remove all containers and volumes (data will be lost)!"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_message $BLUE "Cleaning up infrastructure..."
        
        # Check if devcontainer is connected to the network and disconnect it
        local network_name="azure-kafka-avro-handler_default"
        if docker network ls --format "{{.Name}}" | grep -q "^${network_name}$"; then
            print_message $BLUE "Checking for devcontainer connections to network..."
            
            # Check if azure-kafka-avro-handler container is connected to the network
            if docker network inspect "$network_name" --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' 2>/dev/null | grep -q "azure-kafka-avro-handler"; then
                print_message $BLUE "Disconnecting devcontainer from network..."
                docker network disconnect "$network_name" azure-kafka-avro-handler 2>/dev/null || print_message $YELLOW "Could not disconnect devcontainer (may already be disconnected)"
            fi
        fi
        
        # Now safely bring down the infrastructure
        docker-compose down -v

        print_message $GREEN "Cleanup completed!"
    else
        print_message $YELLOW "Cleanup cancelled."
    fi
}

# Function to view logs
view_logs() {
    local service=$1
    if [ -z "$service" ]; then
        print_message $BLUE "Showing logs for all services..."
        docker-compose logs -f
    else
        print_message $BLUE "Showing logs for $service..."
        docker-compose logs -f "$service"
    fi
}

# Function to create a Kafka topic
create_topic() {
    local topic_name=$1
    
    if [ -z "$topic_name" ]; then
        print_message $RED "Error: Topic name is required"
        echo "Usage: create_topic <topic-name>"
        return 1
    fi
    
    print_message $BLUE "Creating Kafka topic: $topic_name"
    
    # Check if Kafka is running
    if ! docker-compose ps kafka | grep -q "Up"; then
        print_message $RED "Error: Kafka is not running. Please start the infrastructure first."
        return 1
    fi
    
    # Check if topic already exists
    if docker-compose exec -T kafka kafka-topics --bootstrap-server kafka:9092 --list | grep -q "^${topic_name}$"; then
        print_message $YELLOW "Topic '$topic_name' already exists!"
        return 0
    fi
    
    # Create the topic
    if docker-compose exec -T kafka kafka-topics --bootstrap-server kafka:9092 --create --if-not-exists --topic "$topic_name" --partitions 3 --replication-factor 1; then
        print_message $GREEN "Topic '$topic_name' created successfully!"
    else
        print_message $RED "Failed to create topic '$topic_name'"
        return 1
    fi
    
    # List all topics after creation
    print_message $BLUE "Current topics:"
    docker-compose exec -T kafka kafka-topics --bootstrap-server kafka:9092 --list
}

# Function to create an Avro schema
create_schema() {
    local subject=$1
    local schema_file_path=$2
    
    if [ -z "$subject" ] || [ -z "$schema_file_path" ]; then
        print_message $RED "Error: Both subject and schema file path are required"
        echo "Usage: create_schema <subject> <schema-file-path>"
        return 1
    fi
    
    # Check if schema file exists
    if [ ! -f "$schema_file_path" ]; then
        print_message $RED "Error: Schema file '$schema_file_path' not found"
        return 1
    fi
    
    print_message $BLUE "Creating Avro schema for subject: $subject"
    
    # Check if Schema Registry is running
    if ! docker-compose ps schema-registry | grep -q "Up"; then
        print_message $RED "Error: Schema Registry is not running. Please start the infrastructure first."
        return 1
    fi
    
    # Check if schema already exists by trying to get the latest version
    print_message $BLUE "Checking if schema exists for subject '$subject'..."
    
    local schema_exists=false
    if curl -s -f "http://host.docker.internal:8081/subjects/$subject/versions/latest" >/dev/null 2>&1; then
        schema_exists=true
        print_message $YELLOW "Schema for subject '$subject' already exists!"
        
        # Get current version info
        local current_version=$(curl -s "http://host.docker.internal:8081/subjects/$subject/versions/latest" | grep -o '"version":[0-9]*' | cut -d':' -f2)
        print_message $BLUE "Current version: $current_version"
        return 0
    fi
    
    # Read and prepare the schema
    local schema_content=$(cat "$schema_file_path" | jq -Rs .)

    # Create the schema
    print_message $BLUE "Registering new schema..."
    
    local response=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/vnd.schemaregistry.v1+json" \
        --data "{\"schema\":${schema_content}}" \
        "http://host.docker.internal:8081/subjects/$subject/versions")
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        local schema_id=$(echo "$response_body" | grep -o '"id":[0-9]*' | cut -d':' -f2)
        print_message $GREEN "Schema created successfully!"
        print_message $GREEN "Subject: $subject"
        print_message $GREEN "Schema ID: $schema_id"
    else
        print_message $RED "Failed to create schema. HTTP Code: $http_code"
        print_message $RED "Response: $response_body"
        return 1
    fi
    
    # List all subjects after creation
    print_message $BLUE "Current subjects:"
    curl -s "http://host.docker.internal:8081/subjects" | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | sed 's/,/\n/g'
}

# Function to show help
show_help() {
    echo "Kafka Infrastructure Management Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start     Start all infrastructure services"
    echo "  stop      Stop all infrastructure services"
    echo "  restart   Restart all infrastructure services"
    echo "  status    Show status of all services"
    echo "  logs      Show logs for all services"
    echo "  logs <service>  Show logs for specific service"
    echo "  topic <name>  Create a Kafka topic with the specified name"
    echo "  schema <subject> <schema-file>  Create an Avro schema in Schema Registry"
    echo "  cleanup   Remove all containers and volumes (WARNING: Data loss!)"
    echo "  help      Show this help message"
    echo ""
    echo "Services: zookeeper, kafka, schema-registry, kafka-ui"
    echo ""
    echo "Recommended workflow:"
    echo "  1. Start your devcontainer in VS Code"
    echo "  2. $0 start      # Starts all services"
}

# Main script logic
main() {
    check_docker
    
    case "${1:-help}" in
        "start")
            start_infrastructure
            ;;
        "stop")
            stop_infrastructure
            ;;
        "restart")
            restart_infrastructure
            ;;
        "status")
            show_status
            ;;
        "logs")
            view_logs "$2"
            ;;
        "topic")
            if [ -z "$2" ]; then
                print_message $RED "Error: Topic name is required"
                echo "Usage: $0 topic <topic-name>"
                exit 1
            fi
            create_topic "$2"
            ;;
        "schema")
            if [ -z "$2" ] || [ -z "$3" ]; then
                print_message $RED "Error: Both subject and schema file path are required"
                echo "Usage: $0 schema <subject> <schema-file-path>"
                exit 1
            fi
            create_schema "$2" "$3"
            ;;
        "cleanup")
            cleanup
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Run the main function with all arguments
main "$@"
