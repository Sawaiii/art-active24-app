<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Catalog\ContentRepository;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;

/**
 * «Акции» (/sale/ сайта) и кейсы («Примеры работ», /cases/).
 */
final class ContentController
{
    public function __construct(private readonly ContentRepository $content)
    {
    }

    public function sale(Request $request): Response
    {
        return Response::ok($this->content->sale());
    }

    public function cases(Request $request): Response
    {
        $raw = $request->query['category'] ?? null;
        $category = null;
        if ($raw !== null && $raw !== '') {
            if (!preg_match('/^\d{1,6}$/', (string) $raw)) {
                throw HttpError::validation(['category' => 'Неизвестная рубрика']);
            }
            $category = (int) $raw;
        }
        $list = $this->content->cases($category);
        return Response::ok($list, ['total' => count($list['items'])]);
    }

    public function caseStudy(Request $request): Response
    {
        $case = $this->content->caseStudy(strtolower((string) $request->attribute('slug')));
        return Response::ok($case ?? throw HttpError::notFound('Кейс'));
    }
}
