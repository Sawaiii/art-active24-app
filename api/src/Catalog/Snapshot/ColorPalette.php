<?php

declare(strict_types=1);

namespace App\Catalog\Snapshot;

/**
 * Цвет-образец для фильтра «Цвет» по названию характеристики (как кружки на сайте).
 */
final class ColorPalette
{
    private const MAP = [
        'белый' => '#FFFFFF', 'черный' => '#1A1A1A', 'серый' => '#9E9E9E', 'бежевый' => '#E8D9C0',
        'коричневый' => '#7B4B2A', 'красный' => '#E53935', 'бордовый' => '#7B1E2B', 'розовый' => '#F48FB1',
        'оранжевый' => '#FB8C00', 'желтый' => '#FDD835', 'зеленый' => '#43A047', 'оливковый' => '#808000',
        'голубой' => '#64B5F6', 'синий' => '#1E40AF', 'бирюзовый' => '#26C6DA', 'фиолетовый' => '#7E57C2',
        'золотой' => '#D4AF37', 'серебряный' => '#C0C0C0', 'прозрачный' => '#F5F5F7', 'дерево' => '#A0703C',
        'натуральный' => '#C8A27A', 'капучино' => '#B79E86', 'графит' => '#3D3D3D', 'хром' => '#D9D9D9',
    ];

    public static function hex(string $name): ?string
    {
        $key = self::known(self::normalize($name));
        return $key === null ? null : self::MAP[$key];
    }

    /**
     * Единое название цвета для фильтра: «Чёрный»/«черный» → «Черный», «Золото»/«Золотой» → «Золотой».
     * Неизвестный цвет остаётся собой (с заглавной буквы).
     */
    public static function canonical(string $name): string
    {
        $normalized = self::normalize($name);
        $key = self::known($normalized) ?? $normalized;
        return mb_strtoupper(mb_substr($key, 0, 1, 'UTF-8'), 'UTF-8') . mb_substr($key, 1, null, 'UTF-8');
    }

    private static function normalize(string $name): string
    {
        return str_replace('ё', 'е', mb_strtolower(trim($name), 'UTF-8'));
    }

    /** Ключ палитры: точное совпадение или та же основа слова (первые 4 буквы: «золото» → «золотой»). */
    private static function known(string $normalized): ?string
    {
        if (isset(self::MAP[$normalized])) {
            return $normalized;
        }
        // Род и число прилагательного: «белая», «белое», «белые» → «белый».
        if (preg_match('~^(.+?)(ая|яя|ое|ее|ые|ие)$~u', $normalized, $m)) {
            foreach (['ый', 'ий', 'ой'] as $ending) {
                if (isset(self::MAP[$m[1] . $ending])) {
                    return $m[1] . $ending;
                }
            }
        }
        foreach (array_keys(self::MAP) as $color) {
            if (mb_strlen($normalized) >= 4 && str_starts_with($normalized, mb_substr($color, 0, 4))) {
                return $color;
            }
        }
        return null;
    }
}
