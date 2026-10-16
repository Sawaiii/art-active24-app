<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Auth\ManagerPolicy;
use App\Auth\SessionService;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Users\UserRepository;

/**
 * Требует действующий access-токен; кладёт пользователя в атрибут 'user'.
 * Роль вычисляется заново на каждый запрос (ManagerPolicy). С $role = 'manager' — только менеджерам.
 */
final class Authenticate
{
    public function __construct(
        private readonly SessionService $sessions,
        private readonly UserRepository $users,
        private readonly ManagerPolicy $managers,
        private readonly ?string $role = null,
    ) {
    }

    public function __invoke(Request $request, callable $next): Response
    {
        $token = $request->bearerToken() ?? throw HttpError::unauthorized();
        $userId = $this->sessions->authenticate($token) ?? throw new HttpError(401, 'token_expired', 'Сессия истекла');
        $user = $this->users->find($userId) ?? throw HttpError::unauthorized();
        $user = $this->managers->apply($user);
        if ($this->role !== null && $user['role'] !== $this->role) {
            throw HttpError::forbidden();
        }
        return $next($request->withAttribute('user', $user)->withAttribute('token', $token));
    }
}
