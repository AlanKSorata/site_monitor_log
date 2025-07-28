#!/bin/bash

# Error Handling and Recovery Library
# Provides comprehensive error handling, retry mechanisms, and system recovery

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/log-utils.sh"

# Error recovery configuration
DEFAULT_MAX_RETRIES=3
DEFAULT_INITIAL_BACKOFF=1
DEFAULT_MAX_BACKOFF=60
DEFAULT_BACKOFF_MULTIPLIER=2
DEFAULT_JITTER_ENABLED=true
DEFAULT_CIRCUIT_BREAKER_THRESHOLD=5
DEFAULT_CIRCUIT_BREAKER_TIMEOUT=300

# Error recovery state files
ERROR_STATE_DIR="$DATA_DIR/error-recovery"
CIRCUIT_BREAKER_STATE_FILE="$ERROR_STATE_DIR/circuit-breaker.state"
RETRY_STATE_FILE="$ERROR_STATE_DIR/retry.state"
RECOVERY_LOG_FILE="$LOG_DIR/recovery.log"

# Error categories and severity levels
declare -A ERROR_CATEGORIES=(
    ["NETWORK"]=1
    ["HTTP"]=2
    ["TIMEOUT"]=3
    ["CONFIG"]=4
    ["SYSTEM"]=5
    ["CONTENT"]=6
)

declare -A ERROR_SEVERITY=(
    ["CRITICAL"]=1
    ["HIGH"]=2
    ["MEDIUM"]=3
    ["LOW"]=4
)

#
# Initialize error recovery system
#
init_error_recovery() {
    # Ensure error recovery directories exist
    ensure_directory "$ERROR_STATE_DIR"
    
    # Create state files if they don't exist
    local recovery_files=("$CIRCUIT_BREAKER_STATE_FILE" "$RETRY_STATE_FILE" "$RECOVERY_LOG_FILE")
    
    for file in "${recovery_files[@]}"; do
        if [ ! -f "$file" ]; then
            touch "$file" 2>/dev/null || {
                log_error_detailed "Failed to create recovery file: $file"
                return 1
            }
        fi
    done
    
    log_debug_detailed "Error recovery system initialized" "error-recovery"
    return 0
}

#
# Calculate exponential backoff delay with jitter
# Arguments:
#   $1 - Attempt number (starting from 1)
#   $2 - Initial backoff in seconds (optional, defaults to DEFAULT_INITIAL_BACKOFF)
#   $3 - Max backoff in seconds (optional, defaults to DEFAULT_MAX_BACKOFF)
#   $4 - Backoff multiplier (optional, defaults to DEFAULT_BACKOFF_MULTIPLIER)
#   $5 - Enable jitter (optional, defaults to DEFAULT_JITTER_ENABLED)
# Returns:
#   Prints backoff delay in seconds
#
calculate_exponential_backoff() {
    local attempt="$1"
    local initial_backoff="${2:-$DEFAULT_INITIAL_BACKOFF}"
    local max_backoff="${3:-$DEFAULT_MAX_BACKOFF}"
    local multiplier="${4:-$DEFAULT_BACKOFF_MULTIPLIER}"
    local jitter_enabled="${5:-$DEFAULT_JITTER_ENABLED}"
    
    if [ -z "$attempt" ] || ! is_number "$attempt" || [ "$attempt" -lt 1 ]; then
        echo "$initial_backoff"
        return 1
    fi
    
    # Calculate exponential backoff: initial * (multiplier ^ (attempt - 1))
    local backoff="$initial_backoff"
    local i=1
    while [ $i -lt "$attempt" ]; do
        backoff=$((backoff * multiplier))
        i=$((i + 1))
    done
    
    # Cap at maximum backoff
    if [ "$backoff" -gt "$max_backoff" ]; then
        backoff="$max_backoff"
    fi
    
    # Add jitter if enabled (±25% random variation)
    if [ "$jitter_enabled" = true ]; then
        local jitter_range=$((backoff / 4))  # 25% of backoff
        local random_jitter=$((RANDOM % (jitter_range * 2 + 1) - jitter_range))
        backoff=$((backoff + random_jitter))
        
        # Ensure backoff is not negative
        if [ "$backoff" -lt 1 ]; then
            backoff=1
        fi
    fi
    
    echo "$backoff"
}

#
# Execute function with exponential backoff retry
# Arguments:
#   $1 - Function name to execute
#   $2 - Max retries (optional, defaults to DEFAULT_MAX_RETRIES)
#   $3 - Initial backoff (optional, defaults to DEFAULT_INITIAL_BACKOFF)
#   $4 - Context description for logging
#   $@ - Additional arguments passed to the function
# Returns:
#   Exit code of the function on success, or 1 on final failure
#
retry_with_exponential_backoff() {
    local function_name="$1"
    local max_retries="${2:-$DEFAULT_MAX_RETRIES}"
    local initial_backoff="${3:-$DEFAULT_INITIAL_BACKOFF}"
    local context="${4:-$function_name}"
    shift 4
    
    if [ -z "$function_name" ]; then
        log_error_detailed "Function name required for retry mechanism"
        return 1
    fi
    
    if ! command -v "$function_name" >/dev/null 2>&1; then
        log_error_detailed "Function not found: $function_name"
        return 1
    fi
    
    local attempt=1
    local max_attempts=$((max_retries + 1))
    
    while [ $attempt -le $max_attempts ]; do
        log_debug_detailed "Executing $context (attempt $attempt/$max_attempts)" "error-recovery"
        
        # Execute the function with provided arguments
        if "$function_name" "$@"; then
            if [ $attempt -gt 1 ]; then
                log_recovery_event "$context" "RETRY_SUCCESS" "Function succeeded after $attempt attempts"
            fi
            return 0
        fi
        
        local exit_code=$?
        
        # If this was the last attempt, fail
        if [ $attempt -eq $max_attempts ]; then
            log_recovery_event "$context" "RETRY_EXHAUSTED" "Function failed after $max_attempts attempts"
            return $exit_code
        fi
        
        # Calculate backoff delay
        local backoff_delay
        backoff_delay=$(calculate_exponential_backoff "$attempt" "$initial_backoff")
        
        log_recovery_event "$context" "RETRY_ATTEMPT" "Attempt $attempt failed, retrying in ${backoff_delay}s"
        
        # Wait before retry
        sleep "$backoff_delay"
        attempt=$((attempt + 1))
    done
    
    return 1
}

#
# Circuit breaker implementation
# Arguments:
#   $1 - Circuit name/identifier
#   $2 - Function to execute
#   $3 - Failure threshold (optional, defaults to DEFAULT_CIRCUIT_BREAKER_THRESHOLD)
#   $4 - Timeout in seconds (optional, defaults to DEFAULT_CIRCUIT_BREAKER_TIMEOUT)
#   $@ - Additional arguments passed to the function
# Returns:
#   Exit code of the function, or 2 if circuit is open
#
circuit_breaker() {
    local circuit_name="$1"
    local function_name="$2"
    local failure_threshold="${3:-$DEFAULT_CIRCUIT_BREAKER_THRESHOLD}"
    local timeout="${4:-$DEFAULT_CIRCUIT_BREAKER_TIMEOUT}"
    shift 4
    
    if [ -z "$circuit_name" ] || [ -z "$function_name" ]; then
        log_error_detailed "Circuit name and function name required for circuit breaker"
        return 1
    fi
    
    local circuit_state_key="${circuit_name}_state"
    local circuit_failures_key="${circuit_name}_failures"
    local circuit_last_failure_key="${circuit_name}_last_failure"
    
    # Get current circuit state
    local current_state
    current_state=$(get_circuit_breaker_state "$circuit_name" "state")
    local failure_count
    failure_count=$(get_circuit_breaker_state "$circuit_name" "failures")
    local last_failure_time
    last_failure_time=$(get_circuit_breaker_state "$circuit_name" "last_failure")
    
    # Default values if not set
    current_state="${current_state:-CLOSED}"
    failure_count="${failure_count:-0}"
    last_failure_time="${last_failure_time:-0}"
    
    local current_time
    current_time=$(get_epoch_timestamp)
    
    # Check if circuit should transition from OPEN to HALF_OPEN
    if [ "$current_state" = "OPEN" ]; then
        local time_since_failure=$((current_time - last_failure_time))
        if [ "$time_since_failure" -ge "$timeout" ]; then
            current_state="HALF_OPEN"
            set_circuit_breaker_state "$circuit_name" "state" "$current_state"
            log_recovery_event "$circuit_name" "CIRCUIT_HALF_OPEN" "Circuit breaker transitioning to half-open state"
        else
            log_recovery_event "$circuit_name" "CIRCUIT_BLOCKED" "Circuit breaker is open, blocking request"
            return 2
        fi
    fi
    
    # Execute the function
    if "$function_name" "$@"; then
        # Success - reset failure count if circuit was not closed
        if [ "$current_state" != "CLOSED" ]; then
            set_circuit_breaker_state "$circuit_name" "state" "CLOSED"
            set_circuit_breaker_state "$circuit_name" "failures" "0"
            log_recovery_event "$circuit_name" "CIRCUIT_CLOSED" "Circuit breaker closed after successful execution"
        fi
        return 0
    else
        local exit_code=$?
        
        # Failure - increment failure count
        failure_count=$((failure_count + 1))
        set_circuit_breaker_state "$circuit_name" "failures" "$failure_count"
        set_circuit_breaker_state "$circuit_name" "last_failure" "$current_time"
        
        # Check if we should open the circuit
        if [ "$failure_count" -ge "$failure_threshold" ]; then
            set_circuit_breaker_state "$circuit_name" "state" "OPEN"
            log_recovery_event "$circuit_name" "CIRCUIT_OPENED" "Circuit breaker opened after $failure_count failures"
        else
            log_recovery_event "$circuit_name" "CIRCUIT_FAILURE" "Circuit breaker recorded failure ($failure_count/$failure_threshold)"
        fi
        
        return $exit_code
    fi
}

#
# Get circuit breaker state
# Arguments:
#   $1 - Circuit name
#   $2 - State key (state, failures, last_failure)
#
get_circuit_breaker_state() {
    local circuit_name="$1"
    local state_key="$2"
    
    if [ -z "$circuit_name" ] || [ -z "$state_key" ]; then
        return 1
    fi
    
    local state_line
    state_line=$(grep "^${circuit_name}|${state_key}|" "$CIRCUIT_BREAKER_STATE_FILE" 2>/dev/null | tail -n1)
    
    if [ -n "$state_line" ]; then
        echo "$state_line" | cut -d'|' -f3
    fi
}

#
# Set circuit breaker state
# Arguments:
#   $1 - Circuit name
#   $2 - State key (state, failures, last_failure)
#   $3 - State value
#
set_circuit_breaker_state() {
    local circuit_name="$1"
    local state_key="$2"
    local state_value="$3"
    
    if [ -z "$circuit_name" ] || [ -z "$state_key" ] || [ -z "$state_value" ]; then
        return 1
    fi
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Remove existing entry for this circuit and key
    if [ -f "$CIRCUIT_BREAKER_STATE_FILE" ]; then
        grep -v "^${circuit_name}|${state_key}|" "$CIRCUIT_BREAKER_STATE_FILE" > "${CIRCUIT_BREAKER_STATE_FILE}.tmp" 2>/dev/null
        mv "${CIRCUIT_BREAKER_STATE_FILE}.tmp" "$CIRCUIT_BREAKER_STATE_FILE" 2>/dev/null
    fi
    
    # Add new entry
    echo "${circuit_name}|${state_key}|${state_value}|${timestamp}" >> "$CIRCUIT_BREAKER_STATE_FILE"
}

#
# Log recovery event
# Arguments:
#   $1 - Context/component
#   $2 - Event type
#   $3 - Event description
#
log_recovery_event() {
    local context="$1"
    local event_type="$2"
    local description="$3"
    
    if [ -z "$context" ] || [ -z "$event_type" ] || [ -z "$description" ]; then
        return 1
    fi
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Format: timestamp|context|event_type|description
    local log_entry="${timestamp}|${context}|${event_type}|${description}"
    
    # Write to recovery log
    if echo "$log_entry" >> "$RECOVERY_LOG_FILE" 2>/dev/null; then
        log_debug_detailed "Recovery event logged: $event_type for $context" "error-recovery"
    else
        log_error_detailed "Failed to write recovery log entry"
        return 1
    fi
    
    # Also log to main monitoring system based on event type
    case "$event_type" in
        "RETRY_EXHAUSTED"|"CIRCUIT_OPENED")
            log_monitoring_event "$context" "" "" "ERROR" "$description"
            ;;
        "RETRY_SUCCESS"|"CIRCUIT_CLOSED")
            log_monitoring_event "$context" "" "" "RECOVERY" "$description"
            ;;
        *)
            log_monitoring_event "$context" "" "" "INFO" "$description"
            ;;
    esac
    
    return 0
}

#
# Graceful degradation handler
# Arguments:
#   $1 - Service/component name
#   $2 - Primary function
#   $3 - Fallback function
#   $4 - Degradation context
#   $@ - Additional arguments passed to functions
# Returns:
#   Exit code of primary function on success, or fallback function result
#
graceful_degradation() {
    local service_name="$1"
    local primary_function="$2"
    local fallback_function="$3"
    local context="${4:-$service_name}"
    shift 4
    
    if [ -z "$service_name" ] || [ -z "$primary_function" ]; then
        log_error_detailed "Service name and primary function required for graceful degradation"
        return 1
    fi
    
    # Try primary function first
    if "$primary_function" "$@"; then
        return 0
    fi
    
    local primary_exit_code=$?
    log_recovery_event "$service_name" "DEGRADATION_TRIGGERED" "Primary function failed, attempting graceful degradation"
    
    # If fallback function is provided, try it
    if [ -n "$fallback_function" ] && command -v "$fallback_function" >/dev/null 2>&1; then
        if "$fallback_function" "$@"; then
            log_recovery_event "$service_name" "DEGRADATION_SUCCESS" "Fallback function succeeded"
            return 0
        else
            local fallback_exit_code=$?
            log_recovery_event "$service_name" "DEGRADATION_FAILED" "Both primary and fallback functions failed"
            return $fallback_exit_code
        fi
    else
        log_recovery_event "$service_name" "DEGRADATION_UNAVAILABLE" "No fallback function available"
        return $primary_exit_code
    fi
}

#
# System recovery mechanism for daemon restart
# Arguments:
#   $1 - Daemon name
#   $2 - Daemon script path
#   $3 - Max restart attempts (optional, defaults to 3)
#   $4 - Restart delay (optional, defaults to 5 seconds)
# Returns:
#   0 on successful restart, 1 on failure
#
daemon_recovery_restart() {
    local daemon_name="$1"
    local daemon_script="$2"
    local max_attempts="${3:-3}"
    local restart_delay="${4:-5}"
    
    if [ -z "$daemon_name" ] || [ -z "$daemon_script" ]; then
        log_error_detailed "Daemon name and script path required for recovery restart"
        return 1
    fi
    
    if [ ! -f "$daemon_script" ]; then
        log_error_detailed "Daemon script not found: $daemon_script"
        return 1
    fi
    
    log_recovery_event "$daemon_name" "RECOVERY_RESTART_INITIATED" "Starting daemon recovery restart procedure"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_recovery_event "$daemon_name" "RECOVERY_RESTART_ATTEMPT" "Restart attempt $attempt/$max_attempts"
        
        # Stop daemon if running
        if "$daemon_script" status >/dev/null 2>&1; then
            log_recovery_event "$daemon_name" "RECOVERY_STOPPING" "Stopping daemon for restart"
            "$daemon_script" stop >/dev/null 2>&1
            sleep 2
        fi
        
        # Start daemon
        if "$daemon_script" start >/dev/null 2>&1; then
            # Wait a moment and verify it's running
            sleep "$restart_delay"
            if "$daemon_script" status >/dev/null 2>&1; then
                log_recovery_event "$daemon_name" "RECOVERY_RESTART_SUCCESS" "Daemon successfully restarted on attempt $attempt"
                return 0
            else
                log_recovery_event "$daemon_name" "RECOVERY_RESTART_FAILED" "Daemon failed to start properly on attempt $attempt"
            fi
        else
            log_recovery_event "$daemon_name" "RECOVERY_START_FAILED" "Failed to start daemon on attempt $attempt"
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            local backoff_delay
            backoff_delay=$(calculate_exponential_backoff "$attempt" "$restart_delay")
            log_recovery_event "$daemon_name" "RECOVERY_RESTART_DELAY" "Waiting ${backoff_delay}s before next restart attempt"
            sleep "$backoff_delay"
        fi
    done
    
    log_recovery_event "$daemon_name" "RECOVERY_RESTART_EXHAUSTED" "All restart attempts failed"
    return 1
}

#
# Health check with recovery
# Arguments:
#   $1 - Service name
#   $2 - Health check function
#   $3 - Recovery function
#   $4 - Check interval (optional, defaults to 30 seconds)
#   $5 - Max consecutive failures (optional, defaults to 3)
# Returns:
#   Runs continuously, performing health checks and recovery
#
health_check_with_recovery() {
    local service_name="$1"
    local health_check_function="$2"
    local recovery_function="$3"
    local check_interval="${4:-30}"
    local max_failures="${5:-3}"
    
    if [ -z "$service_name" ] || [ -z "$health_check_function" ]; then
        log_error_detailed "Service name and health check function required"
        return 1
    fi
    
    local consecutive_failures=0
    
    log_recovery_event "$service_name" "HEALTH_CHECK_STARTED" "Health monitoring started with ${check_interval}s interval"
    
    while true; do
        if "$health_check_function"; then
            if [ $consecutive_failures -gt 0 ]; then
                log_recovery_event "$service_name" "HEALTH_CHECK_RECOVERED" "Service recovered after $consecutive_failures failures"
                consecutive_failures=0
            fi
        else
            consecutive_failures=$((consecutive_failures + 1))
            log_recovery_event "$service_name" "HEALTH_CHECK_FAILED" "Health check failed ($consecutive_failures/$max_failures)"
            
            if [ $consecutive_failures -ge $max_failures ]; then
                log_recovery_event "$service_name" "HEALTH_CHECK_THRESHOLD" "Max failures reached, triggering recovery"
                
                if [ -n "$recovery_function" ] && command -v "$recovery_function" >/dev/null 2>&1; then
                    if "$recovery_function"; then
                        log_recovery_event "$service_name" "HEALTH_RECOVERY_SUCCESS" "Recovery function succeeded"
                        consecutive_failures=0
                    else
                        log_recovery_event "$service_name" "HEALTH_RECOVERY_FAILED" "Recovery function failed"
                    fi
                else
                    log_recovery_event "$service_name" "HEALTH_RECOVERY_UNAVAILABLE" "No recovery function available"
                fi
            fi
        fi
        
        sleep "$check_interval"
    done
}

#
# Error categorization and severity assessment
# Arguments:
#   $1 - Error message
#   $2 - Error context
#   $3 - Exit code (optional)
# Returns:
#   Prints category|severity|recommended_action
#
categorize_error() {
    local error_message="$1"
    local error_context="$2"
    local exit_code="${3:-1}"
    
    if [ -z "$error_message" ]; then
        echo "UNKNOWN|HIGH|investigate"
        return 1
    fi
    
    local category="UNKNOWN"
    local severity="MEDIUM"
    local recommended_action="investigate"
    
    # Categorize based on error message patterns
    case "$error_message" in
        *"Could not resolve host"*|*"Name or service not known"*)
            category="NETWORK"
            severity="HIGH"
            recommended_action="check_dns"
            ;;
        *"Connection refused"*|*"Failed to connect"*)
            category="NETWORK"
            severity="HIGH"
            recommended_action="check_connectivity"
            ;;
        *"timeout"*|*"timed out"*)
            category="TIMEOUT"
            severity="MEDIUM"
            recommended_action="increase_timeout"
            ;;
        *"SSL"*|*"certificate"*|*"TLS"*)
            category="NETWORK"
            severity="HIGH"
            recommended_action="check_certificates"
            ;;
        *"HTTP"*|*"status"*)
            category="HTTP"
            severity="MEDIUM"
            recommended_action="check_endpoint"
            ;;
        *"configuration"*|*"config"*)
            category="CONFIG"
            severity="HIGH"
            recommended_action="check_configuration"
            ;;
        *"permission"*|*"access denied"*)
            category="SYSTEM"
            severity="HIGH"
            recommended_action="check_permissions"
            ;;
        *"disk"*|*"space"*|*"storage"*)
            category="SYSTEM"
            severity="CRITICAL"
            recommended_action="free_disk_space"
            ;;
        *"content"*|*"hash"*)
            category="CONTENT"
            severity="LOW"
            recommended_action="verify_content"
            ;;
    esac
    
    # Adjust severity based on exit code
    case "$exit_code" in
        2|130|143)  # SIGINT, SIGTERM, or timeout
            severity="MEDIUM"
            ;;
        1)
            # Keep current severity
            ;;
        *)
            if [ "$exit_code" -gt 1 ]; then
                severity="HIGH"
            fi
            ;;
    esac
    
    echo "${category}|${severity}|${recommended_action}"
}

#
# Comprehensive error handler
# Arguments:
#   $1 - Error message
#   $2 - Error context
#   $3 - Exit code (optional)
#   $4 - Recovery function (optional)
# Returns:
#   Logs error and optionally attempts recovery
#
handle_comprehensive_error() {
    local error_message="$1"
    local error_context="$2"
    local exit_code="${3:-1}"
    local recovery_function="$4"
    
    if [ -z "$error_message" ] || [ -z "$error_context" ]; then
        log_error_detailed "Error message and context required for comprehensive error handling"
        return 1
    fi
    
    # Categorize the error
    local error_info
    error_info=$(categorize_error "$error_message" "$error_context" "$exit_code")
    
    local category severity recommended_action
    IFS='|' read -r category severity recommended_action <<< "$error_info"
    
    # Log comprehensive error information
    local timestamp
    timestamp=$(get_timestamp)
    local error_entry="${timestamp}|${error_context}|${category}|${severity}|${exit_code}|${recommended_action}|${error_message}"
    
    if echo "$error_entry" >> "$ERROR_LOG_FILE" 2>/dev/null; then
        log_debug_detailed "Comprehensive error logged: $category/$severity for $error_context" "error-recovery"
    fi
    
    # Log to main monitoring system based on severity
    case "$severity" in
        "CRITICAL")
            log_monitoring_event "$error_context" "" "" "CRITICAL" "$error_message"
            ;;
        "HIGH")
            log_monitoring_event "$error_context" "" "" "ERROR" "$error_message"
            ;;
        "MEDIUM")
            log_monitoring_event "$error_context" "" "" "WARNING" "$error_message"
            ;;
        *)
            log_monitoring_event "$error_context" "" "" "INFO" "$error_message"
            ;;
    esac
    
    # Attempt recovery if function is provided and severity warrants it
    if [ -n "$recovery_function" ] && command -v "$recovery_function" >/dev/null 2>&1; then
        case "$severity" in
            "CRITICAL"|"HIGH")
                log_recovery_event "$error_context" "RECOVERY_INITIATED" "Attempting recovery for $severity error"
                if "$recovery_function" "$error_message" "$error_context" "$exit_code"; then
                    log_recovery_event "$error_context" "RECOVERY_SUCCESS" "Recovery function succeeded"
                    return 0
                else
                    log_recovery_event "$error_context" "RECOVERY_FAILED" "Recovery function failed"
                fi
                ;;
        esac
    fi
    
    return "$exit_code"
}

#
# Clean up old recovery data
# Arguments:
#   $1 - Retention days (optional, defaults to LOG_RETENTION_DAYS)
#
cleanup_recovery_data() {
    local retention_days="${1:-${LOG_RETENTION_DAYS:-30}}"
    
    if ! is_number "$retention_days" || [ "$retention_days" -lt 1 ]; then
        log_error_detailed "Invalid retention days for recovery cleanup: $retention_days"
        return 1
    fi
    
    log_debug_detailed "Cleaning up recovery data older than $retention_days days" "error-recovery"
    
    # Clean up recovery logs
    if [ -f "$RECOVERY_LOG_FILE" ]; then
        cleanup_old_log_entries "$RECOVERY_LOG_FILE" "$retention_days"
    fi
    
    # Clean up circuit breaker state (keep recent state, remove old entries)
    if [ -f "$CIRCUIT_BREAKER_STATE_FILE" ]; then
        cleanup_old_log_entries "$CIRCUIT_BREAKER_STATE_FILE" "$retention_days"
    fi
    
    # Clean up retry state
    if [ -f "$RETRY_STATE_FILE" ]; then
        cleanup_old_log_entries "$RETRY_STATE_FILE" "$retention_days"
    fi
    
    log_debug_detailed "Recovery data cleanup completed" "error-recovery"
    return 0
}

#
# Get recovery statistics
# Returns information about recovery events and circuit breaker states
#
get_recovery_statistics() {
    local recovery_dir="${1:-$ERROR_STATE_DIR}"
    
    if [ ! -d "$recovery_dir" ]; then
        echo "Recovery directory not found: $recovery_dir"
        return 1
    fi
    
    echo "=== Recovery Statistics ==="
    echo "Recovery Directory: $recovery_dir"
    echo ""
    
    # Circuit breaker statistics
    if [ -f "$CIRCUIT_BREAKER_STATE_FILE" ]; then
        echo "Circuit Breaker States:"
        local circuits
        circuits=$(cut -d'|' -f1 "$CIRCUIT_BREAKER_STATE_FILE" | sort -u)
        
        while IFS= read -r circuit; do
            if [ -n "$circuit" ]; then
                local state
                state=$(get_circuit_breaker_state "$circuit" "state")
                local failures
                failures=$(get_circuit_breaker_state "$circuit" "failures")
                printf "  %-20s: %s (%s failures)\n" "$circuit" "${state:-CLOSED}" "${failures:-0}"
            fi
        done <<< "$circuits"
        echo ""
    fi
    
    # Recovery event statistics
    if [ -f "$RECOVERY_LOG_FILE" ]; then
        echo "Recent Recovery Events (last 24 hours):"
        local cutoff_time
        cutoff_time=$(date -d "24 hours ago" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || cutoff_time=""
        
        if [ -n "$cutoff_time" ]; then
            local event_counts
            event_counts=$(awk -F'|' -v cutoff="$cutoff_time" '$1 > cutoff {print $3}' "$RECOVERY_LOG_FILE" | sort | uniq -c | sort -nr)
            
            if [ -n "$event_counts" ]; then
                echo "$event_counts" | while read -r count event_type; do
                    printf "  %-20s: %d\n" "$event_type" "$count"
                done
            else
                echo "  No recent recovery events"
            fi
        else
            echo "  Unable to calculate recent events"
        fi
    fi
    
    echo "=========================="
}

# Initialize error recovery system when this script is sourced
if ! init_error_recovery; then
    echo "WARNING: Failed to initialize error recovery system" >&2
fi

# Export key functions
export -f calculate_exponential_backoff retry_with_exponential_backoff circuit_breaker
export -f graceful_degradation daemon_recovery_restart health_check_with_recovery
export -f categorize_error handle_comprehensive_error log_recovery_event
export -f cleanup_recovery_data get_recovery_statistics

export ERROR_STATE_DIR CIRCUIT_BREAKER_STATE_FILE RETRY_STATE_FILE RECOVERY_LOG_FILE
export DEFAULT_MAX_RETRIES DEFAULT_INITIAL_BACKOFF DEFAULT_MAX_BACKOFF