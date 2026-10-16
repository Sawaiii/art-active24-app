<?php

declare(strict_types=1);

namespace App\Auth;

use App\Db\Database;
use App\Http\HttpError;
use App\Support\Clock;
use App\Support\Logger;
use App\Support\RateLimiter;
use App\Support\Time;

/**
 * Одноразовые коды входа по SMS. Код хранится только как хеш, живёт 5 минут, 5 попыток ввода.
 */
final class OtpService
{
    public const CODE_LENGTH = 6;
    public const RESEND_SECONDS = 60;
    private const TTL_SECONDS = 300;
    private const MAX_ATTEMPTS = 5;
    private const VERIFY_PER_PHONE_HOUR = 10;
    private const GLOBAL_CODES_PER_HOUR = 300;

    public function __construct(
        private readonly Database $db,
        private readonly SmsSender $sms,
        private readonly RateLimiter $limiter,
        private readonly Clock $clock,
        private readonly Logger $logger,
        private readonly string $pepper,
        private readonly ?string $reviewPhone = null,
        private readonly ?string $reviewCode = null,
    ) {
    }

    public function request(PhoneNumber $phone, string $ip): void
    {
        // Сначала лимиты по источнику и общий потолок — чтобы чужие запросы не съедали лимит номера.
        $this->limiter->hit('otp:global', self::GLOBAL_CODES_PER_HOUR, 3600);
        $this->limiter->hit('otp:ip:' . RateLimiter::ipBucket($ip), 20, 3600);
        $this->limiter->hit('otp:phone:' . $phone->value, 1, self::RESEND_SECONDS);
        $this->limiter->hit('otp:phone-hour:' . $phone->value, 5, 3600);

        $isReview = $this->isReviewPhone($phone);
        $code = $isReview
            ? (string) $this->reviewCode
            : str_pad((string) random_int(0, 10 ** self::CODE_LENGTH - 1), self::CODE_LENGTH, '0', STR_PAD_LEFT);
        $now = $this->clock->now();

        $this->db->insert('app_auth_codes', [
            'phone' => $phone->value,
            'code_hash' => $this->hash($phone, $code),
            'attempts' => 0,
            'expires_at' => Time::toDb($now->modify('+' . self::TTL_SECONDS . ' seconds')),
            'ip' => substr($ip, 0, 45),
            'created_at' => Time::toDb($now),
        ]);

        if ($isReview) {
            return;
        }
        try {
            $this->sms->send($phone, "Код для входа в Арт-Актив: {$code}. Никому его не сообщайте.");
        } catch (\RuntimeException $e) {
            $this->logger->error('SMS не отправлено', ['phone' => $phone->masked(), 'reason' => $e->getMessage()]);
            throw new HttpError(503, 'sms_unavailable', 'Не удалось отправить SMS. Попробуйте через минуту');
        }
    }

    /** @throws HttpError 422 при неверном или просроченном коде */
    public function verify(PhoneNumber $phone, string $code, string $ip): void
    {
        $this->limiter->hit('otp:verify:ip:' . RateLimiter::ipBucket($ip), 30, 3600);
        $this->limiter->hit('otp:verify:phone:' . $phone->value, self::VERIFY_PER_PHONE_HOUR, 3600);

        $row = $this->db->one(
            'SELECT id, code_hash, expires_at FROM app_auth_codes
             WHERE phone = ? AND used_at IS NULL ORDER BY id DESC LIMIT 1',
            [$phone->value],
        );
        $now = $this->clock->now();
        if ($row === null || Time::toDb($now) > (string) $row['expires_at']) {
            throw HttpError::validation(['code' => 'Код устарел. Запросите новый']);
        }
        $id = (int) $row['id'];

        // Попытка списывается атомарно ДО сравнения: параллельные запросы не получат больше 5 попыток.
        $claimed = $this->db->run(
            'UPDATE app_auth_codes SET attempts = attempts + 1 WHERE id = ? AND attempts < ? AND used_at IS NULL',
            [$id, self::MAX_ATTEMPTS],
        )->rowCount();
        if ($claimed !== 1) {
            throw HttpError::validation(['code' => 'Слишком много попыток. Запросите новый код']);
        }
        if (!hash_equals((string) $row['code_hash'], $this->hash($phone, trim($code)))) {
            throw HttpError::validation(['code' => 'Неверный код']);
        }
        $used = $this->db->run(
            'UPDATE app_auth_codes SET used_at = ? WHERE id = ? AND used_at IS NULL',
            [Time::toDb($now), $id],
        )->rowCount();
        if ($used !== 1) {
            throw HttpError::validation(['code' => 'Код уже использован. Запросите новый']);
        }
    }

    private function isReviewPhone(PhoneNumber $phone): bool
    {
        return $this->reviewPhone !== null && $this->reviewCode !== null && $phone->value === $this->reviewPhone;
    }

    private function hash(PhoneNumber $phone, string $code): string
    {
        return hash_hmac('sha256', $phone->value . '|' . $code, $this->pepper);
    }
}
