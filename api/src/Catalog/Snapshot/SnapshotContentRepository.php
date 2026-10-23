<?php

declare(strict_types=1);

namespace App\Catalog\Snapshot;

use App\Catalog\CatalogRepository;
use App\Catalog\ContentRepository;

/**
 * Главная, справочная информация, «Акции» и кейсы из снапшота
 * (home.json, info.json, sale.json, cases.json, cases/{slug}.json).
 * Секции главной и кейсы со списком id товаров дополняются карточками из каталога.
 */
final class SnapshotContentRepository implements ContentRepository
{
    /** Slug кейса — как в адресе сайта /cases/{slug}/. */
    public const CASE_SLUG_PATTERN = '/^[a-z0-9][a-z0-9_-]{0,99}$/';

    public function __construct(
        private readonly SnapshotStore $store,
        private readonly CatalogRepository $catalog,
    ) {
    }

    public function home(): array
    {
        $sections = [];
        foreach ($this->store->file('home.json')['sections'] ?? [] as $section) {
            $type = $section['type'] ?? null;
            if ($type === 'products') {
                $ids = array_map('intval', $section['productIds'] ?? []);
                $section['products'] = $ids === [] ? $this->catalog->newest(10) : $this->catalog->summaries($ids);
                unset($section['productIds']);
            } elseif ($type === 'cases') {
                $section['items'] = array_map($this->withCaseSlug(...), $section['items'] ?? []);
            }
            $sections[] = $section;
        }
        return ['sections' => $sections];
    }

    public function info(): array
    {
        return $this->store->file('info.json');
    }

    public function sale(): array
    {
        $sale = $this->store->optional('sale.json') ?? [];
        return [
            'title' => (string) ($sale['title'] ?? 'Выгодные предложения'),
            'url' => $sale['url'] ?? null,
            'items' => array_values($sale['items'] ?? []),
        ];
    }

    public function cases(?int $categoryId): array
    {
        $list = $this->store->optional('cases.json') ?? [];
        $items = array_values($list['items'] ?? []);
        if ($categoryId !== null) {
            $items = array_values(array_filter($items, static fn (array $c) => ($c['categoryId'] ?? null) === $categoryId));
        }
        return [
            'title' => (string) ($list['title'] ?? 'Кейсы'),
            'categories' => array_values($list['categories'] ?? []),
            'items' => $items,
        ];
    }

    public function caseStudy(string $slug): ?array
    {
        if (!preg_match(self::CASE_SLUG_PATTERN, $slug)) {
            return null;
        }
        $case = $this->store->optional("cases/{$slug}.json");
        if ($case === null) {
            return null;
        }
        $case['products'] = $this->catalog->summaries(array_map('intval', $case['productIds'] ?? []));
        unset($case['productIds']);
        return $case;
    }

    /**
     * Плитка кейса на главной получает slug, если карточка кейса есть в снапшоте:
     * клиент откроет её в приложении, иначе — страницу сайта по url.
     *
     * @param array<string, mixed> $item
     * @return array<string, mixed>
     */
    private function withCaseSlug(array $item): array
    {
        $slug = self::caseSlugFromUrl((string) ($item['url'] ?? ''));
        if ($slug !== null && $this->store->optional("cases/{$slug}.json") !== null) {
            $item['slug'] = $slug;
        }
        return $item;
    }

    /** «https://www.art-active24.ru/cases/serpuhov/» → «serpuhov». */
    public static function caseSlugFromUrl(string $url): ?string
    {
        $path = trim((string) (parse_url($url, PHP_URL_PATH) ?? ''), '/');
        $segments = explode('/', $path);
        if (count($segments) !== 2 || $segments[0] !== 'cases') {
            return null;
        }
        $slug = strtolower($segments[1]);
        return preg_match(self::CASE_SLUG_PATTERN, $slug) ? $slug : null;
    }
}
