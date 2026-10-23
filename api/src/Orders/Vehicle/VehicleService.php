<?php

declare(strict_types=1);

namespace App\Orders\Vehicle;

use App\Http\HttpError;
use App\Orders\OrderRepository;
use App\Orders\OrderStatus;
use App\Support\Clock;
use App\Support\Logger;
use App\Support\Time;

/**
 * Машина на карте: менеджер назначает водителя (токен на заказ), приложение водителя шлёт точки,
 * клиент видит последнюю достоверную точку, пока заказ «В пути».
 */
final class VehicleService
{
    /** Пока заказ в этих статусах, водитель может слать точки (выезд раньше смены статуса). */
    private const ACCEPTING = [OrderStatus::Confirmed, OrderStatus::Preparing, OrderStatus::Delivering];

    /** @param list<VehicleLocationSource> $sources */
    public function __construct(
        private readonly OrderRepository $orders,
        private readonly VehicleRepository $vehicles,
        private readonly array $sources,
        private readonly VehicleFixFilter $filter,
        private readonly Clock $clock,
        private readonly Logger $logger,
        private readonly int $staleSeconds = 600,
        private readonly int $tokenTtlHours = 48,
    ) {
    }

    /**
     * @param array<string, mixed> $body DriverAssignmentInput
     * @return array{token: string, expiresAt: string, locationPath: string}
     */
    public function assign(int $orderId, array $body): array
    {
        $this->orders->row($orderId) ?? throw HttpError::notFound('Заказ');
        $driver = $this->text($body['driverName'] ?? null, 100, 'driverName');
        $vehicle = $this->text($body['vehicle'] ?? null, 100, 'vehicle');
        $tracker = $this->text($body['trackerDeviceId'] ?? null, 64, 'trackerDeviceId');
        $token = bin2hex(random_bytes(24));
        $expires = $this->clock->now()->modify("+{$this->tokenTtlHours} hours");
        $this->vehicles->assign($orderId, self::hash($token), $expires, $driver, $vehicle, $tracker);
        return [
            'token' => $token,
            'expiresAt' => Time::toApi(Time::toDb($expires)) ?? '',
            'locationPath' => "/v1/driver/orders/{$orderId}/location",
        ];
    }

    /**
     * Точка от приложения водителя.
     *
     * @param array<string, mixed> $body DriverLocationInput
     * @return array{accepted: bool, reason?: string}
     */
    public function acceptLocation(int $orderId, ?string $token, array $body): array
    {
        $assignment = $token === null || !preg_match('/^[a-f0-9]{48}$/', $token) ? null : $this->vehicles->byTokenHash(self::hash($token));
        $now = $this->clock->now();
        $expired = $assignment === null
            || new \DateTimeImmutable((string) $assignment['token_expires_at'], new \DateTimeZone('UTC')) < $now;
        if ($expired || (int) $assignment['order_id'] !== $orderId) {
            throw new HttpError(401, 'invalid_driver_token', 'Ссылка водителя недействительна — попросите менеджера выдать новую');
        }
        $status = OrderStatus::from((string) ($this->orders->row($orderId)['status'] ?? OrderStatus::Cancelled->value));
        if (!in_array($status, self::ACCEPTING, true)) {
            throw new HttpError(409, 'tracking_closed', 'Заказ уже не в пути — отправка геопозиции не нужна');
        }

        $fix = $this->parseFix($body, $now);
        $reason = $this->filter->reject($fix, VehicleRepository::fixFromRow($assignment), $now);
        if ($reason !== null) {
            $this->vehicles->reject($orderId, $reason);
            $this->logger->info('Точка водителя отклонена', ['order' => $orderId, 'reason' => $reason]);
            return ['accepted' => false, 'reason' => $reason];
        }
        $this->vehicles->saveFix($orderId, $fix);
        return ['accepted' => true];
    }

    /**
     * VehicleLocation для клиента — только пока заказ «В пути».
     *
     * @param array<string, mixed> $order Order
     * @return array<string, mixed>
     */
    public function forCustomer(array $order): array
    {
        if ($order['status'] !== OrderStatus::Delivering->value) {
            throw new HttpError(409, 'tracking_unavailable', 'Машина появится на карте, когда заказ будет в пути');
        }
        $orderId = (int) $order['id'];
        $assignment = $this->vehicles->assignment($orderId);
        [$fix, $source] = $this->freshest($orderId, $assignment);
        $labels = [
            'vehicle' => $assignment['vehicle_label'] ?? null,
            'driverName' => $assignment['driver_name'] ?? null,
        ];
        if ($fix === null) {
            return ['status' => 'unknown'] + $labels;
        }
        $stale = $this->clock->now()->getTimestamp() - $fix->at->getTimestamp() > $this->staleSeconds;
        $status = $stale ? 'unknown' : ($fix->arrived ? 'arrived' : 'enRoute');
        return [
            'status' => $status,
            'lat' => round($fix->lat, 6),
            'lng' => round($fix->lng, 6),
            'accuracy' => round($fix->accuracy),
            'heading' => $fix->heading === null ? null : round($fix->heading),
            'updatedAt' => $fix->at->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d\TH:i:s\Z'),
            'eta' => $status === 'enRoute' && $fix->etaMinutes !== null
                ? $fix->at->modify("+{$fix->etaMinutes} minutes")->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d\TH:i:s\Z')
                : null,
            'source' => $source,
        ] + $labels;
    }

    /**
     * Самая свежая точка из всех источников; сбой источника (трекер недоступен) — пропуск.
     *
     * @param array<string, mixed>|null $assignment
     * @return array{0: ?VehicleFix, 1: ?string}
     */
    private function freshest(int $orderId, ?array $assignment): array
    {
        $best = null;
        $name = null;
        foreach ($this->sources as $source) {
            try {
                $fix = $source->latest($orderId, $assignment);
            } catch (\Throwable $e) {
                $this->logger->error('Машина: источник недоступен', ['source' => $source->name(), 'order' => $orderId, 'message' => $e->getMessage()]);
                continue;
            }
            if ($fix !== null && ($best === null || $fix->at > $best->at)) {
                $best = $fix;
                $name = $source->name();
            }
        }
        return [$best, $name];
    }

    /** @param array<string, mixed> $body */
    private function parseFix(array $body, \DateTimeImmutable $now): VehicleFix
    {
        $errors = [];
        $number = static fn (mixed $v): bool => is_int($v) || is_float($v);
        $lat = $body['lat'] ?? null;
        $lng = $body['lng'] ?? null;
        $accuracy = $body['accuracy'] ?? null;
        if (!$number($lat) || $lat < -90 || $lat > 90) {
            $errors['lat'] = 'Широта — число от −90 до 90';
        }
        if (!$number($lng) || $lng < -180 || $lng > 180) {
            $errors['lng'] = 'Долгота — число от −180 до 180';
        }
        if (!$number($accuracy) || $accuracy <= 0) {
            $errors['accuracy'] = 'Точность — положительное число метров';
        }
        $heading = $body['heading'] ?? null;
        if ($heading !== null && (!$number($heading) || $heading < 0 || $heading > 360)) {
            $errors['heading'] = 'Курс — от 0 до 360';
        }
        $eta = $body['etaMinutes'] ?? null;
        if ($eta !== null && (!is_int($eta) || $eta < 0 || $eta > 1440)) {
            $errors['etaMinutes'] = 'Минуты до прибытия — от 0 до 1440';
        }
        $arrived = $body['arrived'] ?? false;
        if (!is_bool($arrived)) {
            $errors['arrived'] = 'Ожидается true/false';
        }
        $at = $now;
        if (isset($body['recordedAt'])) {
            $parsed = is_string($body['recordedAt']) ? date_create_immutable($body['recordedAt']) : false;
            if ($parsed === false) {
                $errors['recordedAt'] = 'Время в формате ISO-8601';
            } else {
                $at = $parsed->setTimezone(new \DateTimeZone('UTC'));
            }
        }
        if ($errors !== []) {
            throw HttpError::validation($errors);
        }
        return new VehicleFix((float) $lat, (float) $lng, (float) $accuracy, $at, $heading === null ? null : fmod((float) $heading, 360.0), $eta, $arrived === true);
    }

    private function text(mixed $value, int $max, string $field): ?string
    {
        if ($value === null || (is_string($value) && trim($value) === '')) {
            return null;
        }
        if (!is_string($value) || mb_strlen(trim($value)) > $max) {
            throw HttpError::validation([$field => "Не больше {$max} символов"]);
        }
        return trim($value);
    }

    private static function hash(string $token): string
    {
        return hash('sha256', $token);
    }
}
