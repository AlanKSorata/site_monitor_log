#!/bin/bash

# 开发服务器启动脚本
# 启动简单的HTTP服务器来测试nginx集成功能

set -euo pipefail

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_DIR="$PROJECT_ROOT/web"

# 默认端口
DEFAULT_PORT=8080

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "启动开发HTTP服务器测试nginx集成功能"
    echo ""
    echo "OPTIONS:"
    echo "    -p, --port PORT    服务器端口 (默认: $DEFAULT_PORT)"
    echo "    -h, --help        显示此帮助信息"
    echo ""
}

parse_arguments() {
    local port="$DEFAULT_PORT"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--port)
                port="$2"
                if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
                    echo "错误: 端口必须是1024-65535之间的数字"
                    exit 2
                fi
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "错误: 未知选项 $1"
                exit 2
                ;;
        esac
    done
    
    export DEV_SERVER_PORT="$port"
}

# 检查web目录
check_web_directory() {
    if [ ! -d "$WEB_DIR" ]; then
        log_warn "Web目录不存在，正在初始化..."
        "$PROJECT_ROOT/bin/nginx-integration.sh" setup
    fi
    
    if [ ! -f "$WEB_DIR/index.html" ]; then
        log_warn "首页文件不存在，正在生成..."
        "$PROJECT_ROOT/bin/nginx-integration.sh" update 2>/dev/null || true
    fi
}

# 更新API数据
update_api_data() {
    log_info "更新API数据..."
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 更新系统状态API
    cat > "$WEB_DIR/api/status.json" << EOF
{
    "status": "running",
    "last_update": "$timestamp",
    "next_update": "$(date -d '+5 minutes' '+%Y-%m-%d %H:%M:%S')",
    "update_interval": 300,
    "total_websites": 2,
    "websites_up": 2,
    "websites_down": 0,
    "average_response_time": 150
}
EOF
    
    # 更新网站列表API
    cat > "$WEB_DIR/api/websites.json" << 'EOF'
{
    "websites": [
        {
            "url": "https://www.baidu.com",
            "name": "百度",
            "interval": 60,
            "timeout": 10,
            "content_check": true
        },
        {
            "url": "https://www.google.com",
            "name": "Google",
            "interval": 60,
            "timeout": 10,
            "content_check": false
        }
    ],
    "last_update": "$timestamp",
    "total_count": 2
}
EOF
    
    log_success "API数据已更新"
}

# 启动HTTP服务器
start_server() {
    log_info "启动开发HTTP服务器..."
    log_info "端口: $DEV_SERVER_PORT"
    log_info "Web目录: $WEB_DIR"
    
    # 检查端口是否被占用
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$DEV_SERVER_PORT "; then
            log_warn "端口 $DEV_SERVER_PORT 已被占用"
            echo "请使用其他端口或停止占用该端口的进程"
            exit 1
        fi
    fi
    
    echo ""
    echo "=================================================="
    echo "           开发服务器启动成功"
    echo "=================================================="
    echo ""
    echo "🌐 访问地址:"
    echo "   主页: http://localhost:$DEV_SERVER_PORT/"
    echo "   最新报告: http://localhost:$DEV_SERVER_PORT/latest-report.html"
    echo "   系统状态API: http://localhost:$DEV_SERVER_PORT/api/status.json"
    echo "   网站列表API: http://localhost:$DEV_SERVER_PORT/api/websites.json"
    echo ""
    echo "📁 文件目录:"
    echo "   Web根目录: $WEB_DIR"
    echo "   报告目录: $WEB_DIR/reports/"
    echo "   API目录: $WEB_DIR/api/"
    echo ""
    echo "💡 提示:"
    echo "   - 按 Ctrl+C 停止服务器"
    echo "   - 修改文件后刷新浏览器即可看到更新"
    echo "   - 可以在另一个终端运行 ./bin/nginx-integration.sh update 更新报告"
    echo ""
    echo "=================================================="
    echo ""
    
    # 切换到web目录并启动服务器
    cd "$WEB_DIR"
    
    # 尝试使用不同的HTTP服务器
    if command -v python3 >/dev/null 2>&1; then
        log_info "使用Python3 HTTP服务器..."
        python3 -m http.server "$DEV_SERVER_PORT"
    elif command -v python >/dev/null 2>&1; then
        log_info "使用Python HTTP服务器..."
        python -m SimpleHTTPServer "$DEV_SERVER_PORT"
    elif command -v php >/dev/null 2>&1; then
        log_info "使用PHP内置服务器..."
        php -S "localhost:$DEV_SERVER_PORT"
    else
        echo "错误: 未找到可用的HTTP服务器"
        echo "请安装 python3, python 或 php"
        exit 1
    fi
}

# 主函数
main() {
    echo "=================================================="
    echo "    网站监控系统 - 开发服务器"
    echo "=================================================="
    echo ""
    
    # 解析命令行参数
    parse_arguments "$@"
    
    # 检查web目录
    check_web_directory
    
    # 更新API数据
    update_api_data
    
    # 启动服务器
    start_server
}

# 执行主函数
main "$@"