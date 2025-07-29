#!/bin/bash

# Nginx配置修复脚本
# 修复nginx配置问题，提供生产环境部署方案

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

show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "修复nginx配置问题"
    echo ""
    echo "COMMANDS:"
    echo "    check           检查nginx配置问题"
    echo "    fix             修复nginx配置"
    echo "    install         安装修复后的配置"
    echo "    test            测试nginx配置"
    echo ""
    echo "OPTIONS:"
    echo "    --port PORT     nginx监听端口 (默认: 8080)"
    echo "    --root DIR      Web根目录 (默认: /var/www/website-monitor)"
    echo "    -h, --help     显示此帮助信息"
    echo ""
}

parse_arguments() {
    local command=""
    local port="8080"
    local web_root="/var/www/website-monitor"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            check|fix|install|test)
                command="$1"
                shift
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --root)
                web_root="$2"
                shift 2
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
        log_error "请指定命令"
        exit 2
    fi
    
    export NGINX_COMMAND="$command"
    export NGINX_PORT="$port"
    export NGINX_WEB_ROOT="$web_root"
}

# 检查nginx配置问题
check_nginx_config() {
    log_info "检查nginx配置问题..."
    
    local issues=()
    
    # 检查nginx是否安装
    if ! command -v nginx >/dev/null 2>&1; then
        issues+=("nginx未安装")
    fi
    
    # 检查nginx配置语法
    if command -v nginx >/dev/null 2>&1; then
        if ! nginx -t >/dev/null 2>&1; then
            issues+=("nginx配置语法错误")
        fi
    fi
    
    # 检查权限
    if [ "$EUID" -ne 0 ]; then
        issues+=("需要root权限进行系统级配置")
    fi
    
    # 检查端口占用
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$NGINX_PORT "; then
            issues+=("端口 $NGINX_PORT 已被占用")
        fi
    fi
    
    if [ ${#issues[@]} -gt 0 ]; then
        log_warn "发现以下问题："
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        return 1
    else
        log_success "nginx配置检查通过"
        return 0
    fi
}

# 创建修复后的nginx配置
create_fixed_config() {
    log_info "创建修复后的nginx配置..."
    
    cat > "$PROJECT_ROOT/config/nginx-fixed.conf" << EOF
# 修复后的nginx配置 - 网站监控系统
server {
    listen $NGINX_PORT;
    server_name localhost;
    
    # 网站监控报告根目录
    root $NGINX_WEB_ROOT;
    index index.html latest-report.html;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # 主页 - 显示最新报告
    location / {
        try_files \$uri \$uri/ /latest-report.html;
        add_header Cache-Control "no-cache, must-revalidate";
    }
    
    # 最新报告页面
    location /latest {
        try_files /latest-report.html =404;
        add_header Cache-Control "no-cache, must-revalidate";
    }
    
    # 历史报告目录
    location /reports/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }
    
    # API接口 - 获取监控状态
    location /api/status {
        try_files /api/status.json =404;
        add_header Content-Type "application/json";
        add_header Cache-Control "no-cache";
    }
    
    # API接口 - 获取网站列表
    location /api/websites {
        try_files /api/websites.json =404;
        add_header Content-Type "application/json";
        add_header Cache-Control "no-cache";
    }
    
    # 静态资源
    location /assets/ {
        expires 1h;
        add_header Cache-Control "public";
    }
    
    # 健康检查端点
    location /health {
        access_log off;
        return 200 "OK\\n";
        add_header Content-Type "text/plain";
    }
    
    # 禁止访问敏感文件
    location ~ /\\.(conf|log|git|svn)\$ {
        deny all;
        return 404;
    }
    
    # 禁止访问备份文件
    location ~ ~\$ {
        deny all;
        return 404;
    }
    
    # 错误页面
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    
    location = /404.html {
        root $NGINX_WEB_ROOT/error-pages;
        internal;
    }
    
    location = /50x.html {
        root $NGINX_WEB_ROOT/error-pages;
        internal;
    }
}
EOF
    
    log_success "修复后的nginx配置已创建: $PROJECT_ROOT/config/nginx-fixed.conf"
}

# 安装修复后的配置
install_fixed_config() {
    log_info "安装修复后的nginx配置..."
    
    if [ "$EUID" -ne 0 ]; then
        log_error "需要root权限安装nginx配置"
        exit 1
    fi
    
    # 备份现有配置
    if [ -f /etc/nginx/sites-available/website-monitor ]; then
        cp /etc/nginx/sites-available/website-monitor \
           /etc/nginx/sites-available/website-monitor.backup.$(date +%Y%m%d-%H%M%S)
        log_info "已备份现有配置"
    fi
    
    # 安装新配置
    cp "$PROJECT_ROOT/config/nginx-fixed.conf" /etc/nginx/sites-available/website-monitor
    
    # 启用站点
    ln -sf /etc/nginx/sites-available/website-monitor /etc/nginx/sites-enabled/
    
    # 创建web目录
    mkdir -p "$NGINX_WEB_ROOT"/{api,assets,error-pages,reports}
    
    # 设置权限
    chown -R www-data:www-data "$NGINX_WEB_ROOT" 2>/dev/null || \
    chown -R nginx:nginx "$NGINX_WEB_ROOT" 2>/dev/null || \
    chown -R $SUDO_USER:$SUDO_USER "$NGINX_WEB_ROOT"
    
    chmod -R 755 "$NGINX_WEB_ROOT"
    
    log_success "nginx配置已安装"
}

# 测试nginx配置
test_nginx_config() {
    log_info "测试nginx配置..."
    
    if ! command -v nginx >/dev/null 2>&1; then
        log_error "nginx未安装"
        exit 1
    fi
    
    # 测试配置语法
    if nginx -t; then
        log_success "nginx配置语法正确"
    else
        log_error "nginx配置语法错误"
        return 1
    fi
    
    # 重载配置
    if service nginx status >/dev/null 2>&1; then
        service nginx reload
        log_success "nginx配置已重载"
    else
        service nginx start
        log_success "nginx服务已启动"
    fi
    
    # 测试端口监听
    sleep 2
    if netstat -tuln | grep -q ":$NGINX_PORT "; then
        log_success "nginx正在监听端口 $NGINX_PORT"
    else
        log_warn "nginx可能未正确监听端口 $NGINX_PORT"
    fi
}

# 主函数
main() {
    echo "=================================================="
    echo "    Nginx配置修复工具"
    echo "=================================================="
    echo ""
    
    # 解析命令行参数
    parse_arguments "$@"
    
    case "$NGINX_COMMAND" in
        check)
            check_nginx_config
            ;;
        fix)
            create_fixed_config
            ;;
        install)
            create_fixed_config
            install_fixed_config
            ;;
        test)
            test_nginx_config
            ;;
        *)
            log_error "未知命令: $NGINX_COMMAND"
            exit 2
            ;;
    esac
    
    echo ""
    echo "=================================================="
    echo "操作完成"
    echo "=================================================="
    echo ""
    echo "💡 提示："
    echo "  - 开发环境可使用: ./bin/start-dev-server.sh"
    echo "  - 生产环境需要: sudo ./bin/fix-nginx-config.sh install"
    echo "  - 访问地址: http://localhost:$NGINX_PORT"
    echo ""
}

# 执行主函数
main "$@"