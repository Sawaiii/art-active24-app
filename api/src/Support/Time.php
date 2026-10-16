<?php

declare(strict_types=1);

namespace App\Support;

/**
 * Единый формат хранения времени в БД (UTC 'Y-m-d H:i:s') и вывода в API (ISO-8601).
 */
final class Time
{
    public const DB_FORMAT = 'Y-m-d H:i:s';

    public static function toDb(\DateTimeImmutable $time): string
    {
        return $time->setTimezone(new \DateTimeZone('UTC'))->format(self::DB_FORMAT);
    }

    public static function toApi(?string $dbValue): ?string
    {
        if ($dbValue === null || $dbValue === '') {
            return null;
        }
        $time = \DateTimeImmutable::createFromFormat(self::DB_FORMAT, $dbValue, new \DateTimeZone('UTC'));
        return $time === false ? null : $time->format('Y-m-d\TH:i:s\Z');
    }
}
