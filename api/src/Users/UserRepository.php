<?php

declare(strict_types=1);

namespace App\Users;

use App\Db\Database;
use App\Support\Clock;
use App\Support\Time;

/**
 * Пользователи приложения (app_users). Возвращает User в форме контракта.
 */
final class UserRepository
{
    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    /** @return array<string, mixed>|null */
    public function find(int $id): ?array
    {
        $row = $this->db->one('SELECT * FROM app_users WHERE id = ?', [$id]);
        return $row === null ? null : $this->toApi($row);
    }

    /** @return array<string, mixed>|null */
    public function findByPhone(string $phone): ?array
    {
        $row = $this->db->one('SELECT * FROM app_users WHERE phone = ?', [$phone]);
        return $row === null ? null : $this->toApi($row);
    }

    /**
     * Найти по телефону или создать. Параллельный первый вход двух устройств не даёт 500:
     * при нарушении UNIQUE перечитываем созданного соседним запросом пользователя.
     *
     * @return array{0: array<string, mixed>, 1: bool} [пользователь, создан ли сейчас]
     */
    public function findOrCreate(string $phone): array
    {
        $existing = $this->findByPhone($phone);
        if ($existing !== null) {
            return [$existing, false];
        }
        $now = Time::toDb($this->clock->now());
        try {
            $id = $this->db->insert('app_users', ['phone' => $phone, 'created_at' => $now, 'updated_at' => $now]);
        } catch (\PDOException $e) {
            if (!Database::isUniqueViolation($e)) {
                throw $e;
            }
            return [$this->findByPhone($phone) ?? throw $e, false];
        }
        return [$this->find($id) ?? throw new \LogicException('Пользователь не создан'), true];
    }

    /**
     * @param array{name?: ?string, email?: ?string, company?: ?string} $fields
     * @return array<string, mixed>
     */
    public function update(int $id, array $fields): array
    {
        $allowed = array_intersect_key($fields, array_flip(['name', 'email', 'company']));
        if ($allowed !== []) {
            $sets = implode(', ', array_map(static fn (string $k) => "{$k} = :{$k}", array_keys($allowed)));
            $params = [':id' => $id, ':updated_at' => Time::toDb($this->clock->now())];
            foreach ($allowed as $key => $value) {
                $params[':' . $key] = $value;
            }
            $this->db->run("UPDATE app_users SET {$sets}, updated_at = :updated_at WHERE id = :id", $params);
        }
        return $this->find($id) ?? throw new \LogicException('Пользователь не найден');
    }

    /**
     * @param array<string, mixed> $row
     * @return array<string, mixed>
     */
    private function toApi(array $row): array
    {
        return [
            'id' => (int) $row['id'],
            'phone' => (string) $row['phone'],
            'name' => $row['name'],
            'email' => $row['email'],
            'company' => $row['company'],
            'role' => (string) $row['role'],
        ];
    }
}
