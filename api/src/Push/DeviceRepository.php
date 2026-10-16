<?php

declare(strict_types=1);

namespace App\Push;

use App\Db\Database;
use App\Support\Clock;
use App\Support\Time;

/**
 * Push-токены устройств. Токен уникален: при входе другим аккаунтом переезжает к новому пользователю.
 */
final class DeviceRepository
{
    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    public function register(int $userId, string $platform, string $token): void
    {
        $now = Time::toDb($this->clock->now());
        // Токен уникален: REPLACE атомарно переносит его к текущему пользователю.
        $this->db->run(
            'REPLACE INTO app_devices (user_id, platform, token, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
            [$userId, $platform, $token, $now, $now],
        );
    }

    /** Снять токен при выходе — только свой (чужой токен этим запросом не удалить). */
    public function unregister(int $userId, string $token): void
    {
        $this->db->run('DELETE FROM app_devices WHERE user_id = ? AND token = ?', [$userId, $token]);
    }

    /** @return list<array{platform: string, token: string}> */
    public function forUser(int $userId): array
    {
        return array_map(
            static fn (array $r) => ['platform' => (string) $r['platform'], 'token' => (string) $r['token']],
            $this->db->all('SELECT platform, token FROM app_devices WHERE user_id = ?', [$userId]),
        );
    }
}
