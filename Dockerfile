FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    CLASHCTL_HOME=/opt/clashctl \
    TZ=Asia/Shanghai

RUN apt-get update && apt-get install -y --no-install-recommends \
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
