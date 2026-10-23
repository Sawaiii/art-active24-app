<?php

declare(strict_types=1);

namespace App\Orders\Composition;

/**
 * Состав из «Программы КП» по номеру сделки заказа (crmDealId). Ответ клиента КП проходит
 * ту же проверку, что JSON менеджера, — в приложение не попадёт битый состав.
 */
final class KpCompositionSource implements OrderCompositionSource
{
    public function __construct(
        private readonly KpClient $client,
        private readonly CompositionNormalizer $normalizer,
    ) {
    }

    public function composition(array $order): ?array
    {
        $deal = $order['crmDealId'] ?? null;
        if (!is_string($deal) || $deal === '') {
            return null;
        }
        $proposal = $this->client->proposal($deal);
        if ($proposal === null) {
            return null;
        }
        $revision = $proposal['revision'] ?? 1;
        return [
            'source' => 'kp',
            'version' => is_int($revision) && $revision > 0 ? $revision : 1,
            'updatedAt' => is_string($proposal['updatedAt'] ?? null) ? $proposal['updatedAt'] : null,
        ] + $this->normalizer->normalize($proposal);
    }
}
