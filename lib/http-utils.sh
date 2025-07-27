#!/bin/bash

# HTTP Utilities Library
# Provides functions for HTTP requests, response time measurement, and status code handling

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

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