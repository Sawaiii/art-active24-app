<?php

declare(strict_types=1);

namespace App\Auth;

use App\Db\Database;
use App\Http\HttpError;
use App\Support\Clock;
use App\Support\Time;

/**
 * Сессии на непрозрачных токенах: в БД хранятся только SHA-256 хеши.
 * Access живёт 30 минут, refresh — 60 дней и ротируется при каждом обновлении.
 */
final class SessionService
{
    public const ACCESS_TTL = 1800;
    private const REFRESH_TTL = 60 * 86400;
    /** Сессия живёт не дольше 180 дней от входа, даже при регулярном обновлении. */
    private const ABSOLUTE_TTL = 180 * 86400;

    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    /** @return array{accessToken: string, refreshToken: string, expiresIn: int} */
    public function issue(int $userId, ?string $userAgent): array
    {
        [$access, $refresh] = [$this->token(), $this->token()];
        $now = $this->clock->now();
        $this->db->insert('app_sessions', [
            'user_id' => $userId,
            'access_hash' => hash('sha256', $access),
            'access_expires_at' => Time::toDb($now->modify('+' . self::ACCESS_TTL . ' seconds')),
            'refresh_hash' => hash('sha256', $refresh),
            'refresh_expires_at' => Time::toDb($now->modify('+' . self::REFRESH_TTL . ' seconds')),
            'user_agent' => $userAgent === null ? null : mb_substr($userAgent, 0, 255),
            'created_at' => Time::toDb($now),
            'last_used_at' => Time::toDb($now),
        ]);
        return ['accessToken' => $access, 'refreshToken' => $refresh, 'expiresIn' => self::ACCESS_TTL];
    }

    /** @return int|null id пользователя для действующего access-токена */
    public function authenticate(string $accessToken): ?int
    {
        $row = $this->db->one(
            'SELECT id, user_id, access_expires_at FROM app_sessions WHERE access_hash = ? AND revoked_at IS NULL',
            [hash('sha256', $accessToken)],
        );
        if ($row === null || Time::toDb($this->clock->now()) > (string) $row['access_expires_at']) {
            return null;
        }
        return (int) $row['user_id'];
    }

    /** @return array{userId: int, accessToken: string, refreshToken: string, expiresIn: int} */
    public function refresh(string $refreshToken): array
    {
        $oldHash = hash('sha256', $refreshToken);
        $row = $this->db->one(
            'SELECT id, user_id, refresh_expires_at, created_at FROM app_sessions WHERE refresh_hash = ? AND revoked_at IS NULL',
            [$oldHash],
        );
        $now = $this->clock->now();
        $absoluteEnd = $row === null ? null
            : (new \DateTimeImmutable((string) $row['created_at'], new \DateTimeZone('UTC')))->modify('+' . self::ABSOLUTE_TTL . ' seconds');
        if ($row === null || Time::toDb($now) > (string) $row['refresh_expires_at'] || $now > $absoluteEnd) {
            throw HttpError::unauthorized('Сессия истекла, войдите снова');
        }
        [$access, $refresh] = [$this->token(), $this->token()];
        // Условие по старому хешу: из двух параллельных обновлений одним токеном выигрывает ровно одно.
        $updated = $this->db->run(
            'UPDATE app_sessions SET access_hash = ?, access_expires_at = ?, refresh_hash = ?, refresh_expires_at = ?, last_used_at = ?
             WHERE id = ? AND refresh_hash = ? AND revoked_at IS NULL',
            [
                hash('sha256', $access),
                Time::toDb($now->modify('+' . self::ACCESS_TTL . ' seconds')),
                hash('sha256', $refresh),
                Time::toDb(min($now->modify('+' . self::REFRESH_TTL . ' seconds'), $absoluteEnd)),
                Time::toDb($now),
                (int) $row['id'],
                $oldHash,
            ],
        )->rowCount();
        if ($updated !== 1) {
            throw HttpError::unauthorized('Сессия обновлена на другом запросе, войдите снова');
        }
        return ['userId' => (int) $row['user_id'], 'accessToken' => $access, 'refreshToken' => $refresh, 'expiresIn' => self::ACCESS_TTL];
    }

    public function revoke(string $accessToken): void
    {
        $this->db->run(
            'UPDATE app_sessions SET revoked_at = ? WHERE access_hash = ?',
            [Time::toDb($this->clock->now()), hash('sha256', $accessToken)],
        );
    }

    private function token(): string
    {
        return rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
    }
}
