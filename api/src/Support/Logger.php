<?php

declare(strict_types=1);

namespace App\Support;

/**
 * Простой файловый логгер (JSON-строки). Контекст не должен содержать секретов и кодов.
 */
final class Logger
{
    public function __construct(private readonly ?string $file)
    {
    }

    /** @param array<string, mixed> $context */
    public function info(string $message, array $context = []): void
    {
        $this->write('info', $message, $context);
    }

    /** @param array<string, mixed> $context */
    public function error(string $message, array $context = []): void
    {
        $this->write('error', $message, $context);
    }

    /** @param array<string, mixed> $context */
    private function write(string $level, string $message, array $context): void
    {
        if ($this->file === null) {
            return;
        }
        $dir = dirname($this->file);
        if (!is_dir($dir)) {
            @mkdir($dir, 0750, true);
        }
        $line = json_encode(
            ['at' => gmdate('c'), 'level' => $level, 'message' => $message, 'context' => $context],
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PARTIAL_OUTPUT_ON_ERROR,
        );
        file_put_contents($this->file, $line . "\n", FILE_APPEND | LOCK_EX);
    }
}
