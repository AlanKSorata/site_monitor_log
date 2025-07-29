#!/bin/bash

# 最终报告生成器 - 现代化样式
# 生成现代化风格的HTML监控报告，输出到latest-report.html

set -euo pipefail

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"

# 引入必要的库
source "$LIB_DIR/common.sh"
source "$LIB_DIR/log-utils.sh"

# 默认配置
DEFAULT_OUTPUT_FILE="$PROJECT_ROOT/web/latest-report.html"
DEFAULT_REFRESH_INTERVAL=300

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "生成现代化风格的HTML监控报告"
    echo ""
    echo "OPTIONS:"
    echo "    -o, --output FILE       输出文件路径 (默认: $DEFAULT_OUTPUT_FILE)"
    echo "    -r, --refresh SECONDS   自动刷新间隔秒数 (默认: $DEFAULT_REFRESH_INTERVAL, 0=禁用)"
    echo "    -t, --title TITLE       报告标题 (默认: 网站监控仪表板)"
    echo "    -v, --verbose           启用详细输出"
    echo "    -h, --help             显示此帮助信息"
    echo ""
}

parse_arguments() {
    local output_file="$DEFAULT_OUTPUT_FILE"
    local refresh_interval="$DEFAULT_REFRESH_INTERVAL"
    local report_title="网站监控仪表板"
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
    
    export FINAL_OUTPUT_FILE="$output_file"
    export FINAL_REFRESH_INTERVAL="$refresh_interval"
    export FINAL_REPORT_TITLE="$report_title"
    export FINAL_VERBOSE="$verbose"
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

# 分析监控数据
analyze_monitoring_data() {
    local website_configs="$1"
    local temp_file=$(mktemp)
    
    # 获取最近24小时的数据
    local cutoff_time=$(date -d '24 hours ago' '+%Y-%m-%d %H:%M:%S')
    
    if [ -f "$MAIN_LOG_FILE" ]; then
        while IFS='|' read -r url name interval timeout content_check; do
            local latest_status="UNKNOWN"
            local latest_response_time=0
            local latest_timestamp=""
            local status_color="secondary"
            local status_icon="❓"
            
            # 查找该网站的最新记录
            local latest_entry
            latest_entry=$(grep "|$url|" "$MAIN_LOG_FILE" | tail -1)
            
            if [ -n "$latest_entry" ]; then
                IFS='|' read -r timestamp level message check_url response_time status_code final_status <<< "$latest_entry"
                
                if [ "$check_url" = "$url" ]; then
                    latest_status="$final_status"
                    latest_response_time="$response_time"
                    latest_timestamp="$timestamp"
                    
                    # 确定状态颜色和图标
                    case "$final_status" in
                        UP|CONTENT_INITIAL|CONTENT_UNCHANGED)
                            status_color="success"
                            status_icon="✅"
                            ;;
                        CONTENT_CHANGED)
                            status_color="warning"
                            status_icon="⚠️"
                            ;;
                        DOWN|TIMEOUT|ERROR)
                            status_color="danger"
                            status_icon="❌"
                            ;;
                        *)
                            status_color="secondary"
                            status_icon="❓"
                            ;;
                    esac
                fi
            fi
            
            # 计算24小时统计数据
            local day_checks=0
            local day_up=0
            local day_down=0
            local day_total_time=0
            local day_response_count=0
            local uptime_percentage=0
            
            while IFS= read -r log_line; do
                if [[ "$log_line" =~ \|$url\| ]]; then
                    IFS='|' read -r log_timestamp log_level log_message log_url log_response_time log_status_code log_final_status <<< "$log_line"
                    
                    # 检查时间范围
                    if [[ "$log_timestamp" > "$cutoff_time" ]]; then
                        day_checks=$((day_checks + 1))
                        
                        case "$log_final_status" in
                            UP|CONTENT_INITIAL|CONTENT_CHANGED|CONTENT_UNCHANGED)
                                day_up=$((day_up + 1))
                                ;;
                            DOWN|TIMEOUT|ERROR)
                                day_down=$((day_down + 1))
                                ;;
                        esac
                        
                        if [ "$log_response_time" -gt 0 ]; then
                            day_total_time=$((day_total_time + log_response_time))
                            day_response_count=$((day_response_count + 1))
                        fi
                    fi
                fi
            done < "$MAIN_LOG_FILE"
            
            # 计算可用性百分比
            if [ "$day_checks" -gt 0 ]; then
                uptime_percentage=$(( (day_up * 100) / day_checks ))
            fi
            
            # 计算平均响应时间
            local avg_response_time=0
            if [ "$day_response_count" -gt 0 ]; then
                avg_response_time=$((day_total_time / day_response_count))
            fi
            
            # 输出分析结果
            echo "$url|$name|$latest_status|$latest_response_time|$latest_timestamp|$status_color|$status_icon|$uptime_percentage|$avg_response_time|$day_checks" >> "$temp_file"
            
        done < "$website_configs"
    fi
    
    echo "$temp_file"
}

# 生成现代化HTML报告
generate_final_html() {
    local website_configs="$1"
    local analysis_data="$2"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>网站监控仪表板</title>
    <style>
        :root {
            /* 现代化配色方案 */
            --primary-color: #6366f1;
            --primary-dark: #4f46e5;
            --success-color: #10b981;
            --warning-color: #f59e0b;
            --danger-color: #ef4444;
            --secondary-color: #6b7280;
            
            /* 背景色 */
            --bg-primary: #f8fafc;
            --bg-secondary: #ffffff;
            --bg-tertiary: #f1f5f9;
            
            /* 文字颜色 */
            --text-primary: #1e293b;
            --text-secondary: #64748b;
            --text-muted: #94a3b8;
            
            /* 边框和阴影 */
            --border-color: #e2e8f0;
            --shadow-sm: 0 1px 2px 0 rgb(0 0 0 / 0.05);
            --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
            --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);
            --shadow-xl: 0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1);
            
            /* 圆角 */
            --radius-sm: 0.375rem;
            --radius-md: 0.5rem;
            --radius-lg: 0.75rem;
            --radius-xl: 1rem;
        }
        
        /* 暗色主题 */
        [data-theme="dark"] {
            --bg-primary: #0f172a;
            --bg-secondary: #1e293b;
            --bg-tertiary: #334155;
            --text-primary: #f8fafc;
            --text-secondary: #cbd5e1;
            --text-muted: #94a3b8;
            --border-color: #334155;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
            transition: all 0.3s ease;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 1.5rem;
        }
        
        /* 顶部导航栏 */
        .navbar {
            background: var(--bg-secondary);
            border-radius: var(--radius-xl);
            padding: 1.5rem 2rem;
            margin-bottom: 2rem;
            box-shadow: var(--shadow-lg);
            display: flex;
            justify-content: space-between;
            align-items: center;
            border: 1px solid var(--border-color);
        }
        
        .navbar-brand {
            display: flex;
            align-items: center;
            gap: 1rem;
        }
        
        .navbar-brand .icon {
            width: 3rem;
            height: 3rem;
            background: linear-gradient(135deg, var(--primary-color), var(--primary-dark));
            border-radius: var(--radius-lg);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 1.5rem;
        }
        
        .navbar-title {
            font-size: 1.875rem;
            font-weight: 700;
            color: var(--text-primary);
        }
        
        .navbar-subtitle {
            font-size: 0.875rem;
            color: var(--text-secondary);
            margin-top: 0.25rem;
        }
        
        .navbar-controls {
            display: flex;
            align-items: center;
            gap: 1rem;
        }
        
        .theme-toggle {
            background: var(--bg-tertiary);
            border: 1px solid var(--border-color);
            border-radius: var(--radius-md);
            padding: 0.5rem;
            cursor: pointer;
            transition: all 0.2s ease;
            color: var(--text-secondary);
        }
        
        .theme-toggle:hover {
            background: var(--primary-color);
            color: white;
            transform: translateY(-1px);
        }
        
        .refresh-status {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            background: var(--bg-tertiary);
            padding: 0.5rem 1rem;
            border-radius: var(--radius-md);
            font-size: 0.875rem;
            color: var(--text-secondary);
        }
        
        .refresh-spinner {
            width: 1rem;
            height: 1rem;
            border: 2px solid var(--border-color);
            border-top: 2px solid var(--primary-color);
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        /* 统计卡片网格 */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        
        .stat-card {
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: var(--radius-xl);
            padding: 2rem;
            box-shadow: var(--shadow-md);
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }
        
        .stat-card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 4px;
            background: linear-gradient(90deg, var(--primary-color), var(--primary-dark));
        }
        
        .stat-card:hover {
            transform: translateY(-4px);
            box-shadow: var(--shadow-xl);
        }
        
        .stat-card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1rem;
        }
        
        .stat-card-title {
            font-size: 0.875rem;
            font-weight: 600;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        
        .stat-card-icon {
            width: 2.5rem;
            height: 2.5rem;
            border-radius: var(--radius-lg);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.25rem;
            color: white;
        }
        
        .stat-card-icon.total { background: linear-gradient(135deg, var(--primary-color), var(--primary-dark)); }
        .stat-card-icon.success { background: linear-gradient(135deg, var(--success-color), #059669); }
        .stat-card-icon.danger { background: linear-gradient(135deg, var(--danger-color), #dc2626); }
        .stat-card-icon.warning { background: linear-gradient(135deg, var(--warning-color), #d97706); }
        
        .stat-card-value {
            font-size: 2.5rem;
            font-weight: 800;
            color: var(--text-primary);
            margin-bottom: 0.5rem;
        }
        
        .stat-card-change {
            font-size: 0.875rem;
            display: flex;
            align-items: center;
            gap: 0.25rem;
        }
        
        .stat-card-change.positive { color: var(--success-color); }
        .stat-card-change.negative { color: var(--danger-color); }
        .stat-card-change.neutral { color: var(--text-secondary); }
        
        /* 网站监控卡片 */
        .websites-section {
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-radius: var(--radius-xl);
            padding: 2rem;
            box-shadow: var(--shadow-md);
        }
        
        .section-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 2rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid var(--border-color);
        }
        
        .section-title {
            font-size: 1.5rem;
            font-weight: 700;
            color: var(--text-primary);
        }
        
        .section-subtitle {
            font-size: 0.875rem;
            color: var(--text-secondary);
            margin-top: 0.25rem;
        }
        
        .websites-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 1.5rem;
        }
        
        .website-card {
            background: var(--bg-tertiary);
            border: 1px solid var(--border-color);
            border-radius: var(--radius-lg);
            padding: 1.5rem;
            transition: all 0.3s ease;
            position: relative;
        }
        
        .website-card:hover {
            transform: translateY(-2px);
            box-shadow: var(--shadow-lg);
        }
        
        .website-card.status-success { border-left: 4px solid var(--success-color); }
        .website-card.status-warning { border-left: 4px solid var(--warning-color); }
        .website-card.status-danger { border-left: 4px solid var(--danger-color); }
        .website-card.status-secondary { border-left: 4px solid var(--secondary-color); }
        
        .website-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 1rem;
        }
        
        .website-info h3 {
            font-size: 1.125rem;
            font-weight: 600;
            color: var(--text-primary);
            margin-bottom: 0.25rem;
        }
        
        .website-url {
            font-size: 0.875rem;
            color: var(--text-secondary);
            word-break: break-all;
        }
        
        .status-indicator {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.5rem 1rem;
            border-radius: var(--radius-md);
            font-size: 0.875rem;
            font-weight: 600;
        }
        
        .status-indicator.success {
            background: rgba(16, 185, 129, 0.1);
            color: var(--success-color);
        }
        
        .status-indicator.warning {
            background: rgba(245, 158, 11, 0.1);
            color: var(--warning-color);
        }
        
        .status-indicator.danger {
            background: rgba(239, 68, 68, 0.1);
            color: var(--danger-color);
        }
        
        .status-indicator.secondary {
            background: rgba(107, 114, 128, 0.1);
            color: var(--secondary-color);
        }
        
        .website-metrics {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1rem;
            margin-top: 1rem;
        }
        
        .metric {
            text-align: center;
            padding: 1rem;
            background: var(--bg-secondary);
            border-radius: var(--radius-md);
            border: 1px solid var(--border-color);
        }
        
        .metric-value {
            font-size: 1.5rem;
            font-weight: 700;
            color: var(--text-primary);
            margin-bottom: 0.25rem;
        }
        
        .metric-label {
            font-size: 0.75rem;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        
        .last-check {
            margin-top: 1rem;
            padding-top: 1rem;
            border-top: 1px solid var(--border-color);
            font-size: 0.875rem;
            color: var(--text-muted);
            text-align: center;
        }
        
        /* 响应式设计 */
        @media (max-width: 768px) {
            .container {
                padding: 1rem;
            }
            
            .navbar {
                flex-direction: column;
                gap: 1rem;
                text-align: center;
            }
            
            .navbar-controls {
                justify-content: center;
            }
            
            .stats-grid {
                grid-template-columns: repeat(2, 1fr);
                gap: 1rem;
            }
            
            .websites-grid {
                grid-template-columns: 1fr;
            }
            
            .website-metrics {
                grid-template-columns: 1fr;
            }
        }
        
        @media (max-width: 480px) {
            .stats-grid {
                grid-template-columns: 1fr;
            }
            
            .navbar-brand .icon {
                width: 2.5rem;
                height: 2.5rem;
                font-size: 1.25rem;
            }
            
            .navbar-title {
                font-size: 1.5rem;
            }
        }
        
        /* 动画效果 */
        .fade-in {
            animation: fadeIn 0.6s ease-out;
        }
        
        @keyframes fadeIn {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }
        
        .slide-up {
            animation: slideUp 0.4s ease-out;
        }
        
        @keyframes slideUp {
            from {
                opacity: 0;
                transform: translateY(30px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }
    </style>
</head>
<body data-theme="light">
    <div class="container">
        <!-- 导航栏 -->
        <nav class="navbar fade-in">
            <div class="navbar-brand">
                <div class="icon">
                    📊
                </div>
                <div>
EOF

    echo "                    <div class=\"navbar-title\">$FINAL_REPORT_TITLE</div>"
    echo "                    <div class=\"navbar-subtitle\">实时监控 · 高效分析</div>"

    cat << 'EOF'
                </div>
            </div>
            <div class="navbar-controls">
                <button class="theme-toggle" onclick="toggleTheme()">
                    🌙
                </button>
EOF

    if [ "$FINAL_REFRESH_INTERVAL" -gt 0 ]; then
        cat << EOF
                <div class="refresh-status">
                    <div class="refresh-spinner"></div>
                    <span>自动刷新已启用</span>
                </div>
EOF
    fi

    cat << 'EOF'
            </div>
        </nav>

        <!-- 统计概览 -->
        <div class="stats-grid fade-in">
EOF

    # 计算总体统计数据
    local total_websites=0
    local total_up=0
    local total_down=0
    local total_response_time=0
    local response_count=0
    
    if [ -f "$analysis_data" ]; then
        while IFS='|' read -r url name status response_time timestamp color icon uptime avg_time checks; do
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
    
    local uptime_percentage=0
    if [ "$total_websites" -gt 0 ]; then
        uptime_percentage=$(( (total_up * 100) / total_websites ))
    fi

    cat << EOF
            <div class="stat-card slide-up">
                <div class="stat-card-header">
                    <div class="stat-card-title">监控网站</div>
                    <div class="stat-card-icon total">
                        🌐
                    </div>
                </div>
                <div class="stat-card-value">$total_websites</div>
                <div class="stat-card-change neutral">
                    ℹ️ 总计监控站点
                </div>
            </div>

            <div class="stat-card slide-up">
                <div class="stat-card-header">
                    <div class="stat-card-title">正常运行</div>
                    <div class="stat-card-icon success">
                        ✅
                    </div>
                </div>
                <div class="stat-card-value">$total_up</div>
                <div class="stat-card-change positive">
                    📈 ${uptime_percentage}% 可用性
                </div>
            </div>

            <div class="stat-card slide-up">
                <div class="stat-card-header">
                    <div class="stat-card-title">异常状态</div>
                    <div class="stat-card-icon danger">
                        ⚠️
                    </div>
                </div>
                <div class="stat-card-value">$total_down</div>
                <div class="stat-card-change $([ $total_down -eq 0 ] && echo "positive" || echo "negative")">
                    $([ $total_down -eq 0 ] && echo "✅ 全部正常" || echo "❌ 需要关注")
                </div>
            </div>

            <div class="stat-card slide-up">
                <div class="stat-card-header">
                    <div class="stat-card-title">平均响应</div>
                    <div class="stat-card-icon warning">
                        ⏱️
                    </div>
                </div>
                <div class="stat-card-value">${avg_response_time}ms</div>
                <div class="stat-card-change $([ $avg_response_time -lt 1000 ] && echo "positive" || echo "warning")">
                    $([ $avg_response_time -lt 1000 ] && echo "⚡ 响应良好" || echo "⏳ 响应较慢")
                </div>
            </div>
        </div>

        <!-- 网站详情 -->
        <div class="websites-section fade-in">
            <div class="section-header">
                <div>
                    <div class="section-title">网站监控详情</div>
                    <div class="section-subtitle">实时状态 · 性能指标 · 历史数据</div>
                </div>
            </div>

            <div class="websites-grid">
EOF

    # 生成网站卡片
    if [ -f "$analysis_data" ]; then
        while IFS='|' read -r url name status response_time timestamp color icon uptime avg_time checks; do
            # 格式化状态显示
            local status_text="$status"
            case "$status" in
                UP) status_text="正常运行" ;;
                DOWN) status_text="服务离线" ;;
                TIMEOUT) status_text="响应超时" ;;
                ERROR) status_text="连接错误" ;;
                CONTENT_CHANGED) status_text="内容变更" ;;
                CONTENT_UNCHANGED) status_text="内容正常" ;;
                CONTENT_INITIAL) status_text="初始检查" ;;
                UNKNOWN) status_text="状态未知" ;;
            esac
            
            # 格式化时间戳
            local formatted_time="未知"
            if [ -n "$timestamp" ]; then
                formatted_time="$timestamp"
            fi
            
            cat << EOF
                <div class="website-card status-$color slide-up">
                    <div class="website-header">
                        <div class="website-info">
                            <h3>$name</h3>
                            <div class="website-url">$url</div>
                        </div>
                        <div class="status-indicator $color">
                            <span>$icon</span>
                            <span>$status_text</span>
                        </div>
                    </div>
                    
                    <div class="website-metrics">
                        <div class="metric">
                            <div class="metric-value">${uptime}%</div>
                            <div class="metric-label">可用性</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value">${avg_time}ms</div>
                            <div class="metric-label">响应时间</div>
                        </div>
                    </div>
                    
                    <div class="last-check">
                        🕒 最后检查: $formatted_time
                    </div>
                </div>
EOF
        done < "$analysis_data"
    fi

    cat << EOF
            </div>
        </div>
    </div>

    <script>
        // 主题切换功能
        function toggleTheme() {
            const body = document.body;
            const currentTheme = body.getAttribute('data-theme');
            
            if (currentTheme === 'light') {
                body.setAttribute('data-theme', 'dark');
                localStorage.setItem('theme', 'dark');
            } else {
                body.setAttribute('data-theme', 'light');
                localStorage.setItem('theme', 'light');
            }
        }
        
        // 初始化主题
        function initTheme() {
            const savedTheme = localStorage.getItem('theme') || 'light';
            document.body.setAttribute('data-theme', savedTheme);
        }
        
        // 页面加载完成后初始化
        document.addEventListener('DOMContentLoaded', function() {
            initTheme();
            
            // 添加动画延迟
            const cards = document.querySelectorAll('.slide-up');
            cards.forEach((card, index) => {
                card.style.animationDelay = (index * 0.1) + 's';
            });
        });
EOF

    # 添加自动刷新功能
    if [ "$FINAL_REFRESH_INTERVAL" -gt 0 ]; then
        cat << EOF
        
        // 自动刷新功能
        let refreshInterval = $FINAL_REFRESH_INTERVAL * 1000; // 转换为毫秒
        
        // 设置自动刷新
        setTimeout(function() {
            location.reload();
        }, refreshInterval);
        
        // 页面可见性变化时重新设置刷新
        document.addEventListener('visibilitychange', function() {
            if (!document.hidden) {
                setTimeout(function() {
                    location.reload();
                }, refreshInterval);
            }
        });
EOF
    fi

    cat << 'EOF'
    </script>
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
    
    if [ "$FINAL_VERBOSE" = true ]; then
        log_info "开始生成现代化HTML报告..."
    fi
    
    # 确保输出目录存在
    ensure_directory "$(dirname "$FINAL_OUTPUT_FILE")"
    
    # 获取网站配置
    local website_configs
    website_configs=$(get_website_configs)
    
    # 分析监控数据
    local analysis_data
    analysis_data=$(analyze_monitoring_data "$website_configs")
    
    # 生成HTML报告
    generate_final_html "$website_configs" "$analysis_data" > "$FINAL_OUTPUT_FILE"
    
    # 清理临时文件
    rm -f "$website_configs" "$analysis_data"
    
    if [ "$FINAL_VERBOSE" = true ]; then
        log_info "现代化HTML报告已生成: $FINAL_OUTPUT_FILE"
    else
        echo "现代化报告已生成: $FINAL_OUTPUT_FILE"
    fi
}

# 执行主函数
main "$@"