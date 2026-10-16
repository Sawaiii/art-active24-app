<?php

declare(strict_types=1);

namespace App\Catalog\Snapshot;

use App\Catalog\CatalogRepository;
use App\Catalog\ContentRepository;

/**
 * Главная и справочная информация из снапшота (home.json, info.json).
 * Секции главной со списком id товаров дополняются карточками из каталога.
 */
final class SnapshotContentRepository implements ContentRepository
{
    public function __construct(
        private readonly SnapshotStore $store,
        private readonly CatalogRepository $catalog,
    ) {
    }

    public function home(): array
    {
        $sections = [];
        foreach ($this->store->file('home.json')['sections'] ?? [] as $section) {
            if (($section['type'] ?? null) === 'products') {
                $ids = array_map('intval', $section['productIds'] ?? []);
                $section['products'] = $ids === [] ? $this->catalog->newest(10) : $this->catalog->summaries($ids);
                unset($section['productIds']);
            }
            $sections[] = $section;
        }
        return ['sections' => $sections];
    }

    public function info(): array
    {
        return $this->store->file('info.json');
    }
}
