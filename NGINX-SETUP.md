# Nginx 集成设置指南

本指南提供了网站监控系统 nginx 集成的完整解决方案，包括开发环境和生产环境的部署方法。

## 🛠️ 开发环境部署（推荐用于测试）

### 1. 初始化环境

```bash
# 设置开发环境
./bin/nginx-integration.sh setup
```

### 2. 启动开发服务器

```bash
# 启动HTTP服务器（端口8080）
./bin/start-dev-server.sh --port 8080
```

### 3. 访问界面

- **主页**: http://localhost:8080/
- **API 状态**: http://localhost:8080/api/status.json
- **网站列表**: http://localhost:8080/api/websites.json

### 4. 更新报告

```bash
# 在另一个终端中更新报告
./bin/enhanced-report-generator.sh --output web/latest-report.html --refresh 60
```

## 🏭 生产环境部署

### 1. 检查系统要求

```bash
# 检查nginx配置问题
sudo ./bin/fix-nginx-config.sh check
```

### 2. 修复并安装 nginx 配置

```bash
# 创建修复后的配置
./bin/fix-nginx-config.sh fix

# 安装到nginx（需要root权限）
sudo ./bin/fix-nginx-config.sh install --port 8080 --root /var/www/website-monitor
```

### 3. 测试 nginx 配置

```bash
# 测试配置并启动服务
sudo ./bin/fix-nginx-config.sh test
```

### 4. 启动监控服务

```bash
# 启动主监控服务
./bin/monitor.sh start

# 启动nginx集成服务
sudo systemctl start website-monitor-nginx
```

## 🔧 管理命令

### 开发环境命令

```bash
# 启动开发服务器
./bin/start-dev-server.sh --port 8080

# 生成增强版报告
./bin/enhanced-report-generator.sh --output web/latest-report.html --refresh 60

# 更新API数据
./bin/nginx-integration.sh update
```

### 生产环境命令

````bash
# nginx配置管理
sudo ./bin/fix-nginx-config.sh check    # 检查配置
sudo ./bin/fix-nginx-config.sh fix      # 修复配置
sudo ./bin/fix-nginx-config.sh install  # 安装配置
sudo ./bin/fix-nginx-config.sh test     # 测试配置

## 🌐 访问地址

### 开发环境 (端口 8080)

- 主页: http://localhost:8080/
- 最新报告: http://localhost:8080/latest-report.html
- 系统状态 API: http://localhost:8080/api/status.json
- 网站列表 API: http://localhost:8080/api/websites.json
- 健康检查: http://localhost:8080/health

### 生产环境 (可配置端口)

- 主页: http://localhost:端口/
- API 接口: http://localhost:端口/api/
- 历史报告: http://localhost:端口/reports/

### API 接口

- JSON 格式数据
- 实时系统状态
- 网站配置信息
- 无缓存，确保数据实时性

## 🔍 故障排除

### 常见问题及解决方案

1. **nginx 配置错误**

   ```bash
   # 使用修复工具
   sudo ./bin/fix-nginx-config.sh fix
   sudo ./bin/fix-nginx-config.sh install
````

2. **权限问题**

   ```bash
   # 使用开发环境
   ./bin/start-dev-server.sh
   ```

3. **端口被占用**

   ```bash
   # 使用其他端口
   ./bin/start-dev-server.sh --port 8081
   ```

4. **报告不更新**
   ```bash
   # 手动更新报告
   ./bin/enhanced-report-generator.sh --output web/latest-report.html
   ```

### 日志查看

```bash
# 开发服务器日志
# 直接在终端显示

# nginx日志
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# 监控系统日志
tail -f data/logs/monitor.log

# 系统服务日志
sudo journalctl -u website-monitor-nginx -f
```

## 🚀 快速开始

### 最简单的方式（开发环境）

```bash
# 1. 设置环境
./bin/nginx-integration.sh setup

# 2. 启动服务器
./bin/start-dev-server.sh

# 3. 访问 http://localhost:8080/
```

### 生产环境部署

```bash
# 1. 修复nginx配置
sudo ./bin/fix-nginx-config.sh install

# 2. 启动服务
sudo systemctl start website-monitor-nginx

# 3. 访问 http://localhost:8080/
```

## 💡 使用建议

1. **开发阶段**: 使用开发服务器进行功能测试和界面调试
2. **测试阶段**: 使用 nginx 配置进行性能和稳定性测试
3. **生产阶段**: 使用完整的 systemd 服务进行部署
4. **监控阶段**: 定期检查日志和系统状态
