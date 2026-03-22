#!/bin/bash
set -eu

WEB_PORT=${WEB_PORT:-8089}

# -----------------------------------------------------------------------
# 渲染 Nginx 站点配置（替换 WEB_PORT 环境变量）
# -----------------------------------------------------------------------
envsubst '${WEB_PORT}' \
    < /etc/nginx/conf.d/default.conf.template \
    > /etc/nginx/conf.d/default.conf

# -----------------------------------------------------------------------
# 初始化 .env（首次启动时从 .env.example 复制）
# -----------------------------------------------------------------------
if [ ! -f /var/www/html/.env ]; then
    echo "[entrypoint] 未检测到 .env，从 .env.example 复制..."
    cp /var/www/html/.env.example /var/www/html/.env
    echo "[entrypoint] 请编辑 /var/www/html/.env 配置数据库等信息"
fi

# -----------------------------------------------------------------------
# 确保持久化目录存在并权限正确
# -----------------------------------------------------------------------
mkdir -p /var/www/html/storage/app/public \
         /var/www/html/storage/framework/cache \
         /var/www/html/storage/framework/sessions \
         /var/www/html/storage/framework/views \
         /var/www/html/storage/logs \
         /var/www/html/bootstrap/cache

chown -R www-data:www-data \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

chmod -R 775 \
    /var/www/html/storage \
    /var/www/html/bootstrap/cache

# -----------------------------------------------------------------------
# 清除 Laravel 缓存（确保 bootstrap/cache 中无旧的 packages.php 等）
# -----------------------------------------------------------------------
cd /var/www/html
php artisan config:clear  2>/dev/null || true
php artisan cache:clear   2>/dev/null || true
php artisan view:clear    2>/dev/null || true
# 重新生成 package discovery（不含 debugbar）
php artisan package:discover --ansi 2>/dev/null || true

# -----------------------------------------------------------------------
# 自动执行数据库迁移
# -----------------------------------------------------------------------
if [ -f /var/www/html/.env ] && grep -q "^DB_CONNECTION=" /var/www/html/.env; then
    DB_CONN=$(grep "^DB_CONNECTION=" /var/www/html/.env | cut -d= -f2 | tr -d '[:space:]')
    if [ -n "${DB_CONN}" ] && [ "${DB_CONN}" != "null" ]; then
        echo "[entrypoint] 正在执行数据库迁移..."
        php artisan migrate --force 2>&1 && \
            echo "[entrypoint] 数据库迁移完成" || \
            echo "[entrypoint] 警告：数据库迁移失败，请手动检查"
    fi
fi

echo "[entrypoint] 启动 Nginx + PHP-FPM (port: ${WEB_PORT})..."
exec "$@"
