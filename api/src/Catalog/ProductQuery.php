<?php

declare(strict_types=1);

namespace App\Catalog;

use App\Http\HttpError;
use App\Http\Request;

/**
 * Параметры листинга раздела: сортировка, фильтры, страница.
 */
final class ProductQuery
{
    public const SORTS = ['popular', 'price_low', 'price_high', 'new'];

    /** @param list<string> $colors */
    public function __construct(
        public readonly int $categoryId,
        public readonly string $sort = 'popular',
        public readonly ?int $priceMin = null,
        public readonly ?int $priceMax = null,
        public readonly array $colors = [],
        public readonly int $page = 1,
        public readonly int $limit = 24,
    ) {
    }

    public static function fromRequest(int $categoryId, Request $request): self
    {
        $sort = $request->query['sort'] ?? 'popular';
        if (!in_array($sort, self::SORTS, true)) {
            throw HttpError::badRequest('invalid_sort', 'Неизвестная сортировка');
        }
        $priceMin = isset($request->query['priceMin']) ? $request->queryInt('priceMin', 0, 0, PHP_INT_MAX) : null;
        $priceMax = isset($request->query['priceMax']) ? $request->queryInt('priceMax', 0, 0, PHP_INT_MAX) : null;
        $colors = array_values(array_filter(
            array_map('trim', explode(',', $request->query['colors'] ?? '')),
            static fn (string $c) => $c !== '' && mb_strlen($c) <= 40,
        ));

        return new self(
            $categoryId,
            $sort,
            $priceMin,
            $priceMax,
            array_slice($colors, 0, 20),
            $request->queryInt('page', 1, 1, 10000),
            $request->queryInt('limit', 24, 1, 60),
        );
    }

    public function offset(): int
    {
        return ($this->page - 1) * $this->limit;
    }
}
