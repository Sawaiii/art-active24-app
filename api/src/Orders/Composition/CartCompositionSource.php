<?php

declare(strict_types=1);

namespace App\Orders\Composition;

use App\Catalog\CatalogRepository;

/**
 * Запасной состав — из позиций корзины заказа (снимок цен на момент оформления). Разделы — по корневой
 * категории товара в каталоге («Мебель», «Кейтеринг»…), скидка — та же, что в заказе.
 */
final class CartCompositionSource implements OrderCompositionSource
{
    private const FALLBACK_SECTION = 'Позиции заказа';

    /** @var array<int, string> productId → раздел (кэш на запрос) */
    private array $titles = [];

    public function __construct(private readonly CatalogRepository $catalog)
    {
    }

    public function composition(array $order): ?array
    {
        $lines = $order['lines'] ?? [];
        if ($lines === []) {
            return null;
        }
        $groups = [];
        foreach ($lines as $line) {
            $title = $this->sectionTitle((int) $line['productId']);
            $groups[$title][] = $this->line($line);
        }
        $sections = [];
        foreach ($groups as $title => $groupLines) {
            $sections[] = [
                'id' => 'c' . (count($sections) + 1),
                'title' => (string) $title,
                'lines' => $groupLines,
                'subtotal' => array_sum(array_column($groupLines, 'sum')),
            ];
        }
        $discount = $order['discount'] ?? null;
        $delivery = $order['delivery']['method'] ?? null;
        return [
            'source' => 'cart',
            'version' => 1,
            'updatedAt' => $order['createdAt'],
            'sections' => $sections,
            'subtotal' => array_sum(array_column($sections, 'subtotal')),
            'discounts' => is_array($discount) ? [$discount] : null,
            'deliveryNote' => match ($delivery) {
                'delivery' => 'Стоимость доставки рассчитает менеджер',
                'pickup' => 'Самовывоз',
                default => null,
            },
            'total' => (int) $order['total'],
            'hasOnRequest' => (bool) ($order['hasOnRequest'] ?? false),
        ];
    }

    private function sectionTitle(int $productId): string
    {
        if (!array_key_exists($productId, $this->titles)) {
            $product = $this->catalog->product($productId);
            $root = $product['breadcrumbs'][0]['name'] ?? null;
            $this->titles[$productId] = is_string($root) && $root !== '' ? $root : self::FALLBACK_SECTION;
        }
        return $this->titles[$productId];
    }

    /**
     * @param array<string, mixed> $line OrderLine
     * @return array<string, mixed> CompositionLine
     */
    private function line(array $line): array
    {
        $input = is_array($line['input'] ?? null) ? $line['input'] : [];
        $time = is_array($input['time'] ?? null) ? $input['time'] : null;
        $notes = [];
        if ($time !== null && ($time['unit'] ?? null) === 'hours' && !empty($line['timeLabel'])) {
            $notes[] = (string) $line['timeLabel'];
        }
        foreach ($line['extras'] ?? [] as $extra) {
            $qty = (int) ($extra['qty'] ?? 1);
            $notes[] = '+ ' . ($extra['name'] ?? '') . ($qty > 1 ? " × {$qty}" : '');
        }
        $complect = trim((string) ($line['complectTitle'] ?? ''));
        return [
            'name' => (string) $line['productName'] . ($complect !== '' ? ' — ' . $complect : ''),
            'art' => $line['art'] ?? null,
            'qty' => (int) $line['qty'],
            'unit' => (string) ($line['qtyUnit'] ?? 'шт'),
            'days' => $time !== null && ($time['unit'] ?? null) === 'days' ? (int) ($time['value'] ?? 1) : null,
            'price' => (int) $line['unitPrice'],
            'sum' => (int) $line['total'],
            'note' => $notes === [] ? null : implode(', ', $notes),
            'onRequest' => !empty($line['onRequest']) ? true : null,
        ];
    }
}
