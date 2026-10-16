<?php

declare(strict_types=1);

namespace App\Auth;

use App\Http\HttpError;

/**
 * Российский номер в каноническом виде +7XXXXXXXXXX.
 * Для входа по SMS — только мобильный (+79…); контактный телефон заявки может быть городским.
 */
final class PhoneNumber
{
    private function __construct(public readonly string $value)
    {
    }

    public static function parse(mixed $raw, string $field = 'phone', bool $mobileOnly = true): self
    {
        $digits = is_string($raw) ? (string) preg_replace('/\D+/', '', $raw) : '';
        if (strlen($digits) === 10) {
            $digits = '7' . $digits;
        } elseif (strlen($digits) === 11 && $digits[0] === '8') {
            $digits = '7' . substr($digits, 1);
        }
        $pattern = $mobileOnly ? '/^79\d{9}$/' : '/^7[3-9]\d{9}$/';
        if (!preg_match($pattern, $digits)) {
            $hint = $mobileOnly ? 'мобильный номер' : 'номер';
            throw HttpError::validation([$field => "Введите {$hint} в формате +7 (999) 999-99-99"]);
        }
        return new self('+' . $digits);
    }

    public function masked(): string
    {
        return sprintf('+7 (%s) ***-**-%s', substr($this->value, 2, 3), substr($this->value, -2));
    }
}
