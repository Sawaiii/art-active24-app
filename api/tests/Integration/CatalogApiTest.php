<?php

declare(strict_types=1);

namespace Tests\Integration;

final class CatalogApiTest extends ApiTestCase
{
    public function testTreeIsNestedAndSorted(): void
    {
        $res = $this->call('GET', '/v1/catalog/tree');

        $this->assertSame(200, $res['status']);
        $this->assertSame(['Мебель', 'Кейтеринг', 'Персонал'], array_column($res['body']['data'], 'name'));
        $this->assertSame('Столы', $res['body']['data'][0]['children'][0]['name']);
    }

    public function testTreeShowsOnlyMenuCategoriesButOthersStayReachable(): void
    {
        $names = array_column($this->call('GET', '/v1/catalog/tree')['body']['data'], 'name');

        $this->assertNotContains('Мини бургеры', $names);
        $this->assertSame(200, $this->call('GET', '/v1/categories/805')['status'], 'раздел вне меню открывается по ссылке');
    }

    public function testResolveVariantStoredAsFullPath(): void
    {
        $res = $this->call('GET', '/v1/resolve?path=' . rawurlencode('/plov/kupit-plov/'))['body']['data'];

        $this->assertSame(['type' => 'product', 'id' => 469, 'complectId' => 1590, 'priceType' => 'buy'], $res);
    }

    public function testCategoryPageHasBreadcrumbsAndChildren(): void
    {
        $res = $this->call('GET', '/v1/categories/225');

        $this->assertSame([['id' => 257, 'name' => 'Мебель']], $res['body']['data']['breadcrumbs']);
        $this->assertSame([], $res['body']['data']['children']);
        $this->assertSame(404, $this->call('GET', '/v1/categories/999')['status']);
    }

    public function testListingSortsFiltersAndReturnsFacets(): void
    {
        $res = $this->call('GET', '/v1/categories/225/products?sort=price_high');
        $this->assertSame(['Стол чёрный', 'Стол складной Виктория 180 см'], array_column($res['body']['data']['items'], 'name'));
        $this->assertSame(['priceMin' => 770, 'priceMax' => 1500], array_intersect_key($res['body']['data']['facets'], ['priceMin' => 1, 'priceMax' => 1]));
        $this->assertSame(2, $res['body']['meta']['total']);
        $this->assertArrayNotHasKey('categoryIds', $res['body']['data']['items'][0], 'внутренние поля не утекают');

        $filtered = $this->call('GET', '/v1/categories/225/products?colors=' . rawurlencode('Белый'));
        $this->assertSame([7138], array_column($filtered['body']['data']['items'], 'id'));

        $this->assertSame(400, $this->call('GET', '/v1/categories/225/products?sort=random')['status']);
    }

    public function testProductAndMissingProduct(): void
    {
        $this->assertSame('07138', $this->call('GET', '/v1/products/7138')['body']['data']['art']);
        $this->assertSame(404, $this->call('GET', '/v1/products/1')['status']);
    }

    public function testResolveProductVariantVenueAndWebFallback(): void
    {
        $variant = $this->call('GET', '/v1/resolve?path=' . rawurlencode('/plov/plov-s-kuricey/'))['body']['data'];
        $this->assertSame(['type' => 'product', 'id' => 469, 'complectId' => 1590, 'subId' => '1591', 'priceType' => 'rent'], $variant);

        $category = $this->call('GET', '/v1/resolve?path=' . rawurlencode('https://www.art-active24.ru/arenda-stolov/'))['body']['data'];
        $this->assertSame(['type' => 'category', 'id' => 225], $category);

        $venue = $this->call('GET', '/v1/resolve?path=/arenda-ploshchadki/loft-idealista/')['body']['data'];
        $this->assertSame(['type' => 'venue', 'id' => 1], $venue);

        $web = $this->call('GET', '/v1/resolve?path=/o-nas/')['body']['data'];
        $this->assertSame('web', $web['type']);
    }

    public function testSearchIgnoresCaseAndYo(): void
    {
        $res = $this->call('GET', '/v1/search?q=' . rawurlencode('стол ЧЕРНЫЙ'));

        $this->assertSame(7140, $res['body']['data']['products'][0]['id']);
        $this->assertSame(422, $this->call('GET', '/v1/search?q=a')['status']);
    }

    public function testVenueFacetsCountOtherGroups(): void
    {
        $res = $this->call('GET', '/v1/venues?events=2');

        $this->assertSame([1], array_column($res['body']['data']['items'], 'id'));
        // Счётчики своей группы не сужаются её же выбором: корпоратив по-прежнему у обеих площадок.
        $this->assertSame(2, $res['body']['data']['counts']['events'][6]);
        $this->assertSame(1, $res['body']['data']['counts']['types'][7]);
        $this->assertArrayNotHasKey('events', $res['body']['data']['items'][0]);

        $this->assertSame([1], array_column($this->call('GET', '/v1/venues?collection=900002')['body']['data']['items'], 'id'));
        $this->assertSame([2], array_column($this->call('GET', '/v1/venues?priceTo=20000')['body']['data']['items'], 'id'));
        $this->assertSame([1], array_column($this->call('GET', '/v1/venues?props=3,5')['body']['data']['items'], 'id'));
    }

    public function testHomeFillsProductSections(): void
    {
        $sections = $this->call('GET', '/v1/home')['body']['data']['sections'];

        $this->assertSame(7140, $sections[1]['products'][0]['id'], 'новинки — по createdRank');
        $this->assertArrayNotHasKey('productIds', $sections[1]);
    }

    public function testUnknownRouteAndMethod(): void
    {
        $this->assertSame(404, $this->call('GET', '/v1/nope')['status']);
        $this->assertSame(405, $this->call('DELETE', '/v1/home')['status']);
    }
}
