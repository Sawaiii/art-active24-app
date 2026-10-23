<?php

declare(strict_types=1);

namespace App\Orders\Documents;

/**
 * Источник документов заказа (OrderDocument контракта): CRM, Вызов Чат, ссылки менеджера.
 */
interface OrderDocumentsSource
{
    /**
     * @param array<string, mixed> $order Order + crmDealId, vyzovchatEventId
     * @return list<array<string, mixed>> OrderDocument
     */
    public function documents(array $order): array;
}
