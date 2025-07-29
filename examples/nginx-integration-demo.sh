#!/bin/bash

# Nginx集成演示脚本
# 展示如何使用网站监控系统的nginx集成功能

set -euo pipefail

echo "=================================================="
echo "    网站监控系统 - Nginx集成演示"
echo "=================================================="
echo ""

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "1. 检查系统要求..."
echo "   - 检查nginx是否安装"
if command -v nginx >/dev/null 2>&1; then
    echo "     ✓ nginx已安装: $(nginx -v 2>&1)"
else
    echo "     ✗ nginx未安装，请先安装nginx"
    exit 1
fi

echo "   - 检查必要命令"
for cmd in curl systemctl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "     ✓ $cmd 可用"
    else
        echo "     ✗ $cmd 不可用"
        exit 1
    fi
done

echo ""
echo "2. 配置演示网站..."

# 创建演示配置
cat > "$PROJECT_ROOT/config/websites.conf" << 'EOF'
# 演示网站配置
https://www.baidu.com|百度搜索|60|10|true
https://www.google.com|Google搜索|60|10|false
https://github.com|GitHub|120|15|false
https://stackoverflow.com|Stack Overflow|180|20|false
EOF

echo "   ✓ 已配置4个演示网站"

echo ""
echo "3. 生成演示报告..."

# 生成标准HTML报告
if [ -f "$PROJECT_ROOT/bin/report-generator.sh" ]; then
    "$PROJECT_ROOT/bin/report-generator.sh" \
        --format html \
        --period daily \
        --output "$PROJECT_ROOT/demo-report.html" \
        --verbose
    echo "   ✓ 标准HTML报告: $PROJECT_ROOT/demo-report.html"
fi

# 生成增强版HTML报告
if [ -f "$PROJECT_ROOT/bin/enhanced-report-generator.sh" ]; then
    "$PROJECT_ROOT/bin/enhanced-report-generator.sh" \
        --output "$PROJECT_ROOT/demo-enhanced-report.html" \
        --refresh 60 \
        --title "演示监控报告" \
        --verbose
    echo "   ✓ 增强版HTML报告: $PROJECT_ROOT/demo-enhanced-report.html"
fi

echo ""
echo "4. 测试nginx集成功能..."

# 测试nginx集成脚本
if [ -f "$PROJECT_ROOT/bin/nginx-integration.sh" ]; then
    echo "   - 测试nginx集成脚本帮助信息"
    "$PROJECT_ROOT/bin/nginx-integration.sh" --help | head -5
    echo "   ✓ nginx集成脚本正常"
fi

echo ""
echo "5. 演示API数据格式..."

# 创建演示API数据
mkdir -p "$PROJECT_ROOT/demo-api"

# 系统状态API演示
cat > "$PROJECT_ROOT/demo-api/status.json" << 'EOF'
{
    "status": "running",
    "last_update": "2025-07-29 10:30:00",
    "next_update": "2025-07-29 10:35:00",
    "update_interval": 300,
    "total_websites": 4,
    "websites_up": 3,
    "websites_down": 1,
    "average_response_time": 245
}
EOF

# 网站列表API演示
cat > "$PROJECT_ROOT/demo-api/websites.json" << 'EOF'
{
    "websites": [
        {
            "url": "https://www.baidu.com",
            "name": "百度搜索",
            "interval": 60,
            "timeout": 10,
            "content_check": true
        },
        {
            "url": "https://www.google.com",
            "name": "Google搜索",
            "interval": 60,
            "timeout": 10,
            "content_check": false
        },
        {
            "url": "https://github.com",
            "name": "GitHub",
            "interval": 120,
            "timeout": 15,
            "content_check": false
        },
        {
            "url": "https://stackoverflow.com",
            "name": "Stack Overflow",
            "interval": 180,
            "timeout": 20,
            "content_check": false
        }
    ],
    "last_update": "2025-07-29 10:30:00",
    "total_count": 4
}
EOF

echo "   ✓ API演示数据: $PROJECT_ROOT/demo-api/"

echo ""
echo "6. 创建nginx配置演示..."

# 创建演示nginx配置
cat > "$PROJECT_ROOT/demo-nginx.conf" << 'EOF'
# 演示nginx配置 - 网站监控系统
server {
    listen 8080;
    server_name localhost;
    
    root /var/www/website-monitor;
    index index.html latest-report.html;
    
    # 主页
    location / {
        try_files $uri $uri/ /latest-report.html;
        add_header Cache-Control "no-cache, must-revalidate";
    }
    
    # API接口
    location /api/ {
        add_header Content-Type application/json;
        add_header Cache-Control "no-cache";
    }
    
    # 静态资源
    location /assets/ {
        expires 1h;
    }
}
EOF

echo "   ✓ 演示nginx配置: $PROJECT_ROOT/demo-nginx.conf"

echo ""
echo "=================================================="
echo "                演示完成"
echo "=================================================="
echo ""
echo "生成的演示文件："
echo "  - 网站配置: $PROJECT_ROOT/config/websites.conf"
echo "  - 标准报告: $PROJECT_ROOT/demo-report.html"
echo "  - 增强报告: $PROJECT_ROOT/demo-enhanced-report.html"
echo "  - API数据: $PROJECT_ROOT/demo-api/"
echo "  - nginx配置: $PROJECT_ROOT/demo-nginx.conf"
echo ""
echo "下一步操作："
echo "  1. 查看生成的HTML报告文件"
echo "  2. 运行完整安装: sudo $PROJECT_ROOT/bin/install-nginx-integration.sh install"
echo "  3. 或使用快速启动: $PROJECT_ROOT/bin/quick-start-nginx.sh"
echo ""
echo "如需清理演示文件："
echo "  rm -f $PROJECT_ROOT/demo-*.html $PROJECT_ROOT/demo-*.conf"
echo "  rm -rf $PROJECT_ROOT/demo-api"
echo ""