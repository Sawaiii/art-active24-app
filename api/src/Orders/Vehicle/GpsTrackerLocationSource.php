<?php

declare(strict_types=1);

namespace App\Orders\Vehicle;

/**
 * Положение по GPS-трекеру машины (Wialon / Traccar), если менеджер указал устройство.
 * Точки трекера проходят тот же фильтр подмены, что и точки телефона.
 */
final class GpsTrackerLocationSource implements VehicleLocationSource
{
    public function __construct(
        private readonly TrackerClient $client,
        private readonly VehicleFixFilter $filter,
        private readonly \Closure $now,
    ) {
    }

    public function name(): string
    {
        return 'tracker';
    }

    public function latest(int $orderId, ?array $assignment): ?VehicleFix
    {
        $device = $assignment['tracker_device_id'] ?? null;
        if (!is_string($device) || $device === '') {
            return null;
        }
        $fix = $this->client->lastPosition($device);
        if ($fix === null || $this->filter->reject($fix, null, ($this->now)()) !== null) {
            return null;
        }
        return $fix;
    }
}
