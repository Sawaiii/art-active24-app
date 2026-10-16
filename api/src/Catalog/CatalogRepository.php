<?php

declare(strict_types=1);

namespace App\Catalog;

/**
 * Каталог товаров. Реализации: SnapshotCatalogRepository (dev) и MysqlCatalogRepository (прод, по схеме БД CMS).
 * Все методы возвращают данные в форме контракта API (contract/openapi.yaml).
 */
interface CatalogRepository
{
    /** @return list<array<string, mixed>> дерево CategoryNode */
    public function categoryTree(): array;

    /** @return array<string, mixed>|null CategoryPage */
    public function categoryPage(int $id): ?array;

    public function listProducts(ProductQuery $query): ProductPage;

    /** @return array<string, mixed>|null Product */
    public function product(int $id): ?array;

    /**
     * @param list<int> $ids
     * @return list<array<string, mixed>> ProductSummary в порядке $ids (несуществующие пропускаются)
     */
    public function summaries(array $ids): array;

    /** @return list<array<string, mixed>> последние добавленные товары */
    public function newest(int $limit): array;

    /** @return array<string, mixed>|null {type, id, complectId?, subId?, priceType?} */
    public function resolvePath(string $path): ?array;

    /** @return array{products: list<array<string, mixed>>, categories: list<array<string, mixed>>, total: int} */
    public function search(string $query, int $offset, int $limit): array;
}
