<?php

declare(strict_types=1);

namespace App\Orders;

/**
 * Текст заявки для менеджеров — в том же виде, что формирует корзина сайта
 * («<Название. «Комплект». арт.: 07138> x N шт.»), чтобы менеджерам было привычно.
 * Необязательные поля заявки могут отсутствовать.
 */
final class OrderText
{
    /** @param array<string, mixed> $order */
    public static function summary(array $order): string
    {
        $out = ["Заявка {$order['number']} из мобильного приложения"];
        $name = $order['contactName'] ?? null;
        $out[] = 'Телефон: ' . $order['contactPhone'] . ($name ? " ({$name})" : '');

        $from = $order['eventDate'] ?? null;
        if ($from) {
            $to = $order['eventDateTo'] ?? null;
            $out[] = 'Дата мероприятия: ' . self::date((string) $from) . ($to ? ' – ' . self::date((string) $to) : '');
        }
        $delivery = $order['delivery'] ?? null;
        if (is_array($delivery)) {
            $out[] = $delivery['method'] === 'pickup'
                ? 'Самовывоз.'
                : 'Доставка. Адрес доставки: ' . ($delivery['address'] ?? '') . '.';
        }
        if (!empty($order['subject'])) {
            $out[] = 'Запрос: ' . $order['subject'];
        }
        foreach ($order['lines'] ?? [] as $line) {
            $out[] = self::line($line);
        }
        $discount = $order['discount'] ?? null;
        if (is_array($discount) && !empty($discount['amount'])) {
            $out[] = 'Сумма позиций: ' . self::rub((int) ($order['subtotal'] ?? 0));
            $out[] = $discount['title'] . ': −' . self::rub((int) $discount['amount']);
        }
        if (!empty($order['lines'])) {
            $out[] = 'Итого (предварительно): ' . self::rub((int) $order['total'])
                . (!empty($order['hasOnRequest']) ? ' + позиции по запросу' : '');
        }
        if (!empty($order['comment'])) {
            $out[] = 'Комментарий: ' . $order['comment'];
        }
        return implode("\n", $out);
    }

    /** @param array<string, mixed> $line */
    private static function line(array $line): string
    {
        $parts = array_filter([
            $line['productName'] ?? null,
            $line['complectTitle'] ?? null,
            $line['subTitle'] ?? null,
            $line['timeLabel'] ?? null,
        ]);
        $text = implode('. ', $parts) . (!empty($line['art']) ? ". арт.: {$line['art']}" : '');
        $text .= ' x ' . $line['qty'] . ' ' . ($line['qtyUnit'] ?? 'шт');
        $text .= !empty($line['onRequest']) ? ' — цена по запросу' : ' — ' . self::rub((int) $line['total']);
        foreach ($line['extras'] ?? [] as $extra) {
            $text .= "\n    + {$extra['name']}" . ($extra['qty'] > 1 ? " × {$extra['qty']}" : '');
        }
        return $text;
    }

    private static function rub(int $amount): string
    {
        return number_format($amount, 0, '', ' ') . ' ₽';
    }

    private static function date(string $iso): string
    {
        $d = \DateTimeImmutable::createFromFormat('Y-m-d', $iso);
        return $d === false ? $iso : $d->format('d.m.Y');
    }
}
