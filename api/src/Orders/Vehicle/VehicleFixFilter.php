<?php

declare(strict_types=1);

namespace App\Orders\Vehicle;

/**
 * Отсев недостоверных точек телефона водителя (подмена GPS, «прыжки», грубая точность).
 * Правила по порядку:
 *  - точность хуже 500 м                                  → low_accuracy
 *  - время фикса в будущем больше чем на 2 мин            → clock_skew
 *  - фикс старше последней принятой точки                 → stale
 *  - вне Москвы и области (прямоугольник)                 → out_of_region
 *  - у известной точки подмены (Внуково — туда «телепортирует» глушилка в центре), если
 *    машина не была рядом (предыдущая точка дальше 5 км или её нет) → spoof_point
 *  - скорость от предыдущей точки выше 150 км/ч (с учётом радиусов точности обеих точек) → implausible_speed
 */
final class VehicleFixFilter
{
    public const MAX_ACCURACY_M = 500.0;
    public const MAX_SPEED_KMH = 150.0;
    public const MAX_FUTURE_SKEW_S = 120;
    public const SPOOF_RADIUS_M = 1000.0;
    public const SPOOF_NEARBY_M = 5000.0;

    /** Москва и Московская область: minLat, minLng, maxLat, maxLng. */
    public const MOSCOW_REGION = [54.25, 35.14, 56.96, 40.21];

    /** Внуково — куда смещают координаты глушилки GPS в центре Москвы. */
    public const SPOOF_POINTS = [[55.5915, 37.2615]];

    /**
     * @param array{0: float, 1: float, 2: float, 3: float} $region
     * @param list<array{0: float, 1: float}> $spoofPoints
     */
    public function __construct(
        private readonly array $region = self::MOSCOW_REGION,
        private readonly array $spoofPoints = self::SPOOF_POINTS,
    ) {
    }

    /** @return string|null причина отказа или null — точка достоверна */
    public function reject(VehicleFix $fix, ?VehicleFix $previous, \DateTimeImmutable $now): ?string
    {
        if ($fix->accuracy > self::MAX_ACCURACY_M) {
            return 'low_accuracy';
        }
        if ($fix->at->getTimestamp() - $now->getTimestamp() > self::MAX_FUTURE_SKEW_S) {
            return 'clock_skew';
        }
        if ($previous !== null && $fix->at < $previous->at) {
            return 'stale';
        }
        [$minLat, $minLng, $maxLat, $maxLng] = $this->region;
        if ($fix->lat < $minLat || $fix->lat > $maxLat || $fix->lng < $minLng || $fix->lng > $maxLng) {
            return 'out_of_region';
        }
        foreach ($this->spoofPoints as [$lat, $lng]) {
            $wasNearby = $previous !== null && $previous->distanceTo($lat, $lng) <= self::SPOOF_NEARBY_M;
            if ($fix->distanceTo($lat, $lng) <= self::SPOOF_RADIUS_M && !$wasNearby) {
                return 'spoof_point';
            }
        }
        if ($previous !== null) {
            $seconds = max(1, $fix->at->getTimestamp() - $previous->at->getTimestamp());
            // Погрешность обеих точек не считаем движением: «дрожание» на месте — не скачок.
            $meters = max(0.0, $fix->distanceTo($previous->lat, $previous->lng) - $fix->accuracy - $previous->accuracy);
            if ($meters / $seconds * 3.6 > self::MAX_SPEED_KMH) {
                return 'implausible_speed';
            }
        }
        return null;
    }

    /**
     * Прямоугольник из конфигурации «minLat,minLng,maxLat,maxLng».
     *
     * @return array{0: float, 1: float, 2: float, 3: float}
     */
    public static function parseRegion(?string $value): array
    {
        if ($value === null) {
            return self::MOSCOW_REGION;
        }
        $parts = array_map('trim', explode(',', $value));
        if (count($parts) !== 4 || array_filter($parts, static fn ($p) => !is_numeric($p)) !== []) {
            throw new \RuntimeException('VEHICLE_REGION_BBOX: «minLat,minLng,maxLat,maxLng»');
        }
        $box = array_map('floatval', $parts);
        if ($box[0] >= $box[2] || $box[1] >= $box[3]) {
            throw new \RuntimeException('VEHICLE_REGION_BBOX: min меньше max');
        }
        return [$box[0], $box[1], $box[2], $box[3]];
    }

    /**
     * Точки подмены из конфигурации «lat,lng;lat,lng»; пустая строка «-» — без точек.
     *
     * @return list<array{0: float, 1: float}>
     */
    public static function parsePoints(?string $value): array
    {
        if ($value === null) {
            return self::SPOOF_POINTS;
        }
        if (trim($value) === '-') {
            return [];
        }
        $points = [];
        foreach (array_filter(array_map('trim', explode(';', $value))) as $pair) {
            $xy = array_map('trim', explode(',', $pair));
            if (count($xy) !== 2 || !is_numeric($xy[0]) || !is_numeric($xy[1])) {
                throw new \RuntimeException('VEHICLE_SPOOF_POINTS: «lat,lng;lat,lng»');
            }
            $points[] = [(float) $xy[0], (float) $xy[1]];
        }
        return $points;
    }
}
