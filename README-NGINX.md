# 网站监控系统 - Nginx 集成

基于现有的网站监控系统，集成 nginx 服务器实现 Web 界面展示和 API 接口访问，提供专业的监控数据可视化和管理功能。

## 🚀 核心功能

### Web 界面展示

- **实时监控面板**: HTML 界面，显示所有网站的实时状态
- **自动刷新**: 可配置的自动刷新间隔，实时更新监控数据
- **响应式设计**: 支持桌面和移动设备访问
- **状态可视化**: 直观的颜色编码和图表展示

### API 接口

- **RESTful API**: 提供 JSON 格式的监控数据接口
- **系统状态**: 获取整体监控系统运行状态
- **网站列表**: 获取所有监控网站的配置信息
- **实时数据**: 提供最新的监控结果和统计数据

### 定期更新

- **自动报告生成**: 根据配置定期生成最新的监控报告
- **历史数据保存**: 自动保存历史报告，支持数据回溯
- **智能清理**: 自动清理过期的历史数据

### 系统集成

- **Systemd 服务**: 作为系统服务运行，支持开机自启
- **Nginx 集成**: 完整的 nginx 配置，支持反向代理和负载均衡
- **日志管理**: 集成系统日志，便于问题诊断

## 📁 新增文件结构

```
├── bin/
│   ├── nginx-integration.sh          # nginx集成管理脚本
│   ├── enhanced-report-generator.sh  # 增强版报告生成器
│   ├── install-nginx-integration.sh  # 自动安装脚本
│   └── quick-start-nginx.sh          # 快速启动脚本
├── config/
│   ├── nginx.conf                    # nginx配置文件
│   ├── website-monitor-nginx.service # systemd服务配置
│   └── monitor.conf                  # 更新的监控配置
├── docs/
│   └── nginx-integration.md          # 详细使用文档
├── examples/
│   └── nginx-integration-demo.sh     # 演示脚本
└── README-nginx-integration.md       # 本文档
```

## 🛠️ 快速开始

### 方法一：一键安装（推荐）

```bash
# 自动安装nginx集成功能
sudo ./bin/install-nginx-integration.sh install --auto-start

# 查看安装状态
sudo ./bin/install-nginx-integration.sh status
```

### 方法二：快速启动

如果系统已经配置好，可以使用快速启动脚本：

```bash
# 一键启动所有服务
./bin/quick-start-nginx.sh
```

## 🌐 访问界面

安装完成后，可以通过以下地址访问：

- **主页**: `http://localhost/` - 显示最新监控报告
- **最新报告**: `http://localhost/latest` - 最新报告页面
- **历史报告**: `http://localhost/reports/` - 历史报告列表
- **系统状态 API**: `http://localhost/api/status` - JSON 格式系统状态
- **网站列表 API**: `http://localhost/api/websites` - JSON 格式网站列表

## ⚙️ 配置说明

### 主配置文件更新

`config/monitor.conf` 新增了 nginx 集成相关配置：

```properties
# Nginx集成配置
NGINX_INTEGRATION_ENABLED=true          # 启用nginx集成
NGINX_WEB_ROOT=/var/www/website-monitor # Web根目录
NGINX_REPORT_INTERVAL=300               # 报告更新间隔（秒）
ENHANCED_REPORTS_ENABLED=true           # 启用增强版报告
HTML_AUTO_REFRESH=300                   # HTML自动刷新间隔
API_ENABLED=true                        # 启用API接口
MAX_HISTORICAL_REPORTS=50               # 最大历史报告数量
```

### 网站配置

`config/websites.conf` 格式保持不变：

```
# 格式: URL|名称|检查间隔(秒)|超时时间(秒)|内容检查(true/false)
https://www.baidu.com|百度|60|10|true
https://www.google.com|Google|60|10|false
```

## 🔧 管理命令

### nginx 集成服务管理

```bash
# 启动nginx集成服务
./bin/nginx-integration.sh start --interval 300

# 停止nginx集成服务
./bin/nginx-integration.sh stop

# 查看服务状态
./bin/nginx-integration.sh status

# 手动更新报告
./bin/nginx-integration.sh update

# 清理旧报告
./bin/nginx-integration.sh cleanup
```

### 系统服务管理

```bash
# 启动系统服务
sudo systemctl start website-monitor-nginx

# 停止系统服务
sudo systemctl stop website-monitor-nginx

# 查看服务状态
sudo systemctl status website-monitor-nginx

# 查看服务日志
sudo journalctl -u website-monitor-nginx -f
```

### 报告生成

```bash
# 生成标准HTML报告
./bin/report-generator.sh --format html --output report.html

# 生成增强版HTML报告
./bin/enhanced-report-generator.sh --output enhanced.html --refresh 300
```

## 📊 报告类型对比

| 特性       | 标准报告 | 增强版报告       |
| ---------- | -------- | ---------------- |
| 界面设计   | 简单表格 | 现代化卡片式设计 |
| 响应式布局 | 基础支持 | 完全响应式       |
| 自动刷新   | 不支持   | 支持可配置刷新   |
| 状态可视化 | 文字显示 | 颜色编码+图标    |
| 数据展示   | 表格形式 | 卡片+统计面板    |
| 移动端适配 | 一般     | 优秀             |

## 🔌 API 接口详情

### 系统状态接口

**GET** `/api/status`

```json
{
  "status": "running",
  "last_update": "2025-07-29 10:30:00",
  "next_update": "2025-07-29 10:35:00",
  "update_interval": 300,
  "total_websites": 2,
  "websites_up": 2,
  "websites_down": 0,
  "average_response_time": 150
}
```

### 网站列表接口

**GET** `/api/websites`

```json
{
  "websites": [
    {
      "url": "https://www.baidu.com",
      "name": "百度",
      "interval": 60,
      "timeout": 10,
      "content_check": true
    }
  ],
  "last_update": "2025-07-29 10:30:00",
  "total_count": 1
}
```

## 🔒 安全特性

### 访问控制

nginx 配置支持 IP 白名单：

```nginx
location / {
    allow 192.168.1.0/24;
    allow 10.0.0.0/8;
    deny all;
}
```

### HTTPS 支持

可配置 SSL 证书启用 HTTPS：

```nginx
server {
    listen 443 ssl;
    ssl_certificate /path/to/certificate.crt;
    ssl_certificate_key /path/to/private.key;
}
```

## 🛠️ 故障排除

### 常见问题

1. **nginx 配置错误**

   ```bash
   sudo nginx -t  # 测试配置
   ```

2. **权限问题**

   ```bash
   sudo chown -R www-data:www-data /var/www/website-monitor
   ```

3. **服务无法启动**

   ```bash
   sudo journalctl -u website-monitor-nginx -n 50
   ```

4. **报告不更新**
   ```bash
   ./bin/nginx-integration.sh update
   ```

### 日志查看

- **nginx 集成日志**: `sudo journalctl -u website-monitor-nginx -f`
- **nginx 访问日志**: `sudo tail -f /var/log/nginx/access.log`
- **监控系统日志**: `tail -f data/logs/monitor.log`

## 🔄 维护操作

### 定期维护

```bash
# 清理旧报告
./bin/nginx-integration.sh cleanup

# 更新系统
sudo ./bin/install-nginx-integration.sh update

# 重启服务
sudo systemctl restart website-monitor-nginx
```

### 备份和恢复

```bash
# 备份
sudo tar -czf backup-$(date +%Y%m%d).tar.gz \
    /opt/website-monitoring-system/config \
    /opt/website-monitoring-system/data \
    /var/www/website-monitor

# 恢复
sudo tar -xzf backup-20250729.tar.gz -C /
```
