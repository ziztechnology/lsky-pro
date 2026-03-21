<?php

namespace App\Enums;

/**
 * 相册授权级别枚举
 *
 * readonly  (1): 只读  — 仅可浏览相册图片
 * advanced  (2): 高级  — 浏览 + 下载图片
 * ultimate  (3): 究极  — 浏览 + 下载 + 删除图片
 */
enum AlbumAuthorizationLevel: int
{
    case Readonly = 1;
    case Advanced = 2;
    case Ultimate = 3;

    /**
     * 返回中文显示名称
     */
    public function label(): string
    {
        return match ($this) {
            self::Readonly => '只读',
            self::Advanced => '高级',
            self::Ultimate => '究极',
        };
    }

    /**
     * 返回该级别拥有的能力列表
     */
    public function abilities(): array
    {
        return match ($this) {
            self::Readonly => ['view'],
            self::Advanced => ['view', 'download'],
            self::Ultimate => ['view', 'download', 'delete'],
        };
    }

    /**
     * 判断是否拥有某项能力
     */
    public function can(string $ability): bool
    {
        return in_array($ability, $this->abilities(), true);
    }

    /**
     * 从整数值安全解析，不合法时返回 Readonly
     */
    public static function fromIntSafe(int $value): self
    {
        return self::tryFrom($value) ?? self::Readonly;
    }

    /**
     * 返回所有级别的 [value => label] 映射，供前端使用
     */
    public static function options(): array
    {
        return array_map(fn(self $case) => [
            'value' => $case->value,
            'label' => $case->label(),
        ], self::cases());
    }
}
