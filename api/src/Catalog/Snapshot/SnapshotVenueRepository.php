<?php

declare(strict_types=1);

namespace App\Catalog\Snapshot;

use App\Catalog\VenueQuery;
use App\Catalog\VenueRepository;

/**
 * Площадки из снапшота (venues.json, venues/{id}.json, venue-filters.json).
 * Фасеты считаются как на сайте: счётчик опции группы — с учётом фильтров ДРУГИХ групп.
 */
final class SnapshotVenueRepository implements VenueRepository
{
    private const SUMMARY_KEYS = ['id', 'slug', 'name', 'type', 'photos', 'area', 'capacity', 'address', 'metro', 'price'];
    private const GROUPS = ['events' => 'events', 'types' => 'types', 'metro' => 'metroIds', 'props' => 'props'];
    private const RANGE_FIELDS = ['price' => 'priceAmount', 'capacity' => 'capacity', 'area' => 'area'];

    public function __construct(private readonly SnapshotStore $store)
    {
    }

    public function list(VenueQuery $query): array
    {
        $all = $this->store->file('venues.json');
        $matching = array_values(array_filter($all, fn (array $v) => $this->matches($v, $query, null)));
        usort($matching, static fn (array $a, array $b) => ($a['sortPopular'] ?? PHP_INT_MAX) <=> ($b['sortPopular'] ?? PHP_INT_MAX));

        $counts = [];
        foreach (self::GROUPS as $group => $field) {
            $counts[$group] = [];
            foreach ($all as $venue) {
                if (!$this->matches($venue, $query, $group)) {
                    continue;
                }
                foreach ($venue[$field] ?? [] as $id) {
                    $counts[$group][(int) $id] = ($counts[$group][(int) $id] ?? 0) + 1;
                }
            }
        }

        $offset = ($query->page - 1) * $query->limit;
        return [
            'items' => array_map(
                static fn (array $v) => array_intersect_key($v, array_flip(self::SUMMARY_KEYS)),
                array_slice($matching, $offset, $query->limit),
            ),
            'total' => count($matching),
            'counts' => $counts,
        ];
    }

    public function filters(): array
    {
        return $this->store->file('venue-filters.json');
    }

    public function venue(int $id): ?array
    {
        return $this->store->optional("venues/{$id}.json");
    }

    public function idBySlug(string $slug): ?int
    {
        foreach ($this->store->file('venues.json') as $venue) {
            if (($venue['slug'] ?? null) === $slug) {
                return (int) $venue['id'];
            }
        }
        return null;
    }

    /** @param array<string, mixed> $venue */
    private function matches(array $venue, VenueQuery $query, ?string $skipGroup): bool
    {
        $selected = ['events' => $query->events, 'types' => $query->types, 'metro' => $query->metro, 'props' => $query->props];
        foreach (self::GROUPS as $group => $field) {
            if ($group === $skipGroup || $selected[$group] === []) {
                continue;
            }
            $values = array_map('intval', $venue[$field] ?? []);
            // Удобства — все выбранные должны быть; остальные группы — любое из выбранных.
            $ok = $group === 'props'
                ? array_diff($selected[$group], $values) === []
                : array_intersect($selected[$group], $values) !== [];
            if (!$ok) {
                return false;
            }
        }
        if ($query->collection !== null && !in_array($query->collection, $venue['collections'] ?? [], true)) {
            return false;
        }
        foreach ($query->ranges as $key => [$from, $to]) {
            $value = $venue[self::RANGE_FIELDS[$key]] ?? null;
            if (!is_int($value) || ($from !== null && $value < $from) || ($to !== null && $value > $to)) {
                return false;
            }
        }
        return true;
    }
}
