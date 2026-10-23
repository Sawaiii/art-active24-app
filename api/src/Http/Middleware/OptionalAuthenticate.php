<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Auth\ManagerPolicy;
use App\Auth\SessionService;
use App\Http\Request;
use App\Http\Response;
use App\Users\UserRepository;

/**
 * Пользователь, если пришёл действующий access-токен; иначе запрос идёт как гостевой
 * (публичный пересчёт корзины: со входом — со скидкой постоянного клиента, без — без неё).
 */
final class OptionalAuthenticate
{
    public function __construct(
        private readonly SessionService $sessions,
        private readonly UserRepository $users,
        private readonly ManagerPolicy $managers,
    ) {
    }

    public function __invoke(Request $request, callable $next): Response
    {
        $token = $request->bearerToken();
        $userId = $token === null ? null : $this->sessions->authenticate($token);
        $user = $userId === null ? null : $this->users->find($userId);
        return $next($user === null ? $request : $request->withAttribute('user', $this->managers->apply($user)));
    }
}
