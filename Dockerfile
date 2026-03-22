# =============================================================================
# Stage 1: Node.js 前端资源构建
# 编译 TailwindCSS / Laravel Mix 产物
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
# 严格对齐原始镜像：使用 php:8.1（非 apache 变体）作为构建环境
# =============================================================================
FROM php:8.1 AS composer-builder

WORKDIR /build

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl unzip git && \
    curl -sS https://getcomposer.org/installer | php -- \
        --install-dir=/usr/local/bin --filename=composer && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制完整应用代码
COPY . .

# 复制前端构建产物（覆盖 public/js 和 public/css）
COPY --from=node-builder /app/public/js              ./public/js
COPY --from=node-builder /app/public/css             ./public/css
COPY --from=node-builder /app/public/mix-manifest.json ./public/mix-manifest.json

# 安装生产依赖（不含 dev 包），与原始镜像保持一致
RUN php -r "file_exists('.env') || copy('.env.example', '.env');" && \
    composer install \
        --no-dev \
        --no-interaction \
        --no-scripts \
        --no-progress \
        --optimize-autoloader \
        --prefer-dist

# =============================================================================
# Stage 3: 生产运行镜像
# 完全对齐 halcyonazure/lsky-pro-docker 的构建方式
# =============================================================================
FROM php:8.1-apache

LABEL org.opencontainers.image.source="https://github.com/ziztechnology/lsky-pro"
LABEL org.opencontainers.image.description="Lsky Pro - Ziztechnology 定制版（含相册授权功能）"
LABEL org.opencontainers.image.licenses="AGPL-3.0"

# --------------------------------------------------------------------------
# PHP 扩展安装器（与原始镜像完全一致）
# --------------------------------------------------------------------------
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    /usr/local/bin/

# 开启 SSL（与原始镜像完全一致）
RUN a2enmod ssl && a2ensite default-ssl

# 系统依赖 + PHP 扩展 + Apache 模块 + PHP 配置（与原始镜像完全一致）
RUN apt-get update && \
    apt-get install -y --no-install-recommends gettext && \
    apt-get clean && \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    a2enmod rewrite && \
    chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions imagick bcmath pdo_mysql pdo_pgsql redis && \
    \
    { \
    echo 'post_max_size = 100M;'; \
    echo 'upload_max_filesize = 100M;'; \
    echo 'max_execution_time = 600S;'; \
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
    \
    echo 'apc.enable_cli=1' >> /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini && \
    \
    echo 'memory_limit=512M' > /usr/local/etc/php/conf.d/memory-limit.ini && \
    \
    mkdir /var/www/data && \
    chown -R www-data:root /var/www && \
    chmod -R g=u /var/www

# --------------------------------------------------------------------------
# 文件复制（严格对齐原始镜像的 COPY 顺序）
# --------------------------------------------------------------------------
# SSL 证书（自签名，用于 HTTPS 监听）
COPY .docker/ssl /etc/ssl

# 应用代码（来自 composer-builder stage）
COPY --from=composer-builder /build /var/www/lsky/

# Apache 配置模板
COPY .docker/000-default.conf.template /etc/apache2/sites-enabled/
COPY .docker/ports.conf.template       /etc/apache2/

# Entrypoint
COPY .docker/entrypoint.sh /entrypoint.sh

WORKDIR /var/www/html/
VOLUME  /var/www/html

ENV WEB_PORT=8089
ENV HTTPS_PORT=8088

EXPOSE ${WEB_PORT}
EXPOSE ${HTTPS_PORT}

RUN chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apachectl", "-D", "FOREGROUND"]
