<?php

declare(strict_types=1);

namespace App\Catalog;

/**
 * Нормализация текста для поиска: нижний регистр, ё → е, кавычки и знаки → пробел.
 */
final class TextNormalizer
{
    public static function normalize(string $text): string
    {
        $text = mb_strtolower($text, 'UTF-8');
        $text = str_replace('ё', 'е', $text);
        $text = (string) preg_replace('/[^\p{L}\p{N}]+/u', ' ', $text);
        return trim($text);
    }

    /** @return list<string> */
    public static function words(string $text): array
    {
        $normalized = self::normalize($text);
        return $normalized === '' ? [] : array_values(array_unique(explode(' ', $normalized)));
    }
}
