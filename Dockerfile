# 基础镜像可替换（镜像站被屏蔽时，改用镜像代理或本地已有镜像）
ARG BASE_IMAGE=debian:12-slim
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    CLASHCTL_HOME=/opt/clashctl \
    TZ=Asia/Shanghai

# apt 换源：如 --build-arg APT_MIRROR=mirrors.aliyun.com（留空则用默认源）
ARG APT_MIRROR=
RUN if [ -n "$APT_MIRROR" ]; then \
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do \
            [ -f "$f" ] && sed -i "s|deb.debian.org|$APT_MIRROR|g; s|security.debian.org|$APT_MIRROR|g" "$f"; \
        done; \
    fi \
    && apt-get update && apt-get install -y --no-install-recommends \
        bash curl ca-certificates tar unzip gzip coreutils procps iproute2 iptables nftables \
        util-linux iputils-ping dnsutils \
    && rm -rf /var/lib/apt/lists/*

# 构建期安装 clashctl（内核、yq、UI、subconverter 一并下载）
# 国内构建可加: --build-arg GH_PROXY=https://gh-proxy.org/
ARG GH_PROXY=
RUN curl -fsSL "${GH_PROXY}https://raw.githubusercontent.com/nelvko/clashctl/HEAD/install.sh" \
    | bash -s -- ${GH_PROXY:+--gh-proxy "$GH_PROXY"}

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/opt/clashctl/data"]
EXPOSE 7890 9090
ENTRYPOINT ["/entrypoint.sh"]
