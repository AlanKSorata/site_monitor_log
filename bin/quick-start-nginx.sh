#!/bin/bash

# 快速启动脚本 - nginx集成版本
# 一键启动网站监控系统的nginx集成功能

set -euo pipefail

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示欢迎信息
show_welcome() {
    echo "=================================================="
    echo "    网站监控系统 - Nginx集成快速启动"
    echo "=================================================="
    echo ""
    echo "此脚本将帮助您快速启动网站监控系统的nginx集成功能"
    echo ""
}

# 检查系统状态
check_system_status() {
    log_info "检查系统状态..."
    
    local issues=()
    
    # 检查是否已安装
    if [ ! -d "/opt/website-monitoring-system" ]; then
        issues+=("系统未安装")
    fi
    
    # 检查nginx
    if ! command -v nginx >/dev/null 2>&1; then
        issues+=("nginx未安装")
    fi
    
    # 检查必要文件
    if [ ! -f "$PROJECT_ROOT/config/websites.conf" ]; then
        issues+=("网站配置文件不存在")
    fi
    
    if [ ${#issues[@]} -gt 0 ]; then
        log_error "发现以下问题："
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        echo ""
        echo "请先解决这些问题，或运行完整安装："
        echo "  sudo $PROJECT_ROOT/bin/install-nginx-integration.sh install --auto-start"
        exit 1
    fi
    
    log_success "系统状态检查通过"
}

# 检查配置文件
check_configuration() {
    log_info "检查配置文件..."
    
    local websites_count=0
    
    # 检查网站配置
    if [ -f "$PROJECT_ROOT/config/websites.conf" ]; then
        websites_count=$(grep -v '^#' "$PROJECT_ROOT/config/websites.conf" | grep -v '^$' | wc -l)
    fi
    
    if [ "$websites_count" -eq 0 ]; then
        log_warn "未配置监控网站，将使用默认配置"
        
        # 创建默认配置
        cat > "$PROJECT_ROOT/config/websites.conf" << 'EOF'
# 默认网站监控配置
# 格式: URL|名称|检查间隔(秒)|超时时间(秒)|内容检查(true/false)

https://www.baidu.com|百度|60|10|true
https://www.google.com|Google|60|10|false
https://github.com|GitHub|120|15|false
EOF
        
        log_info "已创建默认网站配置，包含 3 个网站"
    else
        log_success "发现 $websites_count 个监控网站配置"
    fi
}

# 启动监控服务
start_monitoring_service() {
    log_info "启动主监控服务..."
    
    if [ -f "$PROJECT_ROOT/bin/monitor.sh" ]; then
        if "$PROJECT_ROOT/bin/monitor.sh" status >/dev/null 2>&1; then
            log_warn "主监控服务已在运行"
        else
            "$PROJECT_ROOT/bin/monitor.sh" start
            log_success "主监控服务已启动"
        fi
    else
        log_error "监控服务脚本不存在"
        return 1
    fi
}

# 启动nginx集成服务
start_nginx_integration() {
    log_info "启动nginx集成服务..."
    
    # 检查是否已安装为系统服务
    if systemctl list-unit-files | grep -q "website-monitor-nginx.service"; then
        if systemctl is-active website-monitor-nginx >/dev/null 2>&1; then
            log_warn "nginx集成系统服务已在运行"
        else
            sudo systemctl start website-monitor-nginx
            log_success "nginx集成系统服务已启动"
        fi
    else
        # 使用脚本方式启动
        if [ -f "$PROJECT_ROOT/bin/nginx-integration.sh" ]; then
            # 检查是否已在运行
            local pid_file="$PROJECT_ROOT/data/nginx-integration.pid"
            if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                log_warn "nginx集成服务已在运行"
            else
                "$PROJECT_ROOT/bin/nginx-integration.sh" start --interval 300
                log_success "nginx集成服务已启动"
            fi
        else
            log_error "nginx集成脚本不存在"
            return 1
        fi
    fi
}

# 生成初始报告
generate_initial_reports() {
    log_info "生成初始监控报告..."
    
    # 等待一下让监控服务收集一些数据
    sleep 5
    
    # 生成标准HTML报告
    if [ -f "$PROJECT_ROOT/bin/report-generator.sh" ]; then
        "$PROJECT_ROOT/bin/report-generator.sh" \
            --format html \
            --period daily \
            --output "$PROJECT_ROOT/data/reports/latest-report.html" \
            >/dev/null 2>&1 || true
    fi
    
    # 生成增强版HTML报告
    if [ -f "$PROJECT_ROOT/bin/enhanced-report-generator.sh" ]; then
        "$PROJECT_ROOT/bin/enhanced-report-generator.sh" \
            --output "$PROJECT_ROOT/data/reports/enhanced-report.html" \
            --refresh 300 \
            >/dev/null 2>&1 || true
    fi
    
    log_success "初始报告已生成"
}

# 检查nginx配置
check_nginx_configuration() {
    log_info "检查nginx配置..."
    
    if nginx -t >/dev/null 2>&1; then
        log_success "nginx配置正常"
    else
        log_error "nginx配置有错误"
        echo "请运行以下命令查看详细错误："
        echo "  sudo nginx -t"
        return 1
    fi
    
    # 重载nginx配置
    if systemctl is-active nginx >/dev/null 2>&1; then
        sudo systemctl reload nginx
        log_success "nginx配置已重载"
    else
        sudo systemctl start nginx
        log_success "nginx服务已启动"
    fi
}

# 显示访问信息
show_access_info() {
    echo ""
    echo "=================================================="
    echo "           启动完成 - 访问信息"
    echo "=================================================="
    echo ""
    
    # 获取nginx端口
    local nginx_port="80"
    if [ -f /etc/nginx/sites-available/website-monitor ]; then
        nginx_port=$(grep -o 'listen [0-9]*' /etc/nginx/sites-available/website-monitor 2>/dev/null | awk '{print $2}' || echo "80")
    fi
    
    echo "🌐 Web界面访问地址："
    echo "   主页: http://localhost:$nginx_port/"
    echo "   最新报告: http://localhost:$nginx_port/latest"
    echo "   历史报告: http://localhost:$nginx_port/reports/"
    echo ""
    
    echo "🔌 API接口地址："
    echo "   系统状态: http://localhost:$nginx_port/api/status"
    echo "   网站列表: http://localhost:$nginx_port/api/websites"
    echo ""
    
    echo "📊 本地报告文件："
    echo "   标准报告: $PROJECT_ROOT/data/reports/latest-report.html"
    echo "   增强报告: $PROJECT_ROOT/data/reports/enhanced-report.html"
    echo ""
    
    echo "🛠️  管理命令："
    echo "   查看状态: $PROJECT_ROOT/bin/nginx-integration.sh status"
    echo "   停止服务: $PROJECT_ROOT/bin/nginx-integration.sh stop"
    echo "   手动更新: $PROJECT_ROOT/bin/nginx-integration.sh update"
    echo ""
    
    echo "📝 日志查看："
    echo "   监控日志: tail -f $PROJECT_ROOT/data/logs/monitor.log"
    echo "   nginx日志: sudo tail -f /var/log/nginx/access.log"
    echo ""
    
    echo "=================================================="
    echo "系统已成功启动，开始监控您的网站！"
    echo "=================================================="
}

# 显示使用提示
show_usage_tips() {
    echo ""
    echo "💡 使用提示："
    echo ""
    echo "1. 修改监控网站："
    echo "   编辑 $PROJECT_ROOT/config/websites.conf"
    echo "   格式: URL|名称|间隔|超时|内容检查"
    echo ""
    echo "2. 修改系统配置："
    echo "   编辑 $PROJECT_ROOT/config/monitor.conf"
    echo ""
    echo "3. 自定义报告样式："
    echo "   编辑 /var/www/website-monitor/assets/style.css"
    echo ""
    echo "4. 查看实时日志："
    echo "   tail -f $PROJECT_ROOT/data/logs/monitor.log"
    echo ""
    echo "5. 完全停止系统："
    echo "   $PROJECT_ROOT/bin/monitor.sh stop"
    echo "   $PROJECT_ROOT/bin/nginx-integration.sh stop"
    echo ""
}

# 主函数
main() {
    show_welcome
    
    # 检查系统状态
    check_system_status
    
    # 检查配置文件
    check_configuration
    
    # 启动监控服务
    start_monitoring_service
    
    # 检查nginx配置
    check_nginx_configuration
    
    # 启动nginx集成服务
    start_nginx_integration
    
    # 生成初始报告
    generate_initial_reports
    
    # 显示访问信息
    show_access_info
    
    # 显示使用提示
    show_usage_tips
}

# 执行主函数
main "$@"