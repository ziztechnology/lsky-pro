# =============================================================================
# Stage 1: Node.js 前端资源构建
# 编译 TailwindCSS / Laravel Mix 产物，避免在生产镜像中安装 Node.js
# =============================================================================
FROM node:18-alpine AS node-builder

WORKDIR /app

# 优先复制 package 文件，利用 Docker 层缓存
COPY package.json package-lock.json webpack.mix.js tailwind.config.js ./
RUN npm ci --prefer-offline

# 复制前端源码并构建
COPY resources/ ./resources/
COPY public/      ./public/
RUN npm run production

# =============================================================================
# Stage 2: PHP Composer 依赖安装
# 使用独立 stage 避免将 composer 工具带入生产镜像
# =============================================================================
FROM php:8.1 AS composer-builder

WORKDIR /build

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl unzip git && \
    curl -sS https://getcomposer.org/installer | php -- \
        --install-dir=/usr/local/bin --filename=composer && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制 composer 文件并安装生产依赖（不含 dev 包）
COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-scripts \
    --no-progress \
    --optimize-autoloader \
    --prefer-dist

# 复制完整应用代码
COPY . .

# 复制前端构建产物（覆盖 public/js 和 public/css）
COPY --from=node-builder /app/public/js    ./public/js
COPY --from=node-builder /app/public/css   ./public/css
COPY --from=node-builder /app/public/mix-manifest.json ./public/mix-manifest.json

# 准备 .env（首次构建时从 example 复制）
RUN php -r "file_exists('.env') || copy('.env.example', '.env');"

# =============================================================================
# Stage 3: 生产运行镜像
# 与原始 halcyonazure/lsky-pro-docker 保持一致的 php:8.1-apache 基础
# =============================================================================
FROM php:8.1-apache AS production

LABEL org.opencontainers.image.source="https://github.com/ziztechnology/lsky-pro"
LABEL org.opencontainers.image.description="Lsky Pro - Ziztechnology 定制版（含相册授权功能）"
LABEL org.opencontainers.image.licenses="AGPL-3.0"

# --------------------------------------------------------------------------
# 系统依赖 + PHP 扩展
# 与原始镜像保持完全一致，确保功能兼容
# --------------------------------------------------------------------------
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    /usr/local/bin/

RUN a2enmod ssl && a2ensite default-ssl

RUN apt-get update && \
    apt-get install -y --no-install-recommends gettext cifs-utils && \
    apt-get clean && rm -rf /var/cache/apt/* /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    a2enmod rewrite && \
    chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions imagick bcmath pdo_mysql pdo_pgsql redis

# PHP 运行时参数调优（与原镜像保持一致）
RUN { \
    echo 'post_max_size = 100M;'; \
    echo 'upload_max_filesize = 100M;'; \
    echo 'max_execution_time = 600;'; \
    } > /usr/local/etc/php/conf.d/docker-php-upload.ini && \
    { \
    echo 'opcache.enable=1'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.revalidate_freq=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo 'apc.enable_cli=1' >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini && \
    echo 'memory_limit=512M' > /usr/local/etc/php/conf.d/memory-limit.ini

# --------------------------------------------------------------------------
# Apache 配置（与原镜像保持一致）
# --------------------------------------------------------------------------
COPY .docker/ssl/                     /etc/ssl
COPY .docker/000-default.conf.template /etc/apache2/sites-enabled/000-default.conf.template
COPY .docker/ports.conf.template       /etc/apache2/ports.conf.template

# --------------------------------------------------------------------------
# 应用代码（来自 composer-builder stage）
# 存放于 /var/www/lsky/，entrypoint 负责首次同步到 /var/www/html/
# --------------------------------------------------------------------------
COPY --from=composer-builder --chown=www-data:www-data /build /var/www/lsky/

# --------------------------------------------------------------------------
# Entrypoint
# --------------------------------------------------------------------------
COPY .docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /var/www/data && \
    chown -R www-data:root /var/www && \
    chmod -R g=u /var/www

WORKDIR /var/www/html
VOLUME  /var/www/html

ENV WEB_PORT=8089
ENV HTTPS_PORT=8088

EXPOSE ${WEB_PORT}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
