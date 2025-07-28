#!/bin/bash

# HTTP Utilities Library
# Provides functions for HTTP requests, response time measurement, and status code handling

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/error-recovery.sh"

# Default timeout in seconds
DEFAULT_TIMEOUT=10
DEFAULT_USER_AGENT="Website-Monitor/1.0"

# HTTP status code categories
HTTP_SUCCESS_MIN=200
HTTP_SUCCESS_MAX=299
HTTP_REDIRECT_MIN=300
HTTP_REDIRECT_MAX=399
HTTP_CLIENT_ERROR_MIN=400
HTTP_CLIENT_ERROR_MAX=499
HTTP_SERVER_ERROR_MIN=500
HTTP_SERVER_ERROR_MAX=599

#
# Perform HTTP request with response time measurement
# Arguments:
#   $1 - URL to check
#   $2 - Timeout in seconds (optional, defaults to DEFAULT_TIMEOUT)
#   $3 - Follow redirects flag (optional, "true" or "false", defaults to "true")
# Returns:
#   Sets global variables: HTTP_STATUS_CODE, HTTP_RESPONSE_TIME_MS, HTTP_ERROR_MESSAGE
#   Exit code: 0 for successful request, 1 for network error, 2 for timeout
#
http_check_website() {
    local url="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"
    local follow_redirects="${3:-true}"
    
    # Initialize return variables
    HTTP_STATUS_CODE=""
    HTTP_RESPONSE_TIME_MS=""
    HTTP_ERROR_MESSAGE=""
    
    # Validate input
    if [[ -z "$url" ]]; then
        HTTP_ERROR_MESSAGE="URL parameter is required"
        return 2
    fi
    
    # Validate URL format
    if ! http_validate_url "$url"; then
        HTTP_ERROR_MESSAGE="Invalid URL format: $url"
        return 2
    fi
    
    # Prepare curl options
    local curl_opts=(
        --silent
        --show-error
        --max-time "$timeout"
        --user-agent "$DEFAULT_USER_AGENT"
        --write-out "%{http_code}|%{time_total}"
        --output /dev/null
    )
    
    # Add redirect handling
    if [[ "$follow_redirects" == "true" ]]; then
        curl_opts+=(--location --max-redirs 5)
    fi
    
    # Record start time for precise measurement
    local start_time
    start_time=$(date +%s%3N)
    
    # Execute curl request
    local curl_output
    local curl_exit_code
    
    curl_output=$(curl "${curl_opts[@]}" "$url" 2>&1)
    curl_exit_code=$?
    
    # Record end time
    local end_time
    end_time=$(date +%s%3N)
    
    # Calculate response time in milliseconds
    HTTP_RESPONSE_TIME_MS=$((end_time - start_time))
    
    # Handle curl exit codes
    case $curl_exit_code in
        0)
            # Success - parse output
            if [[ "$curl_output" =~ ^([0-9]{3})\|([0-9]+\.[0-9]+)$ ]]; then
                HTTP_STATUS_CODE="${BASH_REMATCH[1]}"
                # Use our measured time for consistency
            else
                HTTP_ERROR_MESSAGE="Failed to parse curl output: $curl_output"
                return 1
            fi
            ;;
        6)
            HTTP_ERROR_MESSAGE="Could not resolve host"
            return 1
            ;;
        7)
            HTTP_ERROR_MESSAGE="Failed to connect to host"
            return 1
            ;;
        28)
            HTTP_ERROR_MESSAGE="Operation timeout after ${timeout} seconds"
            return 2
            ;;
        35)
            HTTP_ERROR_MESSAGE="SSL connect error"
            return 1
            ;;
        52)
            HTTP_ERROR_MESSAGE="Empty reply from server"
            return 1
            ;;
        56)
            HTTP_ERROR_MESSAGE="Failure in receiving network data"
            return 1
            ;;
        *)
            HTTP_ERROR_MESSAGE="HTTP request failed with curl exit code $curl_exit_code: $curl_output"
            return 1
            ;;
    esac
    
    return 0
}

#
# Validate URL format
# Arguments:
#   $1 - URL to validate
# Returns:
#   0 if valid, 1 if invalid
#
http_validate_url() {
    local url="$1"
    
    # Check for basic URL structure
    if [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+[a-zA-Z0-9]+(:[0-9]+)?(/.*)?$ ]]; then
        return 0
    fi
    
    return 1
}

#
# Categorize HTTP status code
# Arguments:
#   $1 - HTTP status code
# Returns:
#   Prints category: "success", "redirect", "client_error", "server_error", or "unknown"
#
http_categorize_status() {
    local status_code="$1"
    
    # Validate status code is numeric
    if ! [[ "$status_code" =~ ^[0-9]{3}$ ]]; then
        echo "unknown"
        return 1
    fi
    
    if [[ $status_code -ge $HTTP_SUCCESS_MIN && $status_code -le $HTTP_SUCCESS_MAX ]]; then
        echo "success"
    elif [[ $status_code -ge $HTTP_REDIRECT_MIN && $status_code -le $HTTP_REDIRECT_MAX ]]; then
        echo "redirect"
    elif [[ $status_code -ge $HTTP_CLIENT_ERROR_MIN && $status_code -le $HTTP_CLIENT_ERROR_MAX ]]; then
        echo "client_error"
    elif [[ $status_code -ge $HTTP_SERVER_ERROR_MIN && $status_code -le $HTTP_SERVER_ERROR_MAX ]]; then
        echo "server_error"
    else
        echo "unknown"
    fi
}

#
# Check if HTTP status indicates website is available
# Arguments:
#   $1 - HTTP status code
# Returns:
#   0 if available (2xx or 3xx), 1 if not available
#
http_is_website_available() {
    local status_code="$1"
    local category
    
    category=$(http_categorize_status "$status_code")
    
    case "$category" in
        "success"|"redirect")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

#
# Get human-readable description of HTTP status code
# Arguments:
#   $1 - HTTP status code
# Returns:
#   Prints description of the status code
#
http_get_status_description() {
    local status_code="$1"
    
    case "$status_code" in
        200) echo "OK" ;;
        201) echo "Created" ;;
        204) echo "No Content" ;;
        301) echo "Moved Permanently" ;;
        302) echo "Found" ;;
        304) echo "Not Modified" ;;
        400) echo "Bad Request" ;;
        401) echo "Unauthorized" ;;
        403) echo "Forbidden" ;;
        404) echo "Not Found" ;;
        405) echo "Method Not Allowed" ;;
        408) echo "Request Timeout" ;;
        429) echo "Too Many Requests" ;;
        500) echo "Internal Server Error" ;;
        502) echo "Bad Gateway" ;;
        503) echo "Service Unavailable" ;;
        504) echo "Gateway Timeout" ;;
        *) echo "HTTP $status_code" ;;
    esac
}

#
# Perform HTTP request and return structured result
# Arguments:
#   $1 - URL to check
#   $2 - Timeout in seconds (optional)
# Returns:
#   Prints structured result: "status_code|response_time_ms|category|available|description|error_message"
#   Exit code: 0 for successful request, 1 for network error, 2 for timeout/invalid input
#
http_check_website_structured() {
    local url="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"
    
    # Perform the HTTP check
    http_check_website "$url" "$timeout"
    local check_result=$?
    
    local category="unknown"
    local available="false"
    local description=""
    
    if [[ $check_result -eq 0 && -n "$HTTP_STATUS_CODE" ]]; then
        category=$(http_categorize_status "$HTTP_STATUS_CODE")
        if http_is_website_available "$HTTP_STATUS_CODE"; then
            available="true"
        fi
        description=$(http_get_status_description "$HTTP_STATUS_CODE")
    fi
    
    # Output structured result
    printf "%s|%s|%s|%s|%s|%s\n" \
        "${HTTP_STATUS_CODE:-0}" \
        "${HTTP_RESPONSE_TIME_MS:-0}" \
        "$category" \
        "$available" \
        "$description" \
        "${HTTP_ERROR_MESSAGE:-}"
    
    return $check_result
}

#
# HTTP check with retry and circuit breaker
# Arguments:
#   $1 - URL to check
#   $2 - Timeout in seconds (optional)
#   $3 - Max retries (optional, defaults to DEFAULT_MAX_RETRIES)
#   $4 - Initial backoff (optional, defaults to DEFAULT_INITIAL_BACKOFF)
# Returns:
#   Sets global variables: HTTP_STATUS_CODE, HTTP_RESPONSE_TIME_MS, HTTP_ERROR_MESSAGE
#   Exit code: 0 for success, 1 for failure, 2 for circuit breaker open
#
http_check_website_with_recovery() {
    local url="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"
    local max_retries="${3:-$DEFAULT_MAX_RETRIES}"
    local initial_backoff="${4:-$DEFAULT_INITIAL_BACKOFF}"
    
    if [ -z "$url" ]; then
        HTTP_ERROR_MESSAGE="URL parameter is required"
        return 2
    fi
    
    # Create circuit breaker name based on URL
    local circuit_name
    circuit_name=$(echo "$url" | sed 's|[^a-zA-Z0-9]|_|g')
    
    # Define wrapper function for retry mechanism
    http_check_wrapper() {
        http_check_website "$url" "$timeout"
    }
    
    # Use retry mechanism with circuit breaker
    if retry_with_exponential_backoff http_check_wrapper "$max_retries" "$initial_backoff" "HTTP check for $url"; then
        return 0
    else
        local exit_code=$?
        
        # Handle comprehensive error logging
        if [ -n "${HTTP_ERROR_MESSAGE:-}" ]; then
            handle_comprehensive_error "$HTTP_ERROR_MESSAGE" "HTTP_CHECK_$url" "$exit_code"
        fi
        
        return $exit_code
    fi
}

#
# HTTP check with graceful degradation
# Arguments:
#   $1 - URL to check
#   $2 - Timeout in seconds (optional)
#   $3 - Fallback URL (optional)
# Returns:
#   Sets global variables: HTTP_STATUS_CODE, HTTP_RESPONSE_TIME_MS, HTTP_ERROR_MESSAGE
#   Exit code: 0 for success, 1 for failure
#
http_check_website_with_fallback() {
    local url="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"
    local fallback_url="$3"
    
    if [ -z "$url" ]; then
        HTTP_ERROR_MESSAGE="URL parameter is required"
        return 2
    fi
    
    # Primary check function
    primary_check() {
        http_check_website "$url" "$timeout"
    }
    
    # Fallback check function
    fallback_check() {
        if [ -n "$fallback_url" ]; then
            log_recovery_event "HTTP_FALLBACK_$url" "FALLBACK_TRIGGERED" "Using fallback URL: $fallback_url"
            http_check_website "$fallback_url" "$timeout"
        else
            return 1
        fi
    }
    
    # Use graceful degradation
    graceful_degradation "HTTP_CHECK_$url" primary_check fallback_check "HTTP check with fallback"
}

#
# Robust HTTP content fetching with error recovery
# Arguments:
#   $1 - URL to fetch content from
#   $2 - Output file path
#   $3 - Timeout in seconds (optional)
#   $4 - Max retries (optional)
# Returns:
#   0 on success, 1 on failure
#
http_fetch_content_robust() {
    local url="$1"
    local output_file="$2"
    local timeout="${3:-$DEFAULT_TIMEOUT}"
    local max_retries="${4:-$DEFAULT_MAX_RETRIES}"
    
    if [ -z "$url" ] || [ -z "$output_file" ]; then
        log_error_detailed "URL and output file required for content fetching"
        return 1
    fi
    
    # Ensure output directory exists
    ensure_directory "$(dirname "$output_file")"
    
    # Content fetch function
    fetch_content() {
        local temp_file
        temp_file=$(mktemp) || {
            log_error_detailed "Failed to create temporary file for content fetch"
            return 1
        }
        
        # Fetch content with curl
        if curl --silent --show-error --max-time "$timeout" \
               --user-agent "$DEFAULT_USER_AGENT" \
               --location --max-redirs 5 \
               --output "$temp_file" \
               "$url" 2>/dev/null; then
            
            # Move to final location
            if mv "$temp_file" "$output_file" 2>/dev/null; then
                log_debug_detailed "Content fetched successfully: $url -> $output_file" "http-utils"
                return 0
            else
                rm -f "$temp_file" 2>/dev/null
                log_error_detailed "Failed to move content to output file: $output_file"
                return 1
            fi
        else
            local curl_exit_code=$?
            rm -f "$temp_file" 2>/dev/null
            
            case $curl_exit_code in
                6)
                    log_error_detailed "Could not resolve host for content fetch: $url"
                    ;;
                7)
                    log_error_detailed "Failed to connect to host for content fetch: $url"
                    ;;
                28)
                    log_error_detailed "Content fetch timeout after ${timeout} seconds: $url"
                    ;;
                *)
                    log_error_detailed "Content fetch failed with exit code $curl_exit_code: $url"
                    ;;
            esac
            
            return $curl_exit_code
        fi
    }
    
    # Use retry mechanism for content fetching
    retry_with_exponential_backoff fetch_content "$max_retries" "$DEFAULT_INITIAL_BACKOFF" "Content fetch for $url"
}

#
# HTTP health check function
# Arguments:
#   $1 - URL to check
#   $2 - Expected status code (optional, defaults to 200)
#   $3 - Timeout (optional)
# Returns:
#   0 if healthy, 1 if unhealthy
#
http_health_check() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-$DEFAULT_TIMEOUT}"
    
    if [ -z "$url" ]; then
        return 1
    fi
    
    # Perform HTTP check
    if http_check_website "$url" "$timeout"; then
        if [ "$HTTP_STATUS_CODE" = "$expected_status" ]; then
            return 0
        else
            log_debug_detailed "Health check failed: expected $expected_status, got $HTTP_STATUS_CODE" "http-utils"
            return 1
        fi
    else
        log_debug_detailed "Health check failed: $HTTP_ERROR_MESSAGE" "http-utils"
        return 1
    fi
}

#
# HTTP recovery function for failed requests
# Arguments:
#   $1 - Error message
#   $2 - Error context
#   $3 - Exit code
# Returns:
#   0 if recovery successful, 1 if recovery failed
#
http_recovery_function() {
    local error_message="$1"
    local error_context="$2"
    local exit_code="$3"
    
    log_recovery_event "$error_context" "HTTP_RECOVERY_INITIATED" "Attempting HTTP recovery for: $error_message"
    
    # Extract URL from context if possible
    local url
    url=$(echo "$error_context" | sed 's/HTTP_CHECK_//')
    
    if [ -z "$url" ]; then
        log_recovery_event "$error_context" "HTTP_RECOVERY_FAILED" "Could not extract URL from context"
        return 1
    fi
    
    # Attempt different recovery strategies based on error type
    case "$error_message" in
        *"Could not resolve host"*)
            log_recovery_event "$error_context" "HTTP_RECOVERY_DNS" "Attempting DNS resolution check"
            # Try to resolve host using nslookup or dig
            local hostname
            hostname=$(echo "$url" | sed 's|https\?://||' | cut -d'/' -f1 | cut -d':' -f1)
            
            if command -v nslookup >/dev/null 2>&1; then
                if nslookup "$hostname" >/dev/null 2>&1; then
                    log_recovery_event "$error_context" "HTTP_RECOVERY_DNS_SUCCESS" "DNS resolution successful"
                    return 0
                fi
            elif command -v dig >/dev/null 2>&1; then
                if dig "$hostname" >/dev/null 2>&1; then
                    log_recovery_event "$error_context" "HTTP_RECOVERY_DNS_SUCCESS" "DNS resolution successful"
                    return 0
                fi
            fi
            ;;
        *"timeout"*)
            log_recovery_event "$error_context" "HTTP_RECOVERY_TIMEOUT" "Attempting recovery from timeout"
            # For timeout errors, we can't do much except wait and retry
            sleep 5
            return 0
            ;;
        *"SSL"*|*"certificate"*)
            log_recovery_event "$error_context" "HTTP_RECOVERY_SSL" "SSL/Certificate error detected"
            # For SSL errors, suggest checking certificates but can't auto-recover
            return 1
            ;;
    esac
    
    log_recovery_event "$error_context" "HTTP_RECOVERY_FAILED" "No recovery strategy available for error type"
    return 1
}