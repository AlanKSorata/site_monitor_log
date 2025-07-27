#!/bin/bash

# Individual Website Checker Script
# Performs availability, response time, and content change detection for a single website

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"

# Source required libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/http-utils.sh"

# Default configuration
DEFAULT_TIMEOUT=10
DEFAULT_RETRIES=3
DEFAULT_RETRY_DELAY=2
DEFAULT_CONTENT_CHECK=false
DEFAULT_OUTPUT_FORMAT="structured"
DEFAULT_USER_AGENT="Website-Monitor/1.0"

# Global variables for results
CHECK_TIMESTAMP=""
CHECK_URL=""
CHECK_STATUS_CODE=""
CHECK_RESPONSE_TIME=""
CHECK_CONTENT_HASH=""
CHECK_STATUS=""
CHECK_ERROR_MESSAGE=""

#
# Display usage information
#
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] <URL>

Check website availability, response time, and content changes.

ARGUMENTS:
    URL                     Website URL to check (required)

OPTIONS:
    -t, --timeout SECONDS   Request timeout in seconds (default: $DEFAULT_TIMEOUT)
    -r, --retries COUNT     Number of retry attempts for failed checks (default: $DEFAULT_RETRIES)
    -d, --retry-delay SEC   Delay between retries in seconds (default: $DEFAULT_RETRY_DELAY)
    -c, --content-check     Enable content change detection (default: disabled)
    -f, --format FORMAT     Output format: structured, json, human (default: $DEFAULT_OUTPUT_FORMAT)
    -v, --verbose           Enable verbose logging
    -h, --help             Show this help message

OUTPUT FORMATS:
    structured: timestamp|url|status_code|response_time_ms|content_hash|status|error_message
    json:       JSON formatted output
    human:      Human-readable format

EXAMPLES:
    $0 https://example.com
    $0 --timeout 15 --retries 5 --content-check https://api.service.com
    $0 --format json --verbose https://www.google.com

EXIT CODES:
    0: Website is available
    1: Website is not available or error occurred
    2: Invalid arguments or configuration error
EOF
}

#
# Parse command line arguments
#
parse_arguments() {
    local timeout="$DEFAULT_TIMEOUT"
    local retries="$DEFAULT_RETRIES"
    local retry_delay="$DEFAULT_RETRY_DELAY"
    local content_check="$DEFAULT_CONTENT_CHECK"
    local output_format="$DEFAULT_OUTPUT_FORMAT"
    local verbose=false
    local url=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--timeout)
                timeout="$2"
                if ! is_number "$timeout" || [ "$timeout" -lt 1 ]; then
                    die "Invalid timeout value: $timeout (must be positive integer)" 2
                fi
                shift 2
                ;;
            -r|--retries)
                retries="$2"
                if ! is_number "$retries" || [ "$retries" -lt 0 ]; then
                    die "Invalid retries value: $retries (must be non-negative integer)" 2
                fi
                shift 2
                ;;
            -d|--retry-delay)
                retry_delay="$2"
                if ! is_number "$retry_delay" || [ "$retry_delay" -lt 1 ]; then
                    die "Invalid retry delay value: $retry_delay (must be positive integer)" 2
                fi
                shift 2
                ;;
            -c|--content-check)
                content_check=true
                shift
                ;;
            -f|--format)
                output_format="$2"
                case "$output_format" in
                    structured|json|human)
                        ;;
                    *)
                        die "Invalid output format: $output_format (must be structured, json, or human)" 2
                        ;;
                esac
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
                if [ -z "$url" ]; then
                    url="$1"
                else
                    die "Multiple URLs specified. Only one URL is allowed." 2
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$url" ]; then
        die "URL argument is required. Use --help for usage information." 2
    fi

    # Validate URL format
    if ! http_validate_url "$url"; then
        die "Invalid URL format: $url" 2
    fi

    # Export parsed values
    export CHECK_TIMEOUT="$timeout"
    export CHECK_RETRIES="$retries"
    export CHECK_RETRY_DELAY="$retry_delay"
    export CHECK_CONTENT_CHECK="$content_check"
    export CHECK_OUTPUT_FORMAT="$output_format"
    export CHECK_VERBOSE="$verbose"
    export CHECK_URL="$url"
}

#
# Calculate content hash for change detection
# Arguments:
#   $1 - URL to fetch content from
#   $2 - Timeout in seconds
# Returns:
#   Prints content hash on success, empty string on failure
#   Sets global CONTENT_FETCH_ERROR with error details
#
calculate_content_hash() {
    local url="$1"
    local timeout="$2"
    
    # Initialize error tracking
    CONTENT_FETCH_ERROR=""
    
    # Use curl to get content and calculate hash
    local content_hash=""
    local curl_output
    local curl_error
    local temp_file
    
    # Create temporary file for content
    temp_file=$(mktemp 2>/dev/null) || {
        CONTENT_FETCH_ERROR="Failed to create temporary file for content"
        echo ""
        return 1
    }
    
    # Fetch content with error handling
    curl_error=$(curl --silent --show-error --max-time "$timeout" \
                     --user-agent "$DEFAULT_USER_AGENT" \
                     --location --max-redirs 5 \
                     --output "$temp_file" \
                     "$url" 2>&1)
    local curl_exit_code=$?
    
    if [ $curl_exit_code -eq 0 ]; then
        # Calculate hash from downloaded content
        if [ -s "$temp_file" ]; then
            content_hash=$(sha256sum "$temp_file" 2>/dev/null | cut -d' ' -f1)
            if [ -z "$content_hash" ]; then
                CONTENT_FETCH_ERROR="Failed to calculate content hash"
            fi
        else
            CONTENT_FETCH_ERROR="Downloaded content is empty"
        fi
    else
        # Handle curl errors
        case $curl_exit_code in
            6)
                CONTENT_FETCH_ERROR="Could not resolve host for content fetch"
                ;;
            7)
                CONTENT_FETCH_ERROR="Failed to connect to host for content fetch"
                ;;
            28)
                CONTENT_FETCH_ERROR="Content fetch timeout after ${timeout} seconds"
                ;;
            35)
                CONTENT_FETCH_ERROR="SSL connect error during content fetch"
                ;;
            52)
                CONTENT_FETCH_ERROR="Empty reply from server during content fetch"
                ;;
            *)
                CONTENT_FETCH_ERROR="Content fetch failed: $curl_error"
                ;;
        esac
    fi
    
    # Cleanup temporary file
    rm -f "$temp_file" 2>/dev/null
    
    echo "$content_hash"
    
    if [ -n "$content_hash" ]; then
        return 0
    else
        return 1
    fi
}

#
# Store content hash for future comparison
#
store_content_hash() {
    local url="$1"
    local content_hash="$2"
    
    if [ -z "$content_hash" ]; then
        return 1
    fi
    
    # Create hash filename based on URL
    local hash_filename
    hash_filename=$(echo "$url" | sha256sum | cut -d' ' -f1)
    local hash_file="$DATA_DIR/content-hashes/${hash_filename}.txt"
    
    # Ensure directory exists
    ensure_directory "$DATA_DIR/content-hashes"
    
    # Store hash with timestamp
    echo "$(get_timestamp)|$content_hash" > "$hash_file"
    
    return $?
}

#
# Check for content changes and log detailed information
# Arguments:
#   $1 - URL being checked
#   $2 - Current content hash
# Returns:
#   0 if no change detected, 1 if change detected
#   Sets global CONTENT_CHANGE_SUMMARY with change details
#
check_content_changes() {
    local url="$1"
    local current_hash="$2"
    
    # Initialize change summary
    CONTENT_CHANGE_SUMMARY=""
    
    if [ -z "$current_hash" ]; then
        CONTENT_CHANGE_SUMMARY="Content hash calculation failed"
        return 1
    fi
    
    # Create hash filename based on URL
    local hash_filename
    hash_filename=$(echo "$url" | sha256sum | cut -d' ' -f1)
    local hash_file="$DATA_DIR/content-hashes/${hash_filename}.txt"
    
    # Check if previous hash exists
    if [ ! -f "$hash_file" ]; then
        # First time checking this URL
        if store_content_hash "$url" "$current_hash"; then
            CONTENT_CHANGE_SUMMARY="Initial content hash stored"
            log_content_change "$url" "INITIAL" "$current_hash" "" "First time monitoring this URL"
        else
            CONTENT_CHANGE_SUMMARY="Failed to store initial content hash"
            log_error "Failed to store initial content hash for $url"
            return 1
        fi
        return 0
    fi
    
    # Read previous hash and timestamp
    local previous_entry
    local previous_hash
    local previous_timestamp
    
    previous_entry=$(tail -n 1 "$hash_file" 2>/dev/null)
    if [ -n "$previous_entry" ]; then
        previous_timestamp=$(echo "$previous_entry" | cut -d'|' -f1)
        previous_hash=$(echo "$previous_entry" | cut -d'|' -f2)
    else
        CONTENT_CHANGE_SUMMARY="Failed to read previous content hash"
        log_error "Failed to read previous content hash from $hash_file"
        return 1
    fi
    
    if [ "$current_hash" != "$previous_hash" ]; then
        # Content has changed
        local current_timestamp
        current_timestamp=$(get_timestamp)
        
        # Calculate time since last change
        local time_diff=""
        if [ -n "$previous_timestamp" ]; then
            time_diff=$(calculate_time_difference "$previous_timestamp" "$current_timestamp")
        fi
        
        # Store new hash
        if store_content_hash "$url" "$current_hash"; then
            CONTENT_CHANGE_SUMMARY="Content changed (previous: ${previous_hash:0:8}..., current: ${current_hash:0:8}...)"
            if [ -n "$time_diff" ]; then
                CONTENT_CHANGE_SUMMARY="$CONTENT_CHANGE_SUMMARY, last change: $time_diff ago"
            fi
            
            # Log the content change
            log_content_change "$url" "CHANGED" "$current_hash" "$previous_hash" "$CONTENT_CHANGE_SUMMARY"
        else
            CONTENT_CHANGE_SUMMARY="Content changed but failed to store new hash"
            log_error "Content changed for $url but failed to store new hash"
        fi
        return 1
    else
        CONTENT_CHANGE_SUMMARY="No content change detected"
        return 0
    fi
}

#
# Perform website check with retry mechanism
#
perform_website_check() {
    local url="$1"
    local timeout="$2"
    local retries="$3"
    local retry_delay="$4"
    local content_check="$5"
    
    local attempt=1
    local max_attempts=$((retries + 1))
    local check_result
    local content_hash=""
    local content_changed=false
    
    while [ $attempt -le $max_attempts ]; do
        if [ "$CHECK_VERBOSE" = true ]; then
            log_info "Attempt $attempt/$max_attempts: Checking $url"
        fi
        
        # Perform HTTP check
        http_check_website "$url" "$timeout"
        check_result=$?
        
        # Set global variables from HTTP check
        CHECK_STATUS_CODE="$HTTP_STATUS_CODE"
        CHECK_RESPONSE_TIME="$HTTP_RESPONSE_TIME_MS"
        CHECK_ERROR_MESSAGE="$HTTP_ERROR_MESSAGE"
        
        # Determine status based on HTTP check result
        if [ $check_result -eq 0 ]; then
            if http_is_website_available "$CHECK_STATUS_CODE"; then
                CHECK_STATUS="available"
                
                # Perform content check if enabled
                if [ "$content_check" = true ]; then
                    content_hash=$(calculate_content_hash "$url" "$timeout")
                    if [ -n "$content_hash" ]; then
                        CHECK_CONTENT_HASH="$content_hash"
                        if ! check_content_changes "$url" "$content_hash"; then
                            content_changed=true
                            if [ "$CHECK_VERBOSE" = true ]; then
                                log_info "Content change detected for $url: $CONTENT_CHANGE_SUMMARY"
                            fi
                        else
                            if [ "$CHECK_VERBOSE" = true ]; then
                                log_debug "Content check for $url: $CONTENT_CHANGE_SUMMARY"
                            fi
                        fi
                    else
                        # Handle content fetch errors gracefully
                        if [ -n "$CONTENT_FETCH_ERROR" ]; then
                            if [ "$CHECK_VERBOSE" = true ]; then
                                log_warn "Content hash calculation failed for $url: $CONTENT_FETCH_ERROR"
                            fi
                            # Log the content fetch failure
                            log_content_change "$url" "ERROR" "" "" "Content fetch failed: $CONTENT_FETCH_ERROR"
                        else
                            if [ "$CHECK_VERBOSE" = true ]; then
                                log_warn "Failed to calculate content hash for $url: unknown error"
                            fi
                        fi
                    fi
                fi
                
                # Success - break out of retry loop
                break
            else
                CHECK_STATUS="unavailable"
                CHECK_ERROR_MESSAGE="HTTP status indicates unavailable: $(http_get_status_description "$CHECK_STATUS_CODE")"
                # Don't retry for HTTP error status codes - they're not network errors
                break
            fi
        else
            CHECK_STATUS="error"
            # Error message already set by http_check_website
            
            # If this was the last attempt, break
            if [ $attempt -eq $max_attempts ]; then
                break
            fi
            
            # Wait before retry (only for actual network errors)
            if [ "$CHECK_VERBOSE" = true ]; then
                log_warn "Check failed, retrying in ${retry_delay} seconds..."
            fi
            sleep "$retry_delay"
            attempt=$((attempt + 1))
            continue
        fi
    done
    
    # Add content change information to status if applicable
    if [ "$content_changed" = true ]; then
        if [ -n "$CHECK_ERROR_MESSAGE" ]; then
            CHECK_ERROR_MESSAGE="$CHECK_ERROR_MESSAGE; Content changed"
        else
            CHECK_ERROR_MESSAGE="Content changed"
        fi
    fi
    
    # Return appropriate exit code
    case "$CHECK_STATUS" in
        available)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#
# Format output based on specified format
#
format_output() {
    local format="$1"
    
    case "$format" in
        structured)
            printf "%s|%s|%s|%s|%s|%s|%s\n" \
                "$CHECK_TIMESTAMP" \
                "$CHECK_URL" \
                "${CHECK_STATUS_CODE:-0}" \
                "${CHECK_RESPONSE_TIME:-0}" \
                "${CHECK_CONTENT_HASH:-}" \
                "$CHECK_STATUS" \
                "${CHECK_ERROR_MESSAGE:-}"
            ;;
        json)
            cat << EOF
{
  "timestamp": "$CHECK_TIMESTAMP",
  "url": "$CHECK_URL",
  "status_code": ${CHECK_STATUS_CODE:-0},
  "response_time_ms": ${CHECK_RESPONSE_TIME:-0},
  "content_hash": "${CHECK_CONTENT_HASH:-}",
  "status": "$CHECK_STATUS",
  "error_message": "${CHECK_ERROR_MESSAGE:-}",
  "content_changed": $([ -n "$CHECK_ERROR_MESSAGE" ] && echo "$CHECK_ERROR_MESSAGE" | grep -q "Content changed" && echo "true" || echo "false"),
  "content_change_summary": "${CONTENT_CHANGE_SUMMARY:-}"
}
EOF
            ;;
        human)
            echo "Website Check Results:"
            echo "  URL: $CHECK_URL"
            echo "  Timestamp: $CHECK_TIMESTAMP"
            echo "  Status: $CHECK_STATUS"
            echo "  HTTP Status Code: ${CHECK_STATUS_CODE:-N/A}"
            echo "  Response Time: ${CHECK_RESPONSE_TIME:-N/A}ms"
            if [ -n "$CHECK_CONTENT_HASH" ]; then
                echo "  Content Hash: $CHECK_CONTENT_HASH"
            fi
            if [ -n "$CONTENT_CHANGE_SUMMARY" ]; then
                echo "  Content Change: $CONTENT_CHANGE_SUMMARY"
            fi
            if [ -n "$CHECK_ERROR_MESSAGE" ]; then
                echo "  Error/Notes: $CHECK_ERROR_MESSAGE"
            fi
            ;;
    esac
}

#
# Main execution function
#
main() {
    # Set up signal handlers
    setup_signal_handlers
    
    # Validate required commands
    validate_required_commands
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set timestamp
    CHECK_TIMESTAMP=$(get_timestamp)
    
    # Perform the website check
    if perform_website_check "$CHECK_URL" "$CHECK_TIMEOUT" "$CHECK_RETRIES" "$CHECK_RETRY_DELAY" "$CHECK_CONTENT_CHECK"; then
        check_exit_code=0
    else
        check_exit_code=1
    fi
    
    # Output results
    format_output "$CHECK_OUTPUT_FORMAT"
    
    # Exit with appropriate code
    exit $check_exit_code
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi