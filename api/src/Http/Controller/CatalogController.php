<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Catalog\CatalogRepository;
use App\Catalog\ContentRepository;
use App\Catalog\ProductQuery;
use App\Catalog\VenueRepository;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;

final class CatalogController
{
    private const VENUES_PREFIX = 'arenda-ploshchadki';

    public function __construct(
        private readonly CatalogRepository $catalog,
        private readonly VenueRepository $venues,
        private readonly ContentRepository $content,
    ) {
    }

    public function home(Request $request): Response
    {
        return Response::ok($this->content->home());
    }

    public function info(Request $request): Response
    {
        return Response::ok($this->content->info());
    }

    public function tree(Request $request): Response
    {
        return Response::ok($this->catalog->categoryTree());
    }

    public function category(Request $request): Response
    {
        $page = $this->catalog->categoryPage($this->id($request)) ?? throw HttpError::notFound('Раздел');
        return Response::ok($page);
    }

    public function categoryProducts(Request $request): Response
    {
        $id = $this->id($request);
        if ($this->catalog->categoryPage($id) === null) {
            throw HttpError::notFound('Раздел');
        }
        $query = ProductQuery::fromRequest($id, $request);
        $page = $this->catalog->listProducts($query);
        return Response::ok(
            ['items' => $page->items, 'facets' => $page->facets],
            ['total' => $page->total, 'page' => $query->page, 'limit' => $query->limit],
        );
    }

    public function product(Request $request): Response
    {
        $product = $this->catalog->product($this->id($request)) ?? throw HttpError::notFound('Товар');
        return Response::ok($product);
    }

    public function resolve(Request $request): Response
    {
        $path = (string) ($request->query['path'] ?? '');
        $path = (string) (parse_url($path, PHP_URL_PATH) ?? '');
        $segments = array_values(array_filter(explode('/', trim($path, '/'))));
        if ($segments === [] || count($segments) > 4) {
            throw HttpError::notFound('Страница');
        }
        if ($segments[0] === self::VENUES_PREFIX && isset($segments[1])) {
            $venueId = $this->venues->idBySlug($segments[1]);
            if ($venueId !== null) {
                return Response::ok(['type' => 'venue', 'id' => $venueId]);
            }
        }
        $resolved = $this->catalog->resolvePath($path)
            ?? ['type' => 'web', 'url' => 'https://www.art-active24.ru/' . implode('/', $segments) . '/'];
        return Response::ok($resolved);
    }

    public function search(Request $request): Response
    {
        $q = trim((string) ($request->query['q'] ?? ''));
        if (mb_strlen($q) < 2 || mb_strlen($q) > 100) {
            throw HttpError::validation(['q' => 'Введите от 2 до 100 символов']);
        }
        $page = $request->queryInt('page', 1, 1, 1000);
        $limit = $request->queryInt('limit', 24, 1, 60);
        $result = $this->catalog->search($q, ($page - 1) * $limit, $limit);
        return Response::ok(
            ['products' => $result['products'], 'categories' => $result['categories'], 'correctedQuery' => null],
            ['total' => $result['total'], 'page' => $page, 'limit' => $limit],
        );
    }

    private function id(Request $request): int
    {
        $id = (string) $request->attribute('id');
        if (!preg_match('/^\d{1,10}$/', $id)) {
            throw HttpError::notFound();
        }
        return (int) $id;
    }
}
