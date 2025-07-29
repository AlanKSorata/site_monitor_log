# 网站监控系统

一个基于 Shell 脚本构建的综合性轻量级网站监控解决方案，无需复杂依赖即可提供良好的监控能力。

## 🚀 功能特性

- **多网站监控**：同时监控多个网站，支持可配置的检查间隔
- **实时可用性跟踪**：持续监控并即时更新状态
- **内容变化检测**：基于 SHA256 的内容监控，检测网站变化
- **响应时间分析**：详细的性能指标和慢响应警报
- **综合报告**：支持多种格式的报告生成（HTML、CSV、文本）
- **交互式日志查看器**：实时日志分析，支持过滤和搜索
- **错误恢复**：高级错误处理，包含熔断器模式和指数退避
- **守护进程管理**：完整的生命周期管理，支持启动/停止/重启
- **并发处理**：高效的多网站监控，支持可配置的并发数
- **健康监控**：自动守护进程健康检查和恢复

## 📋 系统要求

### 系统环境

- Unix/Linux 环境（已在 Ubuntu 上测试）
- Bash 4.0 或更高版本
- 标准 POSIX 工具

### 依赖项

```bash
curl grep awk sed sort uniq wc date sha256sum mktemp
```

大多数依赖项在标准 Unix/Linux 系统上都已预装。

## 🛠️ 安装

### 快速安装

1. **下载并解压系统**：

   ```bash
   git clone <repository-url>
   cd website-monitoring-system
   ```

2. **初始化系统**：

   ```bash
   ./bin/system-init.sh init
   ```

3. **配置要监控的网站**：

   ```bash
   nano config/websites.conf
   ```

   按以下格式添加您的网站：

   ```
   https://example.com|示例网站|60|10|false
   https://api.service.com|API 服务|30|15|true
   ```

4. **启动监控**：
   ```bash
   ./bin/system-init.sh start
   ```

### 手动安装

1. **设置目录**：

   ```bash
   ./bin/system-init.sh setup
   ```

2. **验证配置**：

   ```bash
   ./bin/system-init.sh validate
   ```

3. **启动系统**：
   ```bash
   ./bin/system-init.sh start
   ```

## 📖 使用方法

### 基本命令

```bash
# 系统管理
./bin/system-init.sh init      # 初始化完整系统
./bin/system-init.sh start     # 启动监控
./bin/system-init.sh stop      # 停止监控
./bin/system-init.sh restart   # 重启监控
./bin/system-init.sh status    # 显示系统状态

# 独立组件
./bin/check-website.sh https://example.com    # 检查单个网站
./bin/report-generator.sh --format html       # 生成 HTML 报告
./bin/log-viewer.sh                          # 交互式日志查看器
./bin/monitor.sh status                      # 守护进程状态
```

### 配置

#### 监控配置 (`config/monitor.conf`)

```bash
# 监控间隔（秒）
MONITOR_INTERVAL=60
MONITOR_TIMEOUT=30
SLOW_RESPONSE_THRESHOLD=5000

# 并发监控
MAX_CONCURRENT_CHECKS=5
CONCURRENT_TIMEOUT=45

# 内容监控
CONTENT_CHECK_ENABLED=true
CONTENT_HASH_ALGORITHM=sha256

# 日志记录
LOG_LEVEL=INFO
LOG_RETENTION_DAYS=30

# 错误恢复
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=5
CIRCUIT_BREAKER_THRESHOLD=5
```

#### 网站配置 (`config/websites.conf`)

```bash
# 格式：URL|名称|间隔|超时|内容检查
https://www.example.com|主网站|60|10|true
https://api.example.com|API 端点|30|15|false
https://cdn.example.com|CDN 服务|120|20|false
```

## 📊 监控功能

### 网站检查

- HTTP/HTTPS 可用性监控
- 响应时间测量
- HTTP 状态码验证
- SSL 证书验证
- 自定义超时设置
- 指数退避重试机制

### 内容监控

- SHA256 内容哈希
- 变化检测和警报
- 内容比较历史
- 可配置的内容检查间隔

### 性能监控

- 响应时间跟踪
- 慢响应警报
- 性能趋势分析
- 统计报告

### 错误恢复

- 熔断器模式实现
- 指数退避重试策略
- 健康监控和自动恢复
- 故障时的优雅降级

## 📈 报告功能

### 报告格式

- **HTML**：包含图表和统计信息的丰富可视化报告
- **CSV**：用于分析和集成的数据导出
- **文本**：用于邮件/控制台的简单文本报告

### 报告类型

- **日报**：24 小时监控摘要
- **周报**：7 天趋势分析
- **月报**：长期性能概览
- **自定义周期**：用户定义的日期范围

### 生成报告

```bash
# 日报 HTML 格式
./bin/report-generator.sh --format html --period daily

# 周报 CSV 导出
./bin/report-generator.sh --format csv --period weekly --output weekly-data.csv

# 自定义周期报告
./bin/report-generator.sh --format html --period custom \
  --start-date 2025-01-01 --end-date 2025-01-31
```

## 🔍 日志查看器

支持多种查看模式的交互式日志分析：

```bash
# 实时监控视图
./bin/log-viewer.sh

# 统计分析
./bin/log-viewer.sh --stats

# 按网站过滤
./bin/log-viewer.sh --website https://example.com

# 搜索特定事件
./bin/log-viewer.sh --search "timeout"

# 自动刷新模式
./bin/log-viewer.sh --auto-refresh --refresh 10
```

## 🏗️ 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                      网站监控系统                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   系统      │  │   监控      │  │   网站      │         │
│  │   初始化    │  │   守护进程  │  │   检查器    │         │
│  │ system-init │  │ monitor.sh  │  │check-website│         │
│  │    .sh      │  │             │  │    .sh      │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                 │                 │              │
│         └─────────────────┼─────────────────┘              │
│                           │                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   报告      │  │   日志      │  │   共享      │         │
│  │   生成器    │  │   查看器    │  │   库文件    │         │
│  │report-gen.sh│  │log-viewer.sh│  │   lib/      │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
├─────────────────────────────────────────────────────────────┤
│                      数据存储层                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │    日志     │  │   内容      │  │    报告     │         │
│  │ data/logs/  │  │data/content-│  │data/reports/│         │
│  │             │  │   hashes/   │  │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

## 📁 目录结构

```
website-monitoring-system/
├── bin/                    # 可执行脚本
│   ├── system-init.sh      # 系统初始化和管理
│   ├── monitor.sh          # 主监控守护进程
│   ├── check-website.sh    # 单个网站检查器
│   ├── report-generator.sh # 报告生成工具
│   └── log-viewer.sh       # 交互式日志查看器
├── config/                 # 配置文件
│   ├── monitor.conf        # 系统配置
│   └── websites.conf       # 网站配置
├── data/                   # 数据存储
│   ├── logs/              # 监控日志
│   ├── content-hashes/    # 内容比较数据
│   ├── reports/           # 生成的报告
│   ├── temp/              # 临时文件
│   └── error-recovery/    # 错误恢复数据
├── lib/                   # 共享库
│   ├── common.sh          # 通用工具
│   ├── config-utils.sh    # 配置管理
│   ├── http-utils.sh      # HTTP 工具
│   ├── log-utils.sh       # 日志工具
│   ├── advanced-monitoring.sh # 高级监控功能
│   └── error-recovery.sh  # 错误恢复机制
├── test/                  # 测试框架
│   ├── run-tests.sh       # 测试运行器
│   ├── test-framework.sh  # 测试框架
│   └── test-*.sh          # 各个测试套件
└── docs/                  # 文档
    ├── SYSTEM_INTEGRATION.md
    └── USAGE_EXAMPLES.md
```

## 🧪 测试

### 运行测试

```bash
# 运行所有测试
./test/run-tests.sh

# 运行特定测试类别
./test/run-tests.sh unit
./test/run-tests.sh integration
./test/run-tests.sh end-to-end

# 详细输出并生成报告
./test/run-tests.sh -v -r all
```

### 测试类别

- **单元测试**：独立组件测试
- **集成测试**：组件交互测试
- **端到端测试**：完整工作流测试
- **性能测试**：负载和性能测试
- **验证测试**：配置和设置验证

## 🔧 高级配置

### 环境变量

```bash
export CONFIG_DIR="/custom/config/path"
export DATA_DIR="/custom/data/path"
export LOG_LEVEL="DEBUG"
```

### 自定义监控间隔

```bash
# 关键服务的高频监控
https://critical-api.com/health|关键 API|15|5|false

# 常规服务的标准监控
https://website.com|网站|60|10|true

# 后台服务的低频监控
https://backup.service.com|备份服务|300|30|false
```

### 多环境设置

```bash
# 生产环境
CONFIG_DIR="environments/production/config" \
DATA_DIR="environments/production/data" \
./bin/system-init.sh start

# 测试环境
CONFIG_DIR="environments/staging/config" \
DATA_DIR="environments/staging/data" \
./bin/system-init.sh start
```

## 🚨 故障排除

### 常见问题

1. **守护进程无法启动**：

   ```bash
   # 检查配置
   ./bin/system-init.sh validate

   # 查看日志
   tail -f data/logs/monitoring.log
   ```

2. **内存使用过高**：

   ```bash
   # 减少并发检查数
   echo "MAX_CONCURRENT_CHECKS=3" >> config/monitor.conf
   ```

3. **网络连接问题**：
   ```bash
   # 测试单个网站
   ./bin/check-website.sh --verbose https://example.com
   ```

### 调试模式

```bash
# 启用调试日志
echo "LOG_LEVEL=DEBUG" >> config/monitor.conf
./bin/system-init.sh restart
```

### 日志分析

```bash
# 查看最近的错误
tail -100 data/logs/monitoring.log | grep ERROR

# 监控守护进程健康状态
./bin/monitor.sh status

# 查看系统状态
./bin/system-init.sh status
```

## 🔒 安全性

### 文件权限

```bash
# 设置安全权限
chmod 750 bin/*.sh
chmod 640 config/*.conf
chmod 700 data/
```

### 网络安全

- 使用标准 HTTP/HTTPS 协议
- 无需入站网络连接
- 可配置的用户代理字符串
- SSL 证书验证

## 🤝 贡献

1. Fork 仓库
2. 创建功能分支
3. 进行更改
4. 为新功能添加测试
5. 运行测试套件
6. 提交 Pull Request

### 开发环境设置

```bash
# 克隆仓库
git clone <repository-url>
cd website-monitoring-system

# 初始化开发环境
./bin/system-init.sh init

# 运行测试
./test/run-tests.sh
```

## 📄 许可证

本项目采用 MIT 许可证 - 详情请参阅 LICENSE 文件。

## 🆘 支持

- **文档**：详细指南请参阅 `docs/` 目录
- **问题**：通过 GitHub Issues 报告错误和功能请求
- **示例**：实用示例请查看 `docs/USAGE_EXAMPLES.md`

## 🗺️ 路线图

- [ ] Web 仪表板界面
- [ ] 邮件/短信通知
- [ ] 数据库集成
- [ ] Docker 容器化
- [ ] Kubernetes 部署支持
- [ ] REST API 接口
- [ ] Grafana 集成
- [ ] 自定义警报规则

## 📊 性能

- **内存使用**：约 10-50MB，取决于并发检查数
- **CPU 使用**：最小化，事件驱动架构
- **磁盘使用**：可配置的日志保留和轮转
- **网络**：高效的 HTTP 请求，支持连接复用
- **可扩展性**：通过适当配置支持数百个网站
- **响应时间**：毫秒级检测和报告

## 🏆 致谢

- 使用标准 Unix/Linux 工具构建，确保最大兼容性
- 受企业监控解决方案启发
- 专为系统管理员和 DevOps 团队设计
- 社区驱动的开发和测试

---

**网站监控系统** - 为每个人提供可靠、轻量级和全面的网站监控解决方案。
