<?php

declare(strict_types=1);

namespace App\Http;

/**
 * Маршрутизатор: шаблоны вида /v1/products/{id}. Параметры попадают в атрибуты запроса.
 * Middleware — callable(Request, callable $next): Response, применяются к группе маршрутов.
 */
final class Router
{
    /** @var list<array{method: string, regex: string, params: list<string>, handler: callable, middleware: list<callable>}> */
    private array $routes = [];

    /** @param list<callable> $middleware */
    public function add(string $method, string $pattern, callable $handler, array $middleware = []): void
    {
        preg_match_all('/\{(\w+)\}/', $pattern, $m);
        $regex = '#^' . preg_replace('/\\\\\{\w+\\\\\}/', '([^/]+)', preg_quote($pattern, '#')) . '$#';
        $this->routes[] = [
            'method' => $method,
            'regex' => $regex,
            'params' => $m[1],
            'handler' => $handler,
            'middleware' => $middleware,
        ];
    }

    public function dispatch(Request $request): Response
    {
        $allowed = [];
        foreach ($this->routes as $route) {
            if (!preg_match($route['regex'], $request->path, $matches)) {
                continue;
            }
            if ($route['method'] !== $request->method) {
                $allowed[] = $route['method'];
                continue;
            }
            foreach ($route['params'] as $i => $name) {
                $request = $request->withAttribute($name, rawurldecode($matches[$i + 1]));
            }
            return $this->pipeline($route['middleware'], $route['handler'])($request);
        }
        if ($allowed !== []) {
            throw new HttpError(405, 'method_not_allowed', 'Метод не поддерживается');
        }
        throw HttpError::notFound('Маршрут');
    }

    /** @param list<callable> $middleware */
    private function pipeline(array $middleware, callable $handler): callable
    {
        $next = static fn (Request $r): Response => $handler($r);
        foreach (array_reverse($middleware) as $mw) {
            $next = static fn (Request $r): Response => $mw($r, $next);
        }
        return $next;
    }
}
