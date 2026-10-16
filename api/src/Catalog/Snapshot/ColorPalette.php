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
        $key = str_replace('ё', 'е', mb_strtolower(trim($name), 'UTF-8'));
        if (isset(self::MAP[$key])) {
            return self::MAP[$key];
        }
        foreach (self::MAP as $color => $hex) {
            if (str_starts_with($key, mb_substr($color, 0, 4))) {
                return $hex;
            }
        }
        return null;
    }
}
