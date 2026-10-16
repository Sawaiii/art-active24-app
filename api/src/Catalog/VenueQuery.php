<?php

declare(strict_types=1);

namespace App\Catalog;

use App\Http\Request;

/**
 * Фильтры агрегатора площадок. Внутри одной группы — ИЛИ, между группами — И (как на сайте).
 */
final class VenueQuery
{
    /**
     * @param list<int> $events
     * @param list<int> $types
     * @param list<int> $metro
     * @param list<int> $props
     * @param array<string, array{0: ?int, 1: ?int}> $ranges price|capacity|area → [from, to]
     */
    public function __construct(
        public readonly array $events = [],
        public readonly array $types = [],
        public readonly array $metro = [],
        public readonly array $props = [],
        public readonly array $ranges = [],
        public readonly ?int $collection = null,
        public readonly int $page = 1,
        public readonly int $limit = 24,
    ) {
    }

    public static function fromRequest(Request $request): self
    {
        $ranges = [];
        foreach (['price', 'capacity', 'area'] as $key) {
            $from = isset($request->query[$key . 'From']) ? $request->queryInt($key . 'From', 0, 0, PHP_INT_MAX) : null;
            $to = isset($request->query[$key . 'To']) ? $request->queryInt($key . 'To', 0, 0, PHP_INT_MAX) : null;
            if ($from !== null || $to !== null) {
                $ranges[$key] = [$from, $to];
            }
        }
        return new self(
            self::ids($request->query['events'] ?? ''),
            self::ids($request->query['types'] ?? ''),
            self::ids($request->query['metro'] ?? ''),
            self::ids($request->query['props'] ?? ''),
            $ranges,
            isset($request->query['collection']) ? $request->queryInt('collection', 0, 0, PHP_INT_MAX) : null,
            $request->queryInt('page', 1, 1, 10000),
            $request->queryInt('limit', 24, 1, 60),
        );
    }

    /** @return list<int> */
    private static function ids(string $csv): array
    {
        $ids = [];
        foreach (explode(',', $csv) as $part) {
            if (preg_match('/^\d{1,9}$/', trim($part))) {
                $ids[] = (int) trim($part);
            }
        }
        return array_slice(array_values(array_unique($ids)), 0, 100);
    }
}
