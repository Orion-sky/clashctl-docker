# clashctl-docker

用 Docker 运行 [nelvko/clashctl](https://github.com/nelvko/clashctl)（mihomo），默认 host 网络 + TUN。

```bash
cp config/config.example.yaml config/config.yaml   # 填入自己的节点；或在 compose 里设 SUB_URL
docker compose up -d
docker exec -it clashctl bash                       # 里面直接用 clashctl 命令
```

- `network_mode: host`：TUN 会接管宿主机路由，SSH 远程操作前请先确认不会断连。
- 9090 面板默认无密钥，请用 `clashctl secret` 设置或用防火墙限制。
