#!/bin/bash

# Website Monitoring System - Log Viewer Interface
# Provides interactive viewing capabilities for monitoring logs and statistics

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/log-utils.sh"

# Version and script information
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="log-viewer.sh"

# Default configuration
DEFAULT_LINES=50
DEFAULT_REFRESH_INTERVAL=5
MAX_DISPLAY_LINES=1000

# Display modes
MODE_REALTIME="realtime"
MODE_FILTER="filter"
MODE_SEARCH="search"
MODE_STATS="stats"
MODE_HELP="help"

# Global variables for current session
CURRENT_MODE="$MODE_REALTIME"
FILTER_WEBSITE=""
FILTER_DATE_FROM=""
FILTER_DATE_TO=""
FILTER_EVENT_TYPE=""
SEARCH_PATTERN=""
DISPLAY_LINES="$DEFAULT_LINES"
REFRESH_INTERVAL="$DEFAULT_REFRESH_INTERVAL"
AUTO_REFRESH=false

#
# Display usage information
#
show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Website Monitoring System - Log Viewer Interface

OPTIONS:
    --filter <criteria>     Filter logs by criteria (website, event, date)
    --website <url>         Filter by specific website URL
    --since <date>          Show logs since date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)
    --until <date>          Show logs until date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)
    --event <type>          Filter by event type (UP, DOWN, SLOW, CONTENT_CHANGED, etc.)
    --search <pattern>      Search for pattern in log messages
    --lines <number>        Number of lines to display (default: $DEFAULT_LINES)
    --refresh <seconds>     Auto-refresh interval in seconds (default: $DEFAULT_REFRESH_INTERVAL)
    --auto-refresh          Enable automatic refresh
    --stats                 Show summary statistics
    --help                  Show this help message
    --version               Show version information

INTERACTIVE COMMANDS:
    r                       Refresh display
    f                       Set filter criteria
    s                       Search logs
    t                       Show statistics
    c                       Clear filters
    q                       Quit
    h                       Show help

EXAMPLES:
    $SCRIPT_NAME                                    # Real-time monitoring view
    $SCRIPT_NAME --website https://example.com      # Filter by website
    $SCRIPT_NAME --since "2025-01-01"              # Show logs since date
    $SCRIPT_NAME --event DOWN                       # Show only downtime events
    $SCRIPT_NAME --search "timeout"                # Search for timeout events
    $SCRIPT_NAME --stats                           # Show summary statistics
    $SCRIPT_NAME --auto-refresh --refresh 10       # Auto-refresh every 10 seconds

EOF
}

#
# Display version information
#
show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
    echo "Website Monitoring System Log Viewer"
}

#
# Parse command line arguments
#
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --filter)
                CURRENT_MODE="$MODE_FILTER"
                shift
                ;;
            --website)
                FILTER_WEBSITE="$2"
                CURRENT_MODE="$MODE_FILTER"
                shift 2
                ;;
            --since)
                FILTER_DATE_FROM="$2"
                CURRENT_MODE="$MODE_FILTER"
                shift 2
                ;;
            --until)
                FILTER_DATE_TO="$2"
                CURRENT_MODE="$MODE_FILTER"
                shift 2
                ;;
            --event)
                FILTER_EVENT_TYPE="$2"
                CURRENT_MODE="$MODE_FILTER"
                shift 2
                ;;
            --search)
                SEARCH_PATTERN="$2"
                CURRENT_MODE="$MODE_SEARCH"
                shift 2
                ;;
            --lines)
                DISPLAY_LINES="$2"
                if ! is_number "$DISPLAY_LINES" || [ "$DISPLAY_LINES" -lt 1 ]; then
                    die "Invalid number of lines: $DISPLAY_LINES"
                fi
                if [ "$DISPLAY_LINES" -gt "$MAX_DISPLAY_LINES" ]; then
                    DISPLAY_LINES="$MAX_DISPLAY_LINES"
                    log_warn "Lines limited to maximum: $MAX_DISPLAY_LINES"
                fi
                shift 2
                ;;
            --refresh)
                REFRESH_INTERVAL="$2"
                if ! is_number "$REFRESH_INTERVAL" || [ "$REFRESH_INTERVAL" -lt 1 ]; then
                    die "Invalid refresh interval: $REFRESH_INTERVAL"
                fi
                shift 2
                ;;
            --auto-refresh)
                AUTO_REFRESH=true
                shift
                ;;
            --stats)
                CURRENT_MODE="$MODE_STATS"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

#
# Initialize log viewer system
#
init_log_viewer() {
    # Validate required directories and files
    if [ ! -d "$LOG_DIR" ]; then
        die "Log directory not found: $LOG_DIR"
    fi
    
    # Check if main log file exists
    if [ ! -f "$MAIN_LOG_FILE" ]; then
        log_warn "Main log file not found: $MAIN_LOG_FILE"
        log_info "Creating empty log file for display"
        touch "$MAIN_LOG_FILE" 2>/dev/null || die "Cannot create log file: $MAIN_LOG_FILE"
    fi
    
    # Set up signal handlers for graceful exit
    trap 'cleanup_and_exit' EXIT INT TERM
    
    log_debug "Log viewer initialized successfully"
}

#
# Cleanup and exit gracefully
#
cleanup_and_exit() {
    # Clear screen formatting
    echo -e "\033[0m"
    
    # Reset cursor
    echo -e "\033[?25h"
    
    log_debug "Log viewer exiting"
    exit 0
}

# Get list of monitored websites from configuration
#
get_monitored_websites() {
    local websites=()
    
    if [ -f "$CONFIG_DIR/websites.conf" ]; then
        while IFS='|' read -r url name interval timeout content_check || [ -n "$url" ]; do
            # Skip comments and empty lines
            if [[ "$url" =~ ^[[:space:]]*# ]] || [[ "$url" =~ ^[[:space:]]*$ ]]; then
                continue
            fi
            
            # Clean up URL
            url=$(trim_whitespace "$url")
            if [ -n "$url" ]; then
                websites+=("$url")
            fi
        done < "$CONFIG_DIR/websites.conf"
    fi
    
    printf '%s\n' "${websites[@]}"
}

#
# Format timestamp for display
#
format_timestamp() {
    local timestamp="$1"
    local format="${2:-short}"
    
    if [ -z "$timestamp" ]; then
        echo "unknown"
        return
    fi
    
    case "$format" in
        short)
            echo "$timestamp" | cut -d' ' -f2 | cut -d':' -f1,2
            ;;
        full)
            echo "$timestamp"
            ;;
        date)
            echo "$timestamp" | cut -d' ' -f1
            ;;
        *)
            echo "$timestamp"
            ;;
    esac
}

#
# Parse log entry and extract fields
#
parse_log_entry() {
    local log_line="$1"
    local field="$2"
    
    if [ -z "$log_line" ]; then
        return 1
    fi
    
    # Log format: timestamp|level|message|url|status_code|response_time|status
    local timestamp level message url status_code response_time status
    
    IFS='|' read -r timestamp level message url status_code response_time status <<< "$log_line"
    
    case "$field" in
        timestamp)
            echo "$timestamp"
            ;;
        level)
            echo "$level"
            ;;
        message)
            echo "$message"
            ;;
        url)
            echo "$url"
            ;;
        status_code)
            echo "$status_code"
            ;;
        response_time)
            echo "$response_time"
            ;;
        status)
            echo "$status"
            ;;
        all)
            echo "timestamp=$timestamp level=$level message=$message url=$url status_code=$status_code response_time=$response_time status=$status"
            ;;
        *)
            echo "$log_line"
            ;;
    esac
}

#
# Apply filters to log entries
#
apply_filters() {
    local input_file="$1"
    local temp_file
    temp_file=$(mktemp)
    
    # Start with all entries
    cat "$input_file" > "$temp_file"
    
    # Apply website filter
    if [ -n "$FILTER_WEBSITE" ]; then
        grep -F "$FILTER_WEBSITE" "$temp_file" > "${temp_file}.tmp" && mv "${temp_file}.tmp" "$temp_file"
    fi
    
    # Apply date range filters
    if [ -n "$FILTER_DATE_FROM" ]; then
        awk -F'|' -v from_date="$FILTER_DATE_FROM" '
            BEGIN {
                # Convert from_date to comparable format
                gsub(/-/, "", from_date)
                gsub(/:/, "", from_date)
                gsub(/ /, "", from_date)
            }
            {
                # Extract and format timestamp
                timestamp = $1
                gsub(/-/, "", timestamp)
                gsub(/:/, "", timestamp)
                gsub(/ /, "", timestamp)
                
                if (timestamp >= from_date) print $0
            }
        ' "$temp_file" > "${temp_file}.tmp" && mv "${temp_file}.tmp" "$temp_file"
    fi
    
    if [ -n "$FILTER_DATE_TO" ]; then
        awk -F'|' -v to_date="$FILTER_DATE_TO" '
            BEGIN {
                # Convert to_date to comparable format
                gsub(/-/, "", to_date)
                gsub(/:/, "", to_date)
                gsub(/ /, "", to_date)
            }
            {
                # Extract and format timestamp
                timestamp = $1
                gsub(/-/, "", timestamp)
                gsub(/:/, "", timestamp)
                gsub(/ /, "", timestamp)
                
                if (timestamp <= to_date) print $0
            }
        ' "$temp_file" > "${temp_file}.tmp" && mv "${temp_file}.tmp" "$temp_file"
    fi
    
    # Apply event type filter
    if [ -n "$FILTER_EVENT_TYPE" ]; then
        grep -i "$FILTER_EVENT_TYPE" "$temp_file" > "${temp_file}.tmp" && mv "${temp_file}.tmp" "$temp_file"
    fi
    
    # Apply search pattern
    if [ -n "$SEARCH_PATTERN" ]; then
        grep -i "$SEARCH_PATTERN" "$temp_file" > "${temp_file}.tmp" && mv "${temp_file}.tmp" "$temp_file"
    fi
    
    # Output filtered results
    cat "$temp_file"
    
    # Cleanup
    rm -f "$temp_file" "${temp_file}.tmp"
}

#
# Display real-time monitoring status
#
display_realtime_status() {
    clear
    
    echo "=== Website Monitoring System - Real-time Status ==="
    echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Get list of monitored websites
    local websites
    websites=($(get_monitored_websites))
    
    if [ ${#websites[@]} -eq 0 ]; then
        echo "No websites configured for monitoring."
        return
    fi
    
    # Display current status for each website
    printf "%-40s %-8s %-12s %-10s %s\n" "Website" "Status" "Last Check" "Response" "Message"
    printf "%-40s %-8s %-12s %-10s %s\n" "$(printf '%*s' 40 '' | tr ' ' '-')" "$(printf '%*s' 8 '' | tr ' ' '-')" "$(printf '%*s' 12 '' | tr ' ' '-')" "$(printf '%*s' 10 '' | tr ' ' '-')" "$(printf '%*s' 20 '' | tr ' ' '-')"
    
    for website in "${websites[@]}"; do
        local status="UNKNOWN"
        local last_check="never"
        local response_time="N/A"
        local message="No data"
        local color=""
        
        # Get latest status from main log
        if [ -f "$MAIN_LOG_FILE" ]; then
            local latest_entry
            latest_entry=$(grep -F "$website" "$MAIN_LOG_FILE" | tail -1)
            
            if [ -n "$latest_entry" ]; then
                local entry_timestamp entry_status entry_response_time entry_message
                entry_timestamp=$(parse_log_entry "$latest_entry" "timestamp")
                entry_status=$(parse_log_entry "$latest_entry" "status")
                entry_response_time=$(parse_log_entry "$latest_entry" "response_time")
                entry_message=$(parse_log_entry "$latest_entry" "message")
                
                if [ -n "$entry_timestamp" ]; then
                    last_check=$(format_timestamp "$entry_timestamp" "short")
                fi
                
                if [ -n "$entry_status" ]; then
                    status="$entry_status"
                fi
                
                if [ -n "$entry_response_time" ] && [ "$entry_response_time" != "0" ]; then
                    response_time="${entry_response_time}ms"
                fi
                
                if [ -n "$entry_message" ]; then
                    message="$entry_message"
                fi
            fi
        fi
        
        # Set color based on status
        case "$status" in
            "UP"|"OK")
                color="$GREEN"
                ;;
            "DOWN"|"ERROR"|"TIMEOUT")
                color="$RED"
                ;;
            "SLOW"|"WARNING")
                color="$YELLOW"
                ;;
            *)
                color="$NC"
                ;;
        esac
        
        # Truncate long URLs for display
        local display_url="$website"
        if [ ${#display_url} -gt 38 ]; then
            display_url="${display_url:0:35}..."
        fi
        
        # Truncate long messages
        if [ ${#message} -gt 20 ]; then
            message="${message:0:17}..."
        fi
        
        printf "${color}%-40s %-8s %-12s %-10s %s${NC}\n" "$display_url" "$status" "$last_check" "$response_time" "$message"
    done
    
    echo ""
    echo "Press 'r' to refresh, 'f' for filters, 's' for search, 't' for stats, 'q' to quit, 'h' for help"
}

#
# Display filtered log entries
#
display_filtered_logs() {
    clear
    
    echo "=== Website Monitoring System - Filtered Logs ==="
    echo "Filters applied:"
    
    if [ -n "$FILTER_WEBSITE" ]; then
        echo "  Website: $FILTER_WEBSITE"
    fi
    
    if [ -n "$FILTER_DATE_FROM" ]; then
        echo "  From: $FILTER_DATE_FROM"
    fi
    
    if [ -n "$FILTER_DATE_TO" ]; then
        echo "  Until: $FILTER_DATE_TO"
    fi
    
    if [ -n "$FILTER_EVENT_TYPE" ]; then
        echo "  Event Type: $FILTER_EVENT_TYPE"
    fi
    
    if [ -n "$SEARCH_PATTERN" ]; then
        echo "  Search: $SEARCH_PATTERN"
    fi
    
    echo ""
    
    # Apply filters and display results
    local filtered_logs
    filtered_logs=$(apply_filters "$MAIN_LOG_FILE")
    
    if [ -z "$filtered_logs" ]; then
        echo "No log entries match the current filters."
        echo ""
        echo "Press 'c' to clear filters, 'f' to modify filters, 'q' to quit"
        return
    fi
    
    # Display header
    printf "%-19s %-5s %-40s %-8s %s\n" "Timestamp" "Level" "Website" "Status" "Message"
    printf "%-19s %-5s %-40s %-8s %s\n" "$(printf '%*s' 19 '' | tr ' ' '-')" "$(printf '%*s' 5 '' | tr ' ' '-')" "$(printf '%*s' 40 '' | tr ' ' '-')" "$(printf '%*s' 8 '' | tr ' ' '-')" "$(printf '%*s' 20 '' | tr ' ' '-')"
    
    # Display filtered entries (most recent first)
    echo "$filtered_logs" | tail -"$DISPLAY_LINES" | while IFS= read -r line; do
        if [ -n "$line" ]; then
            local timestamp level message url status color
            
            timestamp=$(parse_log_entry "$line" "timestamp")
            level=$(parse_log_entry "$line" "level")
            message=$(parse_log_entry "$line" "message")
            url=$(parse_log_entry "$line" "url")
            status=$(parse_log_entry "$line" "status")
            
            # Set color based on level
            case "$level" in
                "ERROR")
                    color="$RED"
                    ;;
                "WARN")
                    color="$YELLOW"
                    ;;
                "INFO")
                    color="$NC"
                    ;;
                "DEBUG")
                    color="$BLUE"
                    ;;
                *)
                    color="$NC"
                    ;;
            esac
            
            # Format timestamp for display
            local display_timestamp
            display_timestamp=$(format_timestamp "$timestamp" "full")
            
            # Truncate long URLs and messages for display
            local display_url="$url"
            if [ ${#display_url} -gt 38 ]; then
                display_url="${display_url:0:35}..."
            fi
            
            local display_message="$message"
            if [ ${#display_message} -gt 20 ]; then
                display_message="${display_message:0:17}..."
            fi
            
            printf "${color}%-19s %-5s %-40s %-8s %s${NC}\n" "$display_timestamp" "$level" "$display_url" "$status" "$display_message"
        fi
    done
    
    echo ""
    echo "Press 'r' to refresh, 'c' to clear filters, 'f' to modify filters, 'q' to quit"
}

# Display summary statistics
#
display_statistics() {
    clear
    
    echo "=== Website Monitoring System - Statistics ==="
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Get list of monitored websites
    local websites
    websites=($(get_monitored_websites))
    
    if [ ${#websites[@]} -eq 0 ]; then
        echo "No websites configured for monitoring."
        return
    fi
    
    # Calculate statistics for each website
    echo "Website Statistics:"
    printf "%-40s %-10s %-12s %-12s %-10s\n" "Website" "Status" "Uptime %" "Avg Response" "Last Check"
    printf "%-40s %-10s %-12s %-12s %-10s\n" "$(printf '%*s' 40 '' | tr ' ' '-')" "$(printf '%*s' 10 '' | tr ' ' '-')" "$(printf '%*s' 12 '' | tr ' ' '-')" "$(printf '%*s' 12 '' | tr ' ' '-')" "$(printf '%*s' 10 '' | tr ' ' '-')"
    
    for website in "${websites[@]}"; do
        local total_checks=0
        local up_checks=0
        local total_response_time=0
        local response_count=0
        local last_check="never"
        local current_status="UNKNOWN"
        
        # Analyze log entries for this website
        if [ -f "$MAIN_LOG_FILE" ]; then
            while IFS='|' read -r timestamp level message url status_code response_time status; do
                if [ "$url" = "$website" ]; then
                    total_checks=$((total_checks + 1))
                    
                    # Count successful checks
                    if [ "$status" = "UP" ] || [ "$status" = "OK" ]; then
                        up_checks=$((up_checks + 1))
                    fi
                    
                    # Calculate average response time
                    if [ -n "$response_time" ] && is_number "$response_time" && [ "$response_time" -gt 0 ]; then
                        total_response_time=$((total_response_time + response_time))
                        response_count=$((response_count + 1))
                    fi
                    
                    # Update last check and current status
                    last_check=$(format_timestamp "$timestamp" "short")
                    current_status="$status"
                fi
            done < "$MAIN_LOG_FILE"
        fi
        
        # Calculate uptime percentage
        local uptime_percent="N/A"
        if [ "$total_checks" -gt 0 ]; then
            uptime_percent=$(awk "BEGIN {printf \"%.1f\", ($up_checks / $total_checks) * 100}")
        fi
        
        # Calculate average response time
        local avg_response="N/A"
        if [ "$response_count" -gt 0 ]; then
            avg_response=$(awk "BEGIN {printf \"%.0f\", $total_response_time / $response_count}")
            avg_response="${avg_response}ms"
        fi
        
        # Set color based on current status
        local color=""
        case "$current_status" in
            "UP"|"OK")
                color="$GREEN"
                ;;
            "DOWN"|"ERROR"|"TIMEOUT")
                color="$RED"
                ;;
            "SLOW"|"WARNING")
                color="$YELLOW"
                ;;
            *)
                color="$NC"
                ;;
        esac
        
        # Truncate long URLs for display
        local display_url="$website"
        if [ ${#display_url} -gt 38 ]; then
            display_url="${display_url:0:35}..."
        fi
        
        printf "${color}%-40s %-10s %-12s %-12s %-10s${NC}\n" "$display_url" "$current_status" "$uptime_percent" "$avg_response" "$last_check"
    done
    
    echo ""
    
    # Overall system statistics
    echo "System Statistics:"
    
    # Count total log entries
    local total_entries=0
    if [ -f "$MAIN_LOG_FILE" ]; then
        total_entries=$(wc -l < "$MAIN_LOG_FILE" 2>/dev/null || echo 0)
    fi
    
    # Count incidents
    local total_incidents=0
    if [ -f "$INCIDENT_LOG_FILE" ]; then
        total_incidents=$(wc -l < "$INCIDENT_LOG_FILE" 2>/dev/null || echo 0)
    fi
    
    # Count content changes
    local content_changes=0
    if [ -f "$CONTENT_LOG_FILE" ]; then
        content_changes=$(wc -l < "$CONTENT_LOG_FILE" 2>/dev/null || echo 0)
    fi
    
    # Get log file sizes
    local log_size="0 MB"
    if [ -f "$MAIN_LOG_FILE" ] && command -v du >/dev/null 2>&1; then
        log_size=$(du -h "$MAIN_LOG_FILE" 2>/dev/null | cut -f1 || echo "0 MB")
    fi
    
    echo "  Total Log Entries: $total_entries"
    echo "  Total Incidents: $total_incidents"
    echo "  Content Changes: $content_changes"
    echo "  Log File Size: $log_size"
    echo "  Monitored Websites: ${#websites[@]}"
    
    # Recent activity summary
    echo ""
    echo "Recent Activity (last 24 hours):"
    
    local yesterday
    yesterday=$(date -d "yesterday" '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null || echo "")
    
    if [ -n "$yesterday" ] && [ -f "$MAIN_LOG_FILE" ]; then
        local recent_errors recent_warnings recent_info
        recent_errors=$(grep "^[0-9-]* [0-9:]*|ERROR" "$MAIN_LOG_FILE" | grep -c "$yesterday" 2>/dev/null || echo 0)
        recent_warnings=$(grep "^[0-9-]* [0-9:]*|WARN" "$MAIN_LOG_FILE" | grep -c "$yesterday" 2>/dev/null || echo 0)
        recent_info=$(grep "^[0-9-]* [0-9:]*|INFO" "$MAIN_LOG_FILE" | grep -c "$yesterday" 2>/dev/null || echo 0)
        
        echo "  Errors: $recent_errors"
        echo "  Warnings: $recent_warnings"
        echo "  Info Messages: $recent_info"
    else
        echo "  Unable to calculate recent activity"
    fi
    
    echo ""
    echo "Press 'r' to refresh, 'f' for filters, 'q' to quit"
}

#
# Interactive filter setup
#
setup_filters() {
    clear
    echo "=== Filter Setup ==="
    echo ""
    
    # Website filter
    echo "Available websites:"
    local websites
    websites=($(get_monitored_websites))
    
    local i=1
    for website in "${websites[@]}"; do
        echo "  $i) $website"
        i=$((i + 1))
    done
    echo "  0) All websites"
    echo ""
    
    read -p "Select website (number or enter URL): " website_choice
    
    if [ "$website_choice" = "0" ]; then
        FILTER_WEBSITE=""
    elif is_number "$website_choice" && [ "$website_choice" -ge 1 ] && [ "$website_choice" -le ${#websites[@]} ]; then
        FILTER_WEBSITE="${websites[$((website_choice - 1))]}"
    elif [ -n "$website_choice" ]; then
        FILTER_WEBSITE="$website_choice"
    fi
    
    # Date range filter
    echo ""
    read -p "From date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS, empty for no limit): " date_from
    FILTER_DATE_FROM="$date_from"
    
    read -p "Until date (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS, empty for no limit): " date_to
    FILTER_DATE_TO="$date_to"
    
    # Event type filter
    echo ""
    echo "Available event types: UP, DOWN, ERROR, TIMEOUT, SLOW, WARNING, CONTENT_CHANGED"
    read -p "Event type (empty for all): " event_type
    FILTER_EVENT_TYPE="$event_type"
    
    # Update mode
    if [ -n "$FILTER_WEBSITE" ] || [ -n "$FILTER_DATE_FROM" ] || [ -n "$FILTER_DATE_TO" ] || [ -n "$FILTER_EVENT_TYPE" ]; then
        CURRENT_MODE="$MODE_FILTER"
    else
        CURRENT_MODE="$MODE_REALTIME"
    fi
    
    echo ""
    echo "Filters applied. Press any key to continue..."
    read -n 1
}

#
# Interactive search setup
#
setup_search() {
    clear
    echo "=== Search Setup ==="
    echo ""
    
    read -p "Enter search pattern (case-insensitive): " search_pattern
    
    if [ -n "$search_pattern" ]; then
        SEARCH_PATTERN="$search_pattern"
        CURRENT_MODE="$MODE_SEARCH"
        echo "Search pattern set: $search_pattern"
    else
        SEARCH_PATTERN=""
        echo "Search pattern cleared"
    fi
    
    echo ""
    echo "Press any key to continue..."
    read -n 1
}

#
# Clear all filters
#
clear_filters() {
    FILTER_WEBSITE=""
    FILTER_DATE_FROM=""
    FILTER_DATE_TO=""
    FILTER_EVENT_TYPE=""
    SEARCH_PATTERN=""
    CURRENT_MODE="$MODE_REALTIME"
    
    echo "All filters cleared."
    sleep 1
}

#
# Display help information
#
display_help() {
    clear
    echo "=== Website Monitoring System - Log Viewer Help ==="
    echo ""
    echo "INTERACTIVE COMMANDS:"
    echo "  r - Refresh current display"
    echo "  f - Set up filters (website, date range, event type)"
    echo "  s - Set up search pattern"
    echo "  t - Show summary statistics"
    echo "  c - Clear all filters and return to real-time view"
    echo "  h - Show this help"
    echo "  q - Quit log viewer"
    echo ""
    echo "DISPLAY MODES:"
    echo "  Real-time: Shows current status of all monitored websites"
    echo "  Filtered:  Shows log entries matching specified criteria"
    echo "  Search:    Shows log entries containing search pattern"
    echo "  Stats:     Shows summary statistics and trends"
    echo ""
    echo "LOG ENTRY FORMAT:"
    echo "  Timestamp | Level | Message | URL | Status Code | Response Time | Status"
    echo ""
    echo "STATUS CODES:"
    echo "  UP/OK      - Website is accessible and responding normally"
    echo "  DOWN/ERROR - Website is not accessible or returned error"
    echo "  SLOW       - Website responded but exceeded threshold"
    echo "  TIMEOUT    - Website did not respond within timeout period"
    echo ""
    echo "Press any key to continue..."
    read -n 1
}

#
# Main interactive loop
#
run_interactive_mode() {
    while true; do
        # Display current mode
        case "$CURRENT_MODE" in
            "$MODE_REALTIME")
                display_realtime_status
                ;;
            "$MODE_FILTER"|"$MODE_SEARCH")
                display_filtered_logs
                ;;
            "$MODE_STATS")
                display_statistics
                ;;
            "$MODE_HELP")
                display_help
                CURRENT_MODE="$MODE_REALTIME"
                continue
                ;;
        esac
        
        # Handle auto-refresh
        if [ "$AUTO_REFRESH" = true ]; then
            # Non-blocking read with timeout
            if read -t "$REFRESH_INTERVAL" -n 1 command 2>/dev/null; then
                # Process command if entered
                case "$command" in
                    r|R)
                        # Refresh (already handled by loop)
                        ;;
                    f|F)
                        setup_filters
                        ;;
                    s|S)
                        setup_search
                        ;;
                    t|T)
                        CURRENT_MODE="$MODE_STATS"
                        ;;
                    c|C)
                        clear_filters
                        ;;
                    h|H)
                        CURRENT_MODE="$MODE_HELP"
                        ;;
                    q|Q)
                        break
                        ;;
                esac
            fi
            # Continue loop for auto-refresh
        else
            # Blocking read for command
            read -n 1 command
            
            case "$command" in
                r|R)
                    # Refresh (handled by loop)
                    ;;
                f|F)
                    setup_filters
                    ;;
                s|S)
                    setup_search
                    ;;
                t|T)
                    CURRENT_MODE="$MODE_STATS"
                    ;;
                c|C)
                    clear_filters
                    ;;
                h|H)
                    CURRENT_MODE="$MODE_HELP"
                    ;;
                q|Q)
                    break
                    ;;
                *)
                    # Invalid command, continue
                    ;;
            esac
        fi
    done
}

#
# Main function
#
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize log viewer
    init_log_viewer
    
    # Validate required commands
    validate_required_commands
    
    # Run based on mode
    case "$CURRENT_MODE" in
        "$MODE_STATS")
            display_statistics
            echo ""
            echo "Press any key to exit..."
            read -n 1
            ;;
        "$MODE_FILTER"|"$MODE_SEARCH")
            if [ "$AUTO_REFRESH" = true ]; then
                run_interactive_mode
            else
                display_filtered_logs
                echo ""
                echo "Press any key to exit..."
                read -n 1
            fi
            ;;
        *)
            # Default to interactive mode
            run_interactive_mode
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi