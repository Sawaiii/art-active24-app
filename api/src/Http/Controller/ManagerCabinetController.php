<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Loyalty\LoyaltyService;
use App\Orders\Composition\CompositionService;
use App\Orders\Documents\ManagerDocumentsSource;
use App\Orders\Feedback\ClaimService;
use App\Orders\OrderService;
use App\Orders\Vehicle\VehicleService;

/**
 * Менеджер: состав из КП, документы, водитель, связи с CRM / Вызов Чатом, претензии, скидка клиента.
 */
final class ManagerCabinetController
{
    public function __construct(
        private readonly OrderService $orders,
        private readonly CompositionService $composition,
        private readonly ManagerDocumentsSource $documents,
        private readonly VehicleService $vehicles,
        private readonly ClaimService $claims,
        private readonly LoyaltyService $loyalty,
    ) {
    }

    public function putComposition(Request $request): Response
    {
        $order = $this->orders->context($request->attribute('user'), OrderCabinetController::id($request));
        return Response::ok($this->composition->attach($order, $request->json(), $this->managerId($request)));
    }

    public function deleteComposition(Request $request): Response
    {
        $order = $this->orders->context($request->attribute('user'), OrderCabinetController::id($request));
        $this->composition->detach((int) $order['id']);
        return Response::noContent();
    }

    public function addDocument(Request $request): Response
    {
        $order = $this->orders->context($request->attribute('user'), OrderCabinetController::id($request));
        return Response::created($this->documents->add((int) $order['id'], $request->json(), $this->managerId($request)));
    }

    public function deleteDocument(Request $request): Response
    {
        $order = $this->orders->context($request->attribute('user'), OrderCabinetController::id($request));
        $this->documents->delete((int) $order['id'], (string) $request->attribute('docId'));
        return Response::noContent();
    }

    public function assignDriver(Request $request): Response
    {
        return Response::created($this->vehicles->assign(OrderCabinetController::id($request), $request->json()));
    }

    public function links(Request $request): Response
    {
        return Response::ok($this->orders->setLinks(OrderCabinetController::id($request), $request->json()));
    }

    public function claims(Request $request): Response
    {
        $page = $request->queryInt('page', 1, 1, 1000);
        $limit = $request->queryInt('limit', 24, 1, 60);
        $result = $this->claims->listForManager($request->query['status'] ?? null, $page, $limit);
        return Response::ok($result['items'], ['total' => $result['total'], 'page' => $page, 'limit' => $limit]);
    }

    public function updateClaim(Request $request): Response
    {
        return Response::ok($this->claims->managerUpdate(OrderCabinetController::id($request), $request->json()));
    }

    public function loyalty(Request $request): Response
    {
        return Response::ok($this->loyalty->summaryForUser(OrderCabinetController::id($request)));
    }

    public function setLoyalty(Request $request): Response
    {
        $body = $request->json();
        if (!array_key_exists('percent', $body)) {
            throw HttpError::validation(['percent' => 'Укажите скидку или null, чтобы снять']);
        }
        return Response::ok($this->loyalty->setOverride(OrderCabinetController::id($request), $body['percent'], $body['note'] ?? null));
    }

    private function managerId(Request $request): int
    {
        return (int) $request->attribute('user')['id'];
    }
}
