#!/bin/bash

# Logging and Data Storage Utilities
# Provides structured logging, log rotation, incident tracking, and data management

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Log file paths (use environment variable if set, otherwise default)
MAIN_LOG_FILE="${MAIN_LOG_FILE:-$LOG_DIR/monitor.log}"
INCIDENT_LOG_FILE="${INCIDENT_LOG_FILE:-$LOG_DIR/incidents.log}"
CONTENT_LOG_FILE="${CONTENT_LOG_FILE:-$LOG_DIR/content-changes.log}"
ERROR_LOG_FILE="$LOG_DIR/errors.log"
DEBUG_LOG_FILE="$LOG_DIR/debug.log"

# Log rotation settings
DEFAULT_MAX_LOG_SIZE_MB=10
DEFAULT_MAX_LOG_FILES=5

# Log levels with numeric values for filtering
declare -A LOG_LEVELS=(
    ["ERROR"]=1
    ["WARN"]=2
    ["INFO"]=3
    ["DEBUG"]=4
)

# Current log level (can be overridden by configuration)
CURRENT_LOG_LEVEL="${LOG_LEVEL:-INFO}"

#
# Initialize logging system
# Creates necessary directories and log files
#
init_logging_system() {
    local init_errors=()
    
    # Ensure log directory exists
    if ! ensure_directory "$LOG_DIR"; then
        init_errors+=("Failed to create log directory: $LOG_DIR")
    fi
    
    # Create log files if they don't exist
    local log_files=("$MAIN_LOG_FILE" "$INCIDENT_LOG_FILE" "$CONTENT_LOG_FILE" "$ERROR_LOG_FILE" "$DEBUG_LOG_FILE")
    
    for log_file in "${log_files[@]}"; do
        if [ ! -f "$log_file" ]; then
            if ! touch "$log_file" 2>/dev/null; then
                init_errors+=("Failed to create log file: $log_file")
            fi
        fi
    done
    
    # Check write permissions
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ] && [ ! -w "$log_file" ]; then
            init_errors+=("Log file is not writable: $log_file")
        fi
    done
    
    # Report initialization errors
    if [ ${#init_errors[@]} -gt 0 ]; then
        for error in "${init_errors[@]}"; do
            echo "ERROR: $error" >&2
        done
        return 1
    fi
    
    log_debug "Logging system initialized successfully"
    return 0
}

#
# Write structured log entry to specified log file
# Arguments:
#   $1 - Log level (ERROR, WARN, INFO, DEBUG)
#   $2 - Log file path
#   $3 - Message
#   $4 - Additional fields (optional, pipe-separated)
#
write_log_entry() {
    local level="$1"
    local log_file="$2"
    local message="$3"
    local additional_fields="$4"
    
    # Validate inputs
    if [ -z "$level" ] || [ -z "$log_file" ] || [ -z "$message" ]; then
        echo "ERROR: Invalid parameters for log entry" >&2
        return 1
    fi
    
    # Check if log level should be written
    if ! should_log_level "$level"; then
        return 0
    fi
    
    # Get timestamp
    local timestamp
    timestamp=$(get_timestamp)
    
    # Format log entry
    local log_entry="${timestamp}|${level}|${message}"
    if [ -n "$additional_fields" ]; then
        log_entry="${log_entry}|${additional_fields}"
    fi
    
    # Write to log file with error handling
    if ! echo "$log_entry" >> "$log_file" 2>/dev/null; then
        echo "ERROR: Failed to write to log file: $log_file" >&2
        return 1
    fi
    
    return 0
}

#
# Check if log level should be written based on current log level
# Arguments:
#   $1 - Log level to check
# Returns:
#   0 if should log, 1 if should not log
#
should_log_level() {
    local level="$1"
    
    # Get numeric values for comparison
    local level_num="${LOG_LEVELS[$level]:-0}"
    local current_num="${LOG_LEVELS[$CURRENT_LOG_LEVEL]:-3}"
    
    [ "$level_num" -le "$current_num" ]
}

#
# Log monitoring event (website check result)
# Arguments:
#   $1 - URL
#   $2 - Status code
#   $3 - Response time (ms)
#   $4 - Status (UP/DOWN/SLOW/etc.)
#   $5 - Message
#
log_monitoring_event() {
    local url="$1"
    local status_code="$2"
    local response_time="$3"
    local status="$4"
    local message="$5"
    
    if [ -z "$url" ] || [ -z "$status" ]; then
        log_error "URL and status required for monitoring event"
        return 1
    fi
    
    # Determine log level based on status
    local log_level="INFO"
    case "$status" in
        "DOWN"|"ERROR"|"TIMEOUT")
            log_level="ERROR"
            ;;
        "SLOW"|"WARNING")
            log_level="WARN"
            ;;
    esac
    
    # Format additional fields
    local additional_fields="${url}|${status_code:-0}|${response_time:-0}|${status}"
    
    write_log_entry "$log_level" "$MAIN_LOG_FILE" "$message" "$additional_fields"
}

#
# Log incident (downtime, recovery, etc.)
# Arguments:
#   $1 - URL
#   $2 - Incident type (DOWNTIME, RECOVERY, SLOW_RESPONSE, etc.)
#   $3 - Duration (optional, in seconds)
#   $4 - Details
#
log_incident() {
    local url="$1"
    local incident_type="$2"
    local duration="$3"
    local details="$4"
    
    if [ -z "$url" ] || [ -z "$incident_type" ]; then
        log_error "URL and incident type required for incident logging"
        return 1
    fi
    
    # Format duration
    local duration_str=""
    if [ -n "$duration" ] && is_number "$duration"; then
        if [ "$duration" -lt 60 ]; then
            duration_str="${duration}s"
        elif [ "$duration" -lt 3600 ]; then
            duration_str="$((duration / 60))m $((duration % 60))s"
        else
            duration_str="$((duration / 3600))h $(((duration % 3600) / 60))m"
        fi
    fi
    
    # Write to incident log
    local additional_fields="${url}|${incident_type}|${duration_str}|${details:-}"
    write_log_entry "INFO" "$INCIDENT_LOG_FILE" "Incident: $incident_type for $url" "$additional_fields"
    
    # Also log to main log for visibility
    local main_message="$incident_type"
    if [ -n "$duration_str" ]; then
        main_message="$main_message (duration: $duration_str)"
    fi
    if [ -n "$details" ]; then
        main_message="$main_message - $details"
    fi
    
    log_monitoring_event "$url" "" "" "$incident_type" "$main_message"
}

#
# Log content change event
# Arguments:
#   $1 - URL
#   $2 - Change type (INITIAL, CHANGED, UNCHANGED)
#   $3 - Current hash
#   $4 - Previous hash (optional)
#   $5 - Summary (optional)
#
log_content_change_event() {
    local url="$1"
    local change_type="$2"
    local current_hash="$3"
    local previous_hash="$4"
    local summary="$5"
    
    if [ -z "$url" ] || [ -z "$change_type" ] || [ -z "$current_hash" ]; then
        log_error "URL, change type, and current hash required for content change logging"
        return 1
    fi
    
    # Write to content changes log
    local additional_fields="${url}|${change_type}|${current_hash}|${previous_hash:-}|${summary:-}"
    write_log_entry "INFO" "$CONTENT_LOG_FILE" "Content $change_type for $url" "$additional_fields"
    
    # Also log to main log
    local main_message="CONTENT_${change_type}"
    if [ -n "$summary" ]; then
        main_message="$main_message - $summary"
    fi
    
    log_monitoring_event "$url" "" "" "CONTENT_${change_type}" "$main_message"
}

#
# Log error with detailed information
# Arguments:
#   $1 - Error message
#   $2 - Error code (optional)
#   $3 - Context (optional)
#
log_error_detailed() {
    local error_message="$1"
    local error_code="${2:-}"
    local context="${3:-}"
    
    if [ -z "$error_message" ]; then
        return 1
    fi
    
    # Format additional fields
    local additional_fields="${error_code:-}|${context:-}"
    
    # Write to error log
    write_log_entry "ERROR" "$ERROR_LOG_FILE" "$error_message" "$additional_fields"
    
    # Also write to main log
    write_log_entry "ERROR" "$MAIN_LOG_FILE" "$error_message"
    
    # Output to stderr for immediate visibility
    echo "ERROR: $error_message" >&2
}

#
# Log debug information
# Arguments:
#   $1 - Debug message
#   $2 - Component (optional)
#   $3 - Additional data (optional)
#
log_debug_detailed() {
    local debug_message="$1"
    local component="${2:-}"
    local additional_data="${3:-}"
    
    if [ -z "$debug_message" ]; then
        return 1
    fi
    
    # Only log if debug level is enabled
    if ! should_log_level "DEBUG"; then
        return 0
    fi
    
    # Format additional fields
    local additional_fields="${component:-}|${additional_data:-}"
    
    # Write to debug log
    write_log_entry "DEBUG" "$DEBUG_LOG_FILE" "$debug_message" "$additional_fields"
}

#
# Rotate log file if it exceeds size limit
# Arguments:
#   $1 - Log file path
#   $2 - Max size in MB (optional, defaults to DEFAULT_MAX_LOG_SIZE_MB)
#   $3 - Max number of rotated files (optional, defaults to DEFAULT_MAX_LOG_FILES)
#
rotate_log_file_advanced() {
    local log_file="$1"
    local max_size_mb="${2:-$DEFAULT_MAX_LOG_SIZE_MB}"
    local max_files="${3:-$DEFAULT_MAX_LOG_FILES}"
    
    if [ -z "$log_file" ]; then
        log_error_detailed "Log file path required for rotation"
        return 1
    fi
    
    if [ ! -f "$log_file" ]; then
        return 0
    fi
    
    # Get file size in MB
    local file_size_mb=0
    if command -v stat >/dev/null 2>&1; then
        # Try GNU stat first
        local file_size_bytes
        file_size_bytes=$(stat -c%s "$log_file" 2>/dev/null)
        
        # Try BSD stat if GNU stat failed
        if [ -z "$file_size_bytes" ]; then
            file_size_bytes=$(stat -f%z "$log_file" 2>/dev/null)
        fi
        
        # Convert bytes to MB
        if [ -n "$file_size_bytes" ] && is_number "$file_size_bytes"; then
            file_size_mb=$((file_size_bytes / 1024 / 1024))
        fi
    fi
    
    if [ -z "$file_size_mb" ] || ! is_number "$file_size_mb"; then
        log_debug_detailed "Could not determine file size for rotation: $log_file"
        return 1
    fi
    
    if [ "$file_size_mb" -le "$max_size_mb" ]; then
        return 0
    fi
    
    log_debug_detailed "Rotating log file: $log_file (${file_size_mb}MB > ${max_size_mb}MB)"
    
    # Rotate existing files
    local i
    for ((i = max_files - 1; i >= 1; i--)); do
        local old_file="${log_file}.${i}"
        local new_file="${log_file}.$((i + 1))"
        
        if [ -f "$old_file" ]; then
            if [ $i -eq $((max_files - 1)) ]; then
                # Remove oldest file
                rm -f "$old_file"
                log_debug_detailed "Removed oldest rotated log: $old_file"
            else
                # Move to next number
                mv "$old_file" "$new_file" 2>/dev/null
                log_debug_detailed "Rotated log: $old_file -> $new_file"
            fi
        fi
    done
    
    # Move current log to .1
    if mv "$log_file" "${log_file}.1" 2>/dev/null; then
        # Create new empty log file
        touch "$log_file"
        log_debug_detailed "Rotated current log: $log_file -> ${log_file}.1"
        
        # Log rotation event
        write_log_entry "INFO" "$log_file" "Log file rotated (size: ${file_size_mb}MB)"
        
        return 0
    else
        log_error_detailed "Failed to rotate log file: $log_file"
        return 1
    fi
}

#
# Clean up old log files based on retention policy
# Arguments:
#   $1 - Log directory (optional, defaults to LOG_DIR)
#   $2 - Retention days (optional, defaults to LOG_RETENTION_DAYS)
#
cleanup_old_logs() {
    local log_dir="${1:-$LOG_DIR}"
    local retention_days="${2:-${LOG_RETENTION_DAYS:-30}}"
    
    if [ ! -d "$log_dir" ]; then
        log_error_detailed "Log directory does not exist: $log_dir"
        return 1
    fi
    
    if ! is_number "$retention_days" || [ "$retention_days" -lt 1 ]; then
        log_error_detailed "Invalid retention days: $retention_days"
        return 1
    fi
    
    log_debug_detailed "Cleaning up logs older than $retention_days days in: $log_dir"
    
    local removed_count=0
    local total_size=0
    
    # Find and process old log files
    if command -v find >/dev/null 2>&1; then
        while IFS= read -r -d '' file; do
            # Get file size before removal
            local file_size=0
            if command -v stat >/dev/null 2>&1; then
                file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
            fi
            
            if rm -f "$file" 2>/dev/null; then
                removed_count=$((removed_count + 1))
                total_size=$((total_size + file_size))
                log_debug_detailed "Removed old log file: $file"
            else
                log_error_detailed "Failed to remove old log file: $file"
            fi
        done < <(find "$log_dir" -name "*.log*" -type f -mtime +$retention_days -print0 2>/dev/null)
        
        if [ "$removed_count" -gt 0 ]; then
            local size_mb=$((total_size / 1024 / 1024))
            log_debug_detailed "Log cleanup completed: removed $removed_count file(s), freed ${size_mb}MB"
            write_log_entry "INFO" "$MAIN_LOG_FILE" "Log cleanup: removed $removed_count old file(s), freed ${size_mb}MB"
        else
            log_debug_detailed "Log cleanup completed: no old files found"
        fi
    else
        log_error_detailed "find command not available, cannot perform log cleanup"
        return 1
    fi
    
    return 0
}

#
# Perform comprehensive log maintenance
# Rotates large files and cleans up old files
#
perform_log_maintenance() {
    log_debug_detailed "Starting log maintenance"
    
    local maintenance_errors=()
    
    # Rotate large log files
    local log_files=("$MAIN_LOG_FILE" "$INCIDENT_LOG_FILE" "$CONTENT_LOG_FILE" "$ERROR_LOG_FILE" "$DEBUG_LOG_FILE")
    
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            if ! rotate_log_file_advanced "$log_file"; then
                maintenance_errors+=("Failed to rotate: $log_file")
            fi
        fi
    done
    
    # Clean up old files
    if ! cleanup_old_logs; then
        maintenance_errors+=("Failed to clean up old logs")
    fi
    
    # Report maintenance results
    if [ ${#maintenance_errors[@]} -gt 0 ]; then
        for error in "${maintenance_errors[@]}"; do
            log_error_detailed "$error"
        done
        return 1
    fi
    
    log_debug_detailed "Log maintenance completed successfully"
    return 0
}

#
# Get log statistics
# Returns information about log files and their sizes
#
get_log_statistics() {
    local log_dir="${1:-$LOG_DIR}"
    
    if [ ! -d "$log_dir" ]; then
        echo "Log directory not found: $log_dir"
        return 1
    fi
    
    echo "=== Log Statistics ==="
    echo "Log Directory: $log_dir"
    echo "Current Log Level: $CURRENT_LOG_LEVEL"
    echo ""
    
    local total_size=0
    local file_count=0
    
    # Process each log file
    for log_file in "$MAIN_LOG_FILE" "$INCIDENT_LOG_FILE" "$CONTENT_LOG_FILE" "$ERROR_LOG_FILE" "$DEBUG_LOG_FILE"; do
        if [ -f "$log_file" ]; then
            local file_size=0
            local line_count=0
            
            # Get file size
            if command -v stat >/dev/null 2>&1; then
                file_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo 0)
            fi
            
            # Get line count
            if command -v wc >/dev/null 2>&1; then
                line_count=$(wc -l < "$log_file" 2>/dev/null || echo 0)
            fi
            
            local size_mb=$((file_size / 1024 / 1024))
            local size_kb=$(((file_size % (1024 * 1024)) / 1024))
            
            printf "%-20s: %3d MB %3d KB (%d lines)\n" "$(basename "$log_file")" "$size_mb" "$size_kb" "$line_count"
            
            total_size=$((total_size + file_size))
            file_count=$((file_count + 1))
        fi
    done
    
    # Show rotated files count
    local rotated_count=0
    if command -v find >/dev/null 2>&1; then
        rotated_count=$(find "$log_dir" -name "*.log.[0-9]*" -type f 2>/dev/null | wc -l)
    fi
    
    local total_mb=$((total_size / 1024 / 1024))
    echo ""
    echo "Total Size: ${total_mb} MB ($file_count active files)"
    echo "Rotated Files: $rotated_count"
    echo "======================"
}

#
# Validate log file format
# Arguments:
#   $1 - Log file path
#   $2 - Expected format (main, incident, content, error, debug)
#
validate_log_format() {
    local log_file="$1"
    local format_type="$2"
    
    if [ -z "$log_file" ] || [ -z "$format_type" ]; then
        log_error_detailed "Log file and format type required for validation"
        return 1
    fi
    
    if [ ! -f "$log_file" ]; then
        log_error_detailed "Log file does not exist: $log_file"
        return 1
    fi
    
    local validation_errors=()
    local line_count=0
    local valid_lines=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        line_count=$((line_count + 1))
        
        # Skip empty lines
        if [ -z "$line" ]; then
            continue
        fi
        
        # Validate basic format: timestamp|level|message
        if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\|[A-Z]+\|.+ ]]; then
            valid_lines=$((valid_lines + 1))
        else
            validation_errors+=("Line $line_count: Invalid format: $line")
        fi
        
        # Stop after checking first 100 lines for performance
        if [ "$line_count" -ge 100 ]; then
            break
        fi
    done < "$log_file"
    
    # Report validation results
    if [ ${#validation_errors[@]} -gt 0 ]; then
        echo "Log format validation failed for: $log_file"
        echo "Errors found:"
        for error in "${validation_errors[@]}"; do
            echo "  $error"
        done
        return 1
    fi
    
    echo "Log format validation passed for: $log_file"
    echo "Checked $line_count lines, $valid_lines valid"
    return 0
}

#
# Set log level dynamically
# Arguments:
#   $1 - New log level (ERROR, WARN, INFO, DEBUG)
#
set_log_level() {
    local new_level="$1"
    
    if [ -z "$new_level" ]; then
        log_error_detailed "Log level required"
        return 1
    fi
    
    # Validate log level
    if [ -z "${LOG_LEVELS[$new_level]}" ]; then
        log_error_detailed "Invalid log level: $new_level (valid: ERROR, WARN, INFO, DEBUG)"
        return 1
    fi
    
    local old_level="$CURRENT_LOG_LEVEL"
    CURRENT_LOG_LEVEL="$new_level"
    
    log_debug_detailed "Log level changed: $old_level -> $new_level"
    return 0
}

#
# Create data directory structure
# Ensures all necessary data directories exist with proper permissions
#
create_data_directories() {
    local directories=(
        "$DATA_DIR"
        "$LOG_DIR"
        "$DATA_DIR/content-hashes"
        "$DATA_DIR/reports"
        "$DATA_DIR/backups"
        "$DATA_DIR/temp"
    )
    
    local creation_errors=()
    
    for dir in "${directories[@]}"; do
        if ! ensure_directory "$dir"; then
            creation_errors+=("Failed to create directory: $dir")
        fi
    done
    
    # Set appropriate permissions (readable/writable by owner, readable by group)
    for dir in "${directories[@]}"; do
        if [ -d "$dir" ]; then
            chmod 755 "$dir" 2>/dev/null || creation_errors+=("Failed to set permissions for: $dir")
        fi
    done
    
    if [ ${#creation_errors[@]} -gt 0 ]; then
        for error in "${creation_errors[@]}"; do
            log_error_detailed "$error"
        done
        return 1
    fi
    
    log_debug_detailed "Data directory structure created successfully"
    return 0
}

#
# Clean up temporary files and data
# Arguments:
#   $1 - Max age in hours (optional, defaults to 24)
#
cleanup_temp_data() {
    local max_age_hours="${1:-24}"
    local temp_dir="$DATA_DIR/temp"
    
    if [ ! -d "$temp_dir" ]; then
        return 0
    fi
    
    if ! is_number "$max_age_hours" || [ "$max_age_hours" -lt 1 ]; then
        log_error_detailed "Invalid max age hours: $max_age_hours"
        return 1
    fi
    
    local removed_count=0
    
    # Convert hours to minutes for find command
    local max_age_minutes=$((max_age_hours * 60))
    
    if command -v find >/dev/null 2>&1; then
        while IFS= read -r -d '' file; do
            if rm -f "$file" 2>/dev/null; then
                removed_count=$((removed_count + 1))
                log_debug_detailed "Removed temp file: $file"
            fi
        done < <(find "$temp_dir" -type f -mmin +$max_age_minutes -print0 2>/dev/null)
        
        if [ "$removed_count" -gt 0 ]; then
            log_debug_detailed "Cleaned up $removed_count temporary file(s)"
        fi
    fi
    
    return 0
}

# Initialize logging system when this script is sourced
if ! init_logging_system; then
    echo "WARNING: Failed to initialize logging system" >&2
fi

# Export key functions and variables
export -f write_log_entry log_monitoring_event log_incident log_content_change_event
export -f log_error_detailed log_debug_detailed rotate_log_file_advanced
export -f cleanup_old_logs perform_log_maintenance get_log_statistics
export -f validate_log_format set_log_level create_data_directories cleanup_temp_data

export MAIN_LOG_FILE INCIDENT_LOG_FILE CONTENT_LOG_FILE ERROR_LOG_FILE DEBUG_LOG_FILE
export CURRENT_LOG_LEVEL