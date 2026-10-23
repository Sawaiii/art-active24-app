<?php

declare(strict_types=1);

namespace App\Orders\Vehicle;

/**
 * Точка машины: координаты, радиус точности (м), курс, время фикса, оценка прибытия.
 */
final class VehicleFix
{
    public function __construct(
        public readonly float $lat,
        public readonly float $lng,
        public readonly float $accuracy,
        public readonly \DateTimeImmutable $at,
        public readonly ?float $heading = null,
        public readonly ?int $etaMinutes = null,
        public readonly bool $arrived = false,
    ) {
    }

    /** Расстояние по большой окружности, м. */
    public function distanceTo(float $lat, float $lng): float
    {
        return self::distance($this->lat, $this->lng, $lat, $lng);
    }

    public static function distance(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earth = 6_371_000.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;
        return 2 * $earth * asin(min(1.0, sqrt($a)));
    }
}
