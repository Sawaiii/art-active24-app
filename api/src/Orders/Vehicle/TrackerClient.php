<?php

declare(strict_types=1);

namespace App\Orders\Vehicle;

/**
 * Клиент сервиса GPS-трекеров. Устройство машины указывает менеджер при назначении (trackerDeviceId).
 */
interface TrackerClient
{
    public function lastPosition(string $deviceId): ?VehicleFix;
}
