<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Http\Request;
use App\Http\Response;
use App\Orders\Vehicle\VehicleService;

/**
 * Приложение водителя: точки машины по токену заказа (без входа по SMS).
 */
final class DriverController
{
    public function __construct(private readonly VehicleService $vehicles)
    {
    }

    public function location(Request $request): Response
    {
        return Response::ok($this->vehicles->acceptLocation(
            OrderCabinetController::id($request),
            $request->bearerToken(),
            $request->json(),
        ));
    }
}
