<?php

declare(strict_types=1);

namespace Tests\Integration;

use App\Catalog\Snapshot\SnapshotContentRepository;

/**
 * Кейсы, «Акции», секция «Выгодные предложения» главной и ссылка на Max в /v1/info.
 */
final class ContentApiTest extends ApiTestCase
{
    public function testCasesListReturnsSummariesAndCategories(): void
    {
        $res = $this->call('GET', '/v1/cases');

        $this->assertSame(200, $res['status']);
        $data = $res['body']['data'];
        $this->assertSame('Кейсы', $data['title']);
        $this->assertSame(['keytering-ng', 'serpuhov'], array_column($data['items'], 'slug'));
        $this->assertSame([2, 1], array_column($data['categories'], 'id'));
        $this->assertSame(2, $res['body']['meta']['total']);
        $this->assertSame(100, $data['items'][0]['guests']);
    }

    public function testCasesListFiltersByCategory(): void
    {
        $res = $this->call('GET', '/v1/cases?category=1');

        $this->assertSame(['serpuhov'], array_column($res['body']['data']['items'], 'slug'));
        $this->assertSame(422, $this->call('GET', '/v1/cases?category=abc')['status']);
    }

    public function testCaseDetailResolvesProductsAndDropsMissingOnes(): void
    {
        $res = $this->call('GET', '/v1/cases/keytering-ng');

        $this->assertSame(200, $res['status']);
        $case = $res['body']['data'];
        $this->assertSame('Новогодний кейтеринг', $case['title']);
        $this->assertSame([7138], array_column($case['products'], 'id'), 'нет товара 999999 — нет и плитки');
        $this->assertArrayNotHasKey('productIds', $case);
        $this->assertSame(['image', 'video'], array_column($case['media'], 'type'));
        $this->assertSame(['Задача', 'Решение'], array_column($case['sections'], 'title'));
        $this->assertSame(['id' => 2, 'name' => 'Кейтеринг'], $case['category']);
        $this->assertSame('serpuhov', $case['similar'][0]['slug']);
    }

    public function testCaseWithoutProductsHasEmptyRail(): void
    {
        $case = $this->call('GET', '/v1/cases/SERPUHOV')['body']['data'];

        $this->assertSame('serpuhov', $case['slug'], 'slug без учёта регистра, как адрес сайта');
        $this->assertSame([], $case['products']);
    }

    public function testUnknownOrMalformedCaseIsNotFound(): void
    {
        $this->assertSame(404, $this->call('GET', '/v1/cases/den-indii-2024')['status']);
        $this->assertSame(404, $this->call('GET', '/v1/cases/..%2Fhome')['status']);
        $this->assertSame(404, $this->call('GET', '/v1/cases/-bad')['status']);
        $this->assertSame('not_found', $this->call('GET', '/v1/cases/nope')['body']['error']['code']);
    }

    public function testHomeCaseTilesGetSlugOnlyWhenCaseExists(): void
    {
        $sections = $this->call('GET', '/v1/home')['body']['data']['sections'];
        $cases = $this->section($sections, 'cases');

        $this->assertSame('serpuhov', $cases['items'][0]['slug']);
        $this->assertArrayNotHasKey('slug', $cases['items'][1], 'кейса нет в снапшоте — плитка ведёт на сайт');
        $this->assertSame('https://www.art-active24.ru/cases/den-indii-2024/', $cases['items'][1]['url']);
    }

    public function testHomeOffersSectionKeepsSiteOrderAndTags(): void
    {
        $sections = $this->call('GET', '/v1/home')['body']['data']['sections'];
        $types = array_column($sections, 'type');
        $offers = $this->section($sections, 'offers');

        $this->assertGreaterThan(array_search('cases', $types, true), array_search('offers', $types, true));
        $this->assertSame(['Акция 1+1=3', 'Доставка бесплатно'], array_column($offers['items'], 'title'));
        $this->assertArrayNotHasKey('badge', $offers['items'][0]);
        $this->assertSame('Бонус', $offers['items'][1]['badge']);
    }

    public function testSaleReturnsOffers(): void
    {
        $res = $this->call('GET', '/v1/sale');

        $this->assertSame(200, $res['status']);
        $this->assertSame('Выгодные предложения', $res['body']['data']['title']);
        $this->assertSame(['Скидка', 'Бонус'], array_column($res['body']['data']['items'], 'badge'));
        $this->assertSame(405, $this->call('POST', '/v1/sale')['status']);
    }

    public function testResolveCaseAndSaleLinks(): void
    {
        $resolve = fn (string $path) => $this->call('GET', '/v1/resolve?path=' . rawurlencode($path))['body']['data'];

        $this->assertSame(['type' => 'case', 'slug' => 'keytering-ng'], $resolve('https://www.art-active24.ru/cases/keytering-ng/'));
        $this->assertSame(['type' => 'cases'], $resolve('/cases/'));
        $this->assertSame(['type' => 'sale'], $resolve('/sale/'));
        $this->assertSame('web', $resolve('/cases/den-indii-2024/')['type'], 'кейса нет — страница сайта');
    }

    public function testInfoPassesMaxLink(): void
    {
        $info = $this->call('GET', '/v1/info')['body']['data'];

        $this->assertSame('https://max.ru/u/art-active-test', $info['max']);
    }

    public function testCaseSlugFromUrl(): void
    {
        $this->assertSame('serpuhov', SnapshotContentRepository::caseSlugFromUrl('https://www.art-active24.ru/cases/serpuhov/'));
        $this->assertSame('a-b_1', SnapshotContentRepository::caseSlugFromUrl('/cases/A-B_1'));
        $this->assertNull(SnapshotContentRepository::caseSlugFromUrl('/cases/'));
        $this->assertNull(SnapshotContentRepository::caseSlugFromUrl('/plov/'));
        $this->assertNull(SnapshotContentRepository::caseSlugFromUrl('/cases/a/b/'));
    }

    /**
     * @param list<array<string, mixed>> $sections
     * @return array<string, mixed>
     */
    private function section(array $sections, string $type): array
    {
        foreach ($sections as $section) {
            if ($section['type'] === $type) {
                return $section;
            }
        }
        $this->fail("Нет секции {$type}");
    }
}
