#!/bin/bash

# Website Monitoring System - System Initialization Script
# Comprehensive system startup and initialization procedures

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"

# Source required libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/config-utils.sh"
source "$LIB_DIR/log-utils.sh"

# System initialization configuration
INIT_LOG_FILE="$LOG_DIR/system-init.log"
SYSTEM_STATUS_FILE="$DATA_DIR/system-status.txt"

# Default configuration files
DEFAULT_MONITOR_CONFIG="$CONFIG_DIR/monitor.conf"
DEFAULT_WEBSITES_CONFIG="$CONFIG_DIR/websites.conf"

#
# Display usage information
#
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] <COMMAND>

Website Monitoring System - System Initialization

COMMANDS:
    init            Initialize complete system from scratch
    setup           Set up system directories and configuration
    validate        Validate system configuration and dependencies
    start           Start all system components
    stop            Stop all system components
    restart         Restart all system components
    status          Show system status
    reset           Reset system to clean state
    help            Show this help message

OPTIONS:
    -c, --config DIR    Use custom configuration directory
    -d, --data DIR      Use custom data directory
    -v, --verbose       Enable verbose output
    -f, --force         Force operations (skip confirmations)
    -h, --help         Show this help message

EXAMPLES:
    $0 init                     # Initialize complete system
    $0 setup                    # Set up directories and basic config
    $0 validate                 # Validate current configuration
    $0 start                    # Start monitoring system
    $0 status                   # Show system status

EXIT CODES:
    0: Success
    1: General error
    2: Invalid arguments
    3: Configuration error
    4: System not ready
    5: Component failure
EOF
}

#
# Parse command line arguments
#
parse_arguments() {
    local command=""
    local config_dir=""
    local data_dir=""
    local verbose=false
    local force=false

    if [ $# -eq 0 ]; then
        show_usage
        exit 2
    fi

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            init|setup|validate|start|stop|restart|status|reset|help)
                if [ -n "$command" ]; then
                    die "Multiple commands specified. Only one command is allowed." 2
                fi
                command="$1"
                shift
                ;;
            -c|--config)
                config_dir="$2"
                if [ ! -d "$config_dir" ]; then
                    die "Configuration directory not found: $config_dir" 2
                fi
                shift 2
                ;;
            -d|--data)
                data_dir="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                die "Unknown option: $1" 2
                ;;
            *)
                die "Unexpected argument: $1" 2
                ;;
        esac
    done

    # Validate command
    if [ -z "$command" ]; then
        die "No command specified. Use --help for usage information." 2
    fi

    # Export parsed values
    export INIT_COMMAND="$command"
    export INIT_CONFIG_DIR="${config_dir:-$CONFIG_DIR}"
    export INIT_DATA_DIR="${data_dir:-$DATA_DIR}"
    export INIT_VERBOSE="$verbose"
    export INIT_FORCE="$force"
}

#
# Initialize logging for system initialization
#
init_system_logging() {
    # Ensure log directory exists
    ensure_directory "$LOG_DIR"
    
    # Initialize system init log
    echo "=== Website Monitoring System Initialization ===" > "$INIT_LOG_FILE"
    echo "Started at: $(get_timestamp)" >> "$INIT_LOG_FILE"
    echo "Command: $INIT_COMMAND" >> "$INIT_LOG_FILE"
    echo "=================================================" >> "$INIT_LOG_FILE"
    echo "" >> "$INIT_LOG_FILE"
    
    if [ "$INIT_VERBOSE" = true ]; then
        set_log_level "DEBUG"
        echo "Verbose logging enabled"
    fi
    
    log_info "System initialization logging started"
}

#
# Create default configuration files
#
create_default_configs() {
    log_info "Creating default configuration files..."
    
    # Ensure config directory exists
    ensure_directory "$INIT_CONFIG_DIR"
    
    # Create default monitor configuration
    if [ ! -f "$DEFAULT_MONITOR_CONFIG" ] || [ "$INIT_FORCE" = true ]; then
        log_info "Creating default monitor configuration: $DEFAULT_MONITOR_CONFIG"
        
        cat > "$DEFAULT_MONITOR_CONFIG" << 'EOF'
# Website Monitoring System - Main Configuration
# This file contains the primary configuration settings for the monitoring daemon

# Monitoring intervals (in seconds)
MONITOR_INTERVAL=60
MONITOR_TIMEOUT=30
SLOW_RESPONSE_THRESHOLD=5000

# Concurrent monitoring settings
MAX_CONCURRENT_CHECKS=5
CONCURRENT_TIMEOUT=45

# Content monitoring
CONTENT_CHECK_ENABLED=true
CONTENT_HASH_ALGORITHM=sha256

# Logging configuration
LOG_LEVEL=INFO
LOG_ROTATION_SIZE=10M
LOG_RETENTION_DAYS=30

# Error recovery settings
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=5
CIRCUIT_BREAKER_THRESHOLD=5
CIRCUIT_BREAKER_TIMEOUT=300

# Maintenance settings
MAINTENANCE_INTERVAL=3600
CLEANUP_TEMP_FILES=true
CLEANUP_OLD_LOGS=true

# Notification settings (future use)
ENABLE_NOTIFICATIONS=false
NOTIFICATION_EMAIL=""
NOTIFICATION_WEBHOOK=""
EOF
        
        log_info "Default monitor configuration created"
    else
        log_info "Monitor configuration already exists: $DEFAULT_MONITOR_CONFIG"
    fi
    
    # Create default websites configuration
    if [ ! -f "$DEFAULT_WEBSITES_CONFIG" ] || [ "$INIT_FORCE" = true ]; then
        log_info "Creating default websites configuration: $DEFAULT_WEBSITES_CONFIG"
        
        cat > "$DEFAULT_WEBSITES_CONFIG" << 'EOF'
# Website Monitoring Configuration
# Format: URL|Name|Interval|Timeout|ContentCheck
# 
# URL: The website URL to monitor (must include http:// or https://)
# Name: Friendly name for the website
# Interval: Check interval in seconds (overrides global setting)
# Timeout: Request timeout in seconds (overrides global setting)
# ContentCheck: Enable content change detection (true/false)

# Example configurations (uncomment and modify as needed):
# https://www.google.com|Google|60|10|false
# https://www.github.com|GitHub|120|15|true
# https://httpbin.org/status/200|HTTPBin Test|30|5|false

# Add your websites below:
EOF
        
        log_info "Default websites configuration created"
        log_warn "Please edit $DEFAULT_WEBSITES_CONFIG to add websites to monitor"
    else
        log_info "Websites configuration already exists: $DEFAULT_WEBSITES_CONFIG"
    fi
}

#
# Set up system directories
#
setup_system_directories() {
    log_info "Setting up system directories..."
    
    # Core directories
    local directories=(
        "$INIT_DATA_DIR"
        "$INIT_DATA_DIR/logs"
        "$INIT_DATA_DIR/content-hashes"
        "$INIT_DATA_DIR/reports"
        "$INIT_DATA_DIR/backups"
        "$INIT_DATA_DIR/temp"
        "$INIT_DATA_DIR/error-recovery"
        "$INIT_CONFIG_DIR"
    )
    
    for dir in "${directories[@]}"; do
        if ensure_directory "$dir"; then
            log_debug "Created/verified directory: $dir"
        else
            log_error "Failed to create directory: $dir"
            return 1
        fi
    done
    
    # Set appropriate permissions
    chmod 755 "$INIT_DATA_DIR"
    chmod 755 "$INIT_CONFIG_DIR"
    chmod 700 "$INIT_DATA_DIR/temp"
    
    log_info "System directories set up successfully"
    return 0
}

#
# Validate system dependencies
#
validate_dependencies() {
    log_info "Validating system dependencies..."
    
    local required_commands=(
        "curl"
        "grep"
        "awk"
        "sed"
        "sort"
        "uniq"
        "wc"
        "date"
        "sha256sum"
        "mktemp"
    )
    
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
            log_error "Required command not found: $cmd"
        else
            log_debug "Found required command: $cmd"
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_commands[*]}"
        echo "Please install the missing commands and try again."
        return 1
    fi
    
    log_info "All system dependencies validated successfully"
    return 0
}

#
# Validate configuration files
#
validate_configuration() {
    log_info "Validating system configuration..."
    
    # Check monitor configuration
    if [ ! -f "$DEFAULT_MONITOR_CONFIG" ]; then
        log_error "Monitor configuration file not found: $DEFAULT_MONITOR_CONFIG"
        return 1
    fi
    
    # Load and validate monitor config
    if ! load_monitor_config "$DEFAULT_MONITOR_CONFIG"; then
        log_error "Failed to load monitor configuration"
        return 1
    fi
    
    log_debug "Monitor configuration loaded successfully"
    
    # Check websites configuration
    if [ ! -f "$DEFAULT_WEBSITES_CONFIG" ]; then
        log_error "Websites configuration file not found: $DEFAULT_WEBSITES_CONFIG"
        return 1
    fi
    
    # Validate websites configuration
    local websites_config
    if ! websites_config=$(read_websites_config "$DEFAULT_WEBSITES_CONFIG"); then
        log_error "Failed to read websites configuration"
        return 1
    fi
    
    # Count configured websites
    local website_count=0
    while IFS= read -r website_line; do
        if [ -n "$website_line" ]; then
            website_count=$((website_count + 1))
            local url name interval timeout content_check
            IFS='|' read -r url name interval timeout content_check <<< "$website_line"
            
            if ! is_valid_url "$url"; then
                log_warn "Invalid URL in configuration: $url"
            else
                log_debug "Validated website: $name ($url)"
            fi
        fi
    done <<< "$websites_config"
    
    if [ "$website_count" -eq 0 ]; then
        log_warn "No websites configured for monitoring"
        log_warn "Please edit $DEFAULT_WEBSITES_CONFIG to add websites"
    else
        log_info "Configuration validation completed: $website_count website(s) configured"
    fi
    
    return 0
}

#
# Validate executable scripts
#
validate_executables() {
    log_info "Validating executable scripts..."
    
    local executables=(
        "$PROJECT_ROOT/bin/monitor.sh"
        "$PROJECT_ROOT/bin/check-website.sh"
        "$PROJECT_ROOT/bin/report-generator.sh"
        "$PROJECT_ROOT/bin/log-viewer.sh"
    )
    
    for script in "${executables[@]}"; do
        if [ ! -f "$script" ]; then
            log_error "Required script not found: $script"
            return 1
        fi
        
        if [ ! -x "$script" ]; then
            log_warn "Script not executable, fixing: $script"
            chmod +x "$script"
        fi
        
        log_debug "Validated executable: $script"
    done
    
    log_info "All executable scripts validated successfully"
    return 0
}

#
# Test system components
#
test_system_components() {
    log_info "Testing system components..."
    
    # Test monitor daemon configuration
    log_debug "Testing monitor daemon configuration..."
    if ! "$PROJECT_ROOT/bin/monitor.sh" test >/dev/null 2>&1; then
        log_error "Monitor daemon configuration test failed"
        return 1
    fi
    
    # Test website checker with a simple URL
    log_debug "Testing website checker..."
    if ! "$PROJECT_ROOT/bin/check-website.sh" --timeout 5 "https://httpbin.org/status/200" >/dev/null 2>&1; then
        log_warn "Website checker test failed (network connectivity may be limited)"
    fi
    
    # Test report generator
    log_debug "Testing report generator..."
    if ! "$PROJECT_ROOT/bin/report-generator.sh" --help >/dev/null 2>&1; then
        log_error "Report generator test failed"
        return 1
    fi
    
    # Test log viewer
    log_debug "Testing log viewer..."
    if ! "$PROJECT_ROOT/bin/log-viewer.sh" --help >/dev/null 2>&1; then
        log_error "Log viewer test failed"
        return 1
    fi
    
    log_info "System component tests completed successfully"
    return 0
}

#
# Update system status
#
update_system_status() {
    local status="$1"
    local message="$2"
    
    cat > "$SYSTEM_STATUS_FILE" << EOF
System Status: $status
Last Updated: $(get_timestamp)
Message: $message
Configuration Directory: $INIT_CONFIG_DIR
Data Directory: $INIT_DATA_DIR
Monitor Config: $DEFAULT_MONITOR_CONFIG
Websites Config: $DEFAULT_WEBSITES_CONFIG
EOF
    
    log_info "System status updated: $status - $message"
}

#
# Initialize complete system
#
init_system() {
    log_info "Starting complete system initialization..."
    
    # Step 1: Set up directories
    if ! setup_system_directories; then
        update_system_status "FAILED" "Directory setup failed"
        return 1
    fi
    
    # Step 2: Create default configurations
    if ! create_default_configs; then
        update_system_status "FAILED" "Configuration creation failed"
        return 1
    fi
    
    # Step 3: Validate dependencies
    if ! validate_dependencies; then
        update_system_status "FAILED" "Dependency validation failed"
        return 1
    fi
    
    # Step 4: Validate configuration
    if ! validate_configuration; then
        update_system_status "FAILED" "Configuration validation failed"
        return 1
    fi
    
    # Step 5: Validate executables
    if ! validate_executables; then
        update_system_status "FAILED" "Executable validation failed"
        return 1
    fi
    
    # Step 6: Test components
    if ! test_system_components; then
        update_system_status "FAILED" "Component testing failed"
        return 1
    fi
    
    update_system_status "INITIALIZED" "System initialization completed successfully"
    
    log_info "=== System Initialization Complete ==="
    log_info "Configuration directory: $INIT_CONFIG_DIR"
    log_info "Data directory: $INIT_DATA_DIR"
    log_info "Next steps:"
    log_info "  1. Edit $DEFAULT_WEBSITES_CONFIG to add websites to monitor"
    log_info "  2. Run '$0 start' to start the monitoring system"
    log_info "  3. Use '$SCRIPT_DIR/log-viewer.sh' to view monitoring status"
    
    return 0
}

#
# Set up system (directories and basic config only)
#
setup_system() {
    log_info "Setting up system directories and basic configuration..."
    
    if ! setup_system_directories; then
        update_system_status "SETUP_FAILED" "Directory setup failed"
        return 1
    fi
    
    if ! create_default_configs; then
        update_system_status "SETUP_FAILED" "Configuration creation failed"
        return 1
    fi
    
    update_system_status "SETUP_COMPLETE" "Basic system setup completed"
    
    log_info "System setup completed successfully"
    log_info "Next steps:"
    log_info "  1. Run '$0 validate' to validate the configuration"
    log_info "  2. Edit configuration files as needed"
    log_info "  3. Run '$0 init' for complete initialization"
    
    return 0
}

#
# Validate system
#
validate_system() {
    log_info "Validating complete system..."
    
    local validation_errors=0
    
    # Validate dependencies
    if ! validate_dependencies; then
        validation_errors=$((validation_errors + 1))
    fi
    
    # Validate configuration
    if ! validate_configuration; then
        validation_errors=$((validation_errors + 1))
    fi
    
    # Validate executables
    if ! validate_executables; then
        validation_errors=$((validation_errors + 1))
    fi
    
    # Test components
    if ! test_system_components; then
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        update_system_status "VALIDATED" "System validation completed successfully"
        log_info "System validation completed successfully"
        log_info "System is ready to start monitoring"
        return 0
    else
        update_system_status "VALIDATION_FAILED" "System validation failed with $validation_errors error(s)"
        log_error "System validation failed with $validation_errors error(s)"
        return 1
    fi
}

#
# Start system components
#
start_system() {
    log_info "Starting system components..."
    
    # Check if system is initialized
    if [ ! -f "$SYSTEM_STATUS_FILE" ]; then
        log_error "System not initialized. Run '$0 init' first."
        return 1
    fi
    
    # Start monitor daemon in daemon mode
    log_info "Starting monitor daemon in background mode..."
    if "$PROJECT_ROOT/bin/monitor.sh" start --daemon; then
        log_info "Monitor daemon started successfully"
    else
        local exit_code=$?
        log_error "Failed to start monitor daemon (exit code: $exit_code)"
        update_system_status "START_FAILED" "Monitor daemon failed to start (exit code: $exit_code)"
        return 1
    fi
    
    # Wait a moment for daemon to initialize
    sleep 3
    
    # Verify daemon is running
    if "$PROJECT_ROOT/bin/monitor.sh" status >/dev/null 2>&1; then
        update_system_status "RUNNING" "System started successfully"
        log_info "System started successfully"
        log_info "Use '$PROJECT_ROOT/bin/log-viewer.sh' to monitor system status"
        return 0
    else
        log_error "Monitor daemon failed to start properly or stopped unexpectedly"
        log_info "Check logs in data/logs/ for more details"
        update_system_status "START_FAILED" "Monitor daemon not running after startup"
        return 1
    fi
}

#
# Stop system components
#
stop_system() {
    log_info "Stopping system components..."
    
    # Check if system is running
    if [ ! -f "$SYSTEM_STATUS_FILE" ]; then
        log_warn "System status file not found. System may not be running."
    fi
    
    # Stop monitor daemon
    log_info "Stopping monitor daemon..."
    if "$PROJECT_ROOT/bin/monitor.sh" stop; then
        log_info "Monitor daemon stopped successfully"
        update_system_status "STOPPED" "System stopped successfully"
        return 0
    else
        # Check if daemon was already stopped
        if ! "$PROJECT_ROOT/bin/monitor.sh" status >/dev/null 2>&1; then
            log_info "Monitor daemon was already stopped"
            update_system_status "STOPPED" "System stopped (daemon was already stopped)"
            return 0
        else
            log_error "Failed to stop monitor daemon"
            update_system_status "STOP_FAILED" "Failed to stop monitor daemon"
            return 1
        fi
    fi
}

#
# Restart system components
#
restart_system() {
    log_info "Restarting system components..."
    
    # Stop and start monitor daemon in daemon mode
    log_info "Restarting monitor daemon..."
    
    # First stop the daemon if it's running
    "$PROJECT_ROOT/bin/monitor.sh" stop >/dev/null 2>&1 || true
    
    # Wait a moment for cleanup
    sleep 1
    
    # Start daemon in daemon mode
    if "$PROJECT_ROOT/bin/monitor.sh" start --daemon; then
        log_info "Monitor daemon restarted successfully"
        
        # Wait a moment for daemon to initialize
        sleep 3
        
        # Verify daemon is running
        if "$PROJECT_ROOT/bin/monitor.sh" status >/dev/null 2>&1; then
            update_system_status "RUNNING" "System restarted successfully"
            log_info "System restarted successfully"
            return 0
        else
            log_error "Monitor daemon failed to restart properly"
            update_system_status "RESTART_FAILED" "Monitor daemon not running after restart"
            return 1
        fi
    else
        local exit_code=$?
        log_error "Failed to restart monitor daemon (exit code: $exit_code)"
        update_system_status "RESTART_FAILED" "Failed to restart monitor daemon (exit code: $exit_code)"
        return 1
    fi
}

#
# Show system status
#
show_system_status() {
    echo "=== Website Monitoring System Status ==="
    echo ""
    
    # Show system status file if it exists
    if [ -f "$SYSTEM_STATUS_FILE" ]; then
        echo "System Information:"
        cat "$SYSTEM_STATUS_FILE"
        echo ""
    else
        echo "System Status: NOT INITIALIZED"
        echo "Run '$0 init' to initialize the system"
        echo ""
    fi
    
    # Show daemon status
    echo "Daemon Status:"
    if "$PROJECT_ROOT/bin/monitor.sh" status 2>/dev/null; then
        echo ""
    else
        echo "Monitor daemon is not running"
        echo ""
    fi
    
    # Show configuration summary
    echo "Configuration Summary:"
    if [ -f "$DEFAULT_MONITOR_CONFIG" ]; then
        echo "  Monitor Config: $DEFAULT_MONITOR_CONFIG (exists)"
    else
        echo "  Monitor Config: $DEFAULT_MONITOR_CONFIG (missing)"
    fi
    
    if [ -f "$DEFAULT_WEBSITES_CONFIG" ]; then
        local website_count=0
        if [ -s "$DEFAULT_WEBSITES_CONFIG" ]; then
            website_count=$(grep -v '^#' "$DEFAULT_WEBSITES_CONFIG" | grep -v '^[[:space:]]*$' | wc -l)
        fi
        echo "  Websites Config: $DEFAULT_WEBSITES_CONFIG ($website_count websites)"
    else
        echo "  Websites Config: $DEFAULT_WEBSITES_CONFIG (missing)"
    fi
    
    echo ""
    echo "Available Commands:"
    echo "  $0 start    - Start monitoring system"
    echo "  $0 stop     - Stop monitoring system"
    echo "  $0 restart  - Restart monitoring system"
    echo "  $PROJECT_ROOT/bin/log-viewer.sh - View monitoring logs"
    echo "  $PROJECT_ROOT/bin/report-generator.sh - Generate reports"
}

#
# Reset system to clean state
#
reset_system() {
    log_info "Resetting system to clean state..."
    
    if [ "$INIT_FORCE" != true ]; then
        echo "This will remove all monitoring data and reset the system."
        read -p "Are you sure you want to continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Reset cancelled by user"
            return 0
        fi
    fi
    
    # Stop system if running
    log_info "Stopping system components..."
    "$SCRIPT_DIR/monitor.sh" stop 2>/dev/null || true
    
    # Remove data files (but keep configuration)
    log_info "Cleaning data directories..."
    rm -rf "$INIT_DATA_DIR/logs"/*
    rm -rf "$INIT_DATA_DIR/content-hashes"/*
    rm -rf "$INIT_DATA_DIR/reports"/*
    rm -rf "$INIT_DATA_DIR/temp"/*
    rm -rf "$INIT_DATA_DIR/error-recovery"/*
    rm -f "$INIT_DATA_DIR"/*.pid
    rm -f "$INIT_DATA_DIR"/*.lock
    rm -f "$INIT_DATA_DIR"/*.status
    
    # Remove system status
    rm -f "$SYSTEM_STATUS_FILE"
    
    update_system_status "RESET" "System reset to clean state"
    
    log_info "System reset completed successfully"
    log_info "Configuration files have been preserved"
    log_info "Run '$0 init' to reinitialize the system"
    
    return 0
}

#
# Main execution function
#
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Handle help command
    if [ "$INIT_COMMAND" = "help" ]; then
        show_usage
        exit 0
    fi
    
    # Initialize logging
    init_system_logging
    
    # Execute command
    case "$INIT_COMMAND" in
        init)
            init_system
            ;;
        setup)
            setup_system
            ;;
        validate)
            validate_system
            ;;
        start)
            start_system
            ;;
        stop)
            stop_system
            ;;
        restart)
            restart_system
            ;;
        status)
            show_system_status
            ;;
        reset)
            reset_system
            ;;
        *)
            die "Unknown command: $INIT_COMMAND" 2
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi