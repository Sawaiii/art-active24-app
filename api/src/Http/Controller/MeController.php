<?php

declare(strict_types=1);

namespace App\Http\Controller;

use App\Catalog\CatalogRepository;
use App\Http\HttpError;
use App\Http\Request;
use App\Http\Response;
use App\Push\DeviceRepository;
use App\Users\FavoriteRepository;
use App\Users\UserRepository;

final class MeController
{
    public function __construct(
        private readonly UserRepository $users,
        private readonly FavoriteRepository $favorites,
        private readonly DeviceRepository $devices,
        private readonly CatalogRepository $catalog,
    ) {
    }

    public function show(Request $request): Response
    {
        return Response::ok($request->attribute('user'));
    }

    public function update(Request $request): Response
    {
        $body = $request->json();
        $fields = [];
        $errors = [];
        foreach (['name' => 100, 'company' => 150] as $key => $max) {
            if (!array_key_exists($key, $body)) {
                continue;
            }
            $value = is_string($body[$key]) ? trim($body[$key]) : null;
            if ($value === null || mb_strlen($value) > $max) {
                $errors[$key] = "Не больше {$max} символов";
            } else {
                $fields[$key] = $value === '' ? null : $value;
            }
        }
        if (array_key_exists('email', $body)) {
            $email = is_string($body['email']) ? trim($body['email']) : '';
            if ($email !== '' && (mb_strlen($email) > 150 || filter_var($email, FILTER_VALIDATE_EMAIL) === false)) {
                $errors['email'] = 'Некорректный e-mail';
            } else {
                $fields['email'] = $email === '' ? null : $email;
            }
        }
        if ($errors !== []) {
            throw HttpError::validation($errors);
        }
        return Response::ok($this->users->update((int) $request->attribute('user')['id'], $fields));
    }

    public function favorites(Request $request): Response
    {
        $ids = $this->favorites->ids((int) $request->attribute('user')['id']);
        return Response::ok(['items' => $this->catalog->summaries($ids), 'facets' => (object) []]);
    }

    public function replaceFavorites(Request $request): Response
    {
        $ids = $request->json()['productIds'] ?? null;
        if (!is_array($ids) || !array_is_list($ids) || count($ids) > FavoriteRepository::MAX
            || array_filter($ids, static fn ($id) => !is_int($id) || $id <= 0) !== []) {
            throw HttpError::validation(['productIds' => 'Ожидается список id товаров']);
        }
        $userId = (int) $request->attribute('user')['id'];
        $this->favorites->replace($userId, $ids);
        return Response::ok(['items' => $this->catalog->summaries($this->favorites->ids($userId)), 'facets' => (object) []]);
    }

    public function unregisterDevice(Request $request): Response
    {
        $token = $request->json()['token'] ?? null;
        if (!is_string($token) || $token === '' || strlen($token) > 512) {
            throw HttpError::validation(['token' => 'Некорректный push-токен']);
        }
        $this->devices->unregister((int) $request->attribute('user')['id'], $token);
        return Response::noContent();
    }

    public function registerDevice(Request $request): Response
    {
        $body = $request->json();
        $platform = $body['platform'] ?? null;
        $token = $body['token'] ?? null;
        if (!in_array($platform, ['ios', 'android'], true) || !is_string($token) || $token === '' || strlen($token) > 512) {
            throw HttpError::validation(['token' => 'Некорректный push-токен']);
        }
        $this->devices->register((int) $request->attribute('user')['id'], $platform, $token);
        return Response::noContent();
    }
}
