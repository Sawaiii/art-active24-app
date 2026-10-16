<?php

declare(strict_types=1);

namespace App\Catalog;

/**
 * Контент витрины: главная и справочная информация (контакты, доставка, условия).
 */
interface ContentRepository
{
    /** @return array{sections: list<array<string, mixed>>} */
    public function home(): array;

    /** @return array<string, mixed> Info */
    public function info(): array;
}
