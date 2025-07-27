#!/bin/bash

# Common utility functions for website monitoring system
# This file contains shared functions used across multiple components

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
DATA_DIR="$PROJECT_ROOT/data"
LOG_DIR="$DATA_DIR/logs"

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log levels
LOG_LEVEL_ERROR=1
LOG_LEVEL_WARN=2
LOG_LEVEL_INFO=3
LOG_LEVEL_DEBUG=4

# Default log level
DEFAULT_LOG_LEVEL=$LOG_LEVEL_INFO

# Function: log_message
# Purpose: Write formatted log messages with timestamp and level
# Usage: log_message <level> <message>
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Validate log level
    if ! is_valid_log_level "$level"; then
        echo "ERROR: Invalid log level: $level" >&2
        return 1
    fi
    
    # Format and output message
    echo "[$timestamp] [$level] $message"
}

# Function: log_error
# Purpose: Log error messages
# Usage: log_error <message>
log_error() {
    log_message "ERROR" "$1" >&2
}

# Function: log_warn
# Purpose: Log warning messages
# Usage: log_warn <message>
log_warn() {
    log_message "WARN" "$1" >&2
}

# Function: log_info
# Purpose: Log informational messages
# Usage: log_info <message>
log_info() {
    log_message "INFO" "$1" >&2
}

# Function: log_debug
# Purpose: Log debug messages
# Usage: log_debug <message>
log_debug() {
    # Only output debug messages in verbose mode
    if [ "${CHECK_VERBOSE:-false}" = true ]; then
        log_message "DEBUG" "$1" >&2
    fi
}

# Function: is_valid_log_level
# Purpose: Validate log level string
# Usage: is_valid_log_level <level>
is_valid_log_level() {
    local level="$1"
    case "$level" in
        ERROR|WARN|INFO|DEBUG)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function: ensure_directory
# Purpose: Create directory if it doesn't exist
# Usage: ensure_directory <path>
ensure_directory() {
    local dir_path="$1"
    
    if [ -z "$dir_path" ]; then
        log_error "Directory path cannot be empty"
        return 1
    fi
    
    if [ ! -d "$dir_path" ]; then
        if mkdir -p "$dir_path" 2>/dev/null; then
            log_debug "Created directory: $dir_path"
            return 0
        else
            log_error "Failed to create directory: $dir_path"
            return 1
        fi
    fi
    
    return 0
}

# Function: file_exists
# Purpose: Check if file exists and is readable
# Usage: file_exists <file_path>
file_exists() {
    local file_path="$1"
    
    if [ -z "$file_path" ]; then
        return 1
    fi
    
    [ -f "$file_path" ] && [ -r "$file_path" ]
}

# Function: is_valid_url
# Purpose: Basic URL validation
# Usage: is_valid_url <url>
is_valid_url() {
    local url="$1"
    
    if [ -z "$url" ]; then
        return 1
    fi
    
    # Basic URL pattern matching
    echo "$url" | grep -qE '^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$'
}

# Function: is_number
# Purpose: Check if string is a valid number
# Usage: is_number <string>
is_number() {
    local string="$1"
    
    if [ -z "$string" ]; then
        return 1
    fi
    
    echo "$string" | grep -qE '^[0-9]+$'
}

# Function: trim_whitespace
# Purpose: Remove leading and trailing whitespace
# Usage: trim_whitespace <string>
trim_whitespace() {
    local string="$1"
    
    # Remove leading whitespace
    string="${string#"${string%%[![:space:]]*}"}"
    # Remove trailing whitespace
    string="${string%"${string##*[![:space:]]}"}"
    
    echo "$string"
}

# Function: get_timestamp
# Purpose: Get current timestamp in standard format
# Usage: get_timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function: get_epoch_timestamp
# Purpose: Get current epoch timestamp
# Usage: get_epoch_timestamp
get_epoch_timestamp() {
    date '+%s'
}

# Function: calculate_time_difference
# Purpose: Calculate human-readable time difference between two timestamps
# Usage: calculate_time_difference <timestamp1> <timestamp2>
calculate_time_difference() {
    local timestamp1="$1"
    local timestamp2="$2"
    
    if [ -z "$timestamp1" ] || [ -z "$timestamp2" ]; then
        echo "unknown"
        return 1
    fi
    
    # Convert timestamps to epoch seconds
    local epoch1
    local epoch2
    
    epoch1=$(date -d "$timestamp1" +%s 2>/dev/null) || {
        echo "invalid timestamp"
        return 1
    }
    
    epoch2=$(date -d "$timestamp2" +%s 2>/dev/null) || {
        echo "invalid timestamp"
        return 1
    }
    
    # Calculate difference in seconds
    local diff_seconds=$((epoch2 - epoch1))
    
    # Handle negative differences
    if [ $diff_seconds -lt 0 ]; then
        diff_seconds=$((-diff_seconds))
    fi
    
    # Convert to human-readable format
    if [ $diff_seconds -lt 60 ]; then
        echo "${diff_seconds}s"
    elif [ $diff_seconds -lt 3600 ]; then
        local minutes=$((diff_seconds / 60))
        echo "${minutes}m"
    elif [ $diff_seconds -lt 86400 ]; then
        local hours=$((diff_seconds / 3600))
        local minutes=$(((diff_seconds % 3600) / 60))
        if [ $minutes -eq 0 ]; then
            echo "${hours}h"
        else
            echo "${hours}h ${minutes}m"
        fi
    else
        local days=$((diff_seconds / 86400))
        local hours=$(((diff_seconds % 86400) / 3600))
        if [ $hours -eq 0 ]; then
            echo "${days}d"
        else
            echo "${days}d ${hours}h"
        fi
    fi
}

# Function: log_content_change
# Purpose: Log content change events with detailed information
# Usage: log_content_change <url> <change_type> <current_hash> <previous_hash> <summary>
log_content_change() {
    local url="$1"
    local change_type="$2"
    local current_hash="$3"
    local previous_hash="$4"
    local summary="$5"
    
    if [ -z "$url" ] || [ -z "$change_type" ] || [ -z "$current_hash" ]; then
        log_error "Invalid parameters for content change logging"
        return 1
    fi
    
    # Use the new logging system if available
    if command -v log_content_change_event >/dev/null 2>&1; then
        log_content_change_event "$url" "$change_type" "$current_hash" "$previous_hash" "$summary"
        return $?
    fi
    
    # Fallback to original implementation
    local timestamp
    timestamp=$(get_timestamp)
    
    # Ensure content change log directory exists
    ensure_directory "$LOG_DIR"
    
    local content_log_file="$LOG_DIR/content-changes.log"
    
    # Format: timestamp|url|change_type|current_hash|previous_hash|summary
    local log_entry="${timestamp}|${url}|${change_type}|${current_hash}|${previous_hash:-}|${summary:-}"
    
    # Write to content change log
    if echo "$log_entry" >> "$content_log_file" 2>/dev/null; then
        log_debug "Content change logged: $change_type for $url"
        
        # Also log to main monitoring log if it exists
        local main_log_file="$LOG_DIR/monitor.log"
        if [ -f "$main_log_file" ] || touch "$main_log_file" 2>/dev/null; then
            local main_log_entry="${timestamp}|INFO|${url}|CONTENT_${change_type}|${summary:-Content change detected}"
            echo "$main_log_entry" >> "$main_log_file" 2>/dev/null
        fi
        
        return 0
    else
        log_error "Failed to write content change log entry"
        return 1
    fi
}

# Function: validate_required_commands
# Purpose: Check if required system commands are available
# Usage: validate_required_commands
validate_required_commands() {
    local required_commands=("curl" "grep" "awk" "sed" "sort" "uniq")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        return 1
    fi
    
    log_debug "All required commands are available"
    return 0
}

# Function: cleanup_on_exit
# Purpose: Cleanup function to be called on script exit
# Usage: cleanup_on_exit
cleanup_on_exit() {
    log_debug "Performing cleanup on exit"
    # Add cleanup logic here as needed
}

# Function: setup_signal_handlers
# Purpose: Set up signal handlers for graceful shutdown
# Usage: setup_signal_handlers
setup_signal_handlers() {
    trap cleanup_on_exit EXIT
    trap 'log_info "Received SIGINT, shutting down..."; exit 130' INT
    trap 'log_info "Received SIGTERM, shutting down..."; exit 143' TERM
}

# Function: print_colored
# Purpose: Print colored text to terminal
# Usage: print_colored <color> <message>
print_colored() {
    local color="$1"
    local message="$2"
    
    case "$color" in
        red)
            echo -e "${RED}${message}${NC}"
            ;;
        green)
            echo -e "${GREEN}${message}${NC}"
            ;;
        yellow)
            echo -e "${YELLOW}${message}${NC}"
            ;;
        blue)
            echo -e "${BLUE}${message}${NC}"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Error handling and validation functions

# Function: die
# Purpose: Print error message and exit with specified code
# Usage: die <message> [exit_code]
die() {
    local message="$1"
    local exit_code="${2:-1}"
    
    log_error "$message"
    exit "$exit_code"
}

# Function: assert_command_exists
# Purpose: Check if command exists, exit if not found
# Usage: assert_command_exists <command>
assert_command_exists() {
    local command="$1"
    
    if [ -z "$command" ]; then
        die "Command name cannot be empty"
    fi
    
    if ! command -v "$command" >/dev/null 2>&1; then
        die "Required command not found: $command"
    fi
    
    log_debug "Command available: $command"
}

# Function: assert_file_exists
# Purpose: Check if file exists, exit if not found
# Usage: assert_file_exists <file_path>
assert_file_exists() {
    local file_path="$1"
    
    if [ -z "$file_path" ]; then
        die "File path cannot be empty"
    fi
    
    if ! file_exists "$file_path"; then
        die "Required file not found: $file_path"
    fi
    
    log_debug "File exists: $file_path"
}

# Function: assert_directory_exists
# Purpose: Check if directory exists, exit if not found
# Usage: assert_directory_exists <dir_path>
assert_directory_exists() {
    local dir_path="$1"
    
    if [ -z "$dir_path" ]; then
        die "Directory path cannot be empty"
    fi
    
    if [ ! -d "$dir_path" ]; then
        die "Required directory not found: $dir_path"
    fi
    
    log_debug "Directory exists: $dir_path"
}

# Function: validate_input
# Purpose: Validate input against pattern
# Usage: validate_input <input> <pattern> <error_message>
validate_input() {
    local input="$1"
    local pattern="$2"
    local error_message="$3"
    
    if [ -z "$input" ]; then
        log_error "Input cannot be empty: $error_message"
        return 1
    fi
    
    if ! echo "$input" | grep -qE "$pattern"; then
        log_error "Invalid input: $error_message"
        return 1
    fi
    
    return 0
}

# Function: check_disk_space
# Purpose: Check available disk space in specified directory
# Usage: check_disk_space <directory> <min_mb>
check_disk_space() {
    local directory="$1"
    local min_mb="$2"
    
    if [ -z "$directory" ] || [ -z "$min_mb" ]; then
        log_error "Directory and minimum MB required for disk space check"
        return 1
    fi
    
    if [ ! -d "$directory" ]; then
        log_error "Directory does not exist: $directory"
        return 1
    fi
    
    # Get available space in MB (works on most Unix systems)
    local available_mb
    if command -v df >/dev/null 2>&1; then
        available_mb=$(df -m "$directory" | awk 'NR==2 {print $4}')
        
        if [ -n "$available_mb" ] && is_number "$available_mb"; then
            if [ "$available_mb" -lt "$min_mb" ]; then
                log_warn "Low disk space in $directory: ${available_mb}MB available, ${min_mb}MB required"
                return 1
            else
                log_debug "Sufficient disk space in $directory: ${available_mb}MB available"
                return 0
            fi
        fi
    fi
    
    log_warn "Could not determine disk space for: $directory"
    return 1
}

# Function: create_lock_file
# Purpose: Create lock file to prevent multiple instances
# Usage: create_lock_file <lock_file>
create_lock_file() {
    local lock_file="$1"
    
    if [ -z "$lock_file" ]; then
        log_error "Lock file path cannot be empty"
        return 1
    fi
    
    # Check if lock file already exists
    if [ -f "$lock_file" ]; then
        local pid
        pid=$(cat "$lock_file" 2>/dev/null)
        
        # Check if process is still running
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log_error "Another instance is already running (PID: $pid)"
            return 1
        else
            log_warn "Removing stale lock file: $lock_file"
            rm -f "$lock_file"
        fi
    fi
    
    # Create lock file with current PID
    echo $$ > "$lock_file"
    if [ $? -eq 0 ]; then
        log_debug "Created lock file: $lock_file"
        return 0
    else
        log_error "Failed to create lock file: $lock_file"
        return 1
    fi
}

# Function: remove_lock_file
# Purpose: Remove lock file
# Usage: remove_lock_file <lock_file>
remove_lock_file() {
    local lock_file="$1"
    
    if [ -z "$lock_file" ]; then
        return 1
    fi
    
    if [ -f "$lock_file" ]; then
        rm -f "$lock_file"
        log_debug "Removed lock file: $lock_file"
    fi
}

# Function: rotate_log_file
# Purpose: Rotate log file if it exceeds size limit
# Usage: rotate_log_file <log_file> <max_size_mb>
rotate_log_file() {
    local log_file="$1"
    local max_size_mb="$2"
    
    if [ -z "$log_file" ] || [ -z "$max_size_mb" ]; then
        return 1
    fi
    
    if [ ! -f "$log_file" ]; then
        return 0
    fi
    
    # Get file size in MB
    local file_size_mb
    if command -v stat >/dev/null 2>&1; then
        # Try GNU stat first
        file_size_mb=$(stat -c%s "$log_file" 2>/dev/null | awk '{print int($1/1024/1024)}')
        
        # Try BSD stat if GNU stat failed
        if [ -z "$file_size_mb" ]; then
            file_size_mb=$(stat -f%z "$log_file" 2>/dev/null | awk '{print int($1/1024/1024)}')
        fi
    fi
    
    if [ -n "$file_size_mb" ] && is_number "$file_size_mb" && [ "$file_size_mb" -gt "$max_size_mb" ]; then
        local rotated_file="${log_file}.$(date +%Y%m%d_%H%M%S)"
        
        if mv "$log_file" "$rotated_file" 2>/dev/null; then
            log_info "Rotated log file: $log_file -> $rotated_file"
            touch "$log_file"
        else
            log_warn "Failed to rotate log file: $log_file"
        fi
    fi
}

# Function: cleanup_old_files
# Purpose: Remove files older than specified days
# Usage: cleanup_old_files <directory> <days> <pattern>
cleanup_old_files() {
    local directory="$1"
    local days="$2"
    local pattern="${3:-*}"
    
    if [ -z "$directory" ] || [ -z "$days" ]; then
        log_error "Directory and days required for cleanup"
        return 1
    fi
    
    if [ ! -d "$directory" ]; then
        log_error "Directory does not exist: $directory"
        return 1
    fi
    
    if ! is_number "$days" || [ "$days" -lt 1 ]; then
        log_error "Days must be a positive number: $days"
        return 1
    fi
    
    # Find and remove old files
    local removed_count=0
    if command -v find >/dev/null 2>&1; then
        while IFS= read -r -d '' file; do
            if rm -f "$file" 2>/dev/null; then
                removed_count=$((removed_count + 1))
                log_debug "Removed old file: $file"
            fi
        done < <(find "$directory" -name "$pattern" -type f -mtime +$days -print0 2>/dev/null)
        
        if [ "$removed_count" -gt 0 ]; then
            log_info "Cleaned up $removed_count old file(s) from $directory"
        fi
    else
        log_warn "find command not available, skipping cleanup"
    fi
}

# Initialize common directories on source
ensure_directory "$LOG_DIR"
ensure_directory "$DATA_DIR/content-hashes"
ensure_directory "$DATA_DIR/reports"

# Export commonly used variables and functions
export PROJECT_ROOT CONFIG_DIR DATA_DIR LOG_DIR
export RED GREEN YELLOW BLUE NC
export LOG_LEVEL_ERROR LOG_LEVEL_WARN LOG_LEVEL_INFO LOG_LEVEL_DEBUG