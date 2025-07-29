#!/bin/bash

# Nginx集成脚本 - 网站监控系统
# 负责定期生成报告并更新nginx展示内容

set -euo pipefail

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_ROOT/lib"

# 引入必要的库
source "$LIB_DIR/common.sh"
source "$LIB_DIR/log-utils.sh"

# 配置变量
NGINX_WEB_ROOT="/var/www/website-monitor"
NGINX_REPORTS_DIR="$NGINX_WEB_ROOT/reports"
NGINX_API_DIR="$NGINX_WEB_ROOT/api"
NGINX_ASSETS_DIR="$NGINX_WEB_ROOT/assets"
NGINX_ERROR_PAGES_DIR="$NGINX_WEB_ROOT/error-pages"

# 报告更新间隔（秒）
UPDATE_INTERVAL=300  # 5分钟

# 显示使用说明
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Nginx集成管理工具 - 网站监控系统"
    echo ""
    echo "COMMANDS:"
    echo "    setup           初始化nginx集成环境"
    echo "    start           启动定期更新服务"
    echo "    stop            停止定期更新服务"
    echo "    status          查看服务状态"
    echo "    update          手动更新报告"
    echo "    cleanup         清理旧报告文件"
    echo ""
    echo "OPTIONS:"
    echo "    -i, --interval SECONDS  设置更新间隔（默认: $UPDATE_INTERVAL 秒）"
    echo "    -v, --verbose          启用详细输出"
    echo "    -h, --help            显示此帮助信息"
    echo ""
    echo "EXAMPLES:"
    echo "    $0 setup                    # 初始化环境"
    echo "    $0 start --interval 600     # 启动服务，10分钟更新一次"
    echo "    $0 update                   # 手动更新报告"
    echo ""
}

# 解析命令行参数
parse_arguments() {
    local command=""
    local interval="$UPDATE_INTERVAL"
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            setup|start|stop|status|update|cleanup)
                command="$1"
                shift
                ;;
            -i|--interval)
                interval="$2"
                if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 60 ]; then
                    die "更新间隔必须是大于等于60的数字" 2
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
                die "未知选项: $1" 2
                ;;
        esac
    done
    
    if [ -z "$command" ]; then
        die "请指定命令。使用 --help 查看帮助信息" 2
    fi
    
    export NGINX_COMMAND="$command"
    export NGINX_UPDATE_INTERVAL="$interval"
    export NGINX_VERBOSE="$verbose"
}

# 初始化nginx集成环境
setup_nginx_environment() {
    log_info "初始化nginx集成环境..."
    
    # 检查是否有sudo权限
    if [ "$EUID" -ne 0 ]; then
        log_warn "非root用户，使用开发模式..."
        setup_dev_environment
        return 0
    fi
    
    # 创建必要的目录
    mkdir -p "$NGINX_WEB_ROOT"
    mkdir -p "$NGINX_REPORTS_DIR"
    mkdir -p "$NGINX_API_DIR"
    mkdir -p "$NGINX_ASSETS_DIR"
    mkdir -p "$NGINX_ERROR_PAGES_DIR"
    
    # 设置目录权限
    if command -v www-data >/dev/null 2>&1; then
        chown -R www-data:www-data "$NGINX_WEB_ROOT"
    else
        chown -R nginx:nginx "$NGINX_WEB_ROOT" 2>/dev/null || chown -R $USER:$USER "$NGINX_WEB_ROOT"
    fi
    chmod -R 755 "$NGINX_WEB_ROOT"
    
    # 创建CSS样式文件
    create_css_assets
    
    # 创建错误页面
    create_error_pages
    
    # 创建初始API文件
    create_api_files
    
    # 复制nginx配置文件
    if [ -f "$PROJECT_ROOT/config/nginx.conf" ]; then
        sudo cp "$PROJECT_ROOT/config/nginx.conf" /etc/nginx/sites-available/website-monitor
        sudo ln -sf /etc/nginx/sites-available/website-monitor /etc/nginx/sites-enabled/
        log_info "nginx配置文件已安装"
    fi
    
    # 生成初始报告
    generate_initial_report
    
    log_info "nginx集成环境初始化完成"
}

# 开发环境设置（非root用户）
setup_dev_environment() {
    log_info "设置开发环境..."
    
    # 使用项目目录下的web目录
    NGINX_WEB_ROOT="$PROJECT_ROOT/web"
    NGINX_REPORTS_DIR="$NGINX_WEB_ROOT/reports"
    NGINX_API_DIR="$NGINX_WEB_ROOT/api"
    NGINX_ASSETS_DIR="$NGINX_WEB_ROOT/assets"
    NGINX_ERROR_PAGES_DIR="$NGINX_WEB_ROOT/error-pages"
    
    # 创建目录
    mkdir -p "$NGINX_WEB_ROOT"
    mkdir -p "$NGINX_REPORTS_DIR"
    mkdir -p "$NGINX_API_DIR"
    mkdir -p "$NGINX_ASSETS_DIR"
    mkdir -p "$NGINX_ERROR_PAGES_DIR"
    
    # 创建CSS样式文件
    create_css_assets
    
    # 创建错误页面
    create_error_pages
    
    # 创建初始API文件
    create_api_files
    
    # 生成初始报告到项目目录
    generate_dev_report
    
    log_info "开发环境设置完成"
    log_info "Web目录: $NGINX_WEB_ROOT"
    log_info "可以使用简单HTTP服务器测试："
    log_info "  cd $NGINX_WEB_ROOT && python3 -m http.server 8080"
}

# 生成开发环境报告
generate_dev_report() {
    log_info "生成开发环境报告..."
    
    # 生成HTML格式的报告
    "$PROJECT_ROOT/bin/report-generator.sh" \
        --format html \
        --period daily \
        --output "$NGINX_WEB_ROOT/latest-report.html" 2>/dev/null || {
        
        # 如果报告生成失败，创建一个简单的测试页面
        cat > "$NGINX_WEB_ROOT/latest-report.html" << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>网站监控系统 - 开发模式</title>
    <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
    <div class="container">
        <h1>网站监控系统 - 开发模式</h1>
        <div class="report-info">
            <p>系统正在开发模式下运行</p>
            <p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
        </div>
        <h2>系统状态</h2>
        <p>✓ 开发环境已设置</p>
        <p>✓ Web目录已创建</p>
        <p>✓ API接口已准备</p>
        
        <h2>测试链接</h2>
        <ul>
            <li><a href="/api/status">系统状态API</a></li>
            <li><a href="/api/websites">网站列表API</a></li>
            <li><a href="/reports/">历史报告</a></li>
        </ul>
        
        <div class="footer">
            <p>开发模式 - 网站监控系统</p>
        </div>
    </div>
</body>
</html>
EOF
    }
    
    # 创建首页链接（如果符号链接失败，则复制文件）
    if ! ln -sf latest-report.html "$NGINX_WEB_ROOT/index.html" 2>/dev/null; then
        cp "$NGINX_WEB_ROOT/latest-report.html" "$NGINX_WEB_ROOT/index.html"
    fi
    
    log_info "开发环境报告已生成"
}

# 创建CSS样式文件
create_css_assets() {
    cat > "$NGINX_ASSETS_DIR/style.css" << 'EOF'
/* 网站监控系统样式 */
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    margin: 0;
    padding: 20px;
    background-color: #f5f5f5;
    color: #333;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    background: white;
    padding: 30px;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
}

h1 {
    color: #2c3e50;
    text-align: center;
    margin-bottom: 30px;
    border-bottom: 3px solid #3498db;
    padding-bottom: 15px;
}

h2 {
    color: #34495e;
    margin-top: 40px;
    margin-bottom: 20px;
}

.report-info {
    background: #ecf0f1;
    padding: 15px;
    border-radius: 5px;
    margin-bottom: 30px;
    text-align: center;
}

.report-info p {
    margin: 5px 0;
    color: #7f8c8d;
}

table {
    width: 100%;
    border-collapse: collapse;
    margin: 20px 0;
    background: white;
}

th, td {
    padding: 12px;
    text-align: left;
    border-bottom: 1px solid #ddd;
}

th {
    background-color: #3498db;
    color: white;
    font-weight: bold;
}

tr:hover {
    background-color: #f8f9fa;
}

.status-up {
    color: #27ae60;
    font-weight: bold;
}

.status-down {
    color: #e74c3c;
    font-weight: bold;
}

.status-warning {
    color: #f39c12;
    font-weight: bold;
}

.availability-high {
    background-color: #d5f4e6;
    color: #27ae60;
}

.availability-medium {
    background-color: #fef9e7;
    color: #f39c12;
}

.availability-low {
    background-color: #fadbd8;
    color: #e74c3c;
}

.response-time-good {
    color: #27ae60;
}

.response-time-slow {
    color: #f39c12;
}

.response-time-critical {
    color: #e74c3c;
}

.footer {
    text-align: center;
    margin-top: 40px;
    padding-top: 20px;
    border-top: 1px solid #ddd;
    color: #7f8c8d;
    font-size: 14px;
}

.refresh-info {
    position: fixed;
    top: 10px;
    right: 10px;
    background: #3498db;
    color: white;
    padding: 8px 15px;
    border-radius: 5px;
    font-size: 12px;
}

@media (max-width: 768px) {
    .container {
        padding: 15px;
    }
    
    table {
        font-size: 14px;
    }
    
    th, td {
        padding: 8px;
    }
}
EOF
    
    log_info "CSS样式文件已创建"
}

# 创建错误页面
create_error_pages() {
    # 404错误页面
    cat > "$NGINX_ERROR_PAGES_DIR/404.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>页面未找到 - 网站监控系统</title>
    <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
    <div class="container">
        <h1>404 - 页面未找到</h1>
        <p>抱歉，您访问的页面不存在。</p>
        <p><a href="/">返回首页</a></p>
    </div>
</body>
</html>
EOF
    
    # 50x错误页面
    cat > "$NGINX_ERROR_PAGES_DIR/50x.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>服务器错误 - 网站监控系统</title>
    <link rel="stylesheet" href="/assets/style.css">
</head>
<body>
    <div class="container">
        <h1>服务器错误</h1>
        <p>服务器遇到了一个错误，无法完成您的请求。</p>
        <p>请稍后再试，或联系系统管理员。</p>
        <p><a href="/">返回首页</a></p>
    </div>
</body>
</html>
EOF
    
    log_info "错误页面已创建"
}

# 创建API文件
create_api_files() {
    # 系统状态API
    cat > "$NGINX_API_DIR/status.json" << 'EOF'
{
    "status": "running",
    "last_update": "",
    "next_update": "",
    "update_interval": 300,
    "total_websites": 0,
    "websites_up": 0,
    "websites_down": 0,
    "average_response_time": 0
}
EOF
    
    # 网站列表API
    cat > "$NGINX_API_DIR/websites.json" << 'EOF'
{
    "websites": [],
    "last_update": "",
    "total_count": 0
}
EOF
    
    log_info "API文件已创建"
}

# 生成初始报告
generate_initial_report() {
    log_info "生成初始HTML报告..."
    
    # 生成HTML格式的报告
    "$PROJECT_ROOT/bin/report-generator.sh" \
        --format html \
        --period daily \
        --output "$NGINX_WEB_ROOT/latest-report.html"
    
    # 创建首页链接（如果符号链接失败，则复制文件）
    if ! ln -sf latest-report.html "$NGINX_WEB_ROOT/index.html" 2>/dev/null; then
        cp "$NGINX_WEB_ROOT/latest-report.html" "$NGINX_WEB_ROOT/index.html"
    fi
    
    log_info "初始报告已生成"
}

# 更新报告和API数据
update_reports() {
    if [ "$NGINX_VERBOSE" = true ]; then
        log_info "开始更新报告..."
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local report_file="$NGINX_WEB_ROOT/latest-report.html"
    local archive_file="$NGINX_REPORTS_DIR/report-$(date '+%Y%m%d-%H%M%S').html"
    
    # 生成新的HTML报告
    "$PROJECT_ROOT/bin/report-generator.sh" \
        --format html \
        --period daily \
        --output "$report_file" \
        ${NGINX_VERBOSE:+--verbose}
    
    # 归档旧报告
    if [ -f "$report_file" ]; then
        cp "$report_file" "$archive_file"
    fi
    
    # 更新API数据
    update_api_data
    
    # 清理旧报告（保留最近7天）
    find "$NGINX_REPORTS_DIR" -name "report-*.html" -mtime +7 -delete 2>/dev/null || true
    
    if [ "$NGINX_VERBOSE" = true ]; then
        log_info "报告更新完成: $timestamp"
    fi
}

# 更新API数据
update_api_data() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local next_update=$(date -d "+$NGINX_UPDATE_INTERVAL seconds" '+%Y-%m-%d %H:%M:%S')
    
    # 从配置文件读取网站信息
    local total_websites=0
    local websites_json="[]"
    
    if [ -f "$PROJECT_ROOT/config/websites.conf" ]; then
        local websites_array=""
        while IFS= read -r line; do
            # 跳过注释和空行
            if [[ "$line" =~ ^#.*$ ]] || [ -z "$line" ]; then
                continue
            fi
            
            # 解析网站配置: URL|名称|间隔|超时|内容检查
            IFS='|' read -r url name interval timeout content_check <<< "$line"
            
            if [ -n "$url" ] && [ -n "$name" ]; then
                total_websites=$((total_websites + 1))
                
                # 构建JSON条目
                local website_json="{\"url\":\"$url\",\"name\":\"$name\",\"interval\":$interval,\"timeout\":$timeout,\"content_check\":$content_check}"
                
                if [ -z "$websites_array" ]; then
                    websites_array="$website_json"
                else
                    websites_array="$websites_array,$website_json"
                fi
            fi
        done < "$PROJECT_ROOT/config/websites.conf"
        
        if [ -n "$websites_array" ]; then
            websites_json="[$websites_array]"
        fi
    fi
    
    # 更新网站列表API
    cat > "$NGINX_API_DIR/websites.json" << EOF
{
    "websites": $websites_json,
    "last_update": "$timestamp",
    "total_count": $total_websites
}
EOF
    
    # 计算网站状态统计
    local websites_up=0
    local websites_down=0
    local total_response_time=0
    local response_count=0
    
    # 从日志文件分析最新状态
    if [ -f "$MAIN_LOG_FILE" ]; then
        local current_date=$(date '+%Y-%m-%d')
        local temp_stats=$(mktemp)
        
        # 获取今天的最新状态
        grep "^$current_date" "$MAIN_LOG_FILE" | tail -100 | while IFS='|' read -r timestamp level message url response_time status_code final_status; do
            if [ -n "$final_status" ]; then
                case "$final_status" in
                    UP|CONTENT_INITIAL|CONTENT_CHANGED|CONTENT_UNCHANGED)
                        echo "up|$response_time" >> "$temp_stats"
                        ;;
                    DOWN|TIMEOUT|ERROR)
                        echo "down|$response_time" >> "$temp_stats"
                        ;;
                esac
            fi
        done
        
        if [ -f "$temp_stats" ]; then
            websites_up=$(grep "^up|" "$temp_stats" | wc -l)
            websites_down=$(grep "^down|" "$temp_stats" | wc -l)
            
            # 计算平均响应时间
            local total_time=0
            local count=0
            while IFS='|' read -r status response_time; do
                if [ "$response_time" -gt 0 ]; then
                    total_time=$((total_time + response_time))
                    count=$((count + 1))
                fi
            done < "$temp_stats"
            
            if [ "$count" -gt 0 ]; then
                total_response_time=$((total_time / count))
            fi
        fi
        
        rm -f "$temp_stats"
    fi
    
    # 更新状态API
    cat > "$NGINX_API_DIR/status.json" << EOF
{
    "status": "running",
    "last_update": "$timestamp",
    "next_update": "$next_update",
    "update_interval": $NGINX_UPDATE_INTERVAL,
    "total_websites": $total_websites,
    "websites_up": $websites_up,
    "websites_down": $websites_down,
    "average_response_time": $total_response_time
}
EOF
}

# 启动定期更新服务
start_update_service() {
    local pid_file="$DATA_DIR/nginx-integration.pid"
    
    # 检查是否已经运行
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        log_warn "nginx集成服务已经在运行中 (PID: $(cat "$pid_file"))"
        return 0
    fi
    
    log_info "启动nginx集成服务 (更新间隔: ${NGINX_UPDATE_INTERVAL}秒)..."
    
    # 后台运行更新循环
    (
        while true; do
            update_reports
            sleep "$NGINX_UPDATE_INTERVAL"
        done
    ) &
    
    local service_pid=$!
    echo "$service_pid" > "$pid_file"
    
    log_info "nginx集成服务已启动 (PID: $service_pid)"
}

# 停止定期更新服务
stop_update_service() {
    local pid_file="$DATA_DIR/nginx-integration.pid"
    
    if [ ! -f "$pid_file" ]; then
        log_warn "nginx集成服务未运行"
        return 0
    fi
    
    local service_pid
    service_pid=$(cat "$pid_file")
    
    if kill -0 "$service_pid" 2>/dev/null; then
        log_info "停止nginx集成服务 (PID: $service_pid)..."
        kill "$service_pid"
        rm -f "$pid_file"
        log_info "nginx集成服务已停止"
    else
        log_warn "nginx集成服务进程不存在，清理PID文件"
        rm -f "$pid_file"
    fi
}

# 查看服务状态
show_service_status() {
    local pid_file="$DATA_DIR/nginx-integration.pid"
    
    echo "=== nginx集成服务状态 ==="
    
    if [ -f "$pid_file" ]; then
        local service_pid
        service_pid=$(cat "$pid_file")
        
        if kill -0 "$service_pid" 2>/dev/null; then
            echo "状态: 运行中"
            echo "PID: $service_pid"
            echo "更新间隔: ${NGINX_UPDATE_INTERVAL}秒"
        else
            echo "状态: 已停止 (PID文件存在但进程不存在)"
        fi
    else
        echo "状态: 已停止"
    fi
    
    echo ""
    echo "=== nginx配置状态 ==="
    if nginx -t 2>/dev/null; then
        echo "nginx配置: 正常"
    else
        echo "nginx配置: 有错误"
    fi
    
    echo ""
    echo "=== 最新报告信息 ==="
    if [ -f "$NGINX_WEB_ROOT/latest-report.html" ]; then
        local report_time
        report_time=$(stat -c %y "$NGINX_WEB_ROOT/latest-report.html" 2>/dev/null || echo "未知")
        echo "最新报告: $report_time"
    else
        echo "最新报告: 不存在"
    fi
}

# 清理旧报告文件
cleanup_old_reports() {
    log_info "清理旧报告文件..."
    
    local deleted_count=0
    
    # 清理超过7天的报告文件
    if [ -d "$NGINX_REPORTS_DIR" ]; then
        deleted_count=$(find "$NGINX_REPORTS_DIR" -name "report-*.html" -mtime +7 -delete -print | wc -l)
    fi
    
    # 清理项目报告目录中的旧文件
    if [ -d "$PROJECT_ROOT/data/reports" ]; then
        find "$PROJECT_ROOT/data/reports" -name "report-*.html" -mtime +7 -delete 2>/dev/null || true
    fi
    
    log_info "已清理 $deleted_count 个旧报告文件"
}

# 主函数
main() {
    # 验证必要命令
    validate_required_commands
    
    # 解析命令行参数
    parse_arguments "$@"
    
    # 执行相应命令
    case "$NGINX_COMMAND" in
        setup)
            setup_nginx_environment
            ;;
        start)
            start_update_service
            ;;
        stop)
            stop_update_service
            ;;
        status)
            show_service_status
            ;;
        update)
            update_reports
            ;;
        cleanup)
            cleanup_old_reports
            ;;
        *)
            die "未知命令: $NGINX_COMMAND" 2
            ;;
    esac
}

# 执行主函数
main "$@"