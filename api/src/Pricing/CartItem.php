<?php

declare(strict_types=1);

namespace App\Pricing;

use App\Http\HttpError;

/**
 * Позиция корзины в том виде, как её прислал клиент, — провалидированная и неизменяемая.
 * Цены здесь нет: цену всегда считает сервер.
 */
final class CartItem
{
    public const MAX_QTY = 10000;
    public const MAX_TIME = 365;

    /**
     * @param array<string, int> $extras id → кол-во
     * @param array<string, int> $menu   id строки меню → кол-во
     */
    private function __construct(
        public readonly int $productId,
        /** null — строка-опция без комплекта (шаблоны simple/showcase, как add-cart опции на сайте) */
        public readonly ?int $complectId,
        public readonly ?string $subId,
        public readonly string $priceType,
        public readonly ?string $timeUnit,
        public readonly ?int $timeValue,
        public readonly int $qty,
        public readonly array $extras,
        public readonly array $menu,
    ) {
    }

    /** @param array<string, mixed> $data */
    public static function fromArray(array $data, string $fieldPrefix = ''): self
    {
        $errors = [];
        $p = $fieldPrefix;

        $productId = self::positiveInt($data['productId'] ?? null);
        if ($productId === null) {
            $errors[$p . 'productId'] = 'Укажите товар';
        }
        $complectId = self::positiveInt($data['complectId'] ?? null);
        if (array_key_exists('complectId', $data) && $data['complectId'] !== null && $complectId === null) {
            $errors[$p . 'complectId'] = 'Некорректный комплект';
        }

        $qty = self::positiveInt($data['qty'] ?? null);
        if ($qty === null || $qty > self::MAX_QTY) {
            $errors[$p . 'qty'] = 'Количество должно быть от 1 до ' . self::MAX_QTY;
        }

        $priceType = $data['priceType'] ?? 'rent';
        if (!in_array($priceType, ['rent', 'buy'], true)) {
            $errors[$p . 'priceType'] = 'Тип цены: аренда или покупка';
        }

        $subId = $data['subId'] ?? null;
        if ($subId !== null && (!is_string($subId) || $subId === '' || strlen($subId) > 64)) {
            $errors[$p . 'subId'] = 'Некорректный вариант';
        }

        [$timeUnit, $timeValue] = self::parseTime($data['time'] ?? null, $p, $errors);
        $extras = self::parseCounted($data['extras'] ?? [], $p . 'extras', 1, 50, false, $errors);
        $menu = self::parseCounted($data['menu'] ?? [], $p . 'menu', 0, 100, true, $errors);

        if ($complectId === null && $extras === [] && !isset($errors[$p . 'complectId'])) {
            $errors[$p . 'complectId'] = 'Выберите комплект или дополнительную опцию';
        }
        if ($errors !== []) {
            throw HttpError::validation($errors);
        }

        return new self(
            (int) $productId,
            $complectId,
            $subId,
            (string) $priceType,
            $timeUnit,
            $timeValue,
            (int) $qty,
            $extras,
            $menu,
        );
    }

    /** Ключ конфигурации: одинаковые настройки = одна строка корзины (кол-во не входит). */
    public function key(): string
    {
        $extras = $this->extras;
        ksort($extras);
        $menu = $this->menu;
        ksort($menu);
        return substr(hash('sha256', json_encode([
            $this->productId, $this->complectId, $this->subId, $this->priceType,
            $this->timeUnit, $this->timeValue, $extras, $menu,
        ], JSON_THROW_ON_ERROR)), 0, 16);
    }

    public function withQty(int $qty): self
    {
        return new self(
            $this->productId, $this->complectId, $this->subId, $this->priceType,
            $this->timeUnit, $this->timeValue, $qty, $this->extras, $this->menu,
        );
    }

    /** @return array<string, mixed> */
    public function toArray(): array
    {
        $out = ['productId' => $this->productId];
        if ($this->complectId !== null) {
            $out['complectId'] = $this->complectId;
        }
        if ($this->subId !== null) {
            $out['subId'] = $this->subId;
        }
        $out['priceType'] = $this->priceType;
        if ($this->timeUnit !== null) {
            $out['time'] = ['unit' => $this->timeUnit, 'value' => $this->timeValue];
        }
        $out['qty'] = $this->qty;
        if ($this->extras !== []) {
            $out['extras'] = array_map(
                static fn (string $id, int $qty) => ['id' => $id, 'qty' => $qty],
                array_map('strval', array_keys($this->extras)),
                array_values($this->extras),
            );
        }
        if ($this->menu !== []) {
            $out['menu'] = array_map(
                static fn (string $id, int $qty) => ['id' => $id, 'qty' => $qty],
                array_map('strval', array_keys($this->menu)),
                array_values($this->menu),
            );
        }
        return $out;
    }

    private static function positiveInt(mixed $value): ?int
    {
        if (is_int($value) && $value > 0) {
            return $value;
        }
        if (is_string($value) && preg_match('/^[1-9]\d{0,9}$/', $value)) {
            return (int) $value;
        }
        return null;
    }

    /**
     * @param array<string, string> $errors
     * @return array{0: ?string, 1: ?int}
     */
    private static function parseTime(mixed $time, string $p, array &$errors): array
    {
        if ($time === null) {
            return [null, null];
        }
        $unit = is_array($time) ? ($time['unit'] ?? null) : null;
        $value = is_array($time) ? self::positiveInt($time['value'] ?? null) : null;
        if (!in_array($unit, ['hours', 'days'], true) || $value === null || $value > self::MAX_TIME) {
            $errors[$p . 'time'] = 'Некорректное время аренды';
            return [null, null];
        }
        return [$unit, $value];
    }

    /**
     * @param array<string, string> $errors
     * @return array<string, int>
     */
    private static function parseCounted(mixed $list, string $field, int $minQty, int $maxItems, bool $qtyRequired, array &$errors): array
    {
        if (!is_array($list) || !array_is_list($list) || count($list) > $maxItems) {
            $errors[$field] = 'Ожидается список';
            return [];
        }
        $out = [];
        foreach ($list as $row) {
            $id = is_array($row) ? ($row['id'] ?? null) : null;
            $qty = is_array($row) ? ($row['qty'] ?? ($qtyRequired ? null : 1)) : null;
            if (!is_string($id) || $id === '' || strlen($id) > 64 || !is_int($qty) || $qty < $minQty || $qty > self::MAX_QTY) {
                $errors[$field] = 'Некорректный элемент списка';
                return [];
            }
            $out[$id] = ($out[$id] ?? 0) + $qty;
        }
        return $out;
    }
}
