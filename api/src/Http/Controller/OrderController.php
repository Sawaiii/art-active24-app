<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Orders\OrderService;
use App\Orders\OrderStatus;

final class OrderController
{
    public function __construct(private readonly OrderService $orders)
    {
    }

    public function list(Request $request): Response
    {
        $page = $request->queryInt('page', 1, 1, 1000);
        $limit = $request->queryInt('limit', 24, 1, 60);
        $result = $this->orders->listForUser($request->attribute('user'), $page, $limit);
        return Response::ok($result['items'], ['total' => $result['total'], 'page' => $page, 'limit' => $limit]);
    }

    public function show(Request $request): Response
    {
        return Response::ok($this->orders->get($request->attribute('user'), $this->id($request)));
    }

    public function create(Request $request): Response
    {
        return Response::created($this->orders->checkout($request->attribute('user'), $request->json(), $this->idempotencyKey($request)));
    }

    public function createRequest(Request $request): Response
    {
        return Response::created($this->orders->createRequest($request->attribute('user'), $request->json(), $this->idempotencyKey($request)));
    }

    public function cancel(Request $request): Response
    {
        return Response::ok($this->orders->cancel($request->attribute('user'), $this->id($request)));
    }

    public function managerList(Request $request): Response
    {
        $status = isset($request->query['status'])
            ? (OrderStatus::tryFrom($request->query['status']) ?? throw HttpError::badRequest('invalid_status', 'Неизвестный статус'))
            : null;
        $page = $request->queryInt('page', 1, 1, 1000);
        $limit = $request->queryInt('limit', 24, 1, 60);
        $result = $this->orders->listForManager($status, $request->query['q'] ?? null, $page, $limit);
        return Response::ok($result['items'], ['total' => $result['total'], 'page' => $page, 'limit' => $limit]);
    }

    public function managerUpdate(Request $request): Response
    {
        return Response::ok($this->orders->managerUpdate($request->attribute('user'), $this->id($request), $request->json()));
    }

    private function idempotencyKey(Request $request): string
    {
        $key = $request->header('idempotency-key');
        if ($key === null || !preg_match('/^[A-Za-z0-9_-]{8,64}$/', $key)) {
            throw HttpError::badRequest('idempotency_key_required', 'Нужен заголовок Idempotency-Key (8–64 символа)');
        }
        return $key;
    }

    private function id(Request $request): int
    {
        $id = (string) $request->attribute('id');
        if (!preg_match('/^\d{1,10}$/', $id)) {
            throw HttpError::notFound('Заказ');
        }
        return (int) $id;
    }
}
