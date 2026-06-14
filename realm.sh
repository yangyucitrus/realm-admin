#!/bin/bash
# realm-proxy.sh — realm 转发管理交互脚本
# 用法: sudo bash realm-proxy.sh

CONFIG="/etc/realm/config.toml"
SERVICE="realm"
BIN="/usr/local/bin/realm"

# ======== 默认 ========
DEFAULT_LISTEN="[::]"

# ======== 颜色 ========
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()  { echo -e " ${GREEN}✓${NC} $1"; }
err() { echo -e " ${RED}✗${NC} $1"; }
info(){ echo -e " ${CYAN}→${NC} $1"; }
warn(){ echo -e " ${YELLOW}⚠${NC} $1"; }

# ======== 检查依赖 ========
check_deps() {
    if ! command -v systemctl &>/dev/null; then
        err "systemctl 不可用"; exit 1
    fi
    if [ ! -f "$CONFIG" ] && [ ! -f "${BIN}" ]; then
        warn "realm 未安装，请先安装 realm"
        warn "项目: https://github.com/zhboner/realm"
    fi
}

# ======== 解析规则 ========
parse_rules() {
    [ ! -f "$CONFIG" ] && { echo "0"; return; }
    awk 'BEGIN { n=0; listen=""; remote=""; ip="" }
         /^\[\[endpoints\]\]/ {
             if (listen != "") { print n, listen, remote, ip }
             n++; listen=""; remote=""; ip=""
         }
         /^listen *=/ {
             gsub(/^[^"]*"/, ""); gsub(/"[^"]*$/, ""); listen=$0
         }
         /^remote *=/ {
             gsub(/^[^"]*"/, ""); gsub(/"[^"]*$/, ""); remote=$0
         }
         /^bind_send_ip *=/ {
             gsub(/^[^"]*"/, ""); gsub(/"[^"]*$/, ""); ip=$0
         }
         END { if (listen != "") print n, listen, remote, ip }' "$CONFIG"
}

# ======== 生成配置 ========
gen_config() {
    cat <<'EOF'
[network]
# zero-copy splice 模式，v2.9+ 默认启用
# zero_copy = true

[[endpoints]]
EOF
    local first=1
    while IFS=' ' read -r idx l r i; do
        [ -z "$l" ] && continue
        [ "$first" -eq 1 ] && first=0 || echo -e "\n[[endpoints]]"
        echo "listen = \"$l\""
        echo "remote = \"$r\""
        [ -n "$i" ] && [ "$i" != "-" ] && echo "bind_send_ip = \"$i\""
    done < <(parse_rules)
}

# ======== 重写配置 ========
rewrite_config() {
    local tmp
    tmp=$(gen_config)
    if [ $? -ne 0 ]; then err "配置生成失败"; return 1; fi
    echo "$tmp" | sed '/^$/N;/^\n$/D' > "$CONFIG"
    ok "配置已写入 $CONFIG"
}

# ======== 列出规则 ========
list_rules() {
    local rules
    rules=$(parse_rules)
    local count
    count=$(echo "$rules" | wc -l)
    [ "$count" -eq 0 ] || [ -z "$(echo "$rules" | head -1 | awk '{print $1}')" ] && {
        echo " (暂无规则)"
        return 0
    }
    echo ""
    printf "  %-4s %-24s %-24s %-16s\n" "编号" "监听" "目标" "出口IP"
    printf "  %-4s %-24s %-24s %-16s\n" "----" "----" "----" "------"
    local i=0
    IFS=$'\n'
    for rule in $rules; do
        i=$((i+1))
        local idx l r ip
        idx=$(echo "$rule" | awk '{print $1}')
        l=$(echo "$rule" | awk '{print $2}')
        r=$(echo "$rule" | awk '{print $3}')
        ip=$(echo "$rule" | awk '{print $4}')
        [ -z "$ip" ] && ip="-"
        printf "  %-4s %-24s %-24s %-16s\n" "$idx" "$l" "$r" "$ip"
    done
    unset IFS
    echo ""
}

# ======== 服务状态 ========
service_status() {
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        echo -e "${GREEN}运行中${NC}"
    elif systemctl is-active "$SERVICE" 2>/dev/null | grep -q 'deactivating'; then
        echo -e "${YELLOW}正在关闭${NC}"
    else
        echo -e "${RED}未运行${NC}"
    fi
}

service_enabled_text() {
    if systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
        echo -e "${GREEN}已启用${NC}"
    else
        echo -e "${RED}未启用${NC}"
    fi
}

# ======== 重启提示 ========
restart_prompt() {
    echo ""
    info "是否重启 realm 服务使配置生效？"
    echo -n "  [y/n] (默认 y): "; read -r ans
    case "${ans,,}" in
        n|no) warn "配置已保存，记得稍后手动重启" ;;
        *) restart_service ;;
    esac
}

# ======== 服务操作 ========
start_service() {
    systemctl start "$SERVICE" 2>/dev/null
    sleep 1
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        ok "realm 已启动"
    else
        err "启动失败，检查日志: ${YELLOW}journalctl -u $SERVICE -n 20${NC}"
    fi
}

restart_service() {
    systemctl restart "$SERVICE" 2>/dev/null
    sleep 1
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        ok "realm 已重启"
    else
        err "重启失败，检查日志: ${YELLOW}journalctl -u $SERVICE -n 20${NC}"
    fi
}

stop_service() {
    systemctl stop "$SERVICE" 2>/dev/null
    ok "realm 已停止"
}

# ======== 菜单 ========

menu_add() {
    echo ""
    echo -e "${CYAN}━━━ 新增转发规则 ━━━${NC}"

    # 监听地址，默认 [::]:端口
    echo -n "监听端口 (如 10086): "
    read -r port
    echo -n "监听地址 (默认 [::] 双栈): "
    read -r listen
    [ -z "$listen" ] && listen="$DEFAULT_LISTEN"
    local listen_full="$listen:$port"

    echo -n "目标地址 (如 143.14.86.51:10086): "
    read -r remote

    echo -n "出口 IP 绑定 (可留空): "
    read -r bind_ip

    echo ""
    echo "确认添加："
    echo "  监听 → $listen_full"
    echo "  目标 → $remote"
    [ -n "$bind_ip" ] && echo "  出口 → $bind_ip"
    echo -n "  [y/n] (默认 y): "; read -r ans
    case "${ans,,}" in
        n|no) info "已取消"; return ;;
    esac

    # 追加规则
    {
        echo ""
        echo "[[endpoints]]"
        echo "listen = \"$listen_full\""
        echo "remote = \"$remote\""
        [ -n "$bind_ip" ] && echo "bind_send_ip = \"$bind_ip\""
    } >> "$CONFIG"
    ok "规则已添加"

    restart_prompt
}

menu_list() {
    echo ""
    echo -e "${CYAN}━━━ 转发规则列表 ━━━${NC}"
    local rules rules_count
    rules=$(parse_rules)
    rules_count=$(echo "$rules" | wc -l)
    if [ "$rules_count" -eq 0 ] || [ -z "$(echo "$rules" | head -1 | awk '{print $1}' 2>/dev/null)" ]; then
        warn "暂无规则"
        return
    fi
    list_rules

    echo "操作选项："
    echo "  输入编号 → 进入该规则的操作"
    echo "  直接回车 → 返回主菜单"
    echo ""
    echo -n "选择: "; read -r opt

    [ -z "$opt" ] && return

    local idx="$opt"
    if ! echo "$rules" | awk -v n="$idx" '$1==n {found=1; exit} END {exit !found}'; then
        err "规则 #$idx 不存在"
        sleep 1
        return
    fi

    # 提取当前值
    local cur_l cur_r cur_ip
    cur_l=$(echo "$rules" | awk -v n="$idx" '$1==n {print $2}')
    cur_r=$(echo "$rules" | awk -v n="$idx" '$1==n {print $3}')
    cur_ip=$(echo "$rules" | awk -v n="$idx" '$1==n {print $4}')
    [ "$cur_ip" = "-" ] && cur_ip=""

    echo ""
    echo -e "${CYAN}━━━ 规则 #${idx} ━━━${NC}"
    echo "  监听: $cur_l"
    echo "  目标: $cur_r"
    [ -n "$cur_ip" ] && echo "  出口: $cur_ip"
    echo ""
    echo "  操作："
    echo "    [1] 修改"
    echo "    [2] 删除"
    echo "    [0] 返回"
    echo ""
    echo -n "选择 [0/1/2]: "; read -r action

    case "$action" in
        1)  # 修改
            echo ""
            echo -n "确认修改规则 #${idx}？ [y/N]: "; read -r confirm
            case "${confirm,,}" in
                y|yes) ;;
                *) warn "已取消"; return ;;
            esac
            echo ""
            echo -e "${CYAN}━━━ 修改规则 #${idx} ━━━${NC}"
            echo "（留空 = 不修改）"
            echo -n "监听 [当前: $cur_l]: "; read -r new_l
            echo -n "目标 [当前: $cur_r]: "; read -r new_r
            echo -n "出口IP [当前: ${cur_ip:-(无)}]: "; read -r new_ip

            [ -z "$new_l" ] && new_l="$cur_l"
            [ -z "$new_r" ] && new_r="$cur_r"
            [ -z "$new_ip" ] && new_ip="$cur_ip"

            local first=1
            local tmp
            tmp=$(
                local first=1
                while IFS=' ' read -r idx2 l r i; do
                    [ -z "$l" ] && continue
                    [ "$first" -eq 1 ] && first=0 || echo -e "\n[[endpoints]]"
                    if [ "$idx2" = "$idx" ]; then
                        echo "listen = \"$new_l\""
                        echo "remote = \"$new_r\""
                        [ -n "$new_ip" ] && echo "bind_send_ip = \"$new_ip\""
                    else
                        echo "listen = \"$l\""
                        echo "remote = \"$r\""
                        [ -n "$i" ] && [ "$i" != "-" ] && echo "bind_send_ip = \"$i\""
                    fi
                done < <(echo "$rules")
                [ "$first" -eq 1 ] && echo ""
            )
            echo "$tmp" | sed '/^$/N;/^\n$/D' > "$CONFIG"
            ok "规则 #$idx 已更新"
            restart_prompt
            ;;
        2)  # 删除
            echo ""
            echo -n "确认删除规则 #${idx}？ [y/N]: "; read -r confirm
            case "${confirm,,}" in
                y|yes) ;;
                *) warn "已取消"; return ;;
            esac
            local tmp
            tmp=$(
                local first=1
                while IFS=' ' read -r idx2 l r i; do
                    [ -z "$l" ] && continue
                    [ "$idx2" = "$idx" ] && continue
                    [ "$first" -eq 1 ] && first=0 || echo -e "\n[[endpoints]]"
                    echo "listen = \"$l\""
                    echo "remote = \"$r\""
                    [ -n "$i" ] && [ "$i" != "-" ] && echo "bind_send_ip = \"$i\""
                done < <(echo "$rules")
                [ "$first" -eq 1 ] && echo ""
            )
            echo "$tmp" | sed '/^$/N;/^\n$/D' > "$CONFIG"
            ok "规则 #$idx 已删除"
            restart_prompt
            ;;
        0|"") return ;;
        *) return ;;
    esac
}

menu_status() {
    echo ""
    echo -e "${CYAN}━━━ 服务状态 ━━━${NC}"
    printf "  运行状态:  "; service_status
    printf "  开机自启:  "; service_enabled_text
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        local pid
        pid=$(systemctl show -p MainPID "$SERVICE" 2>/dev/null | cut -d= -f2)
        [ -n "$pid" ] && [ "$pid" -gt 1 ] && printf "  进程 PID:  %s\n" "$pid"
        local rss
        rss=$(ps -o rss= -p "$pid" 2>/dev/null)
        [ -n "$rss" ] && printf "  内存占用:  %d MB\n" $((rss/1024))
    fi
    echo ""
    info "配置文件: $CONFIG"
    info "二进制:    $BIN"
}

menu_logs() {
    echo ""
    echo -e "${CYAN}━━━ 实时日志（Ctrl+C 退出）━━━${NC}"
    sleep 1
    journalctl -u "$SERVICE" -n 30 -f --no-pager 2>/dev/null || {
        err "日志不可用，检查 service 名称"
    }
}

menu_start()    { start_service; }
menu_restart()  { restart_service; }
menu_stop()     { stop_service; }

show_header() {
    clear 2>/dev/null || true
    echo ""
    echo -e "  ${YELLOW}╔══════════════════════════════════╗${NC}"
    echo -e "  ${YELLOW}║     Realm 转发管理 v1.0 🍊      ║${NC}"
    echo -e "  ${YELLOW}╚══════════════════════════════════╝${NC}"
    echo ""
    # 规则概览
    echo -e "  ${CYAN}当前规则:${NC}"
    list_rules
    echo -e "  服务状态: $(service_status)  配置文件: $CONFIG"
    echo ""
}

show_menu() {
    echo -e "  ${YELLOW}┌─────────────────────────────────┐${NC}"
    echo -e "  ${YELLOW}│${NC}  ${GREEN}[1]${NC} 查看/修改/删除规则            ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}│${NC}  ${GREEN}[2]${NC} 新增转发规则               ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}│${NC}  ${GREEN}[3]${NC} 启动服务                    ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}│${NC}  ${GREEN}[4]${NC} 重启服务                    ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}│${NC}  ${GREEN}[5]${NC} 停止服务                    ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}│${NC}  ${GREEN}[6]${NC} 服务状态                    ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}│${NC}  ${GREEN}[7]${NC} 实时日志                    ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}│${NC}  ${GREEN}[q]${NC} 退出                       ${YELLOW}│${NC}"
    echo -e "  ${YELLOW}└─────────────────────────────────┘${NC}"
    echo ""
    echo -n "  选择 [1-7/q]: "; read -r choice
    echo ""
}

# ======== 初始化 ========
init() {
    check_deps
    if [ ! -f "$CONFIG" ]; then
        info "配置文件 $CONFIG 不存在，创建默认配置"
        mkdir -p "$(dirname "$CONFIG")"
        cat > "$CONFIG" <<'EOF'
[network]
# zero-copy splice 模式，v2.9+ 默认启用
# zero_copy = true
EOF
        ok "已创建 $CONFIG"
    fi
    # 确保统一换行
    sed -i 's/\r$//' "$CONFIG"
}

# ======== 主循环 ========
init
while true; do
    show_header
    show_menu
    case "$choice" in
        1) menu_list ;;
        2) menu_add ;;
        3) menu_start ;;
        4) menu_restart ;;
        5) menu_stop ;;
        6) menu_status ;;
        7) menu_logs ;;
        q|Q) echo -e "  ${GREEN}bye~${NC} 🍊" ; break ;;
        *) warn "无效选择，按 1-7 或 q" ; sleep 1 ;;
    esac
done
