#!/bin/bash
# realm 零拷贝 TCP 转发管理脚本 🍊
# v2.0 — 全数字操作，自动架构检测

CONFIG="/etc/realm/config.toml"
SERVICE_FILE="/etc/systemd/system/realm.service"
REALM_BIN="/usr/local/bin/realm"

# ========== 颜色 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()  { echo -e " ${GREEN}✓${NC} $1"; }
warn(){ echo -e " ${YELLOW}⚠${NC} $1"; }
err() { echo -e " ${RED}✗${NC} $1"; }

# ========== 架构检测 ==========
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "x86_64-unknown-linux-gnu" ;;
        aarch64) echo "aarch64-unknown-linux-gnu" ;;
        armv7l|armv7) echo "arm-unknown-linux-gnueabihf" ;;
        i686|i386) echo "i686-unknown-linux-gnu" ;;
        *)
            err "不支持的架构: $arch"
            err "realm 官方 release 仅支持 x86_64 / aarch64 / armv7 / i686"
            return 1
            ;;
    esac
}

# ========== 检测 ==========
check_realm_bin()   { [[ -x "$REALM_BIN" ]] && return 0 || return 1; }
check_service_file(){ [[ -f "$SERVICE_FILE" ]] && return 0 || return 1; }
check_service_active(){ systemctl is-active --quiet realm 2>/dev/null && return 0 || return 1; }
check_config()      { [[ -f "$CONFIG" ]] && return 0 || return 1; }

show_status() {
    echo ""
    echo -e " ${CYAN}系统检测:${NC}"
    if check_realm_bin; then
        ok "realm 二进制:  $REALM_BIN"
    else
        err "realm 二进制:  未安装"
    fi
    if check_service_file; then
        ok "systemd 服务:  realm.service"
    else
        err "systemd 服务:  未创建"
    fi
    if check_service_active; then
        ok "运行状态:      运行中"
    else
        warn "运行状态:      未运行"
    fi
    if check_config; then
        local count
        count=$(grep -c '^\[\[endpoints\]\]' "$CONFIG" 2>/dev/null || echo 0)
        ok "已配置:        $count 条规则"
    else
        warn "已配置:        暂无规则"
    fi
    echo ""
}

# ========== 安装 ==========
install_realm() {
    echo ""
    echo -e "${CYAN}━━━ 安装 realm ━━━${NC}"

    if check_realm_bin; then
        warn "realm 已安装在 $REALM_BIN"
        read -r -p "重新安装？ [y/N]: " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
    fi

    local arch_target
    arch_target=$(detect_arch) || return 1

    local url
    url="https://github.com/zhboner/realm/releases/latest/download/realm-${arch_target}.tar.gz"
    echo -e " ${CYAN}→${NC} 下载: $url"
    tmpdir=$(mktemp -d)
    if ! curl -sL "$url" | tar xz -C "$tmpdir" 2>/dev/null; then
        err "下载失败，请检查网络"
        rm -rf "$tmpdir"
        return 1
    fi
    mv "$tmpdir/realm" "$REALM_BIN"
    chmod +x "$REALM_BIN"
    rm -rf "$tmpdir"
    ok "realm 已安装到 $REALM_BIN"

    mkdir -p /etc/realm
    if [[ ! -f "$CONFIG" ]]; then
        echo '[[endpoints]]' > "$CONFIG"
        echo '# listen = "[::]:1080"' >> "$CONFIG"
        echo '# remote = "1.2.3.4:1080"' >> "$CONFIG"
        ok "已创建默认配置 $CONFIG"
    fi

    if [[ ! -f "$SERVICE_FILE" ]]; then
        cat > "$SERVICE_FILE" <<'SERVICE'
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
        systemctl daemon-reload
        ok "已创建 systemd 服务"
    fi

    systemctl enable --now realm 2>/dev/null
    ok "realm 服务已启动并设为开机自启"
    echo ""
}

# ========== 卸载 ==========
uninstall_realm() {
    echo ""
    echo -e "${CYAN}━━━ 卸载 realm ━━━${NC}"
    echo -e " ${YELLOW}⚠  此操作将:${NC}"
    echo "   - 停止并移除 realm 服务"
    echo "   - 删除 /usr/local/bin/realm"
    echo ""
    read -r -p "确认卸载？ [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "已取消" && return

    systemctl stop realm 2>/dev/null
    systemctl disable realm 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    rm -f "$REALM_BIN"
    ok "realm 已卸载"

    read -r -p "是否同时删除配置文件和日志？ [y/N]: " del_conf
    if [[ "$del_conf" == "y" || "$del_conf" == "Y" ]]; then
        rm -rf /etc/realm
        rm -f /var/log/realm*.log 2>/dev/null
        ok "配置文件和日志已清理"
    else
        warn "配置文件保留在 /etc/realm/"
    fi
    echo ""
}

# ========== 规则管理 ==========
list_rules() {
    [[ ! -f "$CONFIG" ]] && return
    grep -n '^\[\[endpoints\]\]' "$CONFIG" | while IFS=: read -r line_no _; do
        local listen remote
        listen=$(sed -n "$((line_no+1))p" "$CONFIG" | grep -oP 'listen\s*=\s*"\K[^"]+')
        remote=$(sed -n "$((line_no+2))p" "$CONFIG" | grep -oP 'remote\s*=\s*"\K[^"]+')
        echo "$line_no|$listen|$remote"
    done
}

view_rules() {
    [[ ! -f "$CONFIG" ]] && echo -e "${YELLOW}暂无配置${NC}" && return
    local rules=()
    while IFS='|' read -r lineno listen remote; do
        rules+=("$lineno|$listen|$remote")
    done < <(list_rules)

    local count=${#rules[@]}
    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}暂无转发规则${NC}"
        return
    fi

    echo ""
    echo -e "${CYAN}现有规则:${NC}"
    for ((i=0; i<count; i++)); do
        IFS='|' read -r lineno listen remote <<< "${rules[$i]}"
        echo -e "  ${GREEN}[$((i+1))]${NC} $listen → $remote"
    done
    echo ""

    read -r -p "选择 [1-$count] / [0] 返回: " idx
    [[ -z "$idx" ]] && idx=0
    [[ "$idx" -eq 0 ]] && return
    [[ "$idx" -gt "$count" || "$idx" -lt 0 ]] && warn "规则 #$idx 不存在" && return

    IFS='|' read -r lineno listen remote <<< "${rules[$((idx-1))]}"
    echo ""
    echo -e "${CYAN}━━━ 规则 #$idx ━━━${NC}"
    echo -e "  监听: ${GREEN}$listen${NC}"
    echo -e "  目标: ${GREEN}$remote${NC}"
    echo ""
    echo -e " ${CYAN}[1]${NC} 修改"
    echo -e " ${CYAN}[2]${NC} 删除"
    echo -e " ${CYAN}[0]${NC} 返回"
    echo ""
    read -r -p "选择 [0/1/2]: " action

    case "$action" in
        1)
            read -r -p "确认修改规则 #$idx？ [y/N]: " confirm
            [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
            echo ""
            echo -e "${CYAN}━━━ 修改规则 #$idx ━━━${NC}"
            read -r -p "监听 [当前: $listen]: " new_listen
            read -r -p "目标 [当前: $remote]: " new_remote
            new_listen="${new_listen:-$listen}"
            new_remote="${new_remote:-$remote}"
            sed -i "${lineno}s/.*/[[endpoints]]/" "$CONFIG"
            sed -i "$((lineno+1))s/.*/listen = \"$new_listen\"/" "$CONFIG"
            sed -i "$((lineno+2))s/.*/remote = \"$new_remote\"/" "$CONFIG"
            ok "规则 #$idx 已更新"
            warn "重启 realm 使新规则生效"
            ;;
        2)
            read -r -p "确认删除规则 #$idx？ [y/N]: " confirm
            [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return
            sed -i "${lineno},+2d" "$CONFIG"
            # 清理可能的空行
            sed -i '/^$/d' "$CONFIG"
            # 如果文件只有注释，补个 [[endpoints]] 占位
            if ! grep -q '^\[\[endpoints\]\]' "$CONFIG" 2>/dev/null; then
                echo '[[endpoints]]' >> "$CONFIG"
            fi
            ok "规则 #$idx 已删除"
            warn "重启 realm 使更新生效"
            ;;
        *) return ;;
    esac
}

# ========== 新增规则 ==========
add_rule() {
    [[ ! -f "$CONFIG" ]] && echo '[[endpoints]]' > "$CONFIG"
    echo ""
    echo -e "${CYAN}━━━ 新增规则 ━━━${NC}"
    read -r -p "监听地址及端口 (默认 [::]:双栈): " listen
    while [[ -z "$listen" ]]; do
        read -r -p "请输端口号或完整地址: " listen
    done
    # 如果只输了数字，自动补全为双栈
    if [[ "$listen" =~ ^[0-9]+$ ]]; then
        listen="[::]:$listen"
    fi

    read -r -p "目标地址及端口: " remote
    while [[ -z "$remote" ]]; do
        read -r -p "目标必须指定: " remote
    done

    echo ""
    echo -e "  监听: ${GREEN}$listen${NC}"
    echo -e "  目标: ${GREEN}$remote${NC}"
    echo ""
    read -r -p "确认添加？ [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "已取消" && return

    # 如果文件只有空的占位 [[endpoints]]，替换掉
    local lines
    lines=$(grep -c '^\[\[endpoints\]\]' "$CONFIG" 2>/dev/null || echo 0)
    if [[ "$lines" -eq 1 ]]; then
        local content_after
        content_after=$(grep -A1 '^\[\[endpoints\]\]' "$CONFIG" | tail -1)
        if [[ -z "$content_after" || "$content_after" =~ ^# ]]; then
            sed -i "0,/^\[\[endpoints\]\]/{/^\[\[endpoints\]\]/d}" "$CONFIG"
            # 清理随后的空行
            sed -i '/^$/d' "$CONFIG"
        fi
    fi

    {
        echo "[[endpoints]]"
        echo "listen = \"$listen\""
        echo "remote = \"$remote\""
    } >> "$CONFIG"

    ok "规则已添加"
    warn "重启 realm 使新规则生效"
    echo ""
}

# ========== 服务管理 ==========
do_start()   { systemctl start realm 2>/dev/null && ok "realm 已启动" || err "启动失败"; }
do_restart() { systemctl restart realm 2>/dev/null && ok "realm 已重启" || err "重启失败"; }
do_stop()    { systemctl stop realm 2>/dev/null && ok "realm 已停止" || err "停止失败"; }
do_status()  { echo ""; systemctl status realm --no-pager 2>/dev/null; echo ""; }
do_logs()    { journalctl -u realm -f --no-pager; }

# ========== 前置检查 ==========
require_installed() {
    if ! check_realm_bin; then
        err "realm 未安装，请先执行 [1] 安装"
        return 1
    fi
    if ! check_service_file; then
        err "systemd 服务未创建，请先执行 [1] 安装"
        return 1
    fi
    return 0
}

# ========== 主循环 ==========
while true; do
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Realm 转发管理 v2.0 🍊       ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════╝${NC}"
    echo ""

    show_status

    echo -e " ${CYAN}安装管理:${NC}"
    echo -e "   ${GREEN}[1]${NC} 安装 realm"
    echo -e "   ${GREEN}[2]${NC} 卸载 realm"
    echo ""
    echo -e " ${CYAN}规则管理:${NC}"
    echo -e "   ${GREEN}[3]${NC} 查看/修改/删除规则"
    echo -e "   ${GREEN}[4]${NC} 新增规则"
    echo ""
    echo -e " ${CYAN}服务管理:${NC}"
    echo -e "   ${GREEN}[5]${NC} 启动服务"
    echo -e "   ${GREEN}[6]${NC} 重启服务"
    echo -e "   ${GREEN}[7]${NC} 停止服务"
    echo -e "   ${GREEN}[8]${NC} 服务状态"
    echo -e "   ${GREEN}[9]${NC} 实时日志"
    echo ""
    echo -e "   ${GREEN}[q]${NC} 退出"
    echo ""

    read -r -p "选择 > " choice

    case "$choice" in
        1) install_realm ;;
        2) uninstall_realm ;;
        3) require_installed && view_rules ;;
        4) require_installed && add_rule ;;
        5) require_installed && do_start ;;
        6) require_installed && do_restart ;;
        7) require_installed && do_stop ;;
        8) require_installed && do_status ;;
        9) require_installed && do_logs ;;
        q|Q) echo -e "${CYAN}bye~ 💕${NC}" && exit 0 ;;
        *) warn "无效选择，按 1-9 或 q" && sleep 1 ;;
    esac
    read -r -p "按回车继续..."
done
