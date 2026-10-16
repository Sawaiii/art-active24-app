<?php

declare(strict_types=1);

namespace App\Catalog\Snapshot;

use App\Catalog\CatalogRepository;
use App\Catalog\ProductPage;
use App\Catalog\ProductQuery;
use App\Catalog\TextNormalizer;

/**
 * Каталог из снапшота (categories.json, products.json, products/{id}.json).
 * Повторяет поведение сайта: товар виден в разделе, если раздел — его основной (основной раздел)
 * или дополнительный (дополнительный); родитель не агрегирует подразделы автоматически.
 */
final class SnapshotCatalogRepository implements CatalogRepository
{
    private const SUMMARY_KEYS = ['id', 'slug', 'name', 'image', 'price', 'badge', 'template'];
    private const NODE_KEYS = ['id', 'name', 'slug', 'url', 'icon', 'image', 'kind'];

    /** @var array<int, array<string, mixed>>|null */
    private ?array $categoriesById = null;
    /** @var array<int, array<string, mixed>>|null */
    private ?array $productsById = null;

    public function __construct(private readonly SnapshotStore $store)
    {
    }

    public function categoryTree(): array
    {
        return $this->childrenOf(null, deep: true);
    }

    public function categoryPage(int $id): ?array
    {
        $category = $this->categories()[$id] ?? null;
        if ($category === null) {
            return null;
        }
        return [
            'category' => $this->node($category),
            'title' => $category['title'] ?? $category['name'],
            'heroVideo' => $category['heroVideo'] ?? null,
            'breadcrumbs' => $this->ancestors($category),
            'children' => $this->childrenOf($id, deep: false),
            'scenarios' => $category['scenarios'] ?? [],
            'seoHtml' => $category['seoHtml'] ?? null,
        ];
    }

    public function listProducts(ProductQuery $query): ProductPage
    {
        $inCategory = array_values(array_filter(
            $this->products(),
            static fn (array $p) => in_array($query->categoryId, $p['categoryIds'] ?? [], true),
        ));
        $facets = $this->facets($inCategory);

        $filtered = array_values(array_filter($inCategory, fn (array $p) => $this->matches($p, $query)));
        usort($filtered, $this->comparator($query->sort));

        $items = array_map(fn (array $p) => $this->summary($p), array_slice($filtered, $query->offset(), $query->limit));
        return new ProductPage($items, count($filtered), $facets);
    }

    public function product(int $id): ?array
    {
        if (!isset($this->products()[$id])) {
            return null;
        }
        return $this->store->optional("products/{$id}.json");
    }

    public function summaries(array $ids): array
    {
        $out = [];
        foreach ($ids as $id) {
            if (isset($this->products()[$id])) {
                $out[] = $this->summary($this->products()[$id]);
            }
        }
        return $out;
    }

    public function newest(int $limit): array
    {
        $all = $this->products();
        usort($all, static fn (array $a, array $b) => ($a['createdRank'] ?? PHP_INT_MAX) <=> ($b['createdRank'] ?? PHP_INT_MAX));
        return array_map(fn (array $p) => $this->summary($p), array_slice($all, 0, $limit));
    }

    public function resolvePath(string $path): ?array
    {
        $segments = array_values(array_filter(explode('/', trim($path, '/')), static fn ($s) => $s !== ''));
        if ($segments === []) {
            return null;
        }
        foreach ($this->categories() as $category) {
            if (trim((string) parse_url((string) ($category['url'] ?? ''), PHP_URL_PATH), '/') === implode('/', $segments)) {
                return ['type' => 'category', 'id' => (int) $category['id']];
            }
        }
        $product = $this->productBySlug($segments[0]);
        if ($product === null) {
            return null;
        }
        $resolved = ['type' => 'product', 'id' => (int) $product['id']];
        if (isset($segments[1])) {
            foreach ($this->product((int) $product['id'])['variantLinks'] ?? [] as $link) {
                // Слаг варианта хранится либо последним сегментом, либо полным путём «товар/вариант».
                $linkSlug = trim((string) ($link['slug'] ?? ''), '/');
                if ($linkSlug === $segments[1] || $linkSlug === $segments[0] . '/' . $segments[1]) {
                    $resolved += array_filter([
                        'complectId' => $link['complectId'] ?? null,
                        'subId' => $link['subId'] ?? null,
                        'priceType' => $link['priceType'] ?? null,
                    ], static fn ($v) => $v !== null);
                }
            }
        }
        return $resolved;
    }

    public function search(string $query, int $offset, int $limit): array
    {
        $words = TextNormalizer::words($query);
        if ($words === []) {
            return ['products' => [], 'categories' => [], 'total' => 0];
        }
        $phrase = implode(' ', $words);

        $scored = [];
        foreach ($this->products() as $product) {
            $score = $this->score(TextNormalizer::normalize((string) $product['name']), $phrase, $words);
            if ($score > 0) {
                $scored[] = [$score, $product];
            }
        }
        usort($scored, static fn (array $a, array $b) => [$b[0], $a[1]['sortPopular'] ?? 0] <=> [$a[0], $b[1]['sortPopular'] ?? 0]);

        $categories = [];
        foreach ($this->categories() as $category) {
            if ($this->score(TextNormalizer::normalize((string) $category['name']), $phrase, $words) >= 50) {
                $categories[] = $this->node($category);
            }
        }

        return [
            'products' => array_map(fn (array $s) => $this->summary($s[1]), array_slice($scored, $offset, $limit)),
            'categories' => array_slice($categories, 0, 10),
            'total' => count($scored),
        ];
    }

    /** @param list<string> $words */
    private function score(string $haystack, string $phrase, array $words): int
    {
        if ($haystack === '') {
            return 0;
        }
        if (str_contains($haystack, $phrase)) {
            return 100 + (str_starts_with($haystack, $phrase) ? 20 : 0);
        }
        $hits = 0;
        foreach ($words as $word) {
            if (mb_strlen($word) >= 2 && str_contains($haystack, $word)) {
                $hits++;
            }
        }
        return $hits === count($words) ? 50 + $hits : ($hits > 0 ? 10 * $hits : 0);
    }

    /** @param array<string, mixed> $product */
    private function matches(array $product, ProductQuery $query): bool
    {
        $amount = $product['price']['amount'] ?? null;
        if ($query->priceMin !== null || $query->priceMax !== null) {
            if (!is_int($amount) || !empty($product['price']['onRequest'])) {
                return false;
            }
            if ($query->priceMin !== null && $amount < $query->priceMin) {
                return false;
            }
            if ($query->priceMax !== null && $amount > $query->priceMax) {
                return false;
            }
        }
        return $query->colors === [] || array_intersect($query->colors, $product['colors'] ?? []) !== [];
    }

    /** @return callable(array<string, mixed>, array<string, mixed>): int */
    private function comparator(string $sort): callable
    {
        // Товары «по запросу» и без цены при сортировке по цене всегда идут в конце.
        $key = static function (array $p) use ($sort): array {
            $noPrice = !empty($p['price']['onRequest']) || !is_int($p['price']['amount'] ?? null) ? 1 : 0;
            $amount = (int) ($p['price']['amount'] ?? 0);
            $popular = $p['sortPopular'] ?? PHP_INT_MAX;
            return match ($sort) {
                'price_low' => [$noPrice, $amount, $popular],
                'price_high' => [$noPrice, -$amount, $popular],
                'new' => [$p['createdRank'] ?? PHP_INT_MAX],
                default => [$popular],
            };
        };
        return static fn (array $a, array $b): int => $key($a) <=> $key($b);
    }

    /**
     * @param list<array<string, mixed>> $products
     * @return array<string, mixed>
     */
    private function facets(array $products): array
    {
        $prices = [];
        $colors = [];
        foreach ($products as $product) {
            if (is_int($product['price']['amount'] ?? null) && empty($product['price']['onRequest']) && $product['price']['amount'] > 0) {
                $prices[] = $product['price']['amount'];
            }
            foreach ($product['colors'] ?? [] as $color) {
                $colors[$color] = ($colors[$color] ?? 0) + 1;
            }
        }
        arsort($colors);
        return [
            'priceMin' => $prices === [] ? null : min($prices),
            'priceMax' => $prices === [] ? null : max($prices),
            'colors' => array_map(
                static fn (string $name, int $count) => ['name' => $name, 'hex' => ColorPalette::hex($name), 'count' => $count],
                array_map('strval', array_keys($colors)),
                array_values($colors),
            ),
        ];
    }

    /**
     * @param array<string, mixed> $category
     * @return list<array{id: int, name: string}>
     */
    private function ancestors(array $category): array
    {
        $chain = [];
        $parentId = $category['parentId'] ?? null;
        while ($parentId !== null && isset($this->categories()[$parentId]) && count($chain) < 10) {
            $parent = $this->categories()[$parentId];
            array_unshift($chain, ['id' => (int) $parent['id'], 'name' => (string) $parent['name']]);
            $parentId = $parent['parentId'] ?? null;
        }
        return $chain;
    }

    /** @return list<array<string, mixed>> */
    private function childrenOf(?int $parentId, bool $deep): array
    {
        // В меню — только разделы из меню сайта; остальные доступны по ссылке и поиску.
        $children = array_values(array_filter(
            $this->categories(),
            static fn (array $c) => ($c['parentId'] ?? null) === $parentId && ($c['inMenu'] ?? true) !== false,
        ));
        usort($children, static fn (array $a, array $b) => ($a['sort'] ?? 0) <=> ($b['sort'] ?? 0));
        return array_map(function (array $c) use ($deep): array {
            $node = $this->node($c);
            if ($deep) {
                $node['children'] = $this->childrenOf((int) $c['id'], true);
            }
            return $node;
        }, $children);
    }

    /**
     * @param array<string, mixed> $category
     * @return array<string, mixed>
     */
    private function node(array $category): array
    {
        return array_intersect_key($category, array_flip(self::NODE_KEYS));
    }

    /**
     * @param array<string, mixed> $product
     * @return array<string, mixed>
     */
    private function summary(array $product): array
    {
        return array_intersect_key($product, array_flip(self::SUMMARY_KEYS));
    }

    /** @return array<string, mixed>|null */
    private function productBySlug(string $slug): ?array
    {
        foreach ($this->products() as $product) {
            if (($product['slug'] ?? null) === $slug) {
                return $product;
            }
        }
        return null;
    }

    /** @return array<int, array<string, mixed>> */
    private function categories(): array
    {
        if ($this->categoriesById === null) {
            $this->categoriesById = [];
            foreach ($this->store->file('categories.json') as $category) {
                $this->categoriesById[(int) $category['id']] = $category;
            }
        }
        return $this->categoriesById;
    }

    /** @return array<int, array<string, mixed>> */
    private function products(): array
    {
        if ($this->productsById === null) {
            $this->productsById = [];
            foreach ($this->store->file('products.json') as $product) {
                $this->productsById[(int) $product['id']] = $product;
            }
        }
        return $this->productsById;
    }
}
