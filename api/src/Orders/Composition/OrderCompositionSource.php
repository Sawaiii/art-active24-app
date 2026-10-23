<?php

declare(strict_types=1);

namespace App\Orders\Composition;

/**
 * Источник состава заказа (OrderComposition контракта). Реализации:
 * KpCompositionSource («Программа КП», по номеру сделки), ManagerCompositionSource (JSON от менеджера),
 * CartCompositionSource (позиции корзины заказа — запасной вариант).
 */
interface OrderCompositionSource
{
    /**
     * @param array<string, mixed> $order Order (контракт) + crmDealId, vyzovchatEventId
     * @return array<string, mixed>|null OrderComposition или null — у источника состава нет
     */
    public function composition(array $order): ?array;
}
