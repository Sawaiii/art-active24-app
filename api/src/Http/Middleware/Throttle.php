<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Http\Request;
use App\Http\Response;
use App\Support\RateLimiter;

/**
 * Лимит запросов с одного адреса для «тяжёлых» публичных эндпоинтов (пересчёт корзины, поиск).
 */
final class Throttle
{
    public function __construct(
        private readonly RateLimiter $limiter,
        private readonly string $name,
        private readonly int $perMinute,
    ) {
    }

    public function __invoke(Request $request, callable $next): Response
    {
        $this->limiter->hit("throttle:{$this->name}:" . RateLimiter::ipBucket($request->clientIp), $this->perMinute, 60);
        return $next($request);
    }
}
