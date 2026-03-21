#!/bin/bash
set -eu

WEB_PORT=${WEB_PORT:-8089}
HTTPS_PORT=${HTTPS_PORT:-8088}

# 渲染 Apache 配置模板（替换端口环境变量）
envsubst '${WEB_PORT} ${HTTPS_PORT}' \
    < /etc/apache2/sites-enabled/000-default.conf.template \
    > /etc/apache2/sites-enabled/000-default.conf

envsubst '${WEB_PORT} ${HTTPS_PORT}' \
    < /etc/apache2/ports.conf.template \
    > /etc/apache2/ports.conf

# -----------------------------------------------------------------------
# 首次初始化：将镜像内的应用代码同步到挂载卷
# 判断依据：public/index.php 是否存在
# -----------------------------------------------------------------------
if [ ! -e '/var/www/html/public/index.php' ]; then
    echo "[entrypoint] 首次启动，正在初始化应用目录..."
    cp -a /var/www/lsky/. /var/www/html/
    # 如果 .env 不存在则从 example 复制
    [ -f /var/www/html/.env ] || cp /var/www/html/.env.example /var/www/html/.env
    echo "[entrypoint] 应用目录初始化完成"
fi

# -----------------------------------------------------------------------
# 版本升级检测：比较镜像内版本号与挂载卷内版本号
# 如果镜像版本更新，则同步核心代码（保留 .env / storage / database）
# -----------------------------------------------------------------------
IMAGE_VERSION_FILE="/var/www/lsky/VERSION"
VOLUME_VERSION_FILE="/var/www/html/VERSION"

if [ -f "${IMAGE_VERSION_FILE}" ]; then
    IMAGE_VERSION=$(cat "${IMAGE_VERSION_FILE}")
    VOLUME_VERSION=$(cat "${VOLUME_VERSION_FILE}" 2>/dev/null || echo "0.0.0")

    if [ "${IMAGE_VERSION}" != "${VOLUME_VERSION}" ]; then
        echo "[entrypoint] 检测到版本更新: ${VOLUME_VERSION} -> ${IMAGE_VERSION}，正在同步代码..."
        # 同步代码：先备份需要保留的文件，全量覆盖后再还原
        # 备份持久化数据
        [ -f /var/www/html/.env ]                        && cp /var/www/html/.env                        /tmp/lsky_env_backup
        [ -d /var/www/html/storage ]                     && cp -a /var/www/html/storage                  /tmp/lsky_storage_backup
        [ -f /var/www/html/database/database.sqlite ]    && cp /var/www/html/database/database.sqlite    /tmp/lsky_sqlite_backup

        # 全量覆盖（镜像代码 -> 挂载卷）
        cp -a /var/www/lsky/. /var/www/html/

        # 还原持久化数据（覆盖镜像内的空占位）
        [ -f /tmp/lsky_env_backup ]     && cp /tmp/lsky_env_backup     /var/www/html/.env
        [ -d /tmp/lsky_storage_backup ] && cp -a /tmp/lsky_storage_backup/. /var/www/html/storage/
        [ -f /tmp/lsky_sqlite_backup ]  && cp /tmp/lsky_sqlite_backup  /var/www/html/database/database.sqlite

        # 清理临时备份
        rm -rf /tmp/lsky_env_backup /tmp/lsky_storage_backup /tmp/lsky_sqlite_backup
        echo "[entrypoint] 代码同步完成"
    fi
fi

# -----------------------------------------------------------------------
# 修正文件权限（确保 Apache www-data 可读写）
# -----------------------------------------------------------------------
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html/
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache 2>/dev/null || true

# -----------------------------------------------------------------------
# 自动执行数据库迁移（仅在 .env 已配置 DB 连接时执行）
# -----------------------------------------------------------------------
if [ -f /var/www/html/.env ] && grep -q "^DB_CONNECTION=" /var/www/html/.env; then
    DB_CONN=$(grep "^DB_CONNECTION=" /var/www/html/.env | cut -d= -f2 | tr -d '[:space:]')
    if [ -n "${DB_CONN}" ] && [ "${DB_CONN}" != "null" ]; then
        echo "[entrypoint] 正在执行数据库迁移..."
        cd /var/www/html && php artisan migrate --force 2>&1 || \
            echo "[entrypoint] 警告：数据库迁移失败，请手动检查"
    fi
fi

echo "[entrypoint] 启动 Apache..."
exec "$@"
