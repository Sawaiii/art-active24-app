<?php

declare(strict_types=1);

namespace App\Orders\Feedback;

use App\Db\Database;
use App\Support\Clock;
use App\Support\Time;

/**
 * Отзывы (один на заказ) и претензии клиентов.
 */
final class FeedbackRepository
{
    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    // MARK: Отзывы

    /** @return array<string, mixed>|null строка app_order_reviews */
    public function review(int $orderId): ?array
    {
        return $this->db->one('SELECT * FROM app_order_reviews WHERE order_id = ?', [$orderId]);
    }

    /**
     * @param list<int> $orderIds
     * @return array<int, array<string, mixed>> order_id → строка
     */
    public function reviewsFor(array $orderIds): array
    {
        if ($orderIds === []) {
            return [];
        }
        $in = implode(',', array_fill(0, count($orderIds), '?'));
        $out = [];
        foreach ($this->db->all("SELECT * FROM app_order_reviews WHERE order_id IN ({$in})", $orderIds) as $row) {
            $out[(int) $row['order_id']] = $row;
        }
        return $out;
    }

    /** @return bool true — создан, false — изменён */
    public function saveReview(int $orderId, int $userId, int $rating, ?string $text): bool
    {
        $now = Time::toDb($this->clock->now());
        if ($this->review($orderId) === null) {
            try {
                $this->db->insert('app_order_reviews', [
                    'order_id' => $orderId, 'user_id' => $userId, 'rating' => $rating, 'text' => $text,
                    'created_at' => $now, 'updated_at' => $now,
                ]);
                return true;
            } catch (\PDOException $e) {
                // Параллельный первый отзыв с другого устройства — дальше как правка.
                if (!Database::isUniqueViolation($e)) {
                    throw $e;
                }
            }
        }
        $this->db->run(
            'UPDATE app_order_reviews SET rating = ?, text = ?, updated_at = ?, forwarded_at = NULL WHERE order_id = ?',
            [$rating, $text, $now, $orderId],
        );
        return false;
    }

    public function markReviewForwarded(int $orderId): void
    {
        $this->db->run('UPDATE app_order_reviews SET forwarded_at = ? WHERE order_id = ?', [Time::toDb($this->clock->now()), $orderId]);
    }

    // MARK: Претензии

    /** @param array<string, mixed> $row колонки без id/времени */
    public function createClaim(array $row): int
    {
        $now = Time::toDb($this->clock->now());
        return $this->db->insert('app_order_claims', $row + ['created_at' => $now, 'updated_at' => $now]);
    }

    /** @return array<string, mixed>|null */
    public function claim(int $id): ?array
    {
        return $this->db->one(
            'SELECT c.*, o.number AS order_number FROM app_order_claims c JOIN app_orders o ON o.id = c.order_id WHERE c.id = ?',
            [$id],
        );
    }

    /**
     * @param list<int> $orderIds
     * @return array<int, list<array<string, mixed>>> order_id → претензии (новые первыми)
     */
    public function claimsFor(array $orderIds): array
    {
        if ($orderIds === []) {
            return [];
        }
        $in = implode(',', array_fill(0, count($orderIds), '?'));
        $out = [];
        foreach ($this->db->all(
            "SELECT c.*, o.number AS order_number FROM app_order_claims c JOIN app_orders o ON o.id = c.order_id
             WHERE c.order_id IN ({$in}) ORDER BY c.id DESC",
            $orderIds,
        ) as $row) {
            $out[(int) $row['order_id']][] = $row;
        }
        return $out;
    }

    /** @param list<string> $statuses */
    public function countClaims(int $orderId, array $statuses): int
    {
        $in = implode(',', array_fill(0, count($statuses), '?'));
        return (int) $this->db->scalar(
            "SELECT COUNT(*) FROM app_order_claims WHERE order_id = ? AND status IN ({$in})",
            [$orderId, ...$statuses],
        );
    }

    /** @return array{items: list<array<string, mixed>>, total: int} */
    public function claimsForManager(?string $status, int $offset, int $limit): array
    {
        $where = $status === null ? '' : 'WHERE c.status = ?';
        $params = $status === null ? [] : [$status];
        return [
            'items' => $this->db->all(
                "SELECT c.*, o.number AS order_number FROM app_order_claims c JOIN app_orders o ON o.id = c.order_id
                 {$where} ORDER BY c.id DESC LIMIT ? OFFSET ?",
                [...$params, $limit, $offset],
            ),
            'total' => (int) $this->db->scalar("SELECT COUNT(*) FROM app_order_claims c {$where}", $params),
        ];
    }

    /**
     * Смена статуса, только если он всё ещё $from (гонка двух менеджеров).
     *
     * @param array<string, mixed> $fields manager_comment, chat_url, chat_app_url
     */
    public function moveClaim(int $id, string $from, string $to, array $fields): bool
    {
        $allowed = array_intersect_key($fields, array_flip(['manager_comment', 'chat_url', 'chat_app_url']));
        $sets = ['status = ?', 'updated_at = ?'];
        $params = [$to, Time::toDb($this->clock->now())];
        foreach ($allowed as $column => $value) {
            $sets[] = "{$column} = ?";
            $params[] = $value;
        }
        return $this->db->run(
            'UPDATE app_order_claims SET ' . implode(', ', $sets) . ' WHERE id = ? AND status = ?',
            [...$params, $id, $from],
        )->rowCount() === 1;
    }
}
