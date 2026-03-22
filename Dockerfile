# =============================================================================
# Stage 1: Node.js 前端资源构建
# =============================================================================
FROM node:18-alpine AS node-builder

WORKDIR /app

COPY package.json package-lock.json webpack.mix.js tailwind.config.js ./
RUN npm ci --prefer-offline

COPY resources/ ./resources/
COPY public/    ./public/
RUN npm run production

# =============================================================================
# Stage 2: PHP Composer 依赖安装
# =============================================================================
FROM php:8.1 AS composer-builder

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl unzip git && \
    curl -sS https://getcomposer.org/installer | php -- \
        --install-dir=/usr/local/bin --filename=composer && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制完整应用代码
COPY . .

# 覆盖前端构建产物
COPY --from=node-builder /app/public/js                ./public/js
COPY --from=node-builder /app/public/css               ./public/css
COPY --from=node-builder /app/public/mix-manifest.json ./public/mix-manifest.json

# 安装生产依赖（不含 dev 包），彻底删除 debugbar
RUN php -r "file_exists('.env') || copy('.env.example', '.env');" && \
    composer install \
        --no-dev \
        --no-interaction \
        --no-scripts \
        --no-progress \
        --optimize-autoloader \
        --prefer-dist && \
    # 彻底删除 debugbar（dev 依赖，防止自动发现）
    rm -rf vendor/barryvdh/laravel-debugbar && \
    # 重新生成 autoload（不含 debugbar）
    composer dump-autoload --optimize --no-dev

# =============================================================================
# Stage 3: 生产运行镜像（Nginx + PHP-FPM，纯 HTTP，无 SSL）
# 关键设计：vendor/ 和代码留在镜像内，只有 storage/ .env database/ 通过卷持久化
# =============================================================================
FROM php:8.1-fpm

LABEL org.opencontainers.image.source="https://github.com/ziztechnology/lsky-pro"
LABEL org.opencontainers.image.description="Lsky Pro - Ziztechnology 定制版（Nginx+FPM，无SSL）"
LABEL org.opencontainers.image.licenses="AGPL-3.0"

# --------------------------------------------------------------------------
# 安装 Nginx + PHP 扩展 + 系统依赖
# --------------------------------------------------------------------------
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    /usr/local/bin/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        gettext-base \
        supervisor && \
    apt-get clean && \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions imagick bcmath pdo_mysql pdo_pgsql redis && \
    \
    { \
    echo 'post_max_size = 100M'; \
    echo 'upload_max_filesize = 100M'; \
    echo 'max_execution_time = 600'; \
    } > /usr/local/etc/php/conf.d/docker-php-upload.ini && \
    \
    { \
    echo 'opcache.enable=1'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.revalidate_freq=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo 'memory_limit=512M' > /usr/local/etc/php/conf.d/memory-limit.ini

# --------------------------------------------------------------------------
# PHP-FPM 配置（TCP 9000，与 Nginx fastcgi_pass 一致）
# --------------------------------------------------------------------------
COPY .docker/php-fpm-www.conf /usr/local/etc/php-fpm.d/www.conf

# --------------------------------------------------------------------------
# Nginx 配置（纯 HTTP，监听 WEB_PORT）
# --------------------------------------------------------------------------
COPY .docker/nginx.conf   /etc/nginx/nginx.conf
COPY .docker/default.conf /etc/nginx/conf.d/default.conf.template

# --------------------------------------------------------------------------
# Supervisor 配置
# --------------------------------------------------------------------------
COPY .docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# --------------------------------------------------------------------------
# 应用代码（vendor 在镜像内，不挂载覆盖）
# --------------------------------------------------------------------------
COPY --from=composer-builder --chown=www-data:www-data /app /var/www/html

# 创建持久化目录占位（storage、database 通过卷挂载）
RUN mkdir -p /var/www/html/storage/app/public \
             /var/www/html/storage/framework/cache \
             /var/www/html/storage/framework/sessions \
             /var/www/html/storage/framework/views \
             /var/www/html/storage/logs \
             /var/www/html/bootstrap/cache && \
    chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html && \
    chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# --------------------------------------------------------------------------
# Entrypoint
# --------------------------------------------------------------------------
COPY .docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /var/www/html

ENV WEB_PORT=8089

EXPOSE ${WEB_PORT}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
