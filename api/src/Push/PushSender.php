<?php

declare(strict_types=1);

namespace App\Push;

/**
 * Push-уведомления на устройства пользователя (APNs/FCM). Сбой доставки не ломает бизнес-операцию.
 */
interface PushSender
{
    /** @param array<string, string> $data */
    public function sendToUser(int $userId, string $title, string $body, array $data): void;
}
