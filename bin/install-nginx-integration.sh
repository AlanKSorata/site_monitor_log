#!/bin/bash

# nginx集成安装脚本
# 自动安装和配置网站监控系统的nginx集成功能

set -euo pipefail

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 配置变量
INSTALL_DIR="/opt/website-monitoring-system"
NGINX_WEB_ROOT="/var/www/website-monitor"
SERVICE_NAME="website-monitor-nginx"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 显示使用说明
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "网站监控系统nginx集成安装工具"
    echo ""
    echo "COMMANDS:"
    echo "    install         安装nginx集成功能"
    echo "    uninstall       卸载nginx集成功能"
    echo "    update          更新nginx集成功能"
    echo "    status          查看安装状态"
    echo ""
    echo "OPTIONS:"
    echo "    --install-dir DIR    安装目录 (默认: $INSTALL_DIR)"
    echo "    --web-root DIR       nginx网站根目录 (默认: $NGINX_WEB_ROOT)"
    echo "    --port PORT          nginx监听端口 (默认: 80)"
    echo "    --auto-start         安装后自动启动服务"
    echo "    -y, --yes           自动确认所有提示"
    echo "    -v, --verbose       启用详细输出"
    echo "    -h, --help         显示此帮助信息"
    echo ""
}

# 解析命令行参数
parse_arguments() {
    local command=""
    local install_dir="$INSTALL_DIR"
    local web_root="$NGINX_WEB_ROOT"
    local port="80"
    local auto_start=false
    local auto_yes=false
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            install|uninstall|update|status)
                command="$1"
                shift
                ;;
            --install-dir)
                install_dir="$2"
                shift 2
                ;;
            --web-root)
                web_root="$2"
                shift 2
                ;;
            --port)
                port="$2"
                if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                    log_error "端口必须是1-65535之间的数字"
                    exit 2
                fi
                shift 2
                ;;
            --auto-start)
                auto_start=true
                shift
                ;;
            -y|--yes)
                auto_yes=true
                shift
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
                log_error "未知选项: $1"
                exit 2
                ;;
        esac
    done
    
    if [ -z "$command" ]; then
        log_error "请指定命令。使用 --help 查看帮助信息"
        exit 2
    fi
    
    export INSTALL_COMMAND="$command"
    export INSTALL_DIR="$install_dir"
    export NGINX_WEB_ROOT="$web_root"
    export NGINX_PORT="$port"
    export AUTO_START="$auto_start"
    export AUTO_YES="$auto_yes"
    export VERBOSE="$verbose"
}

# 检查系统要求
check_requirements() {
    log_info "检查系统要求..."
    
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
    
    # 检查操作系统
    if ! command -v systemctl >/dev/null 2>&1; then
        log_error "此系统不支持systemd，无法安装服务"
        exit 1
    fi
    
    # 检查nginx
    if ! command -v nginx >/dev/null 2>&1; then
        log_warn "未检测到nginx，将尝试安装..."
        install_nginx
    fi
    
    # 检查必要命令
    local missing_commands=()
    for cmd in curl grep awk sed sort uniq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "缺少必要命令: ${missing_commands[*]}"
        exit 1
    fi
    
    log_success "系统要求检查通过"
}

# 安装nginx
install_nginx() {
    log_info "安装nginx..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y nginx
    elif command -v yum >/dev/null 2>&1; then
        yum install -y nginx
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y nginx
    else
        log_error "无法自动安装nginx，请手动安装后重试"
        exit 1
    fi
    
    # 启动nginx服务
    systemctl enable nginx
    systemctl start nginx
    
    log_success "nginx安装完成"
}

# 确认操作
confirm_action() {
    local message="$1"
    
    if [ "$AUTO_YES" = true ]; then
        return 0
    fi
    
    echo -n -e "${YELLOW}$message (y/N): ${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 安装系统
install_system() {
    log_info "开始安装网站监控系统nginx集成..."
    
    # 确认安装
    if ! confirm_action "确定要安装到 $INSTALL_DIR 吗？"; then
        log_info "安装已取消"
        exit 0
    fi
    
    # 创建安装目录
    log_info "创建安装目录..."
    mkdir -p "$INSTALL_DIR"
    
    # 复制项目文件
    log_info "复制项目文件..."
    cp -r "$PROJECT_ROOT"/* "$INSTALL_DIR/"
    
    # 设置文件权限
    log_info "设置文件权限..."
    chown -R root:root "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR"/bin/*.sh
    
    # 创建数据目录
    mkdir -p "$INSTALL_DIR/data"/{logs,content-hashes,reports,backups,temp,error-recovery}
    chown -R www-data:www-data "$INSTALL_DIR/data"
    
    # 安装nginx集成
    log_info "配置nginx集成..."
    "$INSTALL_DIR/bin/nginx-integration.sh" setup
    
    # 更新nginx配置中的端口
    if [ "$NGINX_PORT" != "80" ]; then
        sed -i "s/listen 80;/listen $NGINX_PORT;/" "$INSTALL_DIR/config/nginx.conf"
    fi
    
    # 安装nginx配置
    log_info "安装nginx配置..."
    cp "$INSTALL_DIR/config/nginx.conf" /etc/nginx/sites-available/website-monitor
    ln -sf /etc/nginx/sites-available/website-monitor /etc/nginx/sites-enabled/
    
    # 测试nginx配置
    if ! nginx -t; then
        log_error "nginx配置测试失败"
        exit 1
    fi
    
    # 重载nginx配置
    systemctl reload nginx
    
    # 安装系统服务
    log_info "安装系统服务..."
    
    # 更新服务文件中的路径
    sed "s|/opt/website-monitoring-system|$INSTALL_DIR|g" \
        "$INSTALL_DIR/config/website-monitor-nginx.service" > \
        "/etc/systemd/system/$SERVICE_NAME.service"
    
    # 重载systemd配置
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    # 启动服务（如果指定）
    if [ "$AUTO_START" = true ]; then
        log_info "启动服务..."
        systemctl start "$SERVICE_NAME"
        
        # 启动主监控服务
        if [ -f "$INSTALL_DIR/bin/monitor.sh" ]; then
            "$INSTALL_DIR/bin/monitor.sh" start
        fi
    fi
    
    log_success "安装完成！"
    
    # 显示访问信息
    echo ""
    echo "=== 安装信息 ==="
    echo "安装目录: $INSTALL_DIR"
    echo "Web根目录: $NGINX_WEB_ROOT"
    echo "访问地址: http://localhost:$NGINX_PORT"
    echo "服务名称: $SERVICE_NAME"
    echo ""
    echo "=== 常用命令 ==="
    echo "启动服务: systemctl start $SERVICE_NAME"
    echo "停止服务: systemctl stop $SERVICE_NAME"
    echo "查看状态: systemctl status $SERVICE_NAME"
    echo "查看日志: journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "=== 配置文件 ==="
    echo "网站配置: $INSTALL_DIR/config/websites.conf"
    echo "监控配置: $INSTALL_DIR/config/monitor.conf"
    echo "nginx配置: /etc/nginx/sites-available/website-monitor"
    echo ""
}

# 卸载系统
uninstall_system() {
    log_info "开始卸载网站监控系统nginx集成..."
    
    # 确认卸载
    if ! confirm_action "确定要卸载系统吗？这将删除所有数据！"; then
        log_info "卸载已取消"
        exit 0
    fi
    
    # 停止服务
    log_info "停止服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    # 停止主监控服务
    if [ -f "$INSTALL_DIR/bin/monitor.sh" ]; then
        "$INSTALL_DIR/bin/monitor.sh" stop 2>/dev/null || true
    fi
    
    # 删除系统服务文件
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    
    # 删除nginx配置
    log_info "删除nginx配置..."
    rm -f /etc/nginx/sites-enabled/website-monitor
    rm -f /etc/nginx/sites-available/website-monitor
    systemctl reload nginx
    
    # 删除web目录
    log_info "删除web目录..."
    rm -rf "$NGINX_WEB_ROOT"
    
    # 删除安装目录
    log_info "删除安装目录..."
    rm -rf "$INSTALL_DIR"
    
    log_success "卸载完成！"
}

# 更新系统
update_system() {
    log_info "开始更新网站监控系统nginx集成..."
    
    if [ ! -d "$INSTALL_DIR" ]; then
        log_error "系统未安装，请先运行安装命令"
        exit 1
    fi
    
    # 确认更新
    if ! confirm_action "确定要更新系统吗？"; then
        log_info "更新已取消"
        exit 0
    fi
    
    # 停止服务
    log_info "停止服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    
    # 备份配置文件
    log_info "备份配置文件..."
    local backup_dir="/tmp/website-monitor-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r "$INSTALL_DIR/config" "$backup_dir/"
    cp -r "$INSTALL_DIR/data" "$backup_dir/"
    
    # 更新文件
    log_info "更新系统文件..."
    cp -r "$PROJECT_ROOT"/bin "$INSTALL_DIR/"
    cp -r "$PROJECT_ROOT"/lib "$INSTALL_DIR/"
    
    # 恢复配置文件
    log_info "恢复配置文件..."
    cp -r "$backup_dir/config"/* "$INSTALL_DIR/config/"
    cp -r "$backup_dir/data"/* "$INSTALL_DIR/data/"
    
    # 设置权限
    chown -R root:root "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR"/bin/*.sh
    chown -R www-data:www-data "$INSTALL_DIR/data"
    
    # 重新生成报告
    log_info "重新生成报告..."
    "$INSTALL_DIR/bin/nginx-integration.sh" update
    
    # 启动服务
    log_info "启动服务..."
    systemctl start "$SERVICE_NAME"
    
    log_success "更新完成！"
    log_info "配置备份保存在: $backup_dir"
}

# 查看状态
show_status() {
    echo "=== 网站监控系统nginx集成状态 ==="
    echo ""
    
    # 检查安装状态
    if [ -d "$INSTALL_DIR" ]; then
        echo "安装状态: 已安装"
        echo "安装目录: $INSTALL_DIR"
    else
        echo "安装状态: 未安装"
        return 0
    fi
    
    # 检查服务状态
    echo ""
    echo "=== 服务状态 ==="
    if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
        echo "nginx集成服务: 运行中"
    else
        echo "nginx集成服务: 已停止"
    fi
    
    if [ -f "$INSTALL_DIR/bin/monitor.sh" ]; then
        if "$INSTALL_DIR/bin/monitor.sh" status >/dev/null 2>&1; then
            echo "主监控服务: 运行中"
        else
            echo "主监控服务: 已停止"
        fi
    fi
    
    # 检查nginx状态
    echo ""
    echo "=== nginx状态 ==="
    if systemctl is-active nginx >/dev/null 2>&1; then
        echo "nginx服务: 运行中"
    else
        echo "nginx服务: 已停止"
    fi
    
    if [ -f /etc/nginx/sites-enabled/website-monitor ]; then
        echo "nginx配置: 已启用"
    else
        echo "nginx配置: 未启用"
    fi
    
    # 检查web目录
    echo ""
    echo "=== Web目录状态 ==="
    if [ -d "$NGINX_WEB_ROOT" ]; then
        echo "Web根目录: 存在 ($NGINX_WEB_ROOT)"
        
        if [ -f "$NGINX_WEB_ROOT/latest-report.html" ]; then
            local report_time
            report_time=$(stat -c %y "$NGINX_WEB_ROOT/latest-report.html" 2>/dev/null || echo "未知")
            echo "最新报告: $report_time"
        else
            echo "最新报告: 不存在"
        fi
    else
        echo "Web根目录: 不存在"
    fi
    
    # 显示访问地址
    echo ""
    echo "=== 访问信息 ==="
    local nginx_port
    nginx_port=$(grep -o 'listen [0-9]*' /etc/nginx/sites-available/website-monitor 2>/dev/null | awk '{print $2}' || echo "80")
    echo "访问地址: http://localhost:$nginx_port"
    echo "API状态: http://localhost:$nginx_port/api/status"
    echo "网站列表: http://localhost:$nginx_port/api/websites"
}

# 主函数
main() {
    # 解析命令行参数
    parse_arguments "$@"
    
    # 执行相应命令
    case "$INSTALL_COMMAND" in
        install)
            check_requirements
            install_system
            ;;
        uninstall)
            uninstall_system
            ;;
        update)
            update_system
            ;;
        status)
            show_status
            ;;
        *)
            log_error "未知命令: $INSTALL_COMMAND"
            exit 2
            ;;
    esac
}

# 执行主函数
main "$@"