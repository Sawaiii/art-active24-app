<?php

declare(strict_types=1);

namespace App\Catalog;

/**
 * Контент витрины: главная, справочная информация (контакты, доставка, условия),
 * «Акции» и кейсы («Примеры работ»).
 */
interface ContentRepository
{
    /** @return array{sections: list<array<string, mixed>>} */
    public function home(): array;

    /** @return array<string, mixed> Info */
    public function info(): array;

    /** @return array{title: string, items: list<array<string, mixed>>} Sale («Выгодные предложения») */
    public function sale(): array;

    /**
     * Список кейсов (CaseSummary) с рубриками; $categoryId — фильтр по рубрике.
     *
     * @return array{title: string, categories: list<array<string, mixed>>, items: list<array<string, mixed>>}
     */
    public function cases(?int $categoryId): array;

    /** @return array<string, mixed>|null Case — null, если кейса нет */
    public function caseStudy(string $slug): ?array;
}
