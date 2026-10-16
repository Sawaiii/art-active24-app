<?php

declare(strict_types=1);

namespace App\Cart;

use App\Db\Database;
use App\Pricing\CartItem;
use App\Support\Clock;
use App\Support\Time;

/**
 * Серверная корзина авторизованного пользователя (синхронизация между устройствами).
 * Хранится состав (CartItem), цены — всегда пересчитываются QuoteService.
 */
final class CartRepository
{
    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    /** @return list<CartItem> */
    public function load(int $userId): array
    {
        $json = $this->db->scalar('SELECT items_json FROM app_carts WHERE user_id = ?', [$userId]);
        if (!is_string($json)) {
            return [];
        }
        $items = [];
        foreach (json_decode($json, true, 32, JSON_THROW_ON_ERROR) as $raw) {
            $items[] = CartItem::fromArray($raw);
        }
        return $items;
    }

    /** @param list<CartItem> $items */
    public function save(int $userId, array $items): void
    {
        $json = json_encode(array_map(static fn (CartItem $i) => $i->toArray(), $items), JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
        $now = Time::toDb($this->clock->now());
        // REPLACE атомарен в MySQL и SQLite — параллельные сохранения не дают нарушения ключа.
        $this->db->run('REPLACE INTO app_carts (user_id, items_json, updated_at) VALUES (?, ?, ?)', [$userId, $json, $now]);
    }

    public function clear(int $userId): void
    {
        $this->db->run('DELETE FROM app_carts WHERE user_id = ?', [$userId]);
    }
}
