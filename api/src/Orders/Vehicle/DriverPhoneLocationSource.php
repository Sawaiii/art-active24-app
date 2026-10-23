<?php

declare(strict_types=1);

namespace App\Orders\Vehicle;

/**
 * Последняя достоверная точка, присланная приложением водителя (POST /v1/driver/orders/{id}/location).
 */
final class DriverPhoneLocationSource implements VehicleLocationSource
{
    public function name(): string
    {
        return 'driver';
    }

    public function latest(int $orderId, ?array $assignment): ?VehicleFix
    {
        return $assignment === null ? null : VehicleRepository::fixFromRow($assignment);
    }
}
