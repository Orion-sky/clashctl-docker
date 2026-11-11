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

## 排障：host 模式下容器里能上网，宿主机 `curl` 却是空的

**现象**：容器内 `curl https://www.google.com` 返回 200，宿主机上 `curl http://www.google.com` 返回 `Empty reply from server`（输出为空），`curl https://...` 则 TLS 握手被断开。`ip link` 里能看到 TUN 网卡，`ip rule` 里也有 TUN 的策略路由，路由本身没有问题。

**原因**：宿主机的 DNS 解析被污染。

host 模式下容器和宿主机共用同一套网络，所以路由一样，差别只在域名解析：

- mihomo 的 `dns-hijack` 会劫持经过 TUN 的 53 端口查询，返回 fake-ip（`198.18.x.x`）。
- 但 `systemd-resolved` 的查询套接字绑定在物理网卡（如 `enp7s0`）上，不走 TUN 的策略路由，直接发给路由器的上游 DNS，拿到被污染的假地址（例如 A 记录 `104.244.42.197`、AAAA 记录 `2001::1`）。
- 宿主机的 `curl` 优先连被污染的 `2001::1`，对端直接断开，表现为 `Empty reply`。容器里的 `curl` 碰巧先连了 IPv4 地址，所以看起来能通，这只是巧合。

**排查步骤**（都不会修改系统设置）：

```bash
# 1. TUN 本身是否生效
ip rule                               # 应有 lookup 2022 等规则
ip route show table 2022              # 应有 default via ... dev clashctl

# 2. 宿主机 DNS 当前走谁、结果是否被污染
resolvectl status                     # 看 Current DNS Server
resolvectl query --cache=no www.google.com   # 返回 104.x / 2001::1 等即被污染

# 3. 对比：直接 dig 路由器（会被 TUN 劫持）和 resolved 的结果
dig +short www.google.com @192.168.5.1       # 得到 198.18.x.x 说明劫持正常
dig +short www.google.com @127.0.0.53        # 得到 104.x / 2001::1 说明 resolved 绕过了劫持

# 4. 确认 mihomo 自己的 DNS 可用
dig +short www.google.com A @127.0.0.1 -p 1053   # 应得到 198.18.x.x
```

如果第 3 步两个结果不同，就是这个问题。

**修复**：让 `systemd-resolved` 直接使用 mihomo 的 DNS（本机回环地址，不经过网卡）。需要 systemd ≥ 247（支持 `地址:端口` 写法）：

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNS=127.0.0.1:1053\nDomains=~.\n' | sudo tee /etc/systemd/resolved.conf.d/clash.conf
sudo resolvectl revert enp7s0          # 网卡名按实际情况替换，去掉之前可能手动设的临时 DNS
sudo systemctl restart systemd-resolved

resolvectl query www.google.com        # 应返回 198.18.x.x
curl -I http://www.google.com
```

> 粘贴多行 heredoc 时，结束标记 `EOF` 必须顶格，带缩进会导致 shell 一直等待输入，所以上面用了 `printf` 单行写法。

**注意**：

- 宿主机的 DNS 此后依赖 clashctl 容器。容器停止或启动失败时，宿主机会解析不了域名（容器已设 `restart: unless-stopped`，正常会自动拉起）。恢复办法：删除 `/etc/systemd/resolved.conf.d/clash.conf` 后 `sudo systemctl restart systemd-resolved`。
- 在路由器上改 DNS 解决不了：污染来自路由器的上游；而且 DHCP 不能指定端口，若把 mihomo 改到 53 端口让局域网其他设备也用它，它们会拿到只有本机 TUN 才认识的 fake-ip，反而连不上。
- 不是用 `systemd-resolved` 的发行版，原理相同：确保系统 DNS 查询最终进入 mihomo 的 DNS（`127.0.0.1:1053`）或被 TUN 劫持。

## 常见问题

**日志提示"订阅无效 / 原生配置验证失败"**
查看 `docker exec clashctl cat /opt/clashctl/data/last-failed.yaml` 和 `docker logs clashctl`，通常是配置中有新版 mihomo 不支持的字段或不存在的 geosite 名称。

**`TUN 开启失败`**
确认 `cap_add: [NET_ADMIN]` 与 `/dev/net/tun` 设备已配置，并且宿主机存在 `/dev/net/tun`。

**日志出现 `Start TUN listening error: configure tun interface: add rule 0/8: address family not supported by protocol`**
宿主机内核不支持 IPv6 策略路由（如 Jetson L4T 内核 `# CONFIG_IPV6_MULTIPLE_TABLES is not set`，可用 `ip -6 rule` 验证），`strict-route: true` 会添加 IPv6 规则而失败。入口脚本检测到该情况会自动把 `data/mixin.yaml` 中的 `strict-route` 改为 `false` 并加上 `ipv6: false`。代价是 IPv6 流量可能绕过 TUN。

**`clashctl status` 显示"已选订阅：未选择"**
使用本地配置文件导入时的显示问题，不影响实际使用，以出口 IP 验证为准。

**宿主机 `curl` 返回空 / 解析到奇怪的 IP（104.244.42.197、2001::1）**
见上文[排障](#排障host-模式下容器里能上网宿主机-curl-却是空的)。

**容器反复重启**
`docker logs clashctl` 查看原因；内核退出时容器按设计会一并退出，由 `restart: unless-stopped` 拉起。

## 致谢

- [nelvko/clashctl](https://github.com/nelvko/clashctl)
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
