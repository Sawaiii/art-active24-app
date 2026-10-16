<?php

declare(strict_types=1);

namespace App\Catalog;

/**
 * Площадки (шаблон 119 «Площадка агрегатор»).
 */
interface VenueRepository
{
    /** @return array{items: list<array<string, mixed>>, total: int, counts: array<string, array<int, int>>} */
    public function list(VenueQuery $query): array;

    /** @return array<string, mixed> VenueFilters */
    public function filters(): array;

    /** @return array<string, mixed>|null Venue */
    public function venue(int $id): ?array;

    public function idBySlug(string $slug): ?int;
}
