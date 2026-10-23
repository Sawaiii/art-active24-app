<?php

declare(strict_types=1);

namespace App\Orders\Composition;

use App\Db\Database;
use App\Support\Clock;
use App\Support\Time;

/**
 * Состав, приложенный менеджером (PUT /v1/manager/orders/{id}/composition): хранится нормализованным
 * JSON, версия растёт при каждой замене.
 */
final class ManagerCompositionSource implements OrderCompositionSource
{
    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    public function composition(array $order): ?array
    {
        $row = $this->db->one('SELECT * FROM app_order_compositions WHERE order_id = ?', [(int) $order['id']]);
        if ($row === null) {
            return null;
        }
        $payload = json_decode((string) $row['payload_json'], true);
        if (!is_array($payload)) {
            return null;
        }
        return [
            'source' => 'manager',
            'version' => (int) $row['version'],
            'updatedAt' => Time::toApi((string) $row['updated_at']),
        ] + $payload;
    }

    /** @param array<string, mixed> $normalized результат CompositionNormalizer */
    public function save(int $orderId, array $normalized, int $managerId): void
    {
        $now = Time::toDb($this->clock->now());
        $json = json_encode($normalized, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
        $this->db->transaction(function () use ($orderId, $json, $managerId, $now): void {
            $version = (int) $this->db->scalar('SELECT version FROM app_order_compositions WHERE order_id = ?', [$orderId]);
            if ($version === 0) {
                $this->db->insert('app_order_compositions', [
                    'order_id' => $orderId, 'version' => 1, 'payload_json' => $json, 'updated_by' => $managerId, 'updated_at' => $now,
                ]);
                return;
            }
            $this->db->run(
                'UPDATE app_order_compositions SET version = version + 1, payload_json = ?, updated_by = ?, updated_at = ? WHERE order_id = ?',
                [$json, $managerId, $now, $orderId],
            );
        });
    }

    public function delete(int $orderId): void
    {
        $this->db->run('DELETE FROM app_order_compositions WHERE order_id = ?', [$orderId]);
    }
}
