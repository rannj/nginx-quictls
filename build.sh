#!/bin/bash
set -e

# === 定义变量 ===
NGINX_VERSION="1.29.2"
ZLIB_VERSION="1.3.1"
PCRE2_VERSION="10.45"
OPENSSL_VERSION="3.6.0"
BASE_DIR="/github/home"
NGINX_SRC_DIR="${BASE_DIR}/nginx-${NGINX_VERSION}"
MODULES_DIR="${NGINX_SRC_DIR}/modules"

CC_OPTS=" \
-march=x86-64-v3 \
-mtune=generic \
-O3 \
-pipe \
-fno-plt \
-fexceptions \
-Wp,-D_FORTIFY_SOURCE=3 \
-Wformat \
-Werror=format-security \
-fstack-clash-protection \
-fcf-protection \
-g1 \
-flto=auto \
"
LD_OPTS=" \
-Wl,-O1 \
-Wl,--sort-common \
-Wl,--as-needed \
-Wl,-z,relro \
-Wl,-z,now \
-Wl,-z,pack-relative-relocs \
-flto=auto \
"

# === 切换到工作目录 ===
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# === 1. 安装依赖 ===
echo "[+] Installing dependencies..."
apt-get update -y
apt-get install -y --allow-change-held-packages --allow-downgrades --allow-remove-essential \
  -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
  cmake git libmaxminddb-dev mercurial wget

# === 2. 下载源码 ===
echo "[+] Fetching source code..."

# NGINX
wget -q -O "nginx-${NGINX_VERSION}.tar.gz"  "https://github.com/nginx/nginx/releases/download/release-${NGINX_VERSION}/nginx-${NGINX_VERSION}.tar.gz"
tar -xf "nginx-${NGINX_VERSION}.tar.gz"

# ZLIB
wget -q -O "zlib-${ZLIB_VERSION}.tar.gz"  "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz"
tar -xf "zlib-${ZLIB_VERSION}.tar.gz"

# PCRE2
wget -q -O "pcre2-${PCRE2_VERSION}.tar.gz"  "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz"
tar -xf "pcre2-${PCRE2_VERSION}.tar.gz"

# OPENSSL
wget -q -O "openssl-${OPENSSL_VERSION}.tar.gz" "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
tar -xf "openssl-${OPENSSL_VERSION}.tar.gz"

# Nginx 模块
mkdir -p "$MODULES_DIR"
cd "$MODULES_DIR"
git clone --depth 1 --recursive https://github.com/google/ngx_brotli.git
git clone --depth 1 --recursive https://github.com/openresty/headers-more-nginx-module.git

# === 3. 编译 Brotli 依赖 ===
echo "[+] Building brotli dependency..."
mkdir -p ngx_brotli/deps/brotli/out
cd ngx_brotli/deps/brotli/out
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=installed ..
cmake --build . --config Release --target brotlienc

# === 4. 配置和编译 Nginx ===
echo "[+] Configuring and building Nginx..."
cd "$NGINX_SRC_DIR"
./configure \
--prefix=/etc/nginx --sbin-path=/usr/sbin/nginx \
--conf-path=/etc/nginx/nginx.conf \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--pid-path=/var/run/nginx.pid \
--lock-path=/var/run/nginx.lock \
--http-client-body-temp-path=/var/cache/nginx/client_temp \
--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
--add-module=modules/ngx_brotli \
--add-module=modules/headers-more-nginx-module \
--user=nginx --group=nginx \
--with-pcre-jit \
--with-zlib=../zlib-${ZLIB_VERSION} \
--with-pcre=../pcre2-${PCRE2_VERSION} \
--with-openssl=../openssl-${OPENSSL_VERSION} \
--with-file-aio \
--with-threads \
--with-stream \
--with-stream_realip_module \
--with-stream_ssl_module \
--with-stream_ssl_preread_module \
--with-http_auth_request_module \
--with-http_gunzip_module \
--with-http_gzip_static_module \
--with-http_realip_module \
--with-http_slice_module \
--with-http_ssl_module \
--with-http_sub_module \
--with-http_stub_status_module \
--with-http_v2_module \
--with-http_v3_module \
--without-select_module --without-poll_module \
--without-http_access_module --without-http_autoindex_module \
--without-http_browser_module --without-http_charset_module \
--without-http_empty_gif_module --without-http_limit_conn_module \
--without-http_memcached_module --without-http_mirror_module \
--without-http_referer_module --without-http_split_clients_module \
--without-http_scgi_module --without-http_ssi_module \
--without-http_upstream_hash_module --without-http_upstream_ip_hash_module \
--without-http_upstream_keepalive_module --without-http_upstream_least_conn_module \
--without-http_upstream_random_module --without-http_upstream_zone_module \
--with-cc-opt="$CC_OPTS" \
--with-ld-opt="$LD_OPTS"

# --add-module=modules/ngx_http_geoip2_module \

make -j"$(nproc)"
cp objs/nginx ../
cd ../
hash=$(ls -l nginx | awk '{print $5}')
patch=$(cat /github/workspace/patch)
minor=$(cat /github/workspace/minor)
if [[ $hash != $(cat /github/workspace/hash) ]]; then
  echo $hash > /github/workspace/hash
  if [[ $GITHUB_EVENT_NAME == push ]]; then
    patch=0
    minor=$(($(cat /github/workspace/minor)+1))
    echo $minor > /github/workspace/minor
  else
    patch=$(($(cat /github/workspace/patch)+1))
  fi
  echo $patch > /github/workspace/patch
  change=1
  echo This is a new version.
else
  echo This is an old version.
fi
echo -e "hash=$hash\npatch=$patch\nminor=$minor\nchange=$change" >> $GITHUB_ENV
