<?php

declare(strict_types=1);

namespace App\Auth;

/**
 * Роль менеджера определяется ТОЛЬКО текущей конфигурацией (MANAGER_PHONES) на каждом запросе:
 * убрали номер из списка — права пропадают сразу, без ожидания истечения сессий.
 */
final class ManagerPolicy
{
    /** @var list<string> */
    private readonly array $phones;

    /** @param list<string> $rawPhones */
    public function __construct(array $rawPhones, ?string $reviewPhone)
    {
        $phones = [];
        foreach ($rawPhones as $raw) {
            $phones[] = PhoneNumber::parse($raw, 'MANAGER_PHONES')->value;
        }
        if ($reviewPhone !== null && in_array($reviewPhone, $phones, true)) {
            throw new \RuntimeException('Демо-номер AUTH_REVIEW_PHONE не может быть менеджерским');
        }
        $this->phones = $phones;
    }

    /**
     * @param array<string, mixed> $user
     * @return array<string, mixed>
     */
    public function apply(array $user): array
    {
        return ['role' => in_array($user['phone'], $this->phones, true) ? 'manager' : 'customer'] + $user;
    }
}
