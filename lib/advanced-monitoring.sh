#!/bin/bash

# Advanced Monitoring Features Library
# Provides slow response detection, average response time calculations, and alert mechanisms

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/log-utils.sh"

# Advanced monitoring configuration
RESPONSE_TIME_LOG_FILE="$LOG_DIR/response-times.log"
ALERT_LOG_FILE="$LOG_DIR/alerts.log"
PERFORMANCE_STATS_FILE="$DATA_DIR/performance-stats.txt"

# Default thresholds (can be overridden by configuration)
DEFAULT_SLOW_RESPONSE_THRESHOLD=2000  # milliseconds
DEFAULT_CRITICAL_RESPONSE_THRESHOLD=5000  # milliseconds
DEFAULT_STATS_WINDOW_HOURS=24  # hours for calculating averages

#
# Initialize advanced monitoring system
#
init_advanced_monitoring() {
    # Ensure required directories exist
    ensure_directory "$LOG_DIR"
    ensure_directory "$DATA_DIR"
    
    # Create log files if they don't exist
    local monitoring_files=("$RESPONSE_TIME_LOG_FILE" "$ALERT_LOG_FILE" "$PERFORMANCE_STATS_FILE")
    
    for file in "${monitoring_files[@]}"; do
        if [ ! -f "$file" ]; then
            touch "$file" 2>/dev/null || {
                log_error_detailed "Failed to create monitoring file: $file"
                return 1
            }
        fi
    done
    
    log_debug_detailed "Advanced monitoring system initialized" "advanced-monitoring"
    return 0
}

#
# Log response time measurement
# Arguments:
#   $1 - URL
#   $2 - Response time in milliseconds
#   $3 - Status code
#   $4 - Status (available/unavailable/error)
#
log_response_time() {
    local url="$1"
    local response_time="$2"
    local status_code="$3"
    local status="$4"
    
    if [ -z "$url" ] || [ -z "$response_time" ]; then
        log_error_detailed "URL and response time required for response time logging"
        return 1
    fi
    
    # Validate response time is numeric
    if ! is_number "$response_time"; then
        log_error_detailed "Invalid response time value: $response_time" 2>/dev/null || true
        return 1
    fi
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Format: timestamp|url|response_time_ms|status_code|status
    local log_entry="${timestamp}|${url}|${response_time}|${status_code:-0}|${status:-unknown}"
    
    # Write to response time log
    if echo "$log_entry" >> "$RESPONSE_TIME_LOG_FILE" 2>/dev/null; then
        log_debug_detailed "Response time logged: ${response_time}ms for $url" "advanced-monitoring"
        return 0
    else
        log_error_detailed "Failed to write response time log entry"
        return 1
    fi
}

#
# Check if response time exceeds slow threshold
# Arguments:
#   $1 - Response time in milliseconds
#   $2 - Slow threshold (optional, uses DEFAULT_SLOW_RESPONSE_THRESHOLD if not provided)
# Returns:
#   0 if response is slow, 1 if response is normal
#
is_slow_response() {
    local response_time="$1"
    local threshold="${2:-${SLOW_RESPONSE_THRESHOLD:-$DEFAULT_SLOW_RESPONSE_THRESHOLD}}"
    
    if ! is_number "$response_time" || ! is_number "$threshold"; then
        return 1
    fi
    
    [ "$response_time" -gt "$threshold" ]
}

#
# Check if response time exceeds critical threshold
# Arguments:
#   $1 - Response time in milliseconds
#   $2 - Critical threshold (optional, uses DEFAULT_CRITICAL_RESPONSE_THRESHOLD if not provided)
# Returns:
#   0 if response is critical, 1 if response is not critical
#
is_critical_response() {
    local response_time="$1"
    local threshold="${2:-$DEFAULT_CRITICAL_RESPONSE_THRESHOLD}"
    
    if ! is_number "$response_time" || ! is_number "$threshold"; then
        return 1
    fi
    
    [ "$response_time" -gt "$threshold" ]
}

#
# Generate alert for threshold violation
# Arguments:
#   $1 - URL
#   $2 - Alert type (SLOW_RESPONSE, CRITICAL_RESPONSE, THRESHOLD_VIOLATION)
#   $3 - Response time in milliseconds
#   $4 - Threshold value
#   $5 - Additional details (optional)
#
generate_alert() {
    local url="$1"
    local alert_type="$2"
    local response_time="$3"
    local threshold="$4"
    local details="${5:-}"
    
    if [ -z "$url" ] || [ -z "$alert_type" ] || [ -z "$response_time" ] || [ -z "$threshold" ]; then
        log_error_detailed "URL, alert type, response time, and threshold required for alert generation"
        return 1
    fi
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Format alert message
    local alert_message="$alert_type: ${response_time}ms > ${threshold}ms for $url"
    if [ -n "$details" ]; then
        alert_message="$alert_message - $details"
    fi
    
    # Log to alert file
    local alert_entry="${timestamp}|${alert_type}|${url}|${response_time}|${threshold}|${details:-}"
    if echo "$alert_entry" >> "$ALERT_LOG_FILE" 2>/dev/null; then
        log_debug_detailed "Alert generated: $alert_message" "advanced-monitoring"
    else
        log_error_detailed "Failed to write alert log entry"
        return 1
    fi
    
    # Log to main monitoring system
    case "$alert_type" in
        "SLOW_RESPONSE")
            log_monitoring_event "$url" "" "$response_time" "SLOW" "$alert_message"
            ;;
        "CRITICAL_RESPONSE")
            log_monitoring_event "$url" "" "$response_time" "CRITICAL" "$alert_message"
            ;;
        *)
            log_monitoring_event "$url" "" "$response_time" "WARNING" "$alert_message"
            ;;
    esac
    
    return 0
}

#
# Process response time and generate alerts if needed
# Arguments:
#   $1 - URL
#   $2 - Response time in milliseconds
#   $3 - Status code
#   $4 - Status (available/unavailable/error)
#
process_response_time() {
    local url="$1"
    local response_time="$2"
    local status_code="$3"
    local status="$4"
    
    if [ -z "$url" ] || [ -z "$response_time" ]; then
        return 1
    fi
    
    # Log the response time
    log_response_time "$url" "$response_time" "$status_code" "$status"
    
    # Only check thresholds for successful responses
    if [ "$status" = "available" ]; then
        local slow_threshold="${SLOW_RESPONSE_THRESHOLD:-$DEFAULT_SLOW_RESPONSE_THRESHOLD}"
        local critical_threshold="${CRITICAL_RESPONSE_THRESHOLD:-$DEFAULT_CRITICAL_RESPONSE_THRESHOLD}"
        
        # Check for critical response time first
        if is_critical_response "$response_time" "$critical_threshold"; then
            generate_alert "$url" "CRITICAL_RESPONSE" "$response_time" "$critical_threshold" "Response time critically high"
        elif is_slow_response "$response_time" "$slow_threshold"; then
            generate_alert "$url" "SLOW_RESPONSE" "$response_time" "$slow_threshold" "Response time above threshold"
        fi
    fi
    
    return 0
}

#
# Calculate average response time for a URL over a time window
# Arguments:
#   $1 - URL
#   $2 - Time window in hours (optional, defaults to DEFAULT_STATS_WINDOW_HOURS)
# Returns:
#   Prints average response time in milliseconds, or "N/A" if no data
#
calculate_average_response_time() {
    local url="$1"
    local window_hours="${2:-$DEFAULT_STATS_WINDOW_HOURS}"
    
    if [ -z "$url" ]; then
        echo "N/A"
        return 1
    fi
    
    if ! is_number "$window_hours" || [ "$window_hours" -lt 1 ]; then
        echo "N/A"
        return 1
    fi
    
    # Calculate cutoff timestamp
    local current_epoch
    current_epoch=$(get_epoch_timestamp)
    local cutoff_epoch=$((current_epoch - (window_hours * 3600)))
    
    # Convert cutoff to timestamp format for comparison
    local cutoff_timestamp
    cutoff_timestamp=$(date -d "@$cutoff_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || {
        echo "N/A"
        return 1
    }
    
    if [ ! -f "$RESPONSE_TIME_LOG_FILE" ]; then
        echo "N/A"
        return 1
    fi
    
    # Extract response times for the URL within the time window
    local total_time=0
    local count=0
    
    while IFS='|' read -r timestamp log_url response_time status_code status; do
        # Skip empty lines
        [ -n "$timestamp" ] || continue
        
        # Check if this entry is for our URL
        [ "$log_url" = "$url" ] || continue
        
        # Check if timestamp is within our window
        if [[ "$timestamp" > "$cutoff_timestamp" ]] || [[ "$timestamp" = "$cutoff_timestamp" ]]; then
            # Only include successful responses
            if [ "$status" = "available" ] && is_number "$response_time"; then
                total_time=$((total_time + response_time))
                count=$((count + 1))
            fi
        fi
    done < "$RESPONSE_TIME_LOG_FILE"
    
    if [ "$count" -gt 0 ]; then
        local average=$((total_time / count))
        echo "$average"
        return 0
    else
        echo "N/A"
        return 1
    fi
}

#
# Calculate response time statistics for a URL
# Arguments:
#   $1 - URL
#   $2 - Time window in hours (optional, defaults to DEFAULT_STATS_WINDOW_HOURS)
# Returns:
#   Prints statistics in format: "avg|min|max|count" or "N/A|N/A|N/A|0"
#
calculate_response_time_stats() {
    local url="$1"
    local window_hours="${2:-$DEFAULT_STATS_WINDOW_HOURS}"
    
    if [ -z "$url" ]; then
        echo "N/A|N/A|N/A|0"
        return 1
    fi
    
    if ! is_number "$window_hours" || [ "$window_hours" -lt 1 ]; then
        echo "N/A|N/A|N/A|0"
        return 1
    fi
    
    # Calculate cutoff timestamp
    local current_epoch
    current_epoch=$(get_epoch_timestamp)
    local cutoff_epoch=$((current_epoch - (window_hours * 3600)))
    
    local cutoff_timestamp
    cutoff_timestamp=$(date -d "@$cutoff_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || {
        echo "N/A|N/A|N/A|0"
        return 1
    }
    
    if [ ! -f "$RESPONSE_TIME_LOG_FILE" ]; then
        echo "N/A|N/A|N/A|0"
        return 1
    fi
    
    # Collect response times for the URL within the time window
    local response_times=()
    local total_time=0
    local min_time=""
    local max_time=""
    
    while IFS='|' read -r timestamp log_url response_time status_code status; do
        # Skip empty lines
        [ -n "$timestamp" ] || continue
        
        # Check if this entry is for our URL
        [ "$log_url" = "$url" ] || continue
        
        # Check if timestamp is within our window
        if [[ "$timestamp" > "$cutoff_timestamp" ]] || [[ "$timestamp" = "$cutoff_timestamp" ]]; then
            # Only include successful responses
            if [ "$status" = "available" ] && is_number "$response_time"; then
                response_times+=("$response_time")
                total_time=$((total_time + response_time))
                
                # Update min/max
                if [ -z "$min_time" ] || [ "$response_time" -lt "$min_time" ]; then
                    min_time="$response_time"
                fi
                if [ -z "$max_time" ] || [ "$response_time" -gt "$max_time" ]; then
                    max_time="$response_time"
                fi
            fi
        fi
    done < "$RESPONSE_TIME_LOG_FILE"
    
    local count=${#response_times[@]}
    
    if [ "$count" -gt 0 ]; then
        local average=$((total_time / count))
        echo "${average}|${min_time}|${max_time}|${count}"
        return 0
    else
        echo "N/A|N/A|N/A|0"
        return 1
    fi
}

#
# Update performance statistics file
# Arguments:
#   $1 - URL
#   $2 - Time window in hours (optional)
#
update_performance_stats() {
    local url="$1"
    local window_hours="${2:-$DEFAULT_STATS_WINDOW_HOURS}"
    
    if [ -z "$url" ]; then
        return 1
    fi
    
    # Calculate statistics
    local stats
    stats=$(calculate_response_time_stats "$url" "$window_hours")
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Format: timestamp|url|window_hours|avg|min|max|count
    local stats_entry="${timestamp}|${url}|${window_hours}|${stats}"
    
    # Append to performance stats file
    if echo "$stats_entry" >> "$PERFORMANCE_STATS_FILE" 2>/dev/null; then
        log_debug_detailed "Performance stats updated for $url: $stats" "advanced-monitoring"
        return 0
    else
        log_error_detailed "Failed to update performance stats file"
        return 1
    fi
}

#
# Get enhanced HTTP status information
# Arguments:
#   $1 - HTTP status code
# Returns:
#   Prints detailed status information in format: "category|severity|description|action_required"
#
get_enhanced_status_info() {
    local status_code="$1"
    
    if [ -z "$status_code" ] || ! is_number "$status_code"; then
        echo "unknown|high|Invalid status code|investigate"
        return 1
    fi
    
    local category severity description action_required
    
    case "$status_code" in
        # 2xx Success
        200) category="success"; severity="none"; description="OK - Request successful"; action_required="none" ;;
        201) category="success"; severity="none"; description="Created - Resource created successfully"; action_required="none" ;;
        202) category="success"; severity="low"; description="Accepted - Request accepted for processing"; action_required="monitor" ;;
        204) category="success"; severity="none"; description="No Content - Request successful, no content returned"; action_required="none" ;;
        
        # 3xx Redirection
        301) category="redirect"; severity="low"; description="Moved Permanently - Resource moved to new location"; action_required="update_url" ;;
        302) category="redirect"; severity="low"; description="Found - Resource temporarily moved"; action_required="monitor" ;;
        304) category="redirect"; severity="none"; description="Not Modified - Resource unchanged"; action_required="none" ;;
        307) category="redirect"; severity="low"; description="Temporary Redirect - Resource temporarily moved"; action_required="monitor" ;;
        308) category="redirect"; severity="medium"; description="Permanent Redirect - Resource permanently moved"; action_required="update_url" ;;
        
        # 4xx Client Error
        400) category="client_error"; severity="high"; description="Bad Request - Invalid request syntax"; action_required="investigate" ;;
        401) category="client_error"; severity="high"; description="Unauthorized - Authentication required"; action_required="check_credentials" ;;
        403) category="client_error"; severity="high"; description="Forbidden - Access denied"; action_required="check_permissions" ;;
        404) category="client_error"; severity="high"; description="Not Found - Resource does not exist"; action_required="verify_url" ;;
        405) category="client_error"; severity="medium"; description="Method Not Allowed - HTTP method not supported"; action_required="check_method" ;;
        408) category="client_error"; severity="medium"; description="Request Timeout - Request took too long"; action_required="check_network" ;;
        409) category="client_error"; severity="medium"; description="Conflict - Request conflicts with current state"; action_required="investigate" ;;
        410) category="client_error"; severity="high"; description="Gone - Resource permanently removed"; action_required="remove_url" ;;
        429) category="client_error"; severity="medium"; description="Too Many Requests - Rate limit exceeded"; action_required="reduce_frequency" ;;
        
        # 5xx Server Error
        500) category="server_error"; severity="high"; description="Internal Server Error - Server encountered an error"; action_required="contact_admin" ;;
        501) category="server_error"; severity="medium"; description="Not Implemented - Server does not support functionality"; action_required="investigate" ;;
        502) category="server_error"; severity="high"; description="Bad Gateway - Invalid response from upstream server"; action_required="check_upstream" ;;
        503) category="server_error"; severity="high"; description="Service Unavailable - Server temporarily unavailable"; action_required="retry_later" ;;
        504) category="server_error"; severity="high"; description="Gateway Timeout - Upstream server timeout"; action_required="check_upstream" ;;
        505) category="server_error"; severity="medium"; description="HTTP Version Not Supported - HTTP version not supported"; action_required="check_protocol" ;;
        
        # Unknown status codes
        *)
            if [ "$status_code" -ge 200 ] && [ "$status_code" -lt 300 ]; then
                category="success"; severity="low"; description="HTTP $status_code - Success response"; action_required="none"
            elif [ "$status_code" -ge 300 ] && [ "$status_code" -lt 400 ]; then
                category="redirect"; severity="low"; description="HTTP $status_code - Redirection response"; action_required="monitor"
            elif [ "$status_code" -ge 400 ] && [ "$status_code" -lt 500 ]; then
                category="client_error"; severity="high"; description="HTTP $status_code - Client error"; action_required="investigate"
            elif [ "$status_code" -ge 500 ] && [ "$status_code" -lt 600 ]; then
                category="server_error"; severity="high"; description="HTTP $status_code - Server error"; action_required="contact_admin"
            else
                category="unknown"; severity="high"; description="HTTP $status_code - Unknown status code"; action_required="investigate"
            fi
            ;;
    esac
    
    echo "${category}|${severity}|${description}|${action_required}"
}

#
# Log enhanced error information
# Arguments:
#   $1 - URL
#   $2 - HTTP status code
#   $3 - Response time
#   $4 - Error message
#   $5 - Additional context (optional)
#
log_enhanced_error() {
    local url="$1"
    local status_code="$2"
    local response_time="$3"
    local error_message="$4"
    local context="${5:-}"
    
    if [ -z "$url" ] || [ -z "$status_code" ]; then
        return 1
    fi
    
    # Get enhanced status information
    local status_info
    status_info=$(get_enhanced_status_info "$status_code")
    
    local category severity description action_required
    IFS='|' read -r category severity description action_required <<< "$status_info"
    
    # Create detailed error message
    local detailed_message="$description"
    if [ -n "$error_message" ]; then
        detailed_message="$detailed_message - $error_message"
    fi
    if [ -n "$context" ]; then
        detailed_message="$detailed_message ($context)"
    fi
    
    # Log to error log with enhanced information
    local timestamp
    timestamp=$(get_timestamp)
    local error_entry="${timestamp}|${url}|${status_code}|${category}|${severity}|${action_required}|${response_time:-0}|${detailed_message}"
    
    if echo "$error_entry" >> "$ERROR_LOG_FILE" 2>/dev/null; then
        log_debug_detailed "Enhanced error logged for $url: $detailed_message" "advanced-monitoring"
    fi
    
    # Log to main monitoring system based on severity
    case "$severity" in
        "high")
            log_monitoring_event "$url" "$status_code" "$response_time" "ERROR" "$detailed_message"
            ;;
        "medium")
            log_monitoring_event "$url" "$status_code" "$response_time" "WARNING" "$detailed_message"
            ;;
        *)
            log_monitoring_event "$url" "$status_code" "$response_time" "INFO" "$detailed_message"
            ;;
    esac
    
    return 0
}

#
# Clean up old monitoring data
# Arguments:
#   $1 - Retention days (optional, defaults to LOG_RETENTION_DAYS)
#
cleanup_monitoring_data() {
    local retention_days="${1:-${LOG_RETENTION_DAYS:-30}}"
    
    if ! is_number "$retention_days" || [ "$retention_days" -lt 1 ]; then
        log_error_detailed "Invalid retention days for monitoring cleanup: $retention_days"
        return 1
    fi
    
    log_debug_detailed "Cleaning up monitoring data older than $retention_days days" "advanced-monitoring"
    
    # Clean up response time logs
    if [ -f "$RESPONSE_TIME_LOG_FILE" ]; then
        cleanup_old_log_entries "$RESPONSE_TIME_LOG_FILE" "$retention_days"
    fi
    
    # Clean up alert logs
    if [ -f "$ALERT_LOG_FILE" ]; then
        cleanup_old_log_entries "$ALERT_LOG_FILE" "$retention_days"
    fi
    
    # Clean up performance stats
    if [ -f "$PERFORMANCE_STATS_FILE" ]; then
        cleanup_old_log_entries "$PERFORMANCE_STATS_FILE" "$retention_days"
    fi
    
    log_debug_detailed "Monitoring data cleanup completed" "advanced-monitoring"
    return 0
}

#
# Clean up old entries from a log file based on timestamp
# Arguments:
#   $1 - Log file path
#   $2 - Retention days
#
cleanup_old_log_entries() {
    local log_file="$1"
    local retention_days="$2"
    
    if [ ! -f "$log_file" ]; then
        return 0
    fi
    
    # Calculate cutoff timestamp
    local current_epoch
    current_epoch=$(get_epoch_timestamp)
    local cutoff_epoch=$((current_epoch - (retention_days * 86400)))
    local cutoff_timestamp
    cutoff_timestamp=$(date -d "@$cutoff_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || return 1
    
    # Create temporary file for filtered entries
    local temp_file
    temp_file=$(mktemp) || return 1
    
    local removed_count=0
    local kept_count=0
    
    # Filter entries newer than cutoff
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local timestamp
            timestamp=$(echo "$line" | cut -d'|' -f1)
            
            if [[ "$timestamp" > "$cutoff_timestamp" ]] || [[ "$timestamp" = "$cutoff_timestamp" ]]; then
                echo "$line" >> "$temp_file"
                kept_count=$((kept_count + 1))
            else
                removed_count=$((removed_count + 1))
            fi
        fi
    done < "$log_file"
    
    # Replace original file with filtered content
    if mv "$temp_file" "$log_file" 2>/dev/null; then
        if [ "$removed_count" -gt 0 ]; then
            log_debug_detailed "Cleaned up $removed_count old entries from $(basename "$log_file"), kept $kept_count entries" "advanced-monitoring"
        fi
        return 0
    else
        rm -f "$temp_file" 2>/dev/null
        log_error_detailed "Failed to update log file during cleanup: $log_file"
        return 1
    fi
}

# Initialize advanced monitoring when this script is sourced
if ! init_advanced_monitoring; then
    echo "WARNING: Failed to initialize advanced monitoring system" >&2
fi

# Export key functions
export -f log_response_time is_slow_response is_critical_response generate_alert
export -f process_response_time calculate_average_response_time calculate_response_time_stats
export -f update_performance_stats get_enhanced_status_info log_enhanced_error
export -f cleanup_monitoring_data

export RESPONSE_TIME_LOG_FILE ALERT_LOG_FILE PERFORMANCE_STATS_FILE
export DEFAULT_SLOW_RESPONSE_THRESHOLD DEFAULT_CRITICAL_RESPONSE_THRESHOLD DEFAULT_STATS_WINDOW_HOURS