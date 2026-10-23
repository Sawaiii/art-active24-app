<?php

declare(strict_types=1);

namespace App\Orders\Composition;

use App\Http\HttpError;
use App\Pricing\PriceCalculator;

/**
 * Проверка и нормализация состава (CompositionInput → тело OrderComposition без source/version):
 * суммы строк, итоги разделов, subtotal и total считаются здесь. Используется для JSON менеджера
 * и (после маппинга формата) для «Программы КП».
 */
final class CompositionNormalizer
{
    public const MAX_SECTIONS = 20;
    public const MAX_LINES = 200;
    public const MAX_DISCOUNTS = 5;
    private const DISCOUNT_KINDS = ['loyalty', 'promo', 'manual'];

    /**
     * @param array<string, mixed> $input
     * @return array<string, mixed>
     */
    public function normalize(array $input): array
    {
        $errors = [];
        $rawSections = $input['sections'] ?? null;
        if (!is_array($rawSections) || !array_is_list($rawSections) || $rawSections === [] || count($rawSections) > self::MAX_SECTIONS) {
            throw HttpError::validation(['sections' => 'От 1 до ' . self::MAX_SECTIONS . ' разделов']);
        }
        $sections = [];
        $linesTotal = 0;
        foreach ($rawSections as $s => $raw) {
            $path = "sections.{$s}";
            $raw = is_array($raw) ? $raw : [];
            $title = $this->text($raw['title'] ?? null, 100, "{$path}.title", $errors, required: true);
            $rawLines = $raw['lines'] ?? null;
            if (!is_array($rawLines) || !array_is_list($rawLines) || $rawLines === []) {
                $errors["{$path}.lines"] = 'В разделе нужна хотя бы одна строка';
                continue;
            }
            $linesTotal += count($rawLines);
            $lines = [];
            foreach ($rawLines as $l => $line) {
                $lines[] = $this->line(is_array($line) ? $line : [], "{$path}.lines.{$l}", $errors);
            }
            $sections[] = [
                'id' => 's' . ($s + 1),
                'title' => (string) $title,
                'lines' => $lines,
                'subtotal' => min(array_sum(array_column($lines, 'sum')), PriceCalculator::MAX_TOTAL),
            ];
        }
        if ($linesTotal > self::MAX_LINES) {
            $errors['sections'] = 'Не больше ' . self::MAX_LINES . ' строк';
        }
        $discounts = $this->discounts($input['discounts'] ?? null, $errors);
        $delivery = $this->money($input['delivery'] ?? null, 'delivery', $errors);
        $total = $this->money($input['total'] ?? null, 'total', $errors);
        $meta = [
            'kpNumber' => $this->text($input['kpNumber'] ?? null, 50, 'kpNumber', $errors),
            'kpDate' => $this->date($input['kpDate'] ?? null, 'kpDate', $errors),
            'title' => $this->text($input['title'] ?? null, 200, 'title', $errors),
            'deliveryNote' => $this->text($input['deliveryNote'] ?? null, 200, 'deliveryNote', $errors),
            'vatNote' => $this->text($input['vatNote'] ?? null, 200, 'vatNote', $errors),
        ];
        if ($errors !== []) {
            throw HttpError::validation($errors);
        }

        $subtotal = min(array_sum(array_column($sections, 'subtotal')), PriceCalculator::MAX_TOTAL);
        $computed = max(0, $subtotal - array_sum(array_column($discounts, 'amount')) + ($delivery ?? 0));
        return $meta + [
            'sections' => $sections,
            'subtotal' => $subtotal,
            'discounts' => $discounts === [] ? null : $discounts,
            'delivery' => $delivery,
            'total' => $total ?? min($computed, PriceCalculator::MAX_TOTAL),
            'hasOnRequest' => array_filter(
                array_merge(...array_column($sections, 'lines')),
                static fn (array $l) => !empty($l['onRequest']),
            ) !== [],
        ];
    }

    /**
     * @param array<string, mixed> $raw
     * @param array<string, string> $errors
     * @return array<string, mixed>
     */
    private function line(array $raw, string $path, array &$errors): array
    {
        $qty = $raw['qty'] ?? null;
        if (!(is_int($qty) || is_float($qty)) || $qty < 0 || $qty > 100000) {
            $errors["{$path}.qty"] = 'Количество — число от 0 до 100 000';
            $qty = 0;
        }
        $days = $raw['days'] ?? null;
        if ($days !== null && (!is_int($days) || $days < 1 || $days > 365)) {
            $errors["{$path}.days"] = 'Срок — целое число дней от 1 до 365';
            $days = null;
        }
        $price = $this->money($raw['price'] ?? null, "{$path}.price", $errors) ?? 0;
        if (!array_key_exists('price', $raw)) {
            $errors["{$path}.price"] = 'Укажите цену';
        }
        $sum = $this->money($raw['sum'] ?? null, "{$path}.sum", $errors)
            ?? (int) min(floor($price * $qty * ($days ?? 1) + 0.5 + 1e-9), PriceCalculator::MAX_TOTAL);
        $onRequest = $raw['onRequest'] ?? false;
        return [
            'name' => (string) $this->text($raw['name'] ?? null, 300, "{$path}.name", $errors, required: true),
            'art' => $this->text($raw['art'] ?? null, 30, "{$path}.art", $errors),
            'qty' => is_float($qty) && floor($qty) === $qty ? (int) $qty : $qty,
            'unit' => $this->text($raw['unit'] ?? null, 20, "{$path}.unit", $errors) ?? 'шт',
            'days' => $days,
            'price' => $price,
            'sum' => $sum,
            'note' => $this->text($raw['note'] ?? null, 300, "{$path}.note", $errors),
            'onRequest' => $onRequest === true ? true : null,
        ];
    }

    /**
     * @param array<string, string> $errors
     * @return list<array<string, mixed>>
     */
    private function discounts(mixed $raw, array &$errors): array
    {
        if ($raw === null) {
            return [];
        }
        if (!is_array($raw) || !array_is_list($raw) || count($raw) > self::MAX_DISCOUNTS) {
            $errors['discounts'] = 'Не больше ' . self::MAX_DISCOUNTS . ' скидок';
            return [];
        }
        $out = [];
        foreach ($raw as $i => $item) {
            $item = is_array($item) ? $item : [];
            $kind = $item['kind'] ?? 'manual';
            if (!in_array($kind, self::DISCOUNT_KINDS, true)) {
                $errors["discounts.{$i}.kind"] = 'Тип скидки: loyalty, promo или manual';
            }
            $percent = $item['percent'] ?? null;
            if ($percent !== null && (!is_int($percent) || $percent < 0 || $percent > 100)) {
                $errors["discounts.{$i}.percent"] = 'Процент — от 0 до 100';
                $percent = null;
            }
            $out[] = [
                'kind' => is_string($kind) ? $kind : 'manual',
                'title' => (string) $this->text($item['title'] ?? null, 100, "discounts.{$i}.title", $errors, required: true),
                'percent' => $percent,
                'amount' => $this->money($item['amount'] ?? null, "discounts.{$i}.amount", $errors) ?? 0,
            ];
        }
        return $out;
    }

    /** @param array<string, string> $errors */
    private function money(mixed $value, string $field, array &$errors): ?int
    {
        if ($value === null) {
            return null;
        }
        if (!is_int($value) || $value < 0 || $value > PriceCalculator::MAX_TOTAL) {
            $errors[$field] = 'Сумма — целое число рублей до 1 000 000 000';
            return null;
        }
        return $value;
    }

    /** @param array<string, string> $errors */
    private function text(mixed $value, int $max, string $field, array &$errors, bool $required = false): ?string
    {
        if ($value === null || (is_string($value) && trim($value) === '')) {
            if ($required) {
                $errors[$field] = 'Обязательное поле';
            }
            return null;
        }
        if (!is_string($value) || mb_strlen(trim($value)) > $max) {
            $errors[$field] = "Текст до {$max} символов";
            return null;
        }
        return trim($value);
    }

    /** @param array<string, string> $errors */
    private function date(mixed $value, string $field, array &$errors): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        $date = is_string($value) ? \DateTimeImmutable::createFromFormat('!Y-m-d', $value) : false;
        if ($date === false || $date->format('Y-m-d') !== $value) {
            $errors[$field] = 'Дата в формате ГГГГ-ММ-ДД';
            return null;
        }
        return $value;
    }
}
