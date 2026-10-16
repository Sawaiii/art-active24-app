<?php

declare(strict_types=1);

namespace App\Orders;

use App\Db\Database;
use App\Support\Clock;
use App\Support\Time;

/**
 * Хранение заявок: шапка, позиции (снимок цен на момент оформления), журнал статусов.
 * Текстовые поля обрезаются по размеру колонок MySQL — строгий режим не уронит оформление.
 */
final class OrderRepository
{
    private const ITEM_LIMITS = [
        'product_name' => 300, 'product_slug' => 190, 'image' => 500, 'art' => 20,
        'complect_title' => 300, 'sub_title' => 300, 'time_label' => 20, 'qty_unit' => 30,
    ];

    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    /**
     * @param array<string, mixed> $order колонки app_orders без id/number/status/времени
     * @param list<array<string, mixed>> $lines строки QuoteLine
     * @return int id созданной заявки
     * @throws \PDOException нарушение UNIQUE(user_id, idempotency_key) — заявка с этим ключом уже есть
     */
    public function create(array $order, array $lines, string $historyComment): int
    {
        return $this->db->transaction(function () use ($order, $lines, $historyComment): int {
            $now = Time::toDb($this->clock->now());
            $id = $this->db->insert('app_orders', $order + [
                'status' => OrderStatus::Processing->value,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
            $this->db->run('UPDATE app_orders SET number = ? WHERE id = ?', [sprintf('AA-%06d', $id), $id]);
            foreach (array_values($lines) as $position => $line) {
                $this->db->insert('app_order_items', $this->itemRow($id, $position, $line));
            }
            $this->log($id, OrderStatus::Processing, $historyComment, null);
            return $id;
        });
    }

    /** @return array{id: int, kind: string}|null */
    public function findByIdempotencyKey(int $userId, string $key): ?array
    {
        $row = $this->db->one('SELECT id, kind FROM app_orders WHERE user_id = ? AND idempotency_key = ?', [$userId, $key]);
        return $row === null ? null : ['id' => (int) $row['id'], 'kind' => (string) $row['kind']];
    }

    /** @return array<string, mixed>|null строка app_orders */
    public function row(int $id): ?array
    {
        return $this->db->one('SELECT * FROM app_orders WHERE id = ?', [$id]);
    }

    /**
     * Заявки вместе с позициями и историей — три запроса на любую страницу (без N+1).
     *
     * @param list<int> $ids
     * @return list<array{order: array<string, mixed>, items: list<array<string, mixed>>, history: list<array<string, mixed>>}>
     */
    public function load(array $ids): array
    {
        if ($ids === []) {
            return [];
        }
        $in = implode(',', array_fill(0, count($ids), '?'));
        $orders = [];
        foreach ($this->db->all("SELECT * FROM app_orders WHERE id IN ({$in})", $ids) as $row) {
            $orders[(int) $row['id']] = ['order' => $row, 'items' => [], 'history' => []];
        }
        foreach ($this->db->all("SELECT * FROM app_order_items WHERE order_id IN ({$in}) ORDER BY order_id, position", $ids) as $row) {
            $orders[(int) $row['order_id']]['items'][] = $row;
        }
        foreach ($this->db->all("SELECT * FROM app_order_status_log WHERE order_id IN ({$in}) ORDER BY order_id, id", $ids) as $row) {
            $orders[(int) $row['order_id']]['history'][] = $row;
        }
        return array_values(array_filter(array_map(static fn (int $id) => $orders[$id] ?? null, $ids)));
    }

    /** @return array{ids: list<int>, total: int} */
    public function idsForUser(int $userId, int $offset, int $limit): array
    {
        return [
            'ids' => array_map('intval', array_column($this->db->all(
                'SELECT id FROM app_orders WHERE user_id = ? ORDER BY id DESC LIMIT ? OFFSET ?',
                [$userId, $limit, $offset],
            ), 'id')),
            'total' => (int) $this->db->scalar('SELECT COUNT(*) FROM app_orders WHERE user_id = ?', [$userId]),
        ];
    }

    /** @return array{ids: list<int>, total: int} */
    public function idsForManager(?OrderStatus $status, ?string $search, int $offset, int $limit): array
    {
        $conditions = [];
        $params = [];
        if ($status !== null) {
            $conditions[] = 'status = ?';
            $params[] = $status->value;
        }
        if ($search !== null) {
            // Номер заявки, телефон (по цифрам), имя контакта или тема заявки (товар/площадка).
            $conditions[] = "(number LIKE ? ESCAPE '!' OR contact_phone LIKE ? ESCAPE '!'"
                . " OR contact_name LIKE ? ESCAPE '!' OR subject LIKE ? ESCAPE '!')";
            $digits = (string) preg_replace('/\D+/', '', $search);
            // Код страны (7 / 8) отбрасываем: «8 916…» и «+7 916…» — один и тот же номер.
            if (strlen($digits) >= 4 && ($digits[0] === '7' || $digits[0] === '8')) {
                $digits = substr($digits, 1);
            }
            $text = '%' . self::escapeLike($search) . '%';
            $phone = $digits === '' ? $text : '%' . $digits . '%';
            array_push($params, $text, $phone, $text, $text);
        }
        $where = $conditions === [] ? '' : 'WHERE ' . implode(' AND ', $conditions);
        return [
            'ids' => array_map('intval', array_column($this->db->all(
                "SELECT id FROM app_orders {$where} ORDER BY id DESC LIMIT ? OFFSET ?",
                [...$params, $limit, $offset],
            ), 'id')),
            'total' => (int) $this->db->scalar("SELECT COUNT(*) FROM app_orders {$where}", $params),
        ];
    }

    /** Символы-шаблоны LIKE в пользовательском запросе ищутся буквально («%» не значит «всё»). */
    private static function escapeLike(string $value): string
    {
        return str_replace(['!', '%', '_'], ['!!', '!%', '!_'], $value);
    }

    /**
     * Смена статуса только если он всё ещё $from (защита от гонки клиента и менеджера).
     *
     * @return bool false — статус уже изменили параллельно
     */
    public function changeStatus(int $orderId, OrderStatus $from, OrderStatus $to, ?string $comment, ?int $actorId, ?int $total): bool
    {
        return $this->db->transaction(function () use ($orderId, $from, $to, $comment, $actorId, $total): bool {
            $now = Time::toDb($this->clock->now());
            $changed = $total === null
                ? $this->db->run(
                    'UPDATE app_orders SET status = ?, updated_at = ? WHERE id = ? AND status = ?',
                    [$to->value, $now, $orderId, $from->value],
                )->rowCount()
                : $this->db->run(
                    'UPDATE app_orders SET status = ?, total = ?, updated_at = ? WHERE id = ? AND status = ?',
                    [$to->value, $total, $now, $orderId, $from->value],
                )->rowCount();
            if ($changed !== 1) {
                return false;
            }
            $this->log($orderId, $to, $comment, $actorId);
            return true;
        });
    }

    private function log(int $orderId, OrderStatus $status, ?string $comment, ?int $actorId): void
    {
        $this->db->insert('app_order_status_log', [
            'order_id' => $orderId,
            'status' => $status->value,
            'comment' => $comment,
            'actor_user_id' => $actorId,
            'created_at' => Time::toDb($this->clock->now()),
        ]);
    }

    /**
     * @param array<string, mixed> $line
     * @return array<string, mixed>
     */
    private function itemRow(int $orderId, int $position, array $line): array
    {
        $row = [
            'order_id' => $orderId,
            'position' => $position,
            'product_id' => (int) $line['input']['productId'],
            'product_name' => (string) $line['productName'],
            'product_slug' => $line['productSlug'],
            'image' => $line['image'],
            'art' => $line['art'],
            'complect_title' => $line['complectTitle'],
            'sub_title' => $line['subTitle'],
            'time_label' => $line['timeLabel'],
            'qty' => (int) $line['input']['qty'],
            'qty_unit' => $line['qtyUnit'],
            'unit_price' => (int) $line['unitPrice'],
            'total' => (int) $line['total'],
            'on_request' => $line['onRequest'] ? 1 : 0,
            'extras_json' => json_encode($line['extras'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
            'input_json' => json_encode($line['input'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
        ];
        foreach (self::ITEM_LIMITS as $column => $max) {
            if (is_string($row[$column])) {
                $row[$column] = mb_substr($row[$column], 0, $max);
            }
        }
        return $row;
    }
}
