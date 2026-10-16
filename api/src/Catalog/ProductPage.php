<?php

declare(strict_types=1);

namespace App\Catalog;

/**
 * Страница листинга: товары + общее число + фасеты для фильтров.
 */
final class ProductPage
{
    /**
     * @param list<array<string, mixed>> $items ProductSummary
     * @param array<string, mixed> $facets ProductFacets
     */
    public function __construct(
        public readonly array $items,
        public readonly int $total,
        public readonly array $facets,
    ) {
    }
}
