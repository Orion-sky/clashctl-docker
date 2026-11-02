#!/usr/bin/env bash
# 容器入口：加载订阅 -> 启动内核 -> 开启 TUN -> 保持前台
set -u
export CLASHCTL_HOME=${CLASHCTL_HOME:-/opt/clashctl}
# shellcheck disable=SC1091
. "$CLASHCTL_HOME/scripts/cmd/clashctl.sh"

# 订阅：SUB_URL 为链接；或挂载本地配置到 /config/config.yaml
if [ -n "${SUB_URL:-}" ]; then
    clashctl sub add --use "$SUB_URL" || echo "[entrypoint] 订阅添加失败（可能已存在）"
elif [ -f /config/config.yaml ]; then
    clashctl sub add --use "file:///config/config.yaml" || echo "[entrypoint] 本地配置添加失败（可能已存在）"
fi

# 内核不支持 IPv6 策略路由（如 Jetson L4T 缺 CONFIG_IPV6_MULTIPLE_TABLES）时，
# strict-route 会添加 IPv6 规则而失败（add rule 0/8: address family not supported），自动关闭
MIXIN="$CLASHCTL_HOME/data/mixin.yaml"
if [ -f "$MIXIN" ] && ! ip -6 rule >/dev/null 2>&1; then
    echo "[entrypoint] 内核不支持 IPv6 策略路由，关闭 tun.strict-route 与 ipv6"
    sed -i 's/^\(\s*\)strict-route:\s*true/\1strict-route: false/' "$MIXIN"
    grep -q '^ipv6:' "$MIXIN" || sed -i '1i ipv6: false' "$MIXIN"
fi

clashctl start || { echo "[entrypoint] 内核启动失败"; exit 1; }

if [ "${ENABLE_TUN:-true}" = true ]; then
    clashctl tun on || echo "[entrypoint] TUN 开启失败，请检查 cap_add/NET_ADMIN 与 /dev/net/tun"
fi
clashctl tun || true

# 前台跟随日志；内核退出则容器退出
LOG=$(ls "$CLASHCTL_HOME"/data/*.log 2>/dev/null | head -1)
[ -n "$LOG" ] && tail -F "$LOG" &
while pgrep -x mihomo >/dev/null; do sleep 5; done
echo "[entrypoint] mihomo 已退出"; exit 1
