<?php

declare(strict_types=1);

namespace App\Support;

use App\Db\Database;
use App\Http\HttpError;

/**
 * Ограничение частоты (фиксированное окно) в таблице app_rate_limits.
 * Каждый шаг — одиночный атомарный UPDATE/INSERT, поэтому параллельные запросы не обходят лимит.
 */
final class RateLimiter
{
    private const MAX_RACE_RETRIES = 3;

    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    /** IPv6 считаем по /64 (одному абоненту обычно выдаётся вся подсеть), IPv4 — целиком. */
    public static function ipBucket(string $ip): string
    {
        $packed = @inet_pton($ip);
        if ($packed === false || strlen($packed) !== 16) {
            return $ip;
        }
        return bin2hex(substr($packed, 0, 8)) . '::/64';
    }

    /** @throws HttpError 429, если лимит исчерпан */
    public function hit(string $bucket, int $limit, int $windowSeconds): void
    {
        $now = $this->clock->now();
        $cutoff = Time::toDb($now->modify("-{$windowSeconds} seconds"));

        for ($attempt = 0; $attempt < self::MAX_RACE_RETRIES; $attempt++) {
            // 1. Окно открыто — увеличить счётчик.
            if ($this->db->run(
                'UPDATE app_rate_limits SET hits = hits + 1 WHERE bucket = ? AND window_start > ?',
                [$bucket, $cutoff],
            )->rowCount() === 1) {
                $this->assertWithinLimit($bucket, $limit, $windowSeconds, $now);
                return;
            }
            // 2. Окно истекло — начать новое.
            if ($this->db->run(
                'UPDATE app_rate_limits SET hits = 1, window_start = ? WHERE bucket = ? AND window_start <= ?',
                [Time::toDb($now), $bucket, $cutoff],
            )->rowCount() === 1) {
                return;
            }
            // 3. Записи нет — создать; при гонке с другим запросом повторить с шага 1.
            try {
                $this->db->insert('app_rate_limits', ['bucket' => $bucket, 'window_start' => Time::toDb($now), 'hits' => 1]);
                return;
            } catch (\PDOException $e) {
                if (!Database::isUniqueViolation($e)) {
                    throw $e;
                }
            }
        }
        throw new \RuntimeException("Не удалось обновить лимит {$bucket}");
    }

    private function assertWithinLimit(string $bucket, int $limit, int $windowSeconds, \DateTimeImmutable $now): void
    {
        $row = $this->db->one('SELECT window_start, hits FROM app_rate_limits WHERE bucket = ?', [$bucket]);
        if ($row === null || (int) $row['hits'] <= $limit) {
            return;
        }
        $start = new \DateTimeImmutable((string) $row['window_start'], new \DateTimeZone('UTC'));
        throw HttpError::tooManyRequests(max(1, $windowSeconds - ($now->getTimestamp() - $start->getTimestamp())));
    }
}
