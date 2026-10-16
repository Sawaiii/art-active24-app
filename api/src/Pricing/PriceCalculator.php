<?php

declare(strict_types=1);

namespace App\Pricing;

use App\Http\HttpError;

/**
 * Расчёт цены позиции — повторяет логику карточки сайта 1-в-1.
 * Формулы и эталонные примеры: docs/DATA-MODEL.md, contract/pricing-vectors.json.
 * Принимает комплект и допы в форме контракта API (массивы из CatalogRepository).
 */
final class PriceCalculator
{
    /** Каждый доп. день почасовой аренды — +30% от цены 8 часов (правило сайта). */
    private const HOURLY_EXTRA_DAY_RATE = 0.30;
    private const HOURLY_MAX_HOURS = 8;
    /** Потолок суммы позиции — защита от переполнения INT и заведомо ошибочных заказов. */
    public const MAX_TOTAL = 1_000_000_000;

    /**
     * @param array<string, mixed> $complect
     * @param list<array<string, mixed>> $productExtras
     */
    public function price(array $complect, array $productExtras, CartItem $item): PriceResult
    {
        [$extrasTotal, $extrasLines] = $this->extras($productExtras, $item);

        if (!empty($complect['menu'])) {
            return $this->priceMenu($complect, $item, $extrasTotal, $extrasLines);
        }

        $side = $complect[$item->priceType] ?? null;
        if (!is_array($side)) {
            throw $this->invalid('priceType', 'Этот комплект нельзя ' . ($item->priceType === 'buy' ? 'купить' : 'арендовать'));
        }
        $sub = $this->sub($complect, $item);
        $subSide = is_array($sub[$item->priceType] ?? null) ? $sub[$item->priceType] : [];

        $sale = !empty($side['sale']) || !empty($subSide['sale']);
        $onRequest = !empty($side['onRequest']) || !empty($subSide['onRequest']);
        $minQty = max(1, (int) ($subSide['minQty'] ?? $side['minQty'] ?? 1));
        $stepPct = (float) ($subSide['qtyStepPct'] ?? $side['qtyStepPct'] ?? 0);
        $postfix = (string) ($subSide['postfix'] ?? $side['postfix'] ?? '');
        $label = (string) ($side['label'] ?? '');

        [$mult, $timeLabel] = $sale || !is_array($complect['time'] ?? null)
            ? [1.0, null]
            : $this->timeMultiplier($complect['time'], $item);

        if ($onRequest) {
            return new PriceResult(0, 0, true, $timeLabel, $label, $this->qtyUnit($postfix), $sub['name'] ?? null, $extrasLines);
        }

        $flat = $item->priceType === 'rent' ? (int) ($sub['flatSurcharge'] ?? 0) : 0;
        $base = (int) ($side['amount'] ?? 0) + (int) ($subSide['amount'] ?? 0);
        $unit = self::roundRub($base * $mult) + $flat;

        $lineTotal = $stepPct > 0
            ? $unit * $minQty + $unit * $stepPct / 100 * max(0, $item->qty - $minQty)
            : $unit * max($item->qty, $minQty);
        $total = self::roundRub($lineTotal) + $extrasTotal + (int) ($complect['basePrice'] ?? 0);
        $this->assertTotal($total);

        return new PriceResult($unit, $total, false, $timeLabel, $label, $this->qtyUnit($postfix), $sub['name'] ?? null, $extrasLines);
    }

    /**
     * Строка-опция без комплекта (шаблоны simple/showcase): сумма выбранных допов × количество.
     *
     * @param list<array<string, mixed>> $productExtras
     */
    public function priceOptions(array $productExtras, CartItem $item): PriceResult
    {
        [$extrasTotal, $lines] = $this->extras($productExtras, $item, includeRequired: false);
        $total = $extrasTotal * $item->qty;
        $this->assertTotal($total);
        return new PriceResult($extrasTotal, $total, false, null, 'Опция', 'шт', null, $lines);
    }

    /**
     * Кейтеринг-меню: строки со своими количествами, одна позиция на комплект.
     *
     * @param array<string, mixed> $complect
     * @param list<array{name: string, qty: int, price: int}> $extrasLines
     */
    private function priceMenu(array $complect, CartItem $item, int $extrasTotal, array $extrasLines): PriceResult
    {
        $rows = [];
        foreach ($complect['menu'] as $row) {
            $rows[(string) $row['id']] = $row;
        }
        $rowsTotal = 0;
        foreach ($item->menu as $id => $qty) {
            if (!isset($rows[$id])) {
                throw $this->invalid('menu', 'Позиция меню не найдена');
            }
            $minQty = (int) ($rows[$id]['minQty'] ?? 0);
            if ($qty > 0 && $qty < $minQty) {
                throw $this->invalid('menu', "«{$rows[$id]['name']}» — минимум {$minQty}");
            }
            $rowsTotal += (int) $rows[$id]['price'] * $qty;
        }
        if ($rowsTotal <= 0) {
            throw $this->invalid('menu', 'Выберите хотя бы одну позицию меню');
        }

        $basePrice = (int) ($complect['basePrice'] ?? 0);
        $reward = $complect['reward'] ?? null;
        if (is_array($reward) && ($reward['type'] ?? '') === 'base_free' && $rowsTotal >= (int) ($reward['goal'] ?? PHP_INT_MAX)) {
            $basePrice = 0;
        }

        $label = (string) ($complect['rent']['label'] ?? 'Стоимость');
        $this->assertTotal($rowsTotal + $basePrice + $extrasTotal);
        return new PriceResult($rowsTotal, $rowsTotal + $basePrice + $extrasTotal, false, null, $label, 'набор', null, $extrasLines);
    }

    /**
     * @param array<string, mixed> $complect
     * @return array<string, mixed>
     */
    private function sub(array $complect, CartItem $item): array
    {
        $subs = $complect['subs'] ?? [];
        if ($subs === []) {
            if ($item->subId !== null) {
                throw $this->invalid('subId', 'У комплекта нет вариантов');
            }
            return [];
        }
        foreach ($subs as $sub) {
            if ((string) $sub['id'] === $item->subId) {
                return $sub;
            }
        }
        // Варианты без своей цены для выбранного типа (напр. способ установки батута при покупке)
        // на сайте скрыты — выбирать их не нужно.
        $subsPriced = array_filter($subs, static fn (array $s) => is_array($s[$item->priceType] ?? null));
        if ($item->subId === null && $subsPriced === []) {
            return [];
        }
        throw $this->invalid('subId', $item->subId === null ? 'Выберите вариант' : 'Вариант не найден');
    }

    /**
     * @param array<string, mixed> $rule
     * @return array{0: float, 1: string}
     */
    private function timeMultiplier(array $rule, CartItem $item): array
    {
        $def = max(1, (int) $rule['default']);
        $pct = (float) $rule['percent'] / 100;

        if ($rule['unit'] === 'days') {
            $days = $item->timeUnit === null ? $def : $item->timeValue;
            if ($item->timeUnit === 'hours' || $days < $def) {
                throw $this->invalid('time', "Минимальный срок аренды — {$def} д");
            }
            return [1 + ($days - $def) * $pct, $days . ' д'];
        }

        $maxHours = max(self::HOURLY_MAX_HOURS, $def);
        if ($item->timeUnit === null || $item->timeUnit === 'hours') {
            $hours = $item->timeValue ?? $def;
            if ($hours < $def || $hours > $maxHours) {
                throw $this->invalid('time', "Время аренды — от {$def} до {$maxHours} ч или от 2 дней");
            }
            return [1 + ($hours - $def) * $pct, $hours . ' ч'];
        }

        $days = (int) $item->timeValue;
        if ($days < 2) {
            throw $this->invalid('time', 'Посуточно — от 2 дней');
        }
        $mult8h = 1 + ($maxHours - $def) * $pct;
        return [$mult8h * (1 + self::HOURLY_EXTRA_DAY_RATE * ($days - 1)), $days . ' д'];
    }

    /**
     * @param list<array<string, mixed>> $productExtras
     * @return array{0: int, 1: list<array{name: string, qty: int, price: int}>}
     */
    private function extras(array $productExtras, CartItem $item, bool $includeRequired = true): array
    {
        $byId = [];
        $selected = $item->extras;
        foreach ($productExtras as $extra) {
            $byId[(string) $extra['id']] = $extra;
            // Обязательные допы (напр. барьеры безопасности к батуту) входят в цену всегда.
            if ($includeRequired && !empty($extra['required']) && !isset($selected[(string) $extra['id']])) {
                $selected[(string) $extra['id']] = 1;
            }
        }
        $total = 0;
        $lines = [];
        foreach ($selected as $id => $qty) {
            $extra = $byId[$id] ?? throw $this->invalid('extras', 'Дополнительная опция не найдена');
            $qty = !empty($extra['countable']) ? $qty : 1;
            $price = (int) $extra['price'];
            $total += $price * $qty;
            $lines[] = ['name' => (string) $extra['name'], 'qty' => $qty, 'price' => $price];
        }
        return [$total, $lines];
    }

    /**
     * Округление до рубля, половина — вверх. Одинаково в PHP, Kotlin и Swift (docs/DATA-MODEL.md):
     * эпсилон гасит ошибку представления double (71500.4999… от 64000 × 1.11719 не уходит вниз).
     */
    public static function roundRub(float $amount): int
    {
        return (int) floor($amount + 0.5 + 1e-9);
    }

    private function assertTotal(int $total): void
    {
        if ($total > self::MAX_TOTAL) {
            throw $this->invalid('qty', 'Слишком большая сумма — уточните количество у менеджера');
        }
    }

    /** Единица количества из постфикса цены: «/ порц.» → «порц.», «за 10 человек» → «человек». */
    private function qtyUnit(string $postfix): string
    {
        $unit = trim((string) preg_replace(['~/~u', '~\bза\b~u', '~\d+~u'], '', $postfix));
        return $unit === '' ? 'шт' : $unit;
    }

    private function invalid(string $field, string $message): HttpError
    {
        return HttpError::validation([$field => $message]);
    }
}
