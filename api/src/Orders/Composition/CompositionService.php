<?php

declare(strict_types=1);

namespace App\Orders\Composition;

use App\Support\Logger;

/**
 * Состав заказа: первый источник, у которого он есть, — «Программа КП» → менеджер → корзина.
 * Сбой внешнего источника не ломает экран: логируется, берётся следующий.
 */
final class CompositionService
{
    /** @param list<OrderCompositionSource> $sources по приоритету */
    public function __construct(
        private readonly array $sources,
        private readonly ManagerCompositionSource $manager,
        private readonly CompositionNormalizer $normalizer,
        private readonly Logger $logger,
    ) {
    }

    /**
     * @param array<string, mixed> $order Order + crmDealId, vyzovchatEventId
     * @return array<string, mixed> OrderComposition
     */
    public function forOrder(array $order): array
    {
        foreach ($this->sources as $source) {
            try {
                $composition = $source->composition($order);
            } catch (\Throwable $e) {
                $this->logger->error('Состав заказа: источник недоступен', [
                    'source' => $source::class, 'order' => $order['id'], 'message' => $e->getMessage(),
                ]);
                continue;
            }
            if ($composition !== null) {
                return $composition;
            }
        }
        return [
            'source' => 'none',
            'version' => 1,
            'sections' => [],
            'subtotal' => 0,
            'total' => (int) ($order['total'] ?? 0),
        ];
    }

    /**
     * @param array<string, mixed> $order
     * @param array<string, mixed> $input CompositionInput
     * @return array<string, mixed> OrderComposition (уже из источника «менеджер»)
     */
    public function attach(array $order, array $input, int $managerId): array
    {
        $this->manager->save((int) $order['id'], $this->normalizer->normalize($input), $managerId);
        return $this->manager->composition($order) ?? throw new \LogicException('Состав не сохранён');
    }

    public function detach(int $orderId): void
    {
        $this->manager->delete($orderId);
    }
}
