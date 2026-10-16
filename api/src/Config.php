<?php

declare(strict_types=1);

namespace App;

/**
 * Конфигурация из переменных окружения (или файла .env рядом с api/).
 * Секреты в коде не хранятся; обязательные значения проверяются при старте.
 */
final class Config
{
    /** @param array<string, string> $values */
    private function __construct(private readonly array $values)
    {
    }

    public static function fromEnvironment(string $envFile): self
    {
        $values = [];
        if (is_file($envFile)) {
            foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
                $line = trim($line);
                if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
                    continue;
                }
                [$key, $value] = array_map('trim', explode('=', $line, 2));
                $values[$key] = trim($value, "\"'");
            }
        }
        foreach (getenv() as $key => $value) {
            $values[$key] = (string) $value;
        }
        return new self($values);
    }

    /** @param array<string, string> $values */
    public static function fromArray(array $values): self
    {
        return new self($values);
    }

    public function get(string $key, ?string $default = null): ?string
    {
        $value = $this->values[$key] ?? null;
        return ($value === null || $value === '') ? $default : $value;
    }

    public function require(string $key): string
    {
        $value = $this->get($key);
        if ($value === null) {
            throw new \RuntimeException("Не задана обязательная настройка {$key}");
        }
        return $value;
    }

    public function int(string $key, int $default): int
    {
        $value = $this->get($key);
        return $value === null ? $default : (int) $value;
    }

    public function bool(string $key, bool $default): bool
    {
        $value = $this->get($key);
        return $value === null ? $default : in_array(strtolower($value), ['1', 'true', 'yes', 'on'], true);
    }

    /** @return list<string> */
    public function list(string $key): array
    {
        $value = $this->get($key);
        if ($value === null) {
            return [];
        }
        return array_values(array_filter(array_map('trim', explode(',', $value)), static fn ($v) => $v !== ''));
    }

    public function isProduction(): bool
    {
        return $this->get('APP_ENV', 'production') === 'production';
    }
}
