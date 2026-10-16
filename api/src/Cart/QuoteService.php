<?php

declare(strict_types=1);

namespace App\Cart;

use App\Catalog\CatalogRepository;
use App\Http\HttpError;
use App\Pricing\CartItem;
use App\Pricing\PriceCalculator;

/**
 * Пересчёт корзины на сервере: цены и названия берутся из каталога, клиентским не доверяем.
 * Позиции, которые больше нельзя заказать, помечаются available=false с понятной причиной.
 */
final class QuoteService
{
    public function __construct(
        private readonly CatalogRepository $catalog,
        private readonly PriceCalculator $calculator,
    ) {
    }

    /**
     * @param list<CartItem> $items
     * @return array{lines: list<array<string, mixed>>, total: int, hasOnRequest: bool, count: int}
     */
    public function quote(array $items): array
    {
        $lines = [];
        $products = [];
        foreach ($items as $item) {
            $products[$item->productId] ??= $this->catalog->product($item->productId);
            $lines[] = $this->line($item, $products[$item->productId]);
        }

        $available = array_filter($lines, static fn (array $l) => $l['available']);
        return [
            'lines' => $lines,
            'total' => array_sum(array_column($available, 'total')),
            'hasOnRequest' => array_filter($available, static fn (array $l) => $l['onRequest']) !== [],
            'count' => count($lines),
        ];
    }

    /**
     * @param array<string, mixed>|null $product
     * @return array<string, mixed>
     */
    private function line(CartItem $item, ?array $product): array
    {
        $line = [
            'key' => $item->key(),
            'input' => $item->toArray(),
            'productName' => $product['name'] ?? 'Товар недоступен',
            'productSlug' => $product['slug'] ?? null,
            'image' => $product['media'][0]['url'] ?? null,
            'art' => $product['art'] ?? null,
            'complectTitle' => '',
            'subTitle' => null,
            'priceLabel' => null,
            'timeLabel' => null,
            'qtyUnit' => 'шт',
            'extras' => [],
            'unitPrice' => 0,
            'total' => 0,
            'onRequest' => false,
            'available' => false,
            'warning' => null,
        ];
        if ($product === null) {
            return ['warning' => 'Товар снят с продажи'] + $line;
        }
        if (($product['orderMode'] ?? 'cart') === 'request') {
            return ['warning' => 'Этот товар заказывается через заявку'] + $line;
        }
        if ($item->complectId === null && ($product['orderMode'] ?? 'cart') !== 'toggle') {
            return ['warning' => 'Выберите комплект'] + $line;
        }
        $complect = $item->complectId === null ? null : $this->complect($product, $item->complectId);
        if ($item->complectId !== null && $complect === null) {
            return ['warning' => 'Комплект больше недоступен'] + $line;
        }

        try {
            $price = $complect === null
                ? $this->calculator->priceOptions($product['extras'] ?? [], $item)
                : $this->calculator->price($complect, $product['extras'] ?? [], $item);
        } catch (HttpError $e) {
            $reason = $e->fields === [] ? $e->getMessage() : (string) reset($e->fields);
            return ['complectTitle' => (string) ($complect['title'] ?? ''), 'warning' => $reason] + $line;
        }
        $title = $complect === null
            ? implode(', ', array_column($price->extras, 'name'))
            : (string) $complect['title'];

        return [
            'complectTitle' => $title,
            'subTitle' => $price->subTitle,
            'priceLabel' => $price->priceLabel,
            'timeLabel' => $price->timeLabel,
            'qtyUnit' => $price->qtyUnit,
            'extras' => $complect === null ? [] : $price->extras,
            'unitPrice' => $price->unitPrice,
            'total' => $price->total,
            'onRequest' => $price->onRequest,
            'available' => true,
        ] + $line;
    }

    /**
     * @param array<string, mixed> $product
     * @return array<string, mixed>|null
     */
    private function complect(array $product, int $complectId): ?array
    {
        foreach ($product['complects'] ?? [] as $complect) {
            if ((int) $complect['id'] === $complectId) {
                return $complect;
            }
        }
        return null;
    }
}
