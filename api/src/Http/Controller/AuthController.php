<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Auth\ManagerPolicy;
use App\Auth\OtpService;
use App\Auth\PhoneNumber;
use App\Auth\SessionService;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Users\UserRepository;

final class AuthController
{
    public function __construct(
        private readonly OtpService $otp,
        private readonly SessionService $sessions,
        private readonly UserRepository $users,
        private readonly ManagerPolicy $managers,
    ) {
    }

    public function requestCode(Request $request): Response
    {
        $phone = PhoneNumber::parse($request->json()['phone'] ?? null);
        $this->otp->request($phone, $request->clientIp);
        return Response::ok(['resendIn' => OtpService::RESEND_SECONDS, 'codeLength' => OtpService::CODE_LENGTH]);
    }

    public function verify(Request $request): Response
    {
        $body = $request->json();
        $phone = PhoneNumber::parse($body['phone'] ?? null);
        $code = $body['code'] ?? null;
        if (!is_string($code) || !preg_match('/^\d{' . OtpService::CODE_LENGTH . '}$/', trim($code))) {
            throw HttpError::validation(['code' => 'Введите код из SMS']);
        }
        $this->otp->verify($phone, $code, $request->clientIp);

        [$user, $isNew] = $this->users->findOrCreate($phone->value);
        $user = $this->managers->apply($user);
        $tokens = $this->sessions->issue((int) $user['id'], $request->header('user-agent'));
        return Response::ok($tokens + ['user' => $user, 'isNew' => $isNew]);
    }

    public function refresh(Request $request): Response
    {
        $token = $request->json()['refreshToken'] ?? null;
        if (!is_string($token) || $token === '' || strlen($token) > 200) {
            throw HttpError::unauthorized('Сессия истекла, войдите снова');
        }
        $result = $this->sessions->refresh($token);
        $user = $this->users->find($result['userId']) ?? throw HttpError::unauthorized();
        unset($result['userId']);
        return Response::ok($result + ['user' => $this->managers->apply($user), 'isNew' => false]);
    }

    public function logout(Request $request): Response
    {
        $this->sessions->revoke((string) $request->attribute('token'));
        return Response::noContent();
    }
}
