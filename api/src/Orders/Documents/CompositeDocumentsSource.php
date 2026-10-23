<?php

declare(strict_types=1);

namespace App\Orders\Documents;

use App\Support\Logger;

/**
 * Все документы заказа из всех источников, новые первыми. Недоступный источник (CRM лежит) —
 * в лог, остальные документы клиент всё равно видит.
 */
final class CompositeDocumentsSource implements OrderDocumentsSource
{
    /** @param list<OrderDocumentsSource> $sources */
    public function __construct(
        private readonly array $sources,
        private readonly Logger $logger,
    ) {
    }

    public function documents(array $order): array
    {
        $all = [];
        foreach ($this->sources as $source) {
            try {
                array_push($all, ...$source->documents($order));
            } catch (\Throwable $e) {
                $this->logger->error('Документы заказа: источник недоступен', [
                    'source' => $source::class, 'order' => $order['id'] ?? null, 'message' => $e->getMessage(),
                ]);
            }
        }
        usort($all, static fn (array $a, array $b) => [($b['date'] ?? ''), $a['title']] <=> [($a['date'] ?? ''), $b['title']]);
        return $all;
    }
}
