# clashctl-docker

用 Docker 运行 [nelvko/clashctl](https://github.com/nelvko/clashctl)（mihomo 内核），默认使用 **host 网络 + TUN**，适合没有显示器的 Linux 主机：进入容器后用 `clashctl` 命令管理即可。

## 特性

- 构建时自动安装 clashctl（mihomo 内核、yq、Web 面板、subconverter）
- 启动时自动导入订阅 / 本地配置、启动内核、开启 TUN
- `network_mode: host`：TUN 接管**整台宿主机**的流量
- 数据（订阅、配置、日志）保存在命名卷 `clashctl-data`，重建容器不丢失
- 进入容器后可直接使用 `clashctl` 全部命令

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `Dockerfile` | 基于 `debian:12-slim`，安装依赖与 clashctl |
| `entrypoint.sh` | 导入订阅 → 启动内核 → 开启 TUN → 前台跟随日志；内核退出则容器退出 |
| `docker-compose.yml` | host 网络、`NET_ADMIN`、`/dev/net/tun`、数据卷 |
| `config/config.example.yaml` | 脱敏的 mihomo 配置示例（节点信息为占位符） |
| `.gitignore` | 忽略 `config/config.yaml`，避免提交节点密钥 |

## 前置条件

- Linux 主机，已安装 Docker 与 Docker Compose v2
- 内核支持 TUN（存在 `/dev/net/tun`；没有的话执行 `sudo modprobe tun`）
- 一个订阅链接，或一份自己的 mihomo 配置

## 快速开始

### 方式一：使用订阅链接

编辑 `docker-compose.yml`，取消注释并填写 `SUB_URL`：

```yaml
environment:
  ENABLE_TUN: "true"
  SUB_URL: "https://你的订阅链接"
```

同时删掉（或注释）`volumes` 里的 `./config/config.yaml:/config/config.yaml:ro` 一行，否则文件不存在时 Docker 会把它创建成目录。

### 方式二：使用本地配置文件

```bash
cp config/config.example.yaml config/config.yaml
# 编辑 config/config.yaml，把 YOUR_SERVER_IP / YOUR_UUID / YOUR_REALITY_PUBLIC_KEY / YOUR_SHORT_ID 换成真实值
```

### 启动

```bash
docker compose up -d --build
docker logs -f clashctl        # 查看启动日志
```

- `docker compose up -d --build`：构建镜像并启动容器（网络正常时只需这一条）。
- 网络受限（Docker Hub / GitHub / apt 访问不了或很慢）时，需要给构建传参数，见下文[网络受限时](#网络受限时docker-hub--github--apt-被屏蔽)。

## 日常使用

进入容器，直接使用 `clashctl`：

```bash
docker exec -it clashctl bash
```

```bash
clashctl status              # 内核、TUN、代理地址状态
clashctl tun                 # 查看 TUN 状态
clashctl tun on              # 开启 TUN
clashctl tun off             # 关闭 TUN
clashctl sub add --use "<订阅链接>"   # 添加并启用订阅
clashctl sub ls              # 订阅列表
clashctl node                # 切换节点
clashctl log                 # 查看日志
clashctl secret              # 查看 / 设置 Web 面板密钥
clashctl upgrade             # 升级内核
clashctl -h                  # 全部命令
```

不进入容器，单条命令也可以：

```bash
docker exec clashctl bash -ic 'clashctl status'
```

## 端口

host 模式下直接在宿主机监听：

| 端口 | 用途 |
| --- | --- |
| 7890 | mixed（HTTP / SOCKS5）代理 |
| 9090 | Web 面板 / external-controller API |

## 验证 TUN 是否生效

```bash
ip link show clashctl                 # 宿主机上应有名为 clashctl 的 TUN 网卡
curl https://api.ipify.org            # 应返回代理节点的出口 IP，而非本机公网 IP
```

## 重要提示

### SSH 远程操作的风险

host 模式下 TUN 会修改宿主机路由表。如果你通过 SSH 连接这台主机：

- 首次启动请尽量在能直接操作机器（本机控制台 / IPMI）时进行
- 确认配置里的 `tun.route-exclude-address` 覆盖了你的内网网段，并保证 SSH 来源 IP 不会被接管
- 万一失联，在本机控制台执行 `docker stop clashctl` 即可恢复路由

### Web 面板安全

9090 默认没有密钥，并且在宿主机所有网卡上监听。如果主机有公网 IP，请：

- 执行 `clashctl secret` 设置密钥，或
- 用防火墙限制 9090 的访问来源

### 不要提交真实配置

`config/config.yaml` 含节点的 uuid、密钥等信息，已被 `.gitignore` 忽略。公开仓库中只保留脱敏的 `config.example.yaml`。

## 只想让容器自己走代理，不影响宿主机？

把 `docker-compose.yml` 中的 `network_mode: host` 换成端口映射：

```yaml
    cap_add: [NET_ADMIN]
    devices:
      - /dev/net/tun:/dev/net/tun
    sysctls:
      net.ipv4.ip_forward: "1"
    ports:
      - "7890:7890"
      - "9090:9090"
```

此时 TUN 只接管容器自身的网络。其他容器可通过 `network_mode: "service:clashctl"` 共用它的网络。

## 配置说明

### 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ENABLE_TUN` | `true` | 是否在启动时开启 TUN |
| `SUB_URL` | 空 | 订阅链接；设置后优先于本地配置 |

### 本地配置的注意事项

- 配置须能被当前 mihomo 版本接受。例如 `global-client-fingerprint` 已被移除（改在节点上设置 `client-fingerprint`）；`GEOSITE` 规则中的名称必须存在于 `geosite.dat`，否则内核会启动失败。
- 订阅 / 配置只在**首次**导入。之后要修改，用 `clashctl sub` 命令，或执行 `docker compose down -v` 清空数据卷后重新启动（会丢失所有已保存的订阅与设置）。

## 网络受限时（Docker Hub / GitHub / apt 被屏蔽）

构建过程会访问三类地址：基础镜像（Docker Hub）、apt 源、GitHub（下载 clashctl 与内核）。可通过构建参数分别替换：

| 参数 | 默认值 | 作用 | 示例 |
| --- | --- | --- | --- |
| `BASE_IMAGE` | `debian:12-slim` | 基础镜像，可换成镜像代理地址或本地已有的 Debian 系镜像 | `docker.m.daocloud.io/library/debian:12-slim` |
| `APT_MIRROR` | 空（用默认源） | 替换 apt 源域名，仅对 Debian 系基础镜像有效 | `mirrors.aliyun.com` |
| `GH_PROXY` | 空 | GitHub 下载加速代理 | `https://gh-proxy.org/` |

传参有两种方式，**二选一**：

**方式 A：命令行传参（分两步）**

`docker compose up` 不支持 `--build-arg`，所以要先单独 `build`，再 `up`：

```bash
# 第 1 步：构建（带参数）
docker compose build \
  --build-arg BASE_IMAGE=docker.m.daocloud.io/library/debian:12-slim \
  --build-arg APT_MIRROR=mirrors.aliyun.com \
  --build-arg GH_PROXY=https://gh-proxy.org/

# 第 2 步：启动（不要加 --build，否则会不带参数重新构建）
docker compose up -d
```

**方式 B：写进 `docker-compose.yml`（一条命令）**

编辑 `docker-compose.yml` 的 `build.args`，把需要的参数改成实际值（文件里已有注释示例，改完后不用再传命令行参数）：

```yaml
    build:
      context: .
      args:
        BASE_IMAGE: docker.m.daocloud.io/library/debian:12-slim
        APT_MIRROR: mirrors.aliyun.com
        GH_PROXY: https://gh-proxy.org/
```

之后仍然只用：

```bash
docker compose up -d --build
```

### 离线分发：在能联网的机器上构建，导出到目标机器

镜像里已包含内核、yq 和面板，目标机器无需再访问外网：

```bash
# 能联网的机器
docker compose build
docker save clashctl-docker-clashctl:latest | gzip > clashctl.tar.gz

# 拷贝到目标机器（scp / U 盘）后
gunzip -c clashctl.tar.gz | docker load
```

然后把 `docker-compose.yml` 中的 `build:` 整段换成：

```yaml
    image: clashctl-docker-clashctl:latest
```

再 `docker compose up -d` 即可。注意：镜像按构建机的 CPU 架构生成（x86_64 / arm64），目标机器架构不同则需要在对应架构上重新构建。

### 给 Docker 配置镜像加速（可选）

在 `/etc/docker/daemon.json` 中加入 `registry-mirrors` 后执行 `sudo systemctl restart docker`，之后所有镜像拉取都会走该加速地址。

## 常见问题

**日志提示"订阅无效 / 原生配置验证失败"**
查看 `docker exec clashctl cat /opt/clashctl/data/last-failed.yaml` 和 `docker logs clashctl`，通常是配置中有新版 mihomo 不支持的字段或不存在的 geosite 名称。

**`TUN 开启失败`**
确认 `cap_add: [NET_ADMIN]` 与 `/dev/net/tun` 设备已配置，并且宿主机存在 `/dev/net/tun`。

**`clashctl status` 显示"已选订阅：未选择"**
使用本地配置文件导入时的显示问题，不影响实际使用，以出口 IP 验证为准。

**容器反复重启**
`docker logs clashctl` 查看原因；内核退出时容器按设计会一并退出，由 `restart: unless-stopped` 拉起。

## 致谢

- [nelvko/clashctl](https://github.com/nelvko/clashctl)
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
