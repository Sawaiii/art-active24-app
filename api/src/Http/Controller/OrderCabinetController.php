<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Loyalty\LoyaltyService;
use App\Orders\Composition\CompositionService;
use App\Orders\Documents\OrderDocumentsSource;
use App\Orders\Feedback\ClaimService;
use App\Orders\Feedback\ReviewService;
use App\Orders\OrderService;
use App\Orders\Vehicle\VehicleService;

/**
 * Личный кабинет заказа (клиент): состав, машина, отзыв, претензии, документы, скидка.
 * Доступ к заказу — через OrderService::context (свой заказ или любой для менеджера).
 */
final class OrderCabinetController
{
    public function __construct(
        private readonly OrderService $orders,
        private readonly CompositionService $composition,
        private readonly VehicleService $vehicles,
        private readonly ReviewService $reviews,
        private readonly ClaimService $claims,
        private readonly OrderDocumentsSource $documents,
        private readonly LoyaltyService $loyalty,
    ) {
    }

    public function composition(Request $request): Response
    {
        return Response::ok($this->composition->forOrder($this->order($request)));
    }

    public function vehicle(Request $request): Response
    {
        return Response::ok($this->vehicles->forCustomer($this->order($request)));
    }

    public function review(Request $request): Response
    {
        $result = $this->reviews->submit($this->order($request), $this->userId($request), $request->json());
        return $result['created'] ? Response::created($result['review']) : Response::ok($result['review']);
    }

    public function claims(Request $request): Response
    {
        return Response::ok($this->claims->forOrder($this->order($request)));
    }

    public function createClaim(Request $request): Response
    {
        return Response::created($this->claims->create($this->order($request), $this->userId($request), $request->json()));
    }

    public function documents(Request $request): Response
    {
        return Response::ok($this->documents->documents($this->order($request)));
    }

    public function loyalty(Request $request): Response
    {
        return Response::ok($this->loyalty->summary($this->userId($request)));
    }

    /** @return array<string, mixed> Order + связи */
    private function order(Request $request): array
    {
        return $this->orders->context($request->attribute('user'), self::id($request));
    }

    private function userId(Request $request): int
    {
        return (int) $request->attribute('user')['id'];
    }

    public static function id(Request $request, string $name = 'id'): int
    {
        $id = (string) $request->attribute($name);
        if (!preg_match('/^\d{1,10}$/', $id)) {
            throw HttpError::notFound('Заказ');
        }
        return (int) $id;
    }
}
