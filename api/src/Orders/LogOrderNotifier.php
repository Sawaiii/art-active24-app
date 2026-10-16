<?php

declare(strict_types=1);

namespace App\Orders;

use App\Support\Logger;

/**
 * Для разработки и тестов: уведомления пишутся в лог (в production запрещён — см. Container).
 */
final class LogOrderNotifier implements OrderNotifier
{
    /** @var list<array<string, mixed>> */
    public array $created = [];
    /** @var list<array<string, mixed>> */
    public array $cancelled = [];

    public function __construct(private readonly Logger $logger)
    {
    }

    public function orderCreated(array $order): void
    {
        $this->created[] = $order;
        $this->logger->info("Новая заявка\n" . OrderText::summary($order));
    }

    public function orderCancelled(array $order): void
    {
        $this->cancelled[] = $order;
        $this->logger->info("Заявка {$order['number']} отменена клиентом");
    }
}
