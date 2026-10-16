<?php

declare(strict_types=1);

namespace App\Orders;

/**
 * Уведомление менеджеров о заявках (почта, CRM сайта). Вызывается после записи в БД;
 * OrderService гасит исключения уведомителя — сбой почты не превращает созданную заявку в ошибку.
 */
interface OrderNotifier
{
    /** @param array<string, mixed> $order Order (форма контракта) */
    public function orderCreated(array $order): void;

    /** @param array<string, mixed> $order Order после отмены клиентом */
    public function orderCancelled(array $order): void;
}
