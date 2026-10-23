<?php

declare(strict_types=1);

namespace App\Orders\Vehicle;

/**
 * Источник положения машины заказа: телефон водителя (DriverPhoneLocationSource) или
 * GPS-трекер (GpsTrackerLocationSource: Wialon / Traccar).
 */
interface VehicleLocationSource
{
    /** «driver» | «tracker» — поле source в VehicleLocation. */
    public function name(): string;

    /** @param array<string, mixed>|null $assignment строка app_order_vehicles (может не быть) */
    public function latest(int $orderId, ?array $assignment): ?VehicleFix;
}
