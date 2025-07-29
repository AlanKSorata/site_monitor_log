# 网站监控系统 - 最终使用指南

本指南介绍了简化后的网站监控系统，采用现代化设计风格，提供统一的 HTML 报告展示。

## 🎯 系统特色

### 现代化设计

- **统一样式**: 只保留现代化设计风格，去除其他样式模板
- **响应式布局**: 完美适配桌面和移动设备
- **深色/浅色主题**: 支持主题切换，提供更好的用户体验
- **流畅动画**: 现代化的交互动画和过渡效果
- **实时更新**: 自动刷新功能，实时展示最新监控数据

### 简化架构

- **单一报告**: 所有监控数据统一显示在 `latest-report.html`
- **现代化 UI**: 采用最新的设计趋势和视觉元素
- **API 接口**: 提供 JSON 格式的数据接口
- **开发友好**: 简单的开发服务器，无需复杂配置

## 📁 文件结构

```
website-monitoring-system/
├── bin/
│   ├── report-generator.sh          # 现代化报告生成器
│   ├── nginx-integration.sh         # nginx集成管理
│   ├── start-dev-server.sh          # 开发服务器
│   ├── update-all-reports.sh        # 报告更新脚本
│   └── ...                          # 其他工具脚本
├── config/
│   ├── websites.conf                # 网站配置
│   ├── monitor.conf                 # 监控配置
│   └── nginx.conf                   # nginx配置
├── web/                             # Web文件目录
│   ├── index.html                   # 主页
│   ├── latest-report.html           # 现代化监控报告
│   ├── api/                         # API数据文件
│   ├── assets/                      # 静态资源
│   └── error-pages/                 # 错误页面
└── data/                            # 数据存储目录
```

## 🚀 快速开始

### 1. 配置网站监控

编辑 `config/websites.conf` 文件：

```bash
# 格式: URL|名称|检查间隔(秒)|超时时间(秒)|内容检查(true/false)
https://www.example.com|示例网站|60|10|true
https://www.google.com|Google|120|15|false
```

### 2. 启动监控系统

```bash
# 启动主监控服务
./bin/monitor.sh start

# 生成现代化报告
./bin/report-generator.sh --output web/latest-report.html --refresh 300
```

### 3. 启动 Web 服务

```bash
# 启动开发服务器
./bin/start-dev-server.sh --port 8080

# 访问监控界面
# http://localhost:8080/
```

## 🎨 现代化报告特色

### 视觉设计

- **现代化导航栏**: 品牌标识和主题切换按钮
- **统计概览卡片**: 直观显示监控统计数据
- **网站状态卡片**: 详细的网站监控信息
- **响应式网格**: 自适应不同屏幕尺寸

### 交互功能

- **主题切换**: 深色/浅色主题一键切换
- **自动刷新**: 可配置的自动刷新间隔（无倒计时干扰）
- **悬停效果**: 流畅的卡片悬停动画
- **状态指示**: 直观的颜色编码和图标

### 技术特性

```css
/* 现代化CSS变量系统 */
:root {
  --primary-color: #6366f1;
  --success-color: #10b981;
  --warning-color: #f59e0b;
  --danger-color: #ef4444;
}

/* 响应式网格布局 */
.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 1.5rem;
}

/* 流畅的动画效果 */
.stat-card:hover {
  transform: translateY(-4px);
  box-shadow: var(--shadow-xl);
}
```

## 🔧 管理命令

### 报告生成

```bash
# 生成现代化报告
./bin/report-generator.sh --output web/latest-report.html --refresh 300 --title "网站监控仪表板"

# 更新所有报告和API数据
./bin/update-all-reports.sh --refresh 60 --verbose
```

### 服务管理

```bash
# 监控服务
./bin/monitor.sh start|stop|status|restart

# nginx集成
./bin/nginx-integration.sh setup|start|stop|status|update

# 开发服务器
./bin/start-dev-server.sh --port 8080
```

### 系统维护

```bash
# 查看日志
./bin/log-viewer.sh --website https://example.com

# 检查网站状态
./bin/check-website.sh https://example.com

# nginx配置修复
./bin/fix-nginx-config.sh check|fix|install
```

## 🌐 访问地址

### 开发环境

- **主页**: http://localhost:8080/
- **监控报告**: http://localhost:8080/latest-report.html
- **系统状态 API**: http://localhost:8080/api/status.json
- **网站列表 API**: http://localhost:8080/api/websites.json

### 生产环境

- **主页**: http://your-domain/
- **监控报告**: http://your-domain/latest-report.html
- **API 接口**: http://your-domain/api/

## 📊 API 接口

### 系统状态接口

**GET** `/api/status.json`

```json
{
  "status": "running",
  "last_update": "2025-07-29 12:30:00",
  "next_update": "2025-07-29 12:35:00",
  "update_interval": 300,
  "total_websites": 2,
  "websites_up": 2,
  "websites_down": 0,
  "average_response_time": 150
}
```

### 网站列表接口

**GET** `/api/websites.json`

```json
{
  "websites": [
    {
      "url": "https://www.example.com",
      "name": "示例网站",
      "interval": 60,
      "timeout": 10,
      "content_check": true
    }
  ],
  "last_update": "2025-07-29 12:30:00",
  "total_count": 1
}
```

## 🎯 配置选项

### 监控配置 (config/monitor.conf)

```properties
# 基础配置
DEFAULT_INTERVAL=60                  # 默认检查间隔
DEFAULT_TIMEOUT=10                   # 默认超时时间
MAX_CONCURRENT_CHECKS=10             # 最大并发检查数

# nginx集成配置
NGINX_INTEGRATION_ENABLED=true      # 启用nginx集成
NGINX_REPORT_INTERVAL=300           # 报告更新间隔
HTML_AUTO_REFRESH=300               # HTML自动刷新间隔
```

### 网站配置 (config/websites.conf)

```properties
# 网站监控配置
# 格式: URL|名称|间隔|超时|内容检查
https://www.example.com|示例网站|60|10|true
https://api.example.com|API服务|30|5|false
```

## 🔍 故障排除

### 常见问题

1. **报告不显示数据**

   ```bash
   # 检查监控服务状态
   ./bin/monitor.sh status

   # 手动生成报告
   ./bin/report-generator.sh --output web/latest-report.html --verbose
   ```

2. **开发服务器无法启动**

   ```bash
   # 检查端口占用
   netstat -tuln | grep 8080

   # 使用其他端口
   ./bin/start-dev-server.sh --port 8081
   ```

3. **nginx 配置问题**

   ```bash
   # 检查配置
   ./bin/fix-nginx-config.sh check

   # 修复配置
   sudo ./bin/fix-nginx-config.sh fix
   ```

### 日志查看

```bash
# 监控系统日志
tail -f data/logs/monitor.log

# 开发服务器日志
# 直接在终端显示

# nginx日志
sudo tail -f /var/log/nginx/access.log
```
