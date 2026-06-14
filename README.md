# realm 🛡️

realm TCP 零拷贝转发管理脚本。轻量、直观、全键盘操作，自动检测系统架构。

## 功能

| 菜单 | 功能 |
|------|------|
| `[1]` | 安装 realm（自动检测 CPU 架构，下载对应二进制） |
| `[2]` | 卸载 realm（可选项：保留/删除配置） |
| `[3]` | 查看/修改/删除转发规则 |
| `[4]` | 新增转发规则（默认双栈 `[::]:端口`） |
| `[5]` | 启动服务 |
| `[6]` | 重启服务 |
| `[7]` | 停止服务 |
| `[8]` | 服务状态 |
| `[9]` | 实时日志 |

## 一键运行

```bash
bash <(curl -sL https://raw.githubusercontent.com/yangyucitrus/realm-admin/main/realm.sh)
```

国内加速：
```bash
bash <(curl -sL https://ghproxy.net/https://raw.githubusercontent.com/yangyucitrus/realm-admin/main/realm.sh)
```

## 支持架构

| 架构 | 支持 |
|------|------|
| x86_64 | ✅ |
| ARM64 (aarch64) | ✅ |
| ARMv7 | ✅ |
| i686 | ✅ |

未安装时运行脚本，选择 `[1] 安装 realm` 可自动完成下载、部署、systemd 配置。
