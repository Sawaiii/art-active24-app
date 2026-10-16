<?php

declare(strict_types=1);

namespace App\Db;

use PDO;
use PDOStatement;

/**
 * Тонкая обёртка над PDO: только подготовленные запросы, транзакции, драйвер-зависимые мелочи.
 */
final class Database
{
    private function __construct(private readonly PDO $pdo)
    {
    }

    public static function connect(string $dsn, ?string $user = null, ?string $password = null): self
    {
        $pdo = new PDO($dsn, $user, $password, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_STRINGIFY_FETCHES => false,
        ]);
        if ($pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'sqlite') {
            $pdo->exec('PRAGMA foreign_keys = ON');
            $pdo->exec('PRAGMA journal_mode = WAL');
            $pdo->exec('PRAGMA busy_timeout = 5000');
        } else {
            $pdo->exec("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci");
        }
        return new self($pdo);
    }

    /** Относительный путь SQLite считается от корня api/, а не от текущей папки процесса. */
    public static function resolveDsn(string $dsn, string $root): string
    {
        if (!str_starts_with($dsn, 'sqlite:')) {
            return $dsn;
        }
        $path = substr($dsn, 7);
        $isAbsolute = $path === ':memory:' || str_starts_with($path, '/') || preg_match('~^[A-Za-z]:[\\\\/]~', $path) === 1;
        return $isAbsolute ? $dsn : 'sqlite:' . $root . '/' . $path;
    }

    /** Нарушение UNIQUE/PRIMARY KEY (SQLSTATE 23000 — MySQL и SQLite). */
    public static function isUniqueViolation(\PDOException $e): bool
    {
        return $e->getCode() === '23000' || str_contains($e->getMessage(), 'UNIQUE constraint failed');
    }

    public function driver(): string
    {
        return (string) $this->pdo->getAttribute(PDO::ATTR_DRIVER_NAME);
    }

    /** @param array<string|int, mixed> $params */
    public function run(string $sql, array $params = []): PDOStatement
    {
        $stmt = $this->pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $type = match (true) {
                is_int($value) => PDO::PARAM_INT,
                is_bool($value) => PDO::PARAM_BOOL,
                $value === null => PDO::PARAM_NULL,
                default => PDO::PARAM_STR,
            };
            $stmt->bindValue(is_int($key) ? $key + 1 : $key, $value, $type);
        }
        $stmt->execute();
        return $stmt;
    }

    /**
     * @param array<string|int, mixed> $params
     * @return array<string, mixed>|null
     */
    public function one(string $sql, array $params = []): ?array
    {
        $row = $this->run($sql, $params)->fetch();
        return $row === false ? null : $row;
    }

    /**
     * @param array<string|int, mixed> $params
     * @return list<array<string, mixed>>
     */
    public function all(string $sql, array $params = []): array
    {
        return $this->run($sql, $params)->fetchAll();
    }

    /** @param array<string|int, mixed> $params */
    public function scalar(string $sql, array $params = []): mixed
    {
        $value = $this->run($sql, $params)->fetchColumn();
        return $value === false ? null : $value;
    }

    /** @param array<string, mixed> $row */
    public function insert(string $table, array $row): int
    {
        $columns = array_keys($row);
        $sql = sprintf(
            'INSERT INTO %s (%s) VALUES (%s)',
            $table,
            implode(', ', $columns),
            implode(', ', array_map(static fn ($c) => ':' . $c, $columns)),
        );
        $this->run($sql, array_combine(array_map(static fn ($c) => ':' . $c, $columns), array_values($row)));
        return (int) $this->pdo->lastInsertId();
    }

    /**
     * @template T
     * @param callable(): T $fn
     * @return T
     */
    public function transaction(callable $fn): mixed
    {
        $this->pdo->beginTransaction();
        try {
            $result = $fn();
            // MySQL неявно коммитит DDL — транзакции к этому моменту уже может не быть.
            if ($this->pdo->inTransaction()) {
                $this->pdo->commit();
            }
            return $result;
        } catch (\Throwable $e) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }
            throw $e;
        }
    }

    public function exec(string $sql): void
    {
        $this->pdo->exec($sql);
    }
}
