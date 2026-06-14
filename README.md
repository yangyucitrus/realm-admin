# realm-admin 🛡️

realm 零拷贝 TCP 转发管理交互脚本。轻量、直观、全键盘操作。

## 功能

- **[1]** 查看/修改/删除转发规则
- **[2]** 新增转发规则（默认双栈 `[::]:端口`）
- **[3]** 启动服务
- **[4]** 重启服务（改完规则自动提醒重启）
- **[5]** 停止服务
- **[6]** 查看服务状态
- **[7]** 实时日志

## 依赖

- Linux 系统（Ubuntu / Debian / CentOS）
- systemd
- [realm](https://github.com/zhboner/realm)（v2.9+ 推荐，splice 零拷贝默认开启）

## 安装

```bash
# 1. 安装 realm
curl -sL https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu.tar.gz | tar xz
sudo mv realm /usr/local/bin/
sudo mkdir -p /etc/realm

# 2. 下载脚本
sudo curl -o /usr/local/bin/realm-admin.sh \
  https://raw.githubusercontent.com/yangyucitrus/realm-admin/main/realm-admin.sh
sudo chmod +x /usr/local/bin/realm-admin.sh

# 3. 创建 systemd 服务
sudo tee /etc/systemd/system/realm.service > /dev/null <<'SERVICE'
[Unit]
Description=realm proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/realm -c /etc/realm/config.toml
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SERVICE
sudo systemctl daemon-reload
```

## 使用

```bash
sudo bash /usr/local/bin/realm-admin.sh
```

## 脚本一览

```
监听类型:                     [::]:端口（双栈）
配置路径:                     /etc/realm/config.toml
服务管理:                     systemctl
数据处理:                     内核 splice 零拷贝
```

## 配置示例

```toml
[network]

[[endpoints]]
listen = "[::]:443"
remote = "1.2.3.4:8443"

[[endpoints]]
listen = "[::]:10086"
remote = "143.14.86.51:10086"
```

## 许可

MIT
