#!/bin/bash

# Azure Functions Start Script
# This script starts the Azure Functions runtime with proper environment setup

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
FUNCTION_APP_DIR="/workspaces/azure-kafka-avro-handler"
PYTHON_PATH="/workspaces/azure-kafka-avro-handler/"

print_message $BLUE "Starting Azure Functions Runtime..."

# Set Python path for module imports
export PYTHONPATH="$PYTHON_PATH"
print_message $YELLOW "PYTHONPATH set to: $PYTHONPATH"


# Change to function app directory
cd "$FUNCTION_APP_DIR"

print_message $GREEN "Starting Azure Functions Core Tools..."
print_message $BLUE "Function app directory: $(pwd)"
print_message $BLUE "Python version: $(python --version)"
print_message $BLUE "Func version: $(func --version)"

# Start the Azure Functions runtime
print_message $YELLOW "Starting function host..."
print_message $BLUE "Access your function at: http://localhost:7071"
print_message $BLUE "Press Ctrl+C to stop the function host"

# Run with verbose logging
func start --verbose
