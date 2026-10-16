<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Catalog\VenueQuery;
use App\Catalog\VenueRepository;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;

final class VenueController
{
    public function __construct(private readonly VenueRepository $venues)
    {
    }

    public function list(Request $request): Response
    {
        $query = VenueQuery::fromRequest($request);
        $result = $this->venues->list($query);
        return Response::ok(
            ['items' => $result['items'], 'counts' => $result['counts']],
            ['total' => $result['total'], 'page' => $query->page, 'limit' => $query->limit],
        );
    }

    public function filters(Request $request): Response
    {
        return Response::ok($this->venues->filters());
    }

    public function show(Request $request): Response
    {
        $id = (string) $request->attribute('id');
        $venue = preg_match('/^\d{1,10}$/', $id) ? $this->venues->venue((int) $id) : null;
        return Response::ok($venue ?? throw HttpError::notFound('Площадка'));
    }
}
