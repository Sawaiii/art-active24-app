<?php

declare(strict_types=1);

namespace App\Orders\Vehicle;

use App\Db\Database;
use App\Support\Clock;
use App\Support\Time;

/**
 * Машина заказа (app_order_vehicles): токен водителя (хеш), подписи, последняя достоверная точка.
 */
final class VehicleRepository
{
    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    /** @return array<string, mixed>|null */
    public function assignment(int $orderId): ?array
    {
        return $this->db->one('SELECT * FROM app_order_vehicles WHERE order_id = ?', [$orderId]);
    }

    /** @return array<string, mixed>|null назначение по хешу токена водителя */
    public function byTokenHash(string $hash): ?array
    {
        return $this->db->one('SELECT * FROM app_order_vehicles WHERE token_hash = ?', [$hash]);
    }

    /** Новое назначение или замена токена (прежний токен перестаёт действовать); точка сохраняется. */
    public function assign(int $orderId, string $tokenHash, \DateTimeImmutable $expiresAt, ?string $driver, ?string $vehicle, ?string $trackerId): void
    {
        $now = Time::toDb($this->clock->now());
        $fields = [
            'token_hash' => $tokenHash,
            'token_expires_at' => Time::toDb($expiresAt),
            'driver_name' => $driver,
            'vehicle_label' => $vehicle,
            'tracker_device_id' => $trackerId,
        ];
        $this->db->transaction(function () use ($orderId, $fields, $now): void {
            if ($this->assignment($orderId) === null) {
                $this->db->insert('app_order_vehicles', ['order_id' => $orderId] + $fields + ['created_at' => $now, 'updated_at' => $now]);
                return;
            }
            $this->db->run(
                'UPDATE app_order_vehicles SET token_hash = ?, token_expires_at = ?, driver_name = ?, vehicle_label = ?,
                 tracker_device_id = ?, updated_at = ? WHERE order_id = ?',
                [...array_values($fields), $now, $orderId],
            );
        });
    }

    public function lastFix(int $orderId): ?VehicleFix
    {
        $row = $this->assignment($orderId);
        return $row === null ? null : self::fixFromRow($row);
    }

    public function saveFix(int $orderId, VehicleFix $fix): void
    {
        $this->db->run(
            'UPDATE app_order_vehicles SET lat = ?, lng = ?, accuracy = ?, heading = ?, eta_minutes = ?, arrived = ?,
             fix_at = ?, received_at = ?, updated_at = ? WHERE order_id = ?',
            [
                $fix->lat, $fix->lng, $fix->accuracy, $fix->heading, $fix->etaMinutes, $fix->arrived ? 1 : 0,
                Time::toDb($fix->at), Time::toDb($this->clock->now()), Time::toDb($this->clock->now()), $orderId,
            ],
        );
    }

    public function reject(int $orderId, string $reason): void
    {
        $this->db->run(
            'UPDATE app_order_vehicles SET rejected_count = rejected_count + 1, last_reject_reason = ? WHERE order_id = ?',
            [$reason, $orderId],
        );
    }

    /** @param array<string, mixed> $row */
    public static function fixFromRow(array $row): ?VehicleFix
    {
        if ($row['lat'] === null || $row['lng'] === null || $row['fix_at'] === null) {
            return null;
        }
        return new VehicleFix(
            (float) $row['lat'],
            (float) $row['lng'],
            (float) $row['accuracy'],
            new \DateTimeImmutable((string) $row['fix_at'], new \DateTimeZone('UTC')),
            $row['heading'] === null ? null : (float) $row['heading'],
            $row['eta_minutes'] === null ? null : (int) $row['eta_minutes'],
            (bool) $row['arrived'],
        );
    }
}
