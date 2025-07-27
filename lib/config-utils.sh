#!/bin/bash

# Configuration parsing utilities for website monitoring system
# This file contains functions for reading and validating configuration files

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Default configuration values
DEFAULT_INTERVAL=300
DEFAULT_TIMEOUT=10
DEFAULT_MAX_CONCURRENT=5
DEFAULT_LOG_RETENTION_DAYS=30
DEFAULT_CONTENT_CHECK_ENABLED=true
DEFAULT_SLOW_RESPONSE_THRESHOLD=2000

# Function: read_config_file
# Purpose: Read and parse configuration file
# Usage: read_config_file <config_file>
read_config_file() {
    local config_file="$1"
    
    if [ -z "$config_file" ]; then
        log_error "Configuration file path cannot be empty"
        return 1
    fi
    
    if ! file_exists "$config_file"; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Only log debug if not in test mode
    if [ "${TEST_MODE:-}" != "true" ]; then
        log_debug "Reading configuration file: $config_file"
    fi
    
    # Read file line by line, skip comments and empty lines
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(trim_whitespace "$line")
        if [ -z "$line" ] || [[ "$line" =~ ^#.* ]]; then
            continue
        fi
        
        # Parse key=value pairs
        if [[ "$line" =~ ^[A-Z_][A-Z0-9_]*=.* ]]; then
            echo "$line"
        else
            if [ "${TEST_MODE:-}" != "true" ]; then
                log_warn "Invalid configuration line ignored: $line"
            fi
        fi
    done < "$config_file"
}

# Function: load_monitor_config
# Purpose: Load monitor configuration with defaults
# Usage: load_monitor_config [config_file]
load_monitor_config() {
    local config_file="${1:-$CONFIG_DIR/monitor.conf}"
    
    # Set defaults
    MONITOR_INTERVAL="$DEFAULT_INTERVAL"
    MONITOR_TIMEOUT="$DEFAULT_TIMEOUT"
    MAX_CONCURRENT_CHECKS="$DEFAULT_MAX_CONCURRENT"
    LOG_RETENTION_DAYS="$DEFAULT_LOG_RETENTION_DAYS"
    CONTENT_CHECK_ENABLED="$DEFAULT_CONTENT_CHECK_ENABLED"
    SLOW_RESPONSE_THRESHOLD="$DEFAULT_SLOW_RESPONSE_THRESHOLD"
    
    if file_exists "$config_file"; then
        log_info "Loading monitor configuration from: $config_file"
        
        # Read configuration and set variables
        while IFS= read -r config_line; do
            if [ -n "$config_line" ]; then
                eval "$config_line" 2>/dev/null
            fi
        done < <(read_config_file "$config_file" 2>/dev/null)
        
        # Validate loaded configuration
        validate_monitor_config
    else
        log_warn "Monitor configuration file not found, using defaults: $config_file"
        create_default_monitor_config "$config_file"
    fi
}

# Function: validate_monitor_config
# Purpose: Validate monitor configuration values
# Usage: validate_monitor_config
validate_monitor_config() {
    local validation_errors=()
    
    # Validate interval (check both DEFAULT_INTERVAL and MONITOR_INTERVAL)
    if [ -n "${DEFAULT_INTERVAL:-}" ]; then
        MONITOR_INTERVAL="$DEFAULT_INTERVAL"
    fi
    if ! is_number "$MONITOR_INTERVAL" || [ "$MONITOR_INTERVAL" -lt 10 ]; then
        validation_errors+=("MONITOR_INTERVAL must be a number >= 10")
        MONITOR_INTERVAL="$DEFAULT_INTERVAL"
    fi
    
    # Validate timeout (check both DEFAULT_TIMEOUT and MONITOR_TIMEOUT)
    if [ -n "${DEFAULT_TIMEOUT:-}" ]; then
        MONITOR_TIMEOUT="$DEFAULT_TIMEOUT"
    fi
    if ! is_number "$MONITOR_TIMEOUT" || [ "$MONITOR_TIMEOUT" -lt 1 ]; then
        validation_errors+=("MONITOR_TIMEOUT must be a number >= 1")
        MONITOR_TIMEOUT="$DEFAULT_TIMEOUT"
    fi
    
    # Validate max concurrent checks
    if ! is_number "$MAX_CONCURRENT_CHECKS" || [ "$MAX_CONCURRENT_CHECKS" -lt 1 ]; then
        validation_errors+=("MAX_CONCURRENT_CHECKS must be a number >= 1")
        MAX_CONCURRENT_CHECKS="$DEFAULT_MAX_CONCURRENT"
    fi
    
    # Validate log retention days
    if ! is_number "$LOG_RETENTION_DAYS" || [ "$LOG_RETENTION_DAYS" -lt 1 ]; then
        validation_errors+=("LOG_RETENTION_DAYS must be a number >= 1")
        LOG_RETENTION_DAYS="$DEFAULT_LOG_RETENTION_DAYS"
    fi
    
    # Validate slow response threshold
    if ! is_number "$SLOW_RESPONSE_THRESHOLD" || [ "$SLOW_RESPONSE_THRESHOLD" -lt 100 ]; then
        validation_errors+=("SLOW_RESPONSE_THRESHOLD must be a number >= 100")
        SLOW_RESPONSE_THRESHOLD="$DEFAULT_SLOW_RESPONSE_THRESHOLD"
    fi
    
    # Validate boolean values
    case "$CONTENT_CHECK_ENABLED" in
        true|false|1|0|yes|no)
            ;;
        *)
            validation_errors+=("CONTENT_CHECK_ENABLED must be true/false/1/0/yes/no")
            CONTENT_CHECK_ENABLED="$DEFAULT_CONTENT_CHECK_ENABLED"
            ;;
    esac
    
    # Report validation errors
    if [ ${#validation_errors[@]} -gt 0 ]; then
        log_warn "Configuration validation errors found:"
        for error in "${validation_errors[@]}"; do
            log_warn "  - $error"
        done
        log_warn "Using default values for invalid settings"
    fi
    
    log_debug "Monitor configuration validated successfully"
}

# Function: create_default_monitor_config
# Purpose: Create default monitor configuration file
# Usage: create_default_monitor_config <config_file>
create_default_monitor_config() {
    local config_file="$1"
    
    ensure_directory "$(dirname "$config_file")"
    
    cat > "$config_file" << EOF
# Website Monitoring System Configuration
# This file contains system-wide monitoring settings

# Default check interval in seconds (minimum: 10)
DEFAULT_INTERVAL=$DEFAULT_INTERVAL

# Default timeout for HTTP requests in seconds (minimum: 1)
DEFAULT_TIMEOUT=$DEFAULT_TIMEOUT

# Maximum number of concurrent website checks (minimum: 1)
MAX_CONCURRENT_CHECKS=$DEFAULT_MAX_CONCURRENT

# Log file retention period in days (minimum: 1)
LOG_RETENTION_DAYS=$DEFAULT_LOG_RETENTION_DAYS

# Enable content change detection (true/false)
CONTENT_CHECK_ENABLED=$DEFAULT_CONTENT_CHECK_ENABLED

# Slow response threshold in milliseconds (minimum: 100)
SLOW_RESPONSE_THRESHOLD=$DEFAULT_SLOW_RESPONSE_THRESHOLD

# Log level (ERROR, WARN, INFO, DEBUG)
LOG_LEVEL=INFO
EOF
    
    log_info "Created default monitor configuration: $config_file"
}

# Function: read_websites_config
# Purpose: Read and parse websites configuration file
# Usage: read_websites_config [config_file]
read_websites_config() {
    local config_file="${1:-$CONFIG_DIR/websites.conf}"
    local websites=()
    
    if ! file_exists "$config_file"; then
        log_error "Websites configuration file not found: $config_file"
        create_default_websites_config "$config_file"
        return 1
    fi
    
    log_info "Reading websites configuration from: $config_file"
    
    # Read file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(trim_whitespace "$line")
        if [ -z "$line" ] || [[ "$line" =~ ^#.* ]]; then
            continue
        fi
        
        # Parse website configuration line
        # Format: URL|Name|Check_Interval|Timeout|Content_Check
        if parse_website_config_line "$line"; then
            websites+=("$line")
        else
            log_warn "Invalid website configuration line ignored: $line"
        fi
    done < "$config_file"
    
    if [ ${#websites[@]} -eq 0 ]; then
        log_error "No valid websites found in configuration file"
        return 1
    fi
    
    log_info "Loaded ${#websites[@]} website(s) from configuration"
    
    # Output websites for processing
    printf '%s\n' "${websites[@]}"
}

# Function: parse_website_config_line
# Purpose: Parse and validate a single website configuration line
# Usage: parse_website_config_line <config_line>
parse_website_config_line() {
    local config_line="$1"
    local url name interval timeout content_check
    
    # Split line by pipe character
    IFS='|' read -r url name interval timeout content_check <<< "$config_line"
    
    # Validate URL
    url=$(trim_whitespace "$url")
    if ! is_valid_url "$url"; then
        log_error "Invalid URL in configuration: $url"
        return 1
    fi
    
    # Validate name
    name=$(trim_whitespace "$name")
    if [ -z "$name" ]; then
        name="$url"
    fi
    
    # Validate interval
    interval=$(trim_whitespace "$interval")
    if [ -z "$interval" ]; then
        interval="$DEFAULT_INTERVAL"
    elif ! is_number "$interval" || [ "$interval" -lt 10 ]; then
        log_error "Invalid interval for $url: $interval"
        return 1
    fi
    
    # Validate timeout
    timeout=$(trim_whitespace "$timeout")
    if [ -z "$timeout" ]; then
        timeout="$DEFAULT_TIMEOUT"
    elif ! is_number "$timeout" || [ "$timeout" -lt 1 ]; then
        log_error "Invalid timeout for $url: $timeout"
        return 1
    fi
    
    # Validate content check flag
    content_check=$(trim_whitespace "$content_check")
    if [ -z "$content_check" ]; then
        content_check="$DEFAULT_CONTENT_CHECK_ENABLED"
    fi
    
    case "$content_check" in
        true|false|1|0|yes|no)
            ;;
        *)
            log_error "Invalid content_check value for $url: $content_check"
            return 1
            ;;
    esac
    
    log_debug "Validated website config: $url|$name|$interval|$timeout|$content_check"
    return 0
}

# Function: create_default_websites_config
# Purpose: Create default websites configuration file
# Usage: create_default_websites_config <config_file>
create_default_websites_config() {
    local config_file="$1"
    
    ensure_directory "$(dirname "$config_file")"
    
    cat > "$config_file" << EOF
# Website Monitoring Configuration
# Format: URL|Name|Check_Interval|Timeout|Content_Check
# 
# URL: Website URL to monitor (required)
# Name: Display name for the website (optional, defaults to URL)
# Check_Interval: Check interval in seconds (optional, defaults to system default)
# Timeout: Request timeout in seconds (optional, defaults to system default)
# Content_Check: Enable content change detection (true/false, optional, defaults to system default)

# Example configurations:
# https://example.com|Example Site|300|10|true
# https://api.service.com|API Service|60|5|false
EOF
    
    log_info "Created default websites configuration: $config_file"
}

# Function: get_config_value
# Purpose: Get a specific configuration value
# Usage: get_config_value <key> <config_file>
get_config_value() {
    local key="$1"
    local config_file="$2"
    
    if [ -z "$key" ] || [ -z "$config_file" ]; then
        return 1
    fi
    
    if ! file_exists "$config_file"; then
        return 1
    fi
    
    grep "^${key}=" "$config_file" | cut -d'=' -f2- | head -n1
}

# Function: set_config_value
# Purpose: Set a configuration value in a config file
# Usage: set_config_value <key> <value> <config_file>
set_config_value() {
    local key="$1"
    local value="$2"
    local config_file="$3"
    
    if [ -z "$key" ] || [ -z "$config_file" ]; then
        log_error "Key and config file are required"
        return 1
    fi
    
    # Create config file if it doesn't exist
    if [ ! -f "$config_file" ]; then
        ensure_directory "$(dirname "$config_file")"
        touch "$config_file"
    fi
    
    # Check if key already exists
    if grep -q "^${key}=" "$config_file"; then
        # Update existing key
        sed -i "s/^${key}=.*/${key}=${value}/" "$config_file"
        log_debug "Updated configuration: ${key}=${value}"
    else
        # Add new key
        echo "${key}=${value}" >> "$config_file"
        log_debug "Added configuration: ${key}=${value}"
    fi
    
    return 0
}

# Function: reload_monitor_config
# Purpose: Reload monitor configuration without restart
# Usage: reload_monitor_config [config_file]
reload_monitor_config() {
    local config_file="${1:-$CONFIG_DIR/monitor.conf}"
    local old_interval="$MONITOR_INTERVAL"
    local old_timeout="$MONITOR_TIMEOUT"
    
    log_info "Reloading monitor configuration from: $config_file"
    
    # Store current values for comparison
    local prev_values=(
        "MONITOR_INTERVAL=$MONITOR_INTERVAL"
        "MONITOR_TIMEOUT=$MONITOR_TIMEOUT"
        "MAX_CONCURRENT_CHECKS=$MAX_CONCURRENT_CHECKS"
        "LOG_RETENTION_DAYS=$LOG_RETENTION_DAYS"
        "CONTENT_CHECK_ENABLED=$CONTENT_CHECK_ENABLED"
        "SLOW_RESPONSE_THRESHOLD=$SLOW_RESPONSE_THRESHOLD"
    )
    
    # Reload configuration
    load_monitor_config "$config_file"
    
    # Check for changes
    local changes_detected=false
    local current_values=(
        "MONITOR_INTERVAL=$MONITOR_INTERVAL"
        "MONITOR_TIMEOUT=$MONITOR_TIMEOUT"
        "MAX_CONCURRENT_CHECKS=$MAX_CONCURRENT_CHECKS"
        "LOG_RETENTION_DAYS=$LOG_RETENTION_DAYS"
        "CONTENT_CHECK_ENABLED=$CONTENT_CHECK_ENABLED"
        "SLOW_RESPONSE_THRESHOLD=$SLOW_RESPONSE_THRESHOLD"
    )
    
    for i in "${!prev_values[@]}"; do
        if [ "${prev_values[$i]}" != "${current_values[$i]}" ]; then
            changes_detected=true
            log_info "Configuration changed: ${prev_values[$i]} -> ${current_values[$i]}"
        fi
    done
    
    if [ "$changes_detected" = true ]; then
        log_info "Configuration reload completed with changes"
        return 0
    else
        log_info "Configuration reload completed - no changes detected"
        return 1
    fi
}

# Function: validate_config_file_syntax
# Purpose: Validate configuration file syntax
# Usage: validate_config_file_syntax <config_file> <config_type>
validate_config_file_syntax() {
    local config_file="$1"
    local config_type="$2"
    local errors=()
    local warnings=()
    local line_num=0
    
    if [ -z "$config_file" ] || [ -z "$config_type" ]; then
        log_error "Config file and type are required for validation"
        return 1
    fi
    
    if ! file_exists "$config_file"; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    log_debug "Validating $config_type configuration syntax: $config_file"
    
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        line=$(trim_whitespace "$line")
        
        # Skip empty lines and comments
        if [ -z "$line" ] || [[ "$line" =~ ^#.* ]]; then
            continue
        fi
        
        case "$config_type" in
            "monitor")
                validate_monitor_config_line "$line" "$line_num" errors warnings
                ;;
            "websites")
                validate_websites_config_line "$line" "$line_num" errors warnings
                ;;
            *)
                errors+=("Line $line_num: Unknown configuration type: $config_type")
                ;;
        esac
    done < "$config_file"
    
    # Report validation results
    if [ ${#warnings[@]} -gt 0 ]; then
        log_warn "Configuration warnings in $config_file:"
        for warning in "${warnings[@]}"; do
            log_warn "  $warning"
        done
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        log_error "Configuration errors in $config_file:"
        for error in "${errors[@]}"; do
            log_error "  $error"
        done
        return 1
    fi
    
    log_info "Configuration file validation passed: $config_file"
    return 0
}

# Function: validate_monitor_config_line
# Purpose: Validate a single monitor configuration line
# Usage: validate_monitor_config_line <line> <line_num> <errors_array> <warnings_array>
validate_monitor_config_line() {
    local line="$1"
    local line_num="$2"
    local -n errors_ref=$3
    local -n warnings_ref=$4
    
    # Check for key=value format
    if ! [[ "$line" =~ ^[A-Z_][A-Z0-9_]*=.* ]]; then
        errors_ref+=("Line $line_num: Invalid format, expected KEY=VALUE: $line")
        return 1
    fi
    
    # Extract key and value
    local key="${line%%=*}"
    local value="${line#*=}"
    
    # Validate specific keys
    case "$key" in
        DEFAULT_INTERVAL|MONITOR_INTERVAL)
            if ! is_number "$value" || [ "$value" -lt 10 ]; then
                errors_ref+=("Line $line_num: $key must be a number >= 10, got: $value")
            fi
            ;;
        DEFAULT_TIMEOUT|MONITOR_TIMEOUT)
            if ! is_number "$value" || [ "$value" -lt 1 ]; then
                errors_ref+=("Line $line_num: $key must be a number >= 1, got: $value")
            fi
            ;;
        MAX_CONCURRENT_CHECKS)
            if ! is_number "$value" || [ "$value" -lt 1 ] || [ "$value" -gt 50 ]; then
                errors_ref+=("Line $line_num: $key must be a number between 1-50, got: $value")
            fi
            ;;
        LOG_RETENTION_DAYS)
            if ! is_number "$value" || [ "$value" -lt 1 ] || [ "$value" -gt 365 ]; then
                errors_ref+=("Line $line_num: $key must be a number between 1-365, got: $value")
            fi
            ;;
        SLOW_RESPONSE_THRESHOLD)
            if ! is_number "$value" || [ "$value" -lt 100 ] || [ "$value" -gt 60000 ]; then
                errors_ref+=("Line $line_num: $key must be a number between 100-60000, got: $value")
            fi
            ;;
        CONTENT_CHECK_ENABLED)
            case "$value" in
                true|false|1|0|yes|no) ;;
                *) errors_ref+=("Line $line_num: $key must be true/false/1/0/yes/no, got: $value") ;;
            esac
            ;;
        LOG_LEVEL)
            case "$value" in
                ERROR|WARN|INFO|DEBUG) ;;
                *) errors_ref+=("Line $line_num: $key must be ERROR/WARN/INFO/DEBUG, got: $value") ;;
            esac
            ;;
        *)
            warnings_ref+=("Line $line_num: Unknown configuration key: $key")
            ;;
    esac
}

# Function: validate_websites_config_line
# Purpose: Validate a single websites configuration line
# Usage: validate_websites_config_line <line> <line_num> <errors_array> <warnings_array>
validate_websites_config_line() {
    local line="$1"
    local line_num="$2"
    local -n errors_ref=$3
    local -n warnings_ref=$4
    
    # Count pipe separators
    local pipe_count=$(echo "$line" | tr -cd '|' | wc -c)
    if [ "$pipe_count" -ne 4 ]; then
        errors_ref+=("Line $line_num: Expected 4 pipe separators, found $pipe_count: $line")
        return 1
    fi
    
    # Split line by pipe character
    local url name interval timeout content_check
    IFS='|' read -r url name interval timeout content_check <<< "$line"
    
    # Validate URL
    url=$(trim_whitespace "$url")
    if [ -z "$url" ]; then
        errors_ref+=("Line $line_num: URL cannot be empty")
    elif ! is_valid_url "$url"; then
        errors_ref+=("Line $line_num: Invalid URL format: $url")
    fi
    
    # Validate name (optional)
    name=$(trim_whitespace "$name")
    if [ -n "$name" ] && [ ${#name} -gt 100 ]; then
        warnings_ref+=("Line $line_num: Name is very long (${#name} chars): $name")
    fi
    
    # Validate interval
    interval=$(trim_whitespace "$interval")
    if [ -n "$interval" ]; then
        if ! is_number "$interval" || [ "$interval" -lt 10 ] || [ "$interval" -gt 86400 ]; then
            errors_ref+=("Line $line_num: Interval must be a number between 10-86400, got: $interval")
        fi
    fi
    
    # Validate timeout
    timeout=$(trim_whitespace "$timeout")
    if [ -n "$timeout" ]; then
        if ! is_number "$timeout" || [ "$timeout" -lt 1 ] || [ "$timeout" -gt 300 ]; then
            errors_ref+=("Line $line_num: Timeout must be a number between 1-300, got: $timeout")
        fi
    fi
    
    # Validate content check flag
    content_check=$(trim_whitespace "$content_check")
    if [ -n "$content_check" ]; then
        case "$content_check" in
            true|false|1|0|yes|no) ;;
            *) errors_ref+=("Line $line_num: Content check must be true/false/1/0/yes/no, got: $content_check") ;;
        esac
    fi
}

# Function: backup_config_file
# Purpose: Create a backup of configuration file before changes
# Usage: backup_config_file <config_file>
backup_config_file() {
    local config_file="$1"
    
    if [ -z "$config_file" ]; then
        log_error "Config file path required for backup"
        return 1
    fi
    
    if ! file_exists "$config_file"; then
        log_warn "Config file does not exist, cannot backup: $config_file"
        return 1
    fi
    
    local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if cp "$config_file" "$backup_file" 2>/dev/null; then
        log_info "Created config backup: $backup_file"
        return 0
    else
        log_error "Failed to create config backup: $backup_file"
        return 1
    fi
}

# Function: restore_config_backup
# Purpose: Restore configuration from backup
# Usage: restore_config_backup <config_file> <backup_file>
restore_config_backup() {
    local config_file="$1"
    local backup_file="$2"
    
    if [ -z "$config_file" ] || [ -z "$backup_file" ]; then
        log_error "Config file and backup file required for restore"
        return 1
    fi
    
    if ! file_exists "$backup_file"; then
        log_error "Backup file does not exist: $backup_file"
        return 1
    fi
    
    if cp "$backup_file" "$config_file" 2>/dev/null; then
        log_info "Restored config from backup: $backup_file -> $config_file"
        return 0
    else
        log_error "Failed to restore config from backup: $backup_file"
        return 1
    fi
}

# Function: get_config_file_checksum
# Purpose: Get checksum of configuration file for change detection
# Usage: get_config_file_checksum <config_file>
get_config_file_checksum() {
    local config_file="$1"
    
    if [ -z "$config_file" ]; then
        return 1
    fi
    
    if ! file_exists "$config_file"; then
        return 1
    fi
    
    # Use md5sum if available, fallback to cksum
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$config_file" | cut -d' ' -f1
    elif command -v cksum >/dev/null 2>&1; then
        cksum "$config_file" | cut -d' ' -f1
    else
        # Fallback to file size and modification time
        stat -c "%s-%Y" "$config_file" 2>/dev/null || stat -f "%z-%m" "$config_file" 2>/dev/null
    fi
}

# Function: watch_config_changes
# Purpose: Monitor configuration files for changes
# Usage: watch_config_changes <config_file> <callback_function>
watch_config_changes() {
    local config_file="$1"
    local callback_function="$2"
    local check_interval="${3:-5}"
    
    if [ -z "$config_file" ] || [ -z "$callback_function" ]; then
        log_error "Config file and callback function required for watching"
        return 1
    fi
    
    if ! file_exists "$config_file"; then
        log_error "Config file does not exist: $config_file"
        return 1
    fi
    
    local last_checksum
    last_checksum=$(get_config_file_checksum "$config_file")
    
    log_info "Watching for changes in: $config_file"
    
    while true; do
        sleep "$check_interval"
        
        local current_checksum
        current_checksum=$(get_config_file_checksum "$config_file")
        
        if [ "$current_checksum" != "$last_checksum" ]; then
            log_info "Configuration file changed: $config_file"
            
            # Call the callback function
            if command -v "$callback_function" >/dev/null 2>&1; then
                "$callback_function" "$config_file"
            else
                log_error "Callback function not found: $callback_function"
            fi
            
            last_checksum="$current_checksum"
        fi
    done
}

# Function: export_config_variables
# Purpose: Export configuration variables for use in other scripts
# Usage: export_config_variables
export_config_variables() {
    export MONITOR_INTERVAL
    export MONITOR_TIMEOUT
    export MAX_CONCURRENT_CHECKS
    export LOG_RETENTION_DAYS
    export CONTENT_CHECK_ENABLED
    export SLOW_RESPONSE_THRESHOLD
    export LOG_LEVEL
    
    log_debug "Configuration variables exported"
}

# Function: print_config_summary
# Purpose: Print current configuration summary
# Usage: print_config_summary
print_config_summary() {
    echo "=== Configuration Summary ==="
    echo "Monitor Interval: ${MONITOR_INTERVAL}s"
    echo "Monitor Timeout: ${MONITOR_TIMEOUT}s"
    echo "Max Concurrent Checks: ${MAX_CONCURRENT_CHECKS}"
    echo "Log Retention Days: ${LOG_RETENTION_DAYS}"
    echo "Content Check Enabled: ${CONTENT_CHECK_ENABLED}"
    echo "Slow Response Threshold: ${SLOW_RESPONSE_THRESHOLD}ms"
    echo "Log Level: ${LOG_LEVEL:-INFO}"
    echo "============================"
}