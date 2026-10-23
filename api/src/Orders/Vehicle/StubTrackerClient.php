<?php

declare(strict_types=1);

namespace App\Orders\Vehicle;

use App\Integrations\IntegrationNotReady;

/**
 * Заглушка трекеров (VEHICLE_TRACKER=wialon|traccar + TRACKER_API_URL + TRACKER_API_TOKEN).
 * По умолчанию (VEHICLE_TRACKER=none) трекеров нет — только телефон водителя.
 *
 * Что сделать для боевого режима:
 *  - traccar: GET {TRACKER_API_URL}/api/positions?deviceId={id} (Bearer-токен), берём последнюю позицию:
 *    latitude, longitude, accuracy (м; 0 → считать 50), course, fixTime;
 *  - wialon: POST {TRACKER_API_URL}/wialon/ajax.html?svc=token/login → sid; затем
 *    svc=core/search_item&params={"id":<unit>,"flags":1025} → item.pos {y, x, c, t};
 *  - результат обязательно прогонять через VehicleFixFilter, как точки телефона.
 */
final class StubTrackerClient implements TrackerClient
{
    public function __construct(private readonly string $provider)
    {
    }

    public function lastPosition(string $deviceId): ?VehicleFix
    {
        if ($this->provider === 'none') {
            return null;
        }
        throw IntegrationNotReady::for("трекер {$this->provider}", "позиция устройства {$deviceId}");
    }
}
