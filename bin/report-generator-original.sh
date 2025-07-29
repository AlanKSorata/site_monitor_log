#!/bin/bash

# Report Generation System
# Generates comprehensive monitoring reports from log data

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"

# Source required libraries
source "$LIB_DIR/common.sh"
source "$LIB_DIR/log-utils.sh"

# Default configuration
DEFAULT_FORMAT="text"
DEFAULT_PERIOD="daily"
DEFAULT_OUTPUT_FILE=""
DEFAULT_START_DATE=""
DEFAULT_END_DATE=""

# Default report directory
DEFAULT_REPORTS_DIR="data/reports"

# Report configuration
REPORT_TITLE="Website Monitoring Report"
REPORT_VERSION="1.0"

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Generate comprehensive monitoring reports from log data."
    echo ""
    echo "OPTIONS:"
    echo "    -f, --format FORMAT     Output format: text, html, csv (default: $DEFAULT_FORMAT)"
    echo "    -p, --period PERIOD     Report period: daily, weekly, monthly, custom (default: $DEFAULT_PERIOD)"
    echo "    -o, --output FILE       Output file path (default: auto-generated in $DEFAULT_REPORTS_DIR)"
    echo "    -s, --start-date DATE   Start date for custom period (YYYY-MM-DD)"
    echo "    -e, --end-date DATE     End date for custom period (YYYY-MM-DD)"
    echo "    -w, --website URL       Generate report for specific website only"
    echo "    -v, --verbose           Enable verbose output"
    echo "    -h, --help             Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "    $0 --format text --period daily"
    echo "    $0 --format html --period weekly --output weekly-report.html"
    echo "    $0 --format csv --period custom --start-date 2025-01-01 --end-date 2025-01-31"
    echo ""
    echo "NOTE:"
    echo "    When no output file is specified, reports are automatically saved to:"
    echo "    $DEFAULT_REPORTS_DIR/report-YYYYMMDD-HHMMSS.{txt|html|csv}"
    echo ""
}

parse_arguments() {
    local format="$DEFAULT_FORMAT"
    local period="$DEFAULT_PERIOD"
    local output_file="$DEFAULT_OUTPUT_FILE"
    local start_date="$DEFAULT_START_DATE"
    local end_date="$DEFAULT_END_DATE"
    local website=""
    local verbose=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--format)
                format="$2"
                case "$format" in
                    text|html|csv)
                        ;;
                    *)
                        die "Invalid format: $format (must be text, html, or csv)" 2
                        ;;
                esac
                shift 2
                ;;
            -p|--period)
                period="$2"
                case "$period" in
                    daily|weekly|monthly|custom)
                        ;;
                    *)
                        die "Invalid period: $period (must be daily, weekly, monthly, or custom)" 2
                        ;;
                esac
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -s|--start-date)
                start_date="$2"
                if ! validate_date_format "$start_date"; then
                    die "Invalid start date format: $start_date (use YYYY-MM-DD)" 2
                fi
                shift 2
                ;;
            -e|--end-date)
                end_date="$2"
                if ! validate_date_format "$end_date"; then
                    die "Invalid end date format: $end_date (use YYYY-MM-DD)" 2
                fi
                shift 2
                ;;
            -w|--website)
                website="$2"
                if ! is_valid_url "$website"; then
                    die "Invalid website URL: $website" 2
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
            *)
                die "Unknown option: $1" 2
                ;;
        esac
    done

    # Validate custom period requirements
    if [ "$period" = "custom" ]; then
        if [ -z "$start_date" ] || [ -z "$end_date" ]; then
            die "Custom period requires both --start-date and --end-date" 2
        fi
        
        # Validate date order (allow same date)
        if ! is_date_before_or_equal "$start_date" "$end_date"; then
            die "Start date must be before or equal to end date" 2
        fi
    fi

    # Export configuration
    export REPORT_FORMAT="$format"
    export REPORT_PERIOD="$period"
    export REPORT_OUTPUT_FILE="$output_file"
    export REPORT_START_DATE="$start_date"
    export REPORT_END_DATE="$end_date"
    export REPORT_WEBSITE="$website"
    export REPORT_VERBOSE="$verbose"
}

validate_date_format() {
    local date_str="$1"
    
    if [[ ! "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        return 1
    fi
    
    # Try to parse the date to ensure it's valid
    if ! date -d "$date_str" >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

is_date_before() {
    local date1="$1"
    local date2="$2"
    
    local epoch1
    local epoch2
    
    epoch1=$(date -d "$date1" +%s 2>/dev/null) || return 1
    epoch2=$(date -d "$date2" +%s 2>/dev/null) || return 1
    
    [ "$epoch1" -lt "$epoch2" ]
}

is_date_before_or_equal() {
    local date1="$1"
    local date2="$2"
    
    local epoch1
    local epoch2
    
    epoch1=$(date -d "$date1" +%s 2>/dev/null) || return 1
    epoch2=$(date -d "$date2" +%s 2>/dev/null) || return 1
    
    [ "$epoch1" -le "$epoch2" ]
}

calculate_date_range() {
    local period="$1"
    local start_date=""
    local end_date=""
    
    # Default to current day if no specific period is set
    local current_date=$(date '+%Y-%m-%d')
    
    case "$period" in
        daily)
            # If no start/end dates specified, default to current day
            if [ -z "$REPORT_START_DATE" ] && [ -z "$REPORT_END_DATE" ]; then
                start_date="$current_date"
                end_date="$current_date"
            else
                start_date=$(date -d '1 day ago' '+%Y-%m-%d')
                end_date="$current_date"
            fi
            ;;
        weekly)
            start_date=$(date -d '7 days ago' '+%Y-%m-%d')
            end_date="$current_date"
            ;;
        monthly)
            start_date=$(date -d '30 days ago' '+%Y-%m-%d')
            end_date="$current_date"
            ;;
        custom)
            start_date="$REPORT_START_DATE"
            end_date="$REPORT_END_DATE"
            ;;
        *)
            # Default case: current day
            start_date="$current_date"
            end_date="$current_date"
            ;;
    esac
    
    echo "$start_date|$end_date"
}

is_date_in_range() {
    local check_date="$1"
    local start_date="$2"
    local end_date="$3"
    
    local check_epoch
    local start_epoch
    local end_epoch
    
    check_epoch=$(date -d "$check_date" +%s 2>/dev/null) || return 1
    start_epoch=$(date -d "$start_date" +%s 2>/dev/null) || return 1
    end_epoch=$(date -d "$end_date 23:59:59" +%s 2>/dev/null) || return 1
    
    [ "$check_epoch" -ge "$start_epoch" ] && [ "$check_epoch" -le "$end_epoch" ]
}

parse_monitoring_logs() {
    local start_date="$1"
    local end_date="$2"
    local website_filter="$3"
    
    local temp_file="$DATA_DIR/temp/monitoring_data_$$.tmp"
    ensure_directory "$(dirname "$temp_file")"
    
    # Parse main monitoring log
    if [ -f "$MAIN_LOG_FILE" ]; then
        local processed_lines=0
        local filtered_lines=0
        while IFS= read -r line; do
            processed_lines=$((processed_lines + 1))
            
            # Skip empty lines
            if [ -z "$line" ]; then
                continue
            fi
            
            # Only match monitoring lines with the specific format:
            # timestamp|level|message|url|response_time|status_code|final_status
            # Example: 2025-07-27 08:40:42|ERROR|Website check failed: Google|https://www.google.com|0|0|DOWN
            if [[ ! "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\|.*\|.*\|https?://.*\|[0-9]+\|[0-9]+\|.* ]]; then
                continue
            fi
            
            # Parse the monitoring line with 7 fields
            IFS='|' read -r timestamp level message url response_time status_code final_status <<< "$line"
            
            # Skip malformed entries (must have all required fields)
            if [ -z "$timestamp" ] || [ -z "$level" ] || [ -z "$url" ] || [ -z "$final_status" ]; then
                continue
            fi
            
            # Extract date from timestamp
            local entry_date
            entry_date=$(echo "$timestamp" | cut -d' ' -f1)
            
            # Check if entry is within date range
            if ! is_date_in_range "$entry_date" "$start_date" "$end_date"; then
                continue
            fi
            
            # Apply website filter if specified
            if [ -n "$website_filter" ] && [ "$url" != "$website_filter" ]; then
                continue
            fi
            
            # Write parsed entry to temp file in standardized format
            echo "$timestamp|$url|$status_code|$response_time|$final_status|$message" >> "$temp_file"
            filtered_lines=$((filtered_lines + 1))
            
        done < "$MAIN_LOG_FILE"
        
        if [ "$REPORT_VERBOSE" = true ]; then
            log_info "Processed $processed_lines lines, filtered $filtered_lines valid entries"
        fi
    fi
    
    echo "$temp_file"
}

calculate_availability_stats() {
    local monitoring_data_file="$1"
    local website_filter="$2"
    
    if [ ! -f "$monitoring_data_file" ]; then
        return 1
    fi
    
    # Get unique websites
    local websites
    if [ -n "$website_filter" ]; then
        websites="$website_filter"
    else
        websites=$(cut -d'|' -f2 "$monitoring_data_file" | sort -u)
    fi
    
    local stats_file="$DATA_DIR/temp/availability_stats_$$.tmp"
    
    for website in $websites; do
        local total_checks=0
        local up_checks=0
        local down_checks=0
        local error_checks=0
        
        while IFS='|' read -r timestamp url status_code response_time status message; do
            if [ "$url" = "$website" ]; then
                total_checks=$((total_checks + 1))
                
                case "$status" in
                    UP|CONTENT_INITIAL|CONTENT_CHANGED|CONTENT_UNCHANGED)
                        up_checks=$((up_checks + 1))
                        ;;
                    DOWN|TIMEOUT|ERROR)
                        down_checks=$((down_checks + 1))
                        ;;
                    *)
                        error_checks=$((error_checks + 1))
                        ;;
                esac
            fi
        done < "$monitoring_data_file"
        
        # Calculate availability percentage
        local availability_percent=0
        if [ "$total_checks" -gt 0 ]; then
            availability_percent=$(( (up_checks * 100) / total_checks ))
        fi
        
        echo "$website|$total_checks|$up_checks|$down_checks|$error_checks|$availability_percent" >> "$stats_file"
    done
    
    echo "$stats_file"
}

calculate_response_time_stats() {
    local monitoring_data_file="$1"
    local website_filter="$2"
    
    if [ ! -f "$monitoring_data_file" ]; then
        return 1
    fi
    
    # Get unique websites
    local websites
    if [ -n "$website_filter" ]; then
        websites="$website_filter"
    else
        websites=$(cut -d'|' -f2 "$monitoring_data_file" | sort -u)
    fi
    
    local stats_file="$DATA_DIR/temp/response_time_stats_$$.tmp"
    
    for website in $websites; do
        local response_times=()
        local total_time=0
        local count=0
        local min_time=999999
        local max_time=0
        
        while IFS='|' read -r timestamp url status_code response_time status message; do
            if [ "$url" = "$website" ] && [ -n "$response_time" ] && [ "$response_time" != "0" ]; then
                response_times+=("$response_time")
                total_time=$((total_time + response_time))
                count=$((count + 1))
                
                if [ "$response_time" -lt "$min_time" ]; then
                    min_time="$response_time"
                fi
                
                if [ "$response_time" -gt "$max_time" ]; then
                    max_time="$response_time"
                fi
            fi
        done < "$monitoring_data_file"
        
        # Calculate average response time
        local avg_time=0
        if [ "$count" -gt 0 ]; then
            avg_time=$((total_time / count))
        else
            min_time=0
            max_time=0
        fi
        
        echo "$website|$count|$avg_time|$min_time|$max_time" >> "$stats_file"
    done
    
    echo "$stats_file"
}

generate_text_report() {
    local start_date="$1"
    local end_date="$2"
    local availability_stats_file="$3"
    local response_time_stats_file="$4"
    
    echo "================================================================================"
    echo "                        $REPORT_TITLE"
    echo "================================================================================"
    echo ""
    echo "Report Period: $start_date to $end_date"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Report Version: $REPORT_VERSION"
    echo ""
    echo "================================================================================"
    echo "                           AVAILABILITY SUMMARY"
    echo "================================================================================"
    echo ""

    if [ -f "$availability_stats_file" ]; then
        printf "%-40s %8s %8s %8s %8s %12s\n" "Website" "Total" "Up" "Down" "Error" "Availability"
        printf "%-40s %8s %8s %8s %8s %12s\n" "$(printf '%40s' | tr ' ' '-')" "--------" "--------" "--------" "--------" "------------"
        
        while IFS='|' read -r website total_checks up_checks down_checks error_checks availability_percent; do
            printf "%-40s %8d %8d %8d %8d %10d%%\n" \
                "$website" "$total_checks" "$up_checks" "$down_checks" "$error_checks" "$availability_percent"
        done < "$availability_stats_file"
    else
        echo "No availability data found for the specified period."
    fi

    echo ""
    echo "================================================================================"
    echo "                        RESPONSE TIME STATISTICS"
    echo "================================================================================"
    echo ""

    if [ -f "$response_time_stats_file" ]; then
        printf "%-40s %8s %8s %8s %8s\n" "Website" "Samples" "Avg (ms)" "Min (ms)" "Max (ms)"
        printf "%-40s %8s %8s %8s %8s\n" "$(printf '%40s' | tr ' ' '-')" "--------" "--------" "--------" "--------"
        
        while IFS='|' read -r website count avg_time min_time max_time; do
            printf "%-40s %8d %8d %8d %8d\n" \
                "$website" "$count" "$avg_time" "$min_time" "$max_time"
        done < "$response_time_stats_file"
    else
        echo "No response time data found for the specified period."
    fi

    echo ""
    echo "Report generated by Website Monitoring System v$REPORT_VERSION"
    echo "================================================================================"
}

generate_csv_report() {
    local start_date="$1"
    local end_date="$2"
    local availability_stats_file="$3"
    local response_time_stats_file="$4"
    
    echo "# Website Monitoring Report - CSV Format"
    echo "# Report Period: $start_date to $end_date"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    echo "# Availability Statistics"
    echo "Website,Total Checks,Up Checks,Down Checks,Error Checks,Availability Percent"
    
    if [ -f "$availability_stats_file" ]; then
        while IFS='|' read -r website total_checks up_checks down_checks error_checks availability_percent; do
            echo "\"$website\",$total_checks,$up_checks,$down_checks,$error_checks,$availability_percent"
        done < "$availability_stats_file"
    fi
    
    echo ""
    echo "# Response Time Statistics"
    echo "Website,Sample Count,Average Response Time (ms),Minimum Response Time (ms),Maximum Response Time (ms)"
    
    if [ -f "$response_time_stats_file" ]; then
        while IFS='|' read -r website count avg_time min_time max_time; do
            echo "\"$website\",$count,$avg_time,$min_time,$max_time"
        done < "$response_time_stats_file"
    fi
}

generate_html_report() {
    local start_date="$1"
    local end_date="$2"
    local availability_stats_file="$3"
    local response_time_stats_file="$4"
    
    echo "<!DOCTYPE html>"
    echo "<html><head><title>Website Monitoring Report</title></head><body style='text-align:center'>"
    echo "<h1>$REPORT_TITLE</h1>"
    echo "<p>Report Period: $start_date to $end_date</p>"
    echo "<p>Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>"
    
    echo "<h2>Availability Summary</h2>"
    if [ -f "$availability_stats_file" ]; then
        echo "<table border='1' align='center'>"
        echo "<tr><th>Website</th><th>Total</th><th>Up</th><th>Down</th><th>Error</th><th>Availability</th></tr>"
        
        while IFS='|' read -r website total_checks up_checks down_checks error_checks availability_percent; do
            echo "<tr><td>$website</td><td>$total_checks</td><td>$up_checks</td><td>$down_checks</td><td>$error_checks</td><td>${availability_percent}%</td></tr>"
        done < "$availability_stats_file"
        
        echo "</table>"
    else
        echo "<p>No availability data found.</p>"
    fi
    
    echo "<h2>Response Time Statistics</h2>"
    if [ -f "$response_time_stats_file" ]; then
        echo "<table border='1' align='center'>"
        echo "<tr><th>Website</th><th>Samples</th><th>Avg (ms)</th><th>Min (ms)</th><th>Max (ms)</th></tr>"
        
        while IFS='|' read -r website count avg_time min_time max_time; do
            echo "<tr><td>$website</td><td>$count</td><td>$avg_time</td><td>$min_time</td><td>$max_time</td></tr>"
        done < "$response_time_stats_file"
        
        echo "</table>"
    else
        echo "<p>No response time data found.</p>"
    fi
    
    echo "</body></html>"
}

generate_default_filename() {
    local format="$1"
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    
    local extension=""
    case "$format" in
        text)
            extension="txt"
            ;;
        html)
            extension="html"
            ;;
        csv)
            extension="csv"
            ;;
        *)
            extension="txt"
            ;;
    esac
    
    echo "$DEFAULT_REPORTS_DIR/report-$timestamp.$extension"
}

cleanup_temp_files() {
    local temp_pattern="$DATA_DIR/temp/*_$$.tmp"
    rm -f $temp_pattern 2>/dev/null || true
}

main() {
    # Validate required commands
    validate_required_commands
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set up signal handlers for cleanup
    trap cleanup_temp_files EXIT
    
    # Calculate date range
    local date_range
    date_range=$(calculate_date_range "$REPORT_PERIOD")
    local start_date
    local end_date
    start_date=$(echo "$date_range" | cut -d'|' -f1)
    end_date=$(echo "$date_range" | cut -d'|' -f2)
    
    if [ "$REPORT_VERBOSE" = true ]; then
        log_info "Generating $REPORT_FORMAT report for period: $start_date to $end_date"
        if [ -n "$REPORT_WEBSITE" ]; then
            log_info "Filtering for website: $REPORT_WEBSITE"
        fi
    fi
    
    # Parse log data
    local monitoring_data_file
    monitoring_data_file=$(parse_monitoring_logs "$start_date" "$end_date" "$REPORT_WEBSITE")
    
    # Calculate statistics
    local availability_stats_file
    local response_time_stats_file
    
    availability_stats_file=$(calculate_availability_stats "$monitoring_data_file" "$REPORT_WEBSITE")
    response_time_stats_file=$(calculate_response_time_stats "$monitoring_data_file" "$REPORT_WEBSITE")
    
    # Generate report based on format
    local output_content=""
    case "$REPORT_FORMAT" in
        text)
            output_content=$(generate_text_report "$start_date" "$end_date" "$availability_stats_file" "$response_time_stats_file")
            ;;
        html)
            output_content=$(generate_html_report "$start_date" "$end_date" "$availability_stats_file" "$response_time_stats_file")
            ;;
        csv)
            output_content=$(generate_csv_report "$start_date" "$end_date" "$availability_stats_file" "$response_time_stats_file")
            ;;
    esac
    
    # Determine output file
    local final_output_file="$REPORT_OUTPUT_FILE"
    if [ -z "$final_output_file" ]; then
        # Generate default filename with timestamp
        final_output_file=$(generate_default_filename "$REPORT_FORMAT")
        
        # Ensure reports directory exists
        ensure_directory "$DEFAULT_REPORTS_DIR"
        
        if [ "$REPORT_VERBOSE" = true ]; then
            log_info "No output file specified, using default: $final_output_file"
        fi
    fi
    
    # Output report
    if [ -n "$final_output_file" ]; then
        # Ensure output directory exists
        ensure_directory "$(dirname "$final_output_file")"
        
        echo "$output_content" > "$final_output_file"
        
        if [ "$REPORT_VERBOSE" = true ]; then
            log_info "Report saved to: $final_output_file"
        else
            echo "Report saved to: $final_output_file"
        fi
    else
        echo "$output_content"
    fi
    
    if [ "$REPORT_VERBOSE" = true ]; then
        log_info "Report generation completed successfully"
    fi
}

# Execute main function with all arguments
main "$@"