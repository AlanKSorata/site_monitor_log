#!/bin/bash

# 增强版报告生成器 - 专为nginx集成优化
# 生成带有实时刷新和美化界面的HTML报告

set -euo pipefail

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"

# 引入必要的库
source "$LIB_DIR/common.sh"
source "$LIB_DIR/log-utils.sh"

# 默认配置
DEFAULT_OUTPUT_FILE="$PROJECT_ROOT/data/reports/enhanced-report.html"
DEFAULT_REFRESH_INTERVAL=300  # 5分钟自动刷新

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "生成增强版HTML监控报告，专为nginx展示优化"
    echo ""
    echo "OPTIONS:"
    echo "    -o, --output FILE       输出文件路径 (默认: $DEFAULT_OUTPUT_FILE)"
    echo "    -r, --refresh SECONDS   自动刷新间隔秒数 (默认: $DEFAULT_REFRESH_INTERVAL, 0=禁用)"
    echo "    -t, --title TITLE       报告标题 (默认: 网站监控报告)"
    echo "    -v, --verbose           启用详细输出"
    echo "    -h, --help             显示此帮助信息"
    echo ""
}

parse_arguments() {
    local output_file="$DEFAULT_OUTPUT_FILE"
    local refresh_interval="$DEFAULT_REFRESH_INTERVAL"
    local report_title="网站监控报告"
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -r|--refresh)
                refresh_interval="$2"
                if ! [[ "$refresh_interval" =~ ^[0-9]+$ ]]; then
                    die "刷新间隔必须是数字" 2
                fi
                shift 2
                ;;
            -t|--title)
                report_title="$2"
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
                die "未知选项: $1" 2
                ;;
        esac
    done
    
    export ENHANCED_OUTPUT_FILE="$output_file"
    export ENHANCED_REFRESH_INTERVAL="$refresh_interval"
    export ENHANCED_REPORT_TITLE="$report_title"
    export ENHANCED_VERBOSE="$verbose"
}

# 获取网站配置信息
get_website_configs() {
    local configs_file="$PROJECT_ROOT/config/websites.conf"
    local temp_file=$(mktemp)
    
    if [ -f "$configs_file" ]; then
        while IFS= read -r line; do
            # 跳过注释和空行
            if [[ "$line" =~ ^#.*$ ]] || [ -z "$line" ]; then
                continue
            fi
            
            # 解析配置: URL|名称|间隔|超时|内容检查
            IFS='|' read -r url name interval timeout content_check <<< "$line"
            
            if [ -n "$url" ] && [ -n "$name" ]; then
                echo "$url|$name|$interval|$timeout|$content_check" >> "$temp_file"
            fi
        done < "$configs_file"
    fi
    
    echo "$temp_file"
}

# 分析最新监控数据
analyze_latest_data() {
    local website_configs="$1"
    local temp_file=$(mktemp)
    
    # 获取最近1小时的数据
    local cutoff_time=$(date -d '1 hour ago' '+%Y-%m-%d %H:%M:%S')
    
    if [ -f "$MAIN_LOG_FILE" ]; then
        # 为每个配置的网站分析最新状态
        while IFS='|' read -r url name interval timeout content_check; do
            local latest_status="UNKNOWN"
            local latest_response_time=0
            local latest_timestamp=""
            local status_color="gray"
            
            # 查找该网站的最新记录
            local latest_entry
            latest_entry=$(grep "|$url|" "$MAIN_LOG_FILE" | tail -1)
            
            if [ -n "$latest_entry" ]; then
                IFS='|' read -r timestamp level message check_url response_time status_code final_status <<< "$latest_entry"
                
                if [ "$check_url" = "$url" ]; then
                    latest_status="$final_status"
                    latest_response_time="$response_time"
                    latest_timestamp="$timestamp"
                    
                    # 确定状态颜色
                    case "$final_status" in
                        UP|CONTENT_INITIAL|CONTENT_UNCHANGED)
                            status_color="green"
                            ;;
                        CONTENT_CHANGED)
                            status_color="orange"
                            ;;
                        DOWN|TIMEOUT|ERROR)
                            status_color="red"
                            ;;
                        *)
                            status_color="gray"
                            ;;
                    esac
                fi
            fi
            
            # 计算最近1小时的统计数据
            local hour_checks=0
            local hour_up=0
            local hour_down=0
            local hour_total_time=0
            local hour_response_count=0
            
            while IFS= read -r log_line; do
                if [[ "$log_line" =~ \|$url\| ]]; then
                    IFS='|' read -r log_timestamp log_level log_message log_url log_response_time log_status_code log_final_status <<< "$log_line"
                    
                    # 检查时间范围
                    if [[ "$log_timestamp" > "$cutoff_time" ]]; then
                        hour_checks=$((hour_checks + 1))
                        
                        case "$log_final_status" in
                            UP|CONTENT_INITIAL|CONTENT_CHANGED|CONTENT_UNCHANGED)
                                hour_up=$((hour_up + 1))
                                ;;
                            DOWN|TIMEOUT|ERROR)
                                hour_down=$((hour_down + 1))
                                ;;
                        esac
                        
                        if [ "$log_response_time" -gt 0 ]; then
                            hour_total_time=$((hour_total_time + log_response_time))
                            hour_response_count=$((hour_response_count + 1))
                        fi
                    fi
                fi
            done < "$MAIN_LOG_FILE"
            
            # 计算可用性百分比
            local availability=0
            if [ "$hour_checks" -gt 0 ]; then
                availability=$(( (hour_up * 100) / hour_checks ))
            fi
            
            # 计算平均响应时间
            local avg_response_time=0
            if [ "$hour_response_count" -gt 0 ]; then
                avg_response_time=$((hour_total_time / hour_response_count))
            fi
            
            # 输出分析结果
            echo "$url|$name|$latest_status|$latest_response_time|$latest_timestamp|$status_color|$availability|$avg_response_time|$hour_checks" >> "$temp_file"
            
        done < "$website_configs"
    fi
    
    echo "$temp_file"
}

# 生成增强版HTML报告
generate_enhanced_html() {
    local website_configs="$1"
    local analysis_data="$2"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$ENHANCED_REPORT_TITLE</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', 'Microsoft YaHei', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
            color: white;
            padding: 30px;
            text-align: center;
            position: relative;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .header .subtitle {
            font-size: 1.1em;
            opacity: 0.9;
            margin-bottom: 20px;
        }
        
        .refresh-info {
            position: absolute;
            top: 20px;
            right: 20px;
            background: rgba(255,255,255,0.2);
            padding: 8px 15px;
            border-radius: 20px;
            font-size: 0.9em;
        }
        
        .stats-overview {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            padding: 30px;
            background: #f8f9fa;
        }
        
        .stat-card {
            background: white;
            padding: 25px;
            border-radius: 10px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
            transition: transform 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
        }
        
        .stat-card .number {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .stat-card .label {
            color: #666;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .stat-card.total .number { color: #3498db; }
        .stat-card.up .number { color: #27ae60; }
        .stat-card.down .number { color: #e74c3c; }
        .stat-card.avg-time .number { color: #f39c12; }
        
        .main-content {
            padding: 30px;
        }
        
        .section-title {
            font-size: 1.8em;
            color: #2c3e50;
            margin-bottom: 25px;
            padding-bottom: 10px;
            border-bottom: 3px solid #3498db;
        }
        
        .websites-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 25px;
            margin-bottom: 40px;
        }
        
        .website-card {
            background: white;
            border-radius: 12px;
            padding: 25px;
            box-shadow: 0 8px 25px rgba(0,0,0,0.1);
            border-left: 5px solid #ddd;
            transition: all 0.3s ease;
        }
        
        .website-card:hover {
            transform: translateY(-3px);
            box-shadow: 0 12px 35px rgba(0,0,0,0.15);
        }
        
        .website-card.status-green { border-left-color: #27ae60; }
        .website-card.status-orange { border-left-color: #f39c12; }
        .website-card.status-red { border-left-color: #e74c3c; }
        .website-card.status-gray { border-left-color: #95a5a6; }
        
        .website-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        
        .website-name {
            font-size: 1.3em;
            font-weight: bold;
            color: #2c3e50;
        }
        
        .status-badge {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.8em;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .status-badge.green {
            background: #d5f4e6;
            color: #27ae60;
        }
        
        .status-badge.orange {
            background: #fef9e7;
            color: #f39c12;
        }
        
        .status-badge.red {
            background: #fadbd8;
            color: #e74c3c;
        }
        
        .status-badge.gray {
            background: #ecf0f1;
            color: #95a5a6;
        }
        
        .website-url {
            color: #7f8c8d;
            font-size: 0.9em;
            margin-bottom: 15px;
            word-break: break-all;
        }
        
        .website-metrics {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 15px;
        }
        
        .metric {
            text-align: center;
            padding: 15px;
            background: #f8f9fa;
            border-radius: 8px;
        }
        
        .metric-value {
            font-size: 1.5em;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .metric-label {
            font-size: 0.8em;
            color: #666;
            text-transform: uppercase;
        }
        
        .last-check {
            margin-top: 15px;
            padding-top: 15px;
            border-top: 1px solid #eee;
            font-size: 0.85em;
            color: #7f8c8d;
            text-align: center;
        }
        
        .footer {
            background: #2c3e50;
            color: white;
            text-align: center;
            padding: 20px;
            font-size: 0.9em;
        }
        
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid #f3f3f3;
            border-top: 3px solid #3498db;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        @media (max-width: 768px) {
            .container {
                margin: 10px;
                border-radius: 10px;
            }
            
            .header {
                padding: 20px;
            }
            
            .header h1 {
                font-size: 2em;
            }
            
            .stats-overview {
                grid-template-columns: repeat(2, 1fr);
                padding: 20px;
                gap: 15px;
            }
            
            .websites-grid {
                grid-template-columns: 1fr;
                gap: 20px;
            }
            
            .main-content {
                padding: 20px;
            }
        }
    </style>
EOF

    # 添加自动刷新脚本（如果启用）
    if [ "$ENHANCED_REFRESH_INTERVAL" -gt 0 ]; then
        cat << EOF
    <script>
        // 自动刷新功能
        let refreshInterval = $ENHANCED_REFRESH_INTERVAL;
        let countdown = refreshInterval;
        
        function updateCountdown() {
            const refreshElement = document.getElementById('refresh-countdown');
            if (refreshElement) {
                refreshElement.textContent = countdown + 's';
            }
            
            countdown--;
            if (countdown < 0) {
                location.reload();
            }
        }
        
        // 每秒更新倒计时
        setInterval(updateCountdown, 1000);
        
        // 页面可见性变化时暂停/恢复刷新
        document.addEventListener('visibilitychange', function() {
            if (document.hidden) {
                // 页面隐藏时暂停倒计时
            } else {
                // 页面显示时重置倒计时
                countdown = refreshInterval;
            }
        });
    </script>
EOF
    fi

    cat << EOF
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$ENHANCED_REPORT_TITLE</h1>
            <div class="subtitle">实时监控 · 智能分析 · 可视化展示</div>
EOF

    # 添加刷新信息（如果启用自动刷新）
    if [ "$ENHANCED_REFRESH_INTERVAL" -gt 0 ]; then
        cat << EOF
            <div class="refresh-info">
                <span class="loading"></span>
                自动刷新: <span id="refresh-countdown">${ENHANCED_REFRESH_INTERVAL}s</span>
            </div>
EOF
    fi

    cat << EOF
        </div>
        
        <div class="stats-overview">
EOF

    # 计算总体统计数据
    local total_websites=0
    local total_up=0
    local total_down=0
    local total_response_time=0
    local response_count=0
    
    if [ -f "$analysis_data" ]; then
        while IFS='|' read -r url name status response_time timestamp color availability avg_time checks; do
            total_websites=$((total_websites + 1))
            
            case "$status" in
                UP|CONTENT_INITIAL|CONTENT_UNCHANGED|CONTENT_CHANGED)
                    total_up=$((total_up + 1))
                    ;;
                DOWN|TIMEOUT|ERROR)
                    total_down=$((total_down + 1))
                    ;;
            esac
            
            if [ "$avg_time" -gt 0 ]; then
                total_response_time=$((total_response_time + avg_time))
                response_count=$((response_count + 1))
            fi
        done < "$analysis_data"
    fi
    
    local avg_response_time=0
    if [ "$response_count" -gt 0 ]; then
        avg_response_time=$((total_response_time / response_count))
    fi

    cat << EOF
            <div class="stat-card total">
                <div class="number">$total_websites</div>
                <div class="label">监控网站</div>
            </div>
            <div class="stat-card up">
                <div class="number">$total_up</div>
                <div class="label">正常运行</div>
            </div>
            <div class="stat-card down">
                <div class="number">$total_down</div>
                <div class="label">异常状态</div>
            </div>
            <div class="stat-card avg-time">
                <div class="number">${avg_response_time}ms</div>
                <div class="label">平均响应</div>
            </div>
        </div>
        
        <div class="main-content">
            <h2 class="section-title">网站状态详情</h2>
            <div class="websites-grid">
EOF

    # 生成网站卡片
    if [ -f "$analysis_data" ]; then
        while IFS='|' read -r url name status response_time timestamp color availability avg_time checks; do
            # 格式化状态显示
            local status_text="$status"
            case "$status" in
                UP) status_text="正常" ;;
                DOWN) status_text="离线" ;;
                TIMEOUT) status_text="超时" ;;
                ERROR) status_text="错误" ;;
                CONTENT_CHANGED) status_text="内容变更" ;;
                CONTENT_UNCHANGED) status_text="内容正常" ;;
                CONTENT_INITIAL) status_text="初始检查" ;;
                UNKNOWN) status_text="未知" ;;
            esac
            
            # 格式化时间戳
            local formatted_time="未知"
            if [ -n "$timestamp" ]; then
                formatted_time="$timestamp"
            fi
            
            cat << EOF
                <div class="website-card status-$color">
                    <div class="website-header">
                        <div class="website-name">$name</div>
                        <div class="status-badge $color">$status_text</div>
                    </div>
                    <div class="website-url">$url</div>
                    <div class="website-metrics">
                        <div class="metric">
                            <div class="metric-value">${availability}%</div>
                            <div class="metric-label">可用性</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value">${avg_time}ms</div>
                            <div class="metric-label">响应时间</div>
                        </div>
                    </div>
                    <div class="last-check">
                        最后检查: $formatted_time
                    </div>
                </div>
EOF
        done < "$analysis_data"
    fi

    cat << EOF
            </div>
        </div>
        
        <div class="footer">
            <p>报告生成时间: $current_time | 网站监控系统 v2.0</p>
            <p>数据更新间隔: 每${ENHANCED_REFRESH_INTERVAL}秒自动刷新</p>
        </div>
    </div>
</body>
</html>
EOF
}

# 主函数
main() {
    # 验证必要命令
    validate_required_commands
    
    # 解析命令行参数
    parse_arguments "$@"
    
    if [ "$ENHANCED_VERBOSE" = true ]; then
        log_info "开始生成增强版HTML报告..."
    fi
    
    # 确保输出目录存在
    ensure_directory "$(dirname "$ENHANCED_OUTPUT_FILE")"
    
    # 获取网站配置
    local website_configs
    website_configs=$(get_website_configs)
    
    # 分析最新数据
    local analysis_data
    analysis_data=$(analyze_latest_data "$website_configs")
    
    # 生成HTML报告
    generate_enhanced_html "$website_configs" "$analysis_data" > "$ENHANCED_OUTPUT_FILE"
    
    # 清理临时文件
    rm -f "$website_configs" "$analysis_data"
    
    if [ "$ENHANCED_VERBOSE" = true ]; then
        log_info "增强版HTML报告已生成: $ENHANCED_OUTPUT_FILE"
    else
        echo "报告已生成: $ENHANCED_OUTPUT_FILE"
    fi
}

# 执行主函数
main "$@"