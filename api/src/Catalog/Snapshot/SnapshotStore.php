<?php

declare(strict_types=1);

namespace App\Catalog\Snapshot;

/**
 * Читает JSON-файлы снапшота (tools/snapshot → api/data/snapshot). Файлы загружаются лениво
 * и кэшируются на время запроса.
 */
final class SnapshotStore
{
    /** @var array<string, mixed> */
    private array $cache = [];

    public function __construct(private readonly string $dir)
    {
        if (!is_dir($dir)) {
            throw new \RuntimeException("Каталог снапшота не найден: {$dir}");
        }
    }

    /** @return array<mixed> */
    public function file(string $name): array
    {
        if (!array_key_exists($name, $this->cache)) {
            $this->cache[$name] = $this->read($this->dir . '/' . $name, required: true);
        }
        return $this->cache[$name];
    }

    /** @return array<mixed>|null */
    public function optional(string $relativePath): ?array
    {
        if (!preg_match('~^[a-z0-9_-]+(/[a-z0-9_-]+)?\.json$~i', $relativePath)) {
            throw new \InvalidArgumentException('Недопустимый путь снапшота');
        }
        return $this->read($this->dir . '/' . $relativePath, required: false);
    }

    /** @return array<mixed>|null */
    private function read(string $path, bool $required): ?array
    {
        if (!is_file($path)) {
            if ($required) {
                throw new \RuntimeException("Нет файла снапшота: {$path}");
            }
            return null;
        }
        $data = json_decode((string) file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($data)) {
            throw new \RuntimeException("Файл снапшота не является JSON-массивом/объектом: {$path}");
        }
        return $data;
    }
}
