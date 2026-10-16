<?php

declare(strict_types=1);

namespace App\Push;

use App\Support\Logger;

/**
 * Пока ключи APNs/FCM не выданы: push пишется в лог. Реальная отправка — FcmPushSender (см. api/README.md).
 */
final class LogPushSender implements PushSender
{
    /** @var list<array{userId: int, title: string, body: string, data: array<string, string>}> */
    public array $sent = [];

    public function __construct(private readonly Logger $logger)
    {
    }

    public function sendToUser(int $userId, string $title, string $body, array $data): void
    {
        $this->sent[] = ['userId' => $userId, 'title' => $title, 'body' => $body, 'data' => $data];
        $this->logger->info('push', ['userId' => $userId, 'title' => $title, 'body' => $body, 'data' => $data]);
    }
}
