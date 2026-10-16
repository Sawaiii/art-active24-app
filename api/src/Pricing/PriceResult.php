<?php

declare(strict_types=1);

namespace App\Pricing;

/**
 * Результат расчёта одной позиции.
 */
final class PriceResult
{
    /** @param list<array{name: string, qty: int, price: int}> $extras */
    public function __construct(
        public readonly int $unitPrice,
        public readonly int $total,
        public readonly bool $onRequest,
        public readonly ?string $timeLabel,
        public readonly string $priceLabel,
        public readonly string $qtyUnit,
        public readonly ?string $subTitle,
        public readonly array $extras,
    ) {
    }
}
