#!/bin/bash

# Website Monitoring Daemon
# Simplified concurrent monitoring without process leaks

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"

# Source required libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/config-utils.sh"
source "$LIB_DIR/log-utils.sh"
source "$LIB_DIR/advanced-monitoring.sh"
source "$LIB_DIR/error-recovery.sh"

# Daemon configuration
DAEMON_NAME="website-monitor"
PID_FILE="$DATA_DIR/${DAEMON_NAME}.pid"
LOCK_FILE="$DATA_DIR/${DAEMON_NAME}.lock"
STATUS_FILE="$DATA_DIR/${DAEMON_NAME}.status"

# Default daemon settings
DEFAULT_DAEMON_MODE="foreground"
DEFAULT_LOG_TO_FILE=true
DEFAULT_MAINTENANCE_INTERVAL=3600  # 1 hour

# Global daemon state
DAEMON_RUNNING=false
DAEMON_SHUTDOWN_REQUESTED=false
DAEMON_PID=$$$
DAEMON_START_TIME=""
DAEMON_LAST_MAINTENANCE=""

# Website monitoring state
declare -A WEBSITE_LAST_CHECK=()
declare -A WEBSITE_NEXT_CHECK=()
declare -A WEBSITE_CHECK_COUNT=()
declare -A WEBSITE_ERROR_COUNT=()
declare -A WEBSITE_STATUS=()

# Simplified concurrent monitoring state
declare -A ACTIVE_CHECKS=()
ACTIVE_CHECK_COUNT=0

#
# Display usage information
#
show_usage() {
    cat << EOF
Usage: $0 <COMMAND> [OPTIONS]

Website monitoring daemon with lifecycle management.

COMMANDS:
    start       Start the monitoring daemon
    stop        Stop the monitoring daemon
    restart     Restart the monitoring daemon
    status      Show daemon status
    reload      Reload configuration without restart
    test        Test configuration and exit

OPTIONS:
    -d, --daemon        Run in daemon mode (background)
    -f, --foreground    Run in foreground mode (default)
    -c, --config FILE   Use specific configuration file
    -v, --verbose       Enable verbose logging
    -h, --help         Show this help message

EXIT CODES:
    0: Success
    1: General error
    2: Invalid arguments
    3: Daemon already running
    4: Daemon not running
    5: Configuration error
EOF
}

#
# Parse command line arguments
#
parse_arguments() {
    local command=""
    local daemon_mode="$DEFAULT_DAEMON_MODE"
    local config_file=""
    local verbose=false

    if [ $# -eq 0 ]; then
        show_usage
        exit 2
    fi

    # Check for help first
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi

    # First argument must be command
    command="$1"
    shift

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--daemon)
                daemon_mode="daemon"
                shift
                ;;
            -f|--foreground)
                daemon_mode="foreground"
                shift
                ;;
            -c|--config)
                config_file="$2"
                if [ ! -f "$config_file" ]; then
                    die "Configuration file not found: $config_file" 2
                fi
                shift 2
                ;;
            -v|--verbose)
                verbose=true
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
    case "$command" in
        start|stop|restart|status|reload|test)
            ;;
        *)
            die "Invalid command: $command" 2
            ;;
    esac

    # Export parsed values
    export DAEMON_COMMAND="$command"
    export DAEMON_MODE="$daemon_mode"
    export DAEMON_CONFIG_FILE="${config_file:-$CONFIG_DIR/monitor.conf}"
    export DAEMON_VERBOSE="$verbose"
}

#
# Initialize daemon environment
#
init_daemon() {
    # Set up logging
    if [ "$DAEMON_VERBOSE" = true ]; then
        set_log_level "DEBUG"
    fi

    # Create necessary directories
    create_data_directories

    # Initialize logging system
    init_logging_system

    # Load configuration
    load_monitor_config "$DAEMON_CONFIG_FILE"
    export_config_variables

    # Set daemon start time
    DAEMON_START_TIME=$(get_timestamp)

    log_info "Daemon environment initialized"
}

#
# Check if daemon is running
#
is_daemon_running() {
    if [ ! -f "$PID_FILE" ]; then
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)

    if [ -z "$pid" ]; then
        return 1
    fi

    # Check if process is actually running
    if kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        # Remove stale PID file
        rm -f "$PID_FILE"
        return 1
    fi
}

#
# Get daemon status information
#
get_daemon_status() {
    if is_daemon_running; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        
        echo "Status: Running"
        echo "PID: $pid"
        
        if [ -f "$STATUS_FILE" ]; then
            echo "--- Daemon Information ---"
            cat "$STATUS_FILE"
        fi
        
        return 0
    else
        echo "Status: Not running"
        return 1
    fi
}

#
# Create daemon status file
#
update_daemon_status() {
    local status_info=""
    
    status_info+="Start Time: $DAEMON_START_TIME\n"
    status_info+="Current Time: $(get_timestamp)\n"
    status_info+="Configuration: $DAEMON_CONFIG_FILE\n"
    status_info+="Log Level: $CURRENT_LOG_LEVEL\n"
    status_info+="Monitor Interval: ${MONITOR_INTERVAL}s\n"
    status_info+="Monitor Timeout: ${MONITOR_TIMEOUT}s\n"
    status_info+="Max Concurrent: $MAX_CONCURRENT_CHECKS\n"
    status_info+="Content Check: $CONTENT_CHECK_ENABLED\n"
    
    # Add concurrent monitoring statistics
    status_info+="Active Checks: $ACTIVE_CHECK_COUNT\n"
    
    # Add website statistics
    local total_websites=0
    local active_websites=0
    local error_websites=0
    
    for url in "${!WEBSITE_STATUS[@]}"; do
        total_websites=$((total_websites + 1))
        case "${WEBSITE_STATUS[$url]}" in
            "available")
                active_websites=$((active_websites + 1))
                ;;
            "unavailable"|"error")
                error_websites=$((error_websites + 1))
                ;;
        esac
    done
    
    status_info+="Total Websites: $total_websites\n"
    status_info+="Available: $active_websites\n"
    status_info+="Unavailable/Error: $error_websites\n"
    
    if [ -n "$DAEMON_LAST_MAINTENANCE" ]; then
        status_info+="Last Maintenance: $DAEMON_LAST_MAINTENANCE\n"
    fi
    
    echo -e "$status_info" > "$STATUS_FILE"
}

#
# Start daemon process
#
start_daemon() {
    if is_daemon_running; then
        echo "Daemon is already running"
        exit 3
    fi

    echo "Starting website monitoring daemon..."

    # Initialize daemon environment
    init_daemon

    # Create lock file
    if ! create_lock_file "$LOCK_FILE"; then
        die "Failed to create lock file" 1
    fi

    # Set up signal handlers for graceful shutdown
    setup_daemon_signal_handlers

    if [ "$DAEMON_MODE" = "daemon" ]; then
        # Fork to background
        (
            # Redirect output to log files
            exec >> "$MAIN_LOG_FILE" 2>&1
            
            # Run main daemon loop
            run_daemon_loop
        ) &
        
        local daemon_pid=$!
        echo "$daemon_pid" > "$PID_FILE"
        
        # Wait a moment to ensure daemon started successfully
        sleep 2
        
        if kill -0 "$daemon_pid" 2>/dev/null; then
            echo "Daemon started successfully (PID: $daemon_pid)"
            log_info "Website monitoring daemon started in background mode"
        else
            echo "Failed to start daemon"
            exit 1
        fi
    else
        # Run in foreground
        echo $$ > "$PID_FILE"
        echo "Running in foreground mode (Ctrl+C to stop)..."
        log_info "Website monitoring daemon started in foreground mode"
        run_daemon_loop
    fi
}

#
# Stop daemon process
#
stop_daemon() {
    local no_exit="${1:-}"
    
    if ! is_daemon_running; then
        echo "Daemon is not running"
        if [ "$no_exit" = "no_exit" ]; then
            return 4
        else
            exit 4
        fi
    fi

    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)

    echo "Stopping website monitoring daemon (PID: $pid)..."

    # Send TERM signal for graceful shutdown
    if kill -TERM "$pid" 2>/dev/null; then
        # Wait for graceful shutdown
        local wait_count=0
        while [ $wait_count -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            wait_count=$((wait_count + 1))
        done

        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            echo "Daemon did not stop gracefully, forcing shutdown..."
            kill -KILL "$pid" 2>/dev/null
        fi

        # Clean up files
        rm -f "$PID_FILE" "$LOCK_FILE" "$STATUS_FILE"
        echo "Daemon stopped successfully"
        return 0
    else
        echo "Failed to stop daemon"
        if [ "$no_exit" = "no_exit" ]; then
            return 1
        else
            exit 1
        fi
    fi
}

#
# Restart daemon process
#
restart_daemon() {
    echo "Restarting website monitoring daemon..."
    
    if is_daemon_running; then
        stop_daemon "no_exit"
        sleep 2
    fi
    
    start_daemon
}

#
# Test configuration
#
test_configuration() {
    echo "Testing configuration..."

    # Initialize environment
    init_daemon

    # Test monitor configuration
    echo "Monitor configuration:"
    print_config_summary

    # Test websites configuration
    echo ""
    echo "Testing websites configuration..."
    
    local websites_config
    if websites_config=$(read_websites_config "$CONFIG_DIR/websites.conf"); then
        local website_count=0
        while IFS= read -r website_line; do
            if [ -n "$website_line" ]; then
                website_count=$((website_count + 1))
                local url name interval timeout content_check
                IFS='|' read -r url name interval timeout content_check <<< "$website_line"
                echo "  $website_count. $name ($url) - Interval: ${interval}s, Timeout: ${timeout}s, Content Check: $content_check"
            fi
        done <<< "$websites_config"
        
        echo ""
        echo "Configuration test passed: $website_count website(s) configured"
    else
        echo "Configuration test failed: Invalid websites configuration"
        exit 5
    fi
}

#
# Set up signal handlers for daemon
#
setup_daemon_signal_handlers() {
    trap 'handle_daemon_shutdown' TERM INT
    trap 'handle_config_reload' USR1
    trap 'handle_maintenance_signal' USR2
}

#
# Handle daemon shutdown signal
#
handle_daemon_shutdown() {
    log_info "Shutdown signal received, initiating graceful shutdown..."
    DAEMON_SHUTDOWN_REQUESTED=true
    DAEMON_RUNNING=false
}

#
# Handle configuration reload signal
#
handle_config_reload() {
    log_info "Configuration reload signal received"
    
    # Reload monitor configuration
    if reload_monitor_config "$DAEMON_CONFIG_FILE"; then
        log_info "Configuration reloaded successfully"
        export_config_variables
        
        # Update status file
        update_daemon_status
    else
        log_warn "Configuration reload failed, continuing with current settings"
    fi
}

#
# Handle maintenance signal
#
handle_maintenance_signal() {
    log_info "Maintenance signal received, performing maintenance..."
    perform_daemon_maintenance
}

#
# Load websites from configuration
#
load_websites() {
    local websites_config
    
    # Clear existing website state
    WEBSITE_LAST_CHECK=()
    WEBSITE_NEXT_CHECK=()
    WEBSITE_CHECK_COUNT=()
    WEBSITE_ERROR_COUNT=()
    WEBSITE_STATUS=()
    
    if websites_config=$(read_websites_config "$CONFIG_DIR/websites.conf"); then
        local current_time
        current_time=$(get_epoch_timestamp)
        
        while IFS= read -r website_line; do
            if [ -n "$website_line" ]; then
                local url name interval timeout content_check
                IFS='|' read -r url name interval timeout content_check <<< "$website_line"
                
                # Validate URL before using as array key
                if [ -n "$url" ] && is_valid_url "$url"; then
                    # Initialize website state
                    WEBSITE_LAST_CHECK["$url"]=0
                    WEBSITE_NEXT_CHECK["$url"]=$current_time
                    WEBSITE_CHECK_COUNT["$url"]=0
                    WEBSITE_ERROR_COUNT["$url"]=0
                    WEBSITE_STATUS["$url"]="unknown"
                    
                    log_debug "Loaded website: $name ($url) - Interval: ${interval}s"
                else
                    log_warn "Skipping invalid URL: $url"
                fi
            fi
        done <<< "$websites_config"
        
        local website_count=${#WEBSITE_LAST_CHECK[@]}
        log_info "Loaded $website_count website(s) for monitoring"
        return 0
    else
        log_error "Failed to load websites configuration"
        return 1
    fi
}

#
# Check if website is due for monitoring
#
is_website_due_for_check() {
    local url="$1"
    local current_time
    current_time=$(get_epoch_timestamp)
    
    local next_check_time="${WEBSITE_NEXT_CHECK[$url]:-0}"
    
    [ "$current_time" -ge "$next_check_time" ]
}

#
# Get website configuration from loaded config
#
get_website_config() {
    local url="$1"
    local websites_config
    
    if websites_config=$(read_websites_config "$CONFIG_DIR/websites.conf"); then
        while IFS= read -r website_line; do
            if [ -n "$website_line" ]; then
                local config_url name interval timeout content_check
                IFS='|' read -r config_url name interval timeout content_check <<< "$website_line"
                
                if [ "$config_url" = "$url" ]; then
                    echo "$website_line"
                    return 0
                fi
            fi
        done <<< "$websites_config"
    fi
    
    return 1
}

#
# Simplified concurrent website check
#
check_website_simple() {
    local url="$1"
    local website_config

    # echo "$SCRIPT_DIR" # /mnt/e/pro_oriented/learn/tmp_space/lib
    
    if ! website_config=$(get_website_config "$url"); then
        log_error "Website configuration not found: $url"
        return 1
    fi
    
    local name interval timeout content_check
    IFS='|' read -r url name interval timeout content_check <<< "$website_config"
    
    # Prepare check command
    local check_cmd="$SCRIPT_DIR/../bin/check-website.sh"
    local check_args=()
    
    check_args+=("--timeout" "$timeout")
    check_args+=("--format" "structured")
    
    # Enable content check if configured
    case "$content_check" in
        true|1|yes)
            check_args+=("--content-check")
            ;;
    esac
    
    # Add verbose flag if daemon is in verbose mode
    if [ "$DAEMON_VERBOSE" = true ]; then
        check_args+=("--verbose")
    fi
    
    check_args+=("$url")
    
    log_debug "Checking website: $name ($url)"
    log_debug "Check command: $check_cmd ${check_args[*]}"
    log_debug "Working directory: $(pwd)"
    log_debug "Check script exists: $([ -f "$check_cmd" ] && echo "YES" || echo "NO")"
    
    # Execute check and capture result
    local check_result
    local check_output
    
    if check_output=$("$check_cmd" "${check_args[@]}" 2>&1); then
        check_result=0
        log_debug "Check command succeeded: $check_output"
    else
        check_result=$?
        log_debug "Check command failed (exit code: $check_result): $check_output"
    fi
    
    # Parse structured output
    local timestamp_result url_result status_code response_time content_hash status_result error_message
    IFS='|' read -r timestamp_result url_result status_code response_time content_hash status_result error_message <<< "$check_output"
    
    # Update website state
    local current_time
    current_time=$(get_epoch_timestamp)
    
    WEBSITE_LAST_CHECK["$url"]=$current_time
    WEBSITE_NEXT_CHECK["$url"]=$((current_time + interval))
    WEBSITE_CHECK_COUNT["$url"]=$((${WEBSITE_CHECK_COUNT["$url"]} + 1))
    
    if [ $check_result -eq 0 ]; then
        WEBSITE_STATUS["$url"]="available"
        WEBSITE_ERROR_COUNT["$url"]=0
        
        # Log successful check
        log_monitoring_event "$url" "$status_code" "$response_time" "UP" "Website check successful: $name"
        
        # Check for slow response
        if [ -n "$response_time" ] && is_number "$response_time" && [ "$response_time" -gt "$SLOW_RESPONSE_THRESHOLD" ]; then
            log_monitoring_event "$url" "$status_code" "$response_time" "SLOW" "Slow response detected: ${response_time}ms > ${SLOW_RESPONSE_THRESHOLD}ms"
        fi
    else
        WEBSITE_STATUS["$url"]="unavailable"
        WEBSITE_ERROR_COUNT["$url"]=$((${WEBSITE_ERROR_COUNT["$url"]} + 1))
        
        # Log failed check
        local log_message="Website check failed: $name"
        if [ -n "$error_message" ]; then
            log_message="$log_message - $error_message"
        fi
        
        log_monitoring_event "$url" "${status_code:-0}" "${response_time:-0}" "DOWN" "$log_message"
        
        # Log incident if this is a new failure or recurring issue
        local error_count=${WEBSITE_ERROR_COUNT["$url"]}
        if [ "$error_count" -eq 1 ]; then
            log_incident "$url" "DOWNTIME" "" "Website became unavailable"
        elif [ $((error_count % 5)) -eq 0 ]; then
            log_incident "$url" "PERSISTENT_DOWNTIME" "" "Website still unavailable after $error_count checks"
        fi
    fi
    
    log_debug "Website check completed: $name ($url) - Status: ${WEBSITE_STATUS["$url"]}, Errors: ${WEBSITE_ERROR_COUNT["$url"]}"
}

#
# Perform maintenance tasks with error recovery
#
perform_daemon_maintenance() {
    log_debug "Starting daemon maintenance"
    
    # Define maintenance functions with error handling
    maintenance_log_cleanup() {
        perform_log_maintenance
    }
    
    maintenance_temp_cleanup() {
        cleanup_temp_data
    }
    
    maintenance_recovery_cleanup() {
        cleanup_recovery_data
    }
    
    maintenance_status_update() {
        update_daemon_status
    }
    
    # Execute maintenance tasks with retry mechanism
    local maintenance_errors=()
    
    if ! retry_with_exponential_backoff maintenance_log_cleanup 2 1 "Log maintenance"; then
        maintenance_errors+=("Log maintenance failed")
    fi
    
    if ! retry_with_exponential_backoff maintenance_temp_cleanup 2 1 "Temp cleanup"; then
        maintenance_errors+=("Temp cleanup failed")
    fi
    
    if ! retry_with_exponential_backoff maintenance_recovery_cleanup 2 1 "Recovery cleanup"; then
        maintenance_errors+=("Recovery cleanup failed")
    fi
    
    if ! retry_with_exponential_backoff maintenance_status_update 2 1 "Status update"; then
        maintenance_errors+=("Status update failed")
    fi
    
    # Report maintenance results
    if [ ${#maintenance_errors[@]} -gt 0 ]; then
        for error in "${maintenance_errors[@]}"; do
            log_recovery_event "DAEMON_MAINTENANCE" "MAINTENANCE_ERROR" "$error"
        done
        log_warn "Daemon maintenance completed with errors: ${maintenance_errors[*]}"
    else
        log_debug "Daemon maintenance completed successfully"
    fi
    
    # Update last maintenance time
    DAEMON_LAST_MAINTENANCE=$(get_timestamp)
}

#
# Main daemon monitoring loop with simplified concurrent processing
#
run_daemon_loop() {
    DAEMON_RUNNING=true
    
    log_info "Starting main daemon loop with simplified concurrent monitoring"
    
    # Load websites configuration
    if ! load_websites; then
        die "Failed to load websites configuration" 5
    fi
    
    # Initialize maintenance timer
    local last_maintenance_time
    last_maintenance_time=$(get_epoch_timestamp)
    
    # Main monitoring loop
    while [ "$DAEMON_RUNNING" = true ] && [ "$DAEMON_SHUTDOWN_REQUESTED" = false ]; do
        local current_time
        current_time=$(get_epoch_timestamp)
        
        # Check websites that are due for monitoring
        local active_checks=0
        local max_concurrent=${MAX_CONCURRENT_CHECKS:-5}
        
        for url in "${!WEBSITE_LAST_CHECK[@]}"; do
            # Respect concurrent check limit
            if [ "$active_checks" -ge "$max_concurrent" ]; then
                break
            fi
            
            if is_website_due_for_check "$url"; then
                # Run check in background with simplified approach
                (check_website_simple "$url") &
                active_checks=$((active_checks + 1))
                ACTIVE_CHECK_COUNT=$active_checks
            fi
        done
        
        # Wait for background checks to complete
        wait
        ACTIVE_CHECK_COUNT=0
        
        # Perform maintenance if needed
        local maintenance_interval=${DEFAULT_MAINTENANCE_INTERVAL}
        if [ $((current_time - last_maintenance_time)) -ge $maintenance_interval ]; then
            perform_daemon_maintenance
            last_maintenance_time=$current_time
        fi
        
        # Update daemon status periodically
        update_daemon_status
        
        # Sleep for a short interval before next iteration
        sleep ${DEFAULT_MAINTENANCE_INTERVAL}
    done
    
    # Cleanup on exit
    log_info "Daemon loop exiting, performing cleanup..."
    remove_lock_file "$LOCK_FILE"
    rm -f "$PID_FILE" "$STATUS_FILE"
    
    log_info "Website monitoring daemon stopped"
}

#
# Daemon health check function
#
daemon_health_check() {
    # Check if daemon is running
    if ! is_daemon_running; then
        return 1
    fi
    
    # Check if status file is recent (updated within last 2 intervals)
    if [ -f "$STATUS_FILE" ]; then
        local status_age
        status_age=$(stat -c %Y "$STATUS_FILE" 2>/dev/null || stat -f %m "$STATUS_FILE" 2>/dev/null || echo 0)
        local current_time
        current_time=$(get_epoch_timestamp)
        local max_age=$((DEFAULT_MAINTENANCE_INTERVAL * 2))
        
        if [ $((current_time - status_age)) -gt $max_age ]; then
            log_recovery_event "DAEMON_HEALTH" "STALE_STATUS" "Status file is stale (age: $((current_time - status_age))s)"
            return 1
        fi
    else
        log_recovery_event "DAEMON_HEALTH" "MISSING_STATUS" "Status file is missing"
        return 1
    fi
    
    # Check if log files are being written to
    if [ -f "$MAIN_LOG_FILE" ]; then
        local log_age
        log_age=$(stat -c %Y "$MAIN_LOG_FILE" 2>/dev/null || stat -f %m "$MAIN_LOG_FILE" 2>/dev/null || echo 0)
        local current_time
        current_time=$(get_epoch_timestamp)
        local max_log_age=$((DEFAULT_MAINTENANCE_INTERVAL * 3))
        
        if [ $((current_time - log_age)) -gt $max_log_age ]; then
            log_recovery_event "DAEMON_HEALTH" "STALE_LOGS" "Log file is stale (age: $((current_time - log_age))s)"
            return 1
        fi
    fi
    
    return 0
}

#
# Daemon recovery function
#
daemon_recovery() {
    local error_message="$1"
    local error_context="$2"
    local exit_code="$3"
    
    log_recovery_event "DAEMON_RECOVERY" "RECOVERY_INITIATED" "Attempting daemon recovery: $error_message"
    
    # Try to restart the daemon
    if daemon_recovery_restart "$DAEMON_NAME" "$0" 3 10; then
        log_recovery_event "DAEMON_RECOVERY" "RECOVERY_SUCCESS" "Daemon successfully recovered"
        return 0
    else
        log_recovery_event "DAEMON_RECOVERY" "RECOVERY_FAILED" "Daemon recovery failed"
        return 1
    fi
}

#
# Start daemon health monitoring (runs in background)
#
start_daemon_health_monitoring() {
    if [ "$DAEMON_MODE" = "daemon" ]; then
        # Start health monitoring in background
        (
            health_check_with_recovery "$DAEMON_NAME" daemon_health_check daemon_recovery 60 3
        ) &
        
        local health_monitor_pid=$!
        echo "$health_monitor_pid" > "${PID_FILE}.health"
        log_info "Daemon health monitoring started (PID: $health_monitor_pid)"
    fi
}

#
# Stop daemon health monitoring
#
stop_daemon_health_monitoring() {
    local health_pid_file="${PID_FILE}.health"
    
    if [ -f "$health_pid_file" ]; then
        local health_pid
        health_pid=$(cat "$health_pid_file" 2>/dev/null)
        
        if [ -n "$health_pid" ] && kill -0 "$health_pid" 2>/dev/null; then
            kill -TERM "$health_pid" 2>/dev/null
            log_info "Daemon health monitoring stopped"
        fi
        
        rm -f "$health_pid_file"
    fi
}

#
# Enhanced daemon startup with health monitoring
#
start_daemon_enhanced() {
    if is_daemon_running; then
        echo "Daemon is already running"
        exit 3
    fi

    echo "Starting website monitoring daemon with enhanced error recovery..."

    # Initialize daemon environment
    init_daemon

    # Create lock file
    if ! create_lock_file "$LOCK_FILE"; then
        die "Failed to create lock file" 1
    fi

    # Set up signal handlers for graceful shutdown
    setup_daemon_signal_handlers

    if [ "$DAEMON_MODE" = "daemon" ]; then
        # Fork to background
        (
            # Redirect output to log files
            exec >> "$MAIN_LOG_FILE" 2>&1
            
            # Run main daemon loop
            run_daemon_loop
        ) &
        
        local daemon_pid=$!
        echo "$daemon_pid" > "$PID_FILE"
        
        # Wait a moment to ensure daemon started successfully
        sleep 2
        
        if kill -0 "$daemon_pid" 2>/dev/null; then
            echo "Daemon started successfully (PID: $daemon_pid)"
            log_info "Website monitoring daemon started in background mode"
            
            # Start health monitoring
            start_daemon_health_monitoring
        else
            echo "Failed to start daemon"
            exit 1
        fi
    else
        # Run in foreground
        echo $ > "$PID_FILE"
        echo "Running in foreground mode (Ctrl+C to stop)..."
        log_info "Website monitoring daemon started in foreground mode"
        run_daemon_loop
    fi
}

#
# Enhanced daemon stop with health monitoring cleanup
#
stop_daemon_enhanced() {
    local no_exit="${1:-}"
    
    if ! is_daemon_running; then
        echo "Daemon is not running"
        if [ "$no_exit" = "no_exit" ]; then
            return 4
        else
            exit 4
        fi
    fi

    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)

    echo "Stopping website monitoring daemon (PID: $pid)..."

    # Stop health monitoring first
    stop_daemon_health_monitoring

    # Send TERM signal for graceful shutdown
    if kill -TERM "$pid" 2>/dev/null; then
        # Wait for graceful shutdown
        local wait_count=0
        while [ $wait_count -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            wait_count=$((wait_count + 1))
        done

        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            echo "Daemon did not stop gracefully, forcing shutdown..."
            kill -KILL "$pid" 2>/dev/null
        fi

        # Clean up files
        rm -f "$PID_FILE" "$LOCK_FILE" "$STATUS_FILE"
        echo "Daemon stopped successfully"
        return 0
    else
        echo "Failed to stop daemon"
        if [ "$no_exit" = "no_exit" ]; then
            return 1
        else
            exit 1
        fi
    fi
}

#
# Main execution function
#
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute command
    case "$DAEMON_COMMAND" in
        start)
            start_daemon_enhanced
            ;;
        stop)
            stop_daemon_enhanced
            ;;
        restart)
            echo "Restarting website monitoring daemon..."
            if is_daemon_running; then
                stop_daemon_enhanced "no_exit"
                sleep 2
            fi
            start_daemon_enhanced
            ;;
        status)
            get_daemon_status
            echo ""
            get_recovery_statistics
            ;;
        reload)
            handle_config_reload
            ;;
        test)
            test_configuration
            ;;
        *)
            die "Unknown command: $DAEMON_COMMAND" 2
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi