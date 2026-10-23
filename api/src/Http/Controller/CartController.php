<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Cart\CartRepository;
use App\Cart\QuoteService;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Loyalty\LoyaltyService;
use App\Pricing\CartItem;

final class CartController
{
    private const MAX_ITEMS = 100;

    public function __construct(
        private readonly QuoteService $quotes,
        private readonly CartRepository $carts,
        private readonly LoyaltyService $loyalty,
    ) {
    }

    public function quote(Request $request): Response
    {
        return Response::ok($this->priced($request, $this->items($request)));
    }

    public function get(Request $request): Response
    {
        $user = $request->attribute('user');
        return Response::ok($this->priced($request, $this->carts->load((int) $user['id'])));
    }

    public function put(Request $request): Response
    {
        $user = $request->attribute('user');
        $items = $this->merge($this->items($request));
        $this->carts->save((int) $user['id'], $items);
        return Response::ok($this->priced($request, $items));
    }

    /**
     * Расчёт + скидка постоянного клиента, если пользователь вошёл (гостю — без скидки).
     *
     * @param list<CartItem> $items
     * @return array<string, mixed> Quote
     */
    private function priced(Request $request, array $items): array
    {
        $quote = $this->quotes->quote($items);
        $user = $request->attribute('user');
        return $user === null ? $quote : $this->loyalty->applyToQuote($quote, $this->loyalty->percentFor((int) $user['id']));
    }

    /** @return list<CartItem> */
    private function items(Request $request): array
    {
        $raw = $request->json()['items'] ?? null;
        if (!is_array($raw) || !array_is_list($raw) || count($raw) > self::MAX_ITEMS) {
            throw HttpError::validation(['items' => 'Ожидается список до ' . self::MAX_ITEMS . ' позиций']);
        }
        $items = [];
        foreach ($raw as $i => $item) {
            $items[] = CartItem::fromArray(is_array($item) ? $item : [], "items.{$i}.");
        }
        return $items;
    }

    /**
     * Одинаковые конфигурации схлопываются в одну строку с суммой количеств.
     *
     * @param list<CartItem> $items
     * @return list<CartItem>
     */
    private function merge(array $items): array
    {
        $byKey = [];
        foreach ($items as $item) {
            $key = $item->key();
            $byKey[$key] = isset($byKey[$key])
                ? $byKey[$key]->withQty(min(CartItem::MAX_QTY, $byKey[$key]->qty + $item->qty))
                : $item;
        }
        return array_values($byKey);
    }
}
