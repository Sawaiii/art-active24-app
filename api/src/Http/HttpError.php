<?php

declare(strict_types=1);

namespace App\Http;

/**
 * Ошибка, которую можно показать клиенту: HTTP-статус + машинный код + текст для пользователя.
 */
final class HttpError extends \RuntimeException
{
    /** @param array<string, string> $fields ошибки по полям формы */
    public function __construct(
        public readonly int $status,
        public readonly string $errorCode,
        string $message,
        public readonly array $fields = [],
        public readonly ?int $retryAfter = null,
    ) {
        parent::__construct($message);
    }

    public static function badRequest(string $code, string $message): self
    {
        return new self(400, $code, $message);
    }

    /** @param array<string, string> $fields */
    public static function validation(array $fields): self
    {
        return new self(422, 'validation_failed', 'Проверьте правильность заполнения', $fields);
    }

    public static function unauthorized(string $message = 'Требуется вход'): self
    {
        return new self(401, 'unauthorized', $message);
    }

    public static function forbidden(): self
    {
        return new self(403, 'forbidden', 'Недостаточно прав');
    }

    public static function notFound(string $what = 'Ресурс'): self
    {
        return new self(404, 'not_found', "{$what} не найден");
    }

    public static function tooManyRequests(int $retryAfter): self
    {
        return new self(429, 'too_many_requests', "Слишком часто. Повторите через {$retryAfter} с", [], $retryAfter);
    }
}
