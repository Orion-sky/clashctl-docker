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
