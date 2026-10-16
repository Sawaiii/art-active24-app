<?php

declare(strict_types=1);

namespace App\Users;

use App\Db\Database;
use App\Support\Clock;
use App\Support\Time;

/**
 * Избранное пользователя (порядок — последние добавленные первыми).
 */
final class FavoriteRepository
{
    public const MAX = 500;

    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    /** @return list<int> */
    public function ids(int $userId): array
    {
        return array_map('intval', array_column(
            $this->db->all('SELECT product_id FROM app_favorites WHERE user_id = ? ORDER BY created_at DESC, product_id DESC', [$userId]),
            'product_id',
        ));
    }

    /** @param list<int> $productIds порядок клиента: первый — самый новый */
    public function replace(int $userId, array $productIds): void
    {
        $now = $this->clock->now();
        $this->db->transaction(function () use ($userId, $productIds, $now): void {
            $this->db->run('DELETE FROM app_favorites WHERE user_id = ?', [$userId]);
            foreach (array_values(array_unique($productIds)) as $i => $productId) {
                $this->db->insert('app_favorites', [
                    'user_id' => $userId,
                    'product_id' => $productId,
                    'created_at' => Time::toDb($now->modify("-{$i} seconds")),
                ]);
            }
        });
    }
}
