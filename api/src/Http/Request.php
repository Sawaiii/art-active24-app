<?php

declare(strict_types=1);

namespace App\Http;

/**
 * Неизменяемый HTTP-запрос. Атрибуты (параметры маршрута, текущий пользователь)
 * добавляются через with*(), возвращающие новый экземпляр.
 */
final class Request
{
    /**
     * @param array<string, string> $query
     * @param array<string, string> $headers ключи в нижнем регистре
     * @param array<string, mixed> $attributes
     */
    public function __construct(
        public readonly string $method,
        public readonly string $path,
        public readonly array $query = [],
        public readonly array $headers = [],
        public readonly string $rawBody = '',
        public readonly string $clientIp = '',
        private readonly array $attributes = [],
    ) {
    }

    /**
     * @param list<string> $trustedProxies адреса обратных прокси (nginx перед PHP). Только от них
     *        принимаем X-Forwarded-For — иначе клиент подделал бы IP и обошёл лимиты.
     */
    public static function fromGlobals(array $trustedProxies = []): self
    {
        $headers = [];
        foreach ($_SERVER as $key => $value) {
            if (str_starts_with($key, 'HTTP_')) {
                $headers[strtolower(str_replace('_', '-', substr($key, 5)))] = (string) $value;
            }
        }
        if (isset($_SERVER['CONTENT_TYPE'])) {
            $headers['content-type'] = (string) $_SERVER['CONTENT_TYPE'];
        }

        $path = parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH) ?: '/';

        return new self(
            strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET')),
            rtrim($path, '/') ?: '/',
            array_filter($_GET, static fn ($v, $k) => is_string($v) && is_string($k), ARRAY_FILTER_USE_BOTH),
            $headers,
            (string) file_get_contents('php://input', false, null, 0, self::MAX_BODY_BYTES + 1),
            self::clientIp((string) ($_SERVER['REMOTE_ADDR'] ?? ''), $headers['x-forwarded-for'] ?? null, $trustedProxies),
        );
    }

    /** Ограничение тела запроса: API принимает только небольшие JSON. */
    public const MAX_BODY_BYTES = 65536;

    /** @param list<string> $trustedProxies */
    public static function clientIp(string $remoteAddr, ?string $forwardedFor, array $trustedProxies): string
    {
        if ($forwardedFor === null || !in_array($remoteAddr, $trustedProxies, true)) {
            return $remoteAddr;
        }
        // Справа налево: первый адрес, который не является нашим прокси, — реальный клиент.
        foreach (array_reverse(array_map('trim', explode(',', $forwardedFor))) as $ip) {
            if (filter_var($ip, FILTER_VALIDATE_IP) !== false && !in_array($ip, $trustedProxies, true)) {
                return $ip;
            }
        }
        return $remoteAddr;
    }

    public function header(string $name): ?string
    {
        return $this->headers[strtolower($name)] ?? null;
    }

    public function bearerToken(): ?string
    {
        $auth = $this->header('authorization');
        if ($auth === null || !preg_match('/^Bearer\s+(\S+)$/i', $auth, $m)) {
            return null;
        }
        return $m[1];
    }

    /** @return array<string, mixed> */
    public function json(): array
    {
        if (strlen($this->rawBody) > self::MAX_BODY_BYTES) {
            throw new HttpError(413, 'payload_too_large', 'Слишком большой запрос');
        }
        if (trim($this->rawBody) === '') {
            return [];
        }
        try {
            $data = json_decode($this->rawBody, true, 32, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw HttpError::badRequest('invalid_json', 'Тело запроса не является корректным JSON');
        }
        if (!is_array($data) || array_is_list($data) && $data !== []) {
            throw HttpError::badRequest('invalid_json', 'Ожидается JSON-объект');
        }
        return $data;
    }

    public function queryInt(string $key, int $default, int $min, int $max): int
    {
        if (!isset($this->query[$key]) || $this->query[$key] === '') {
            return $default;
        }
        if (!preg_match('/^-?\d+$/', $this->query[$key])) {
            throw HttpError::badRequest('invalid_query', "Параметр {$key} должен быть целым числом");
        }
        return max($min, min($max, (int) $this->query[$key]));
    }

    public function attribute(string $key, mixed $default = null): mixed
    {
        return $this->attributes[$key] ?? $default;
    }

    public function withAttribute(string $key, mixed $value): self
    {
        return new self(
            $this->method,
            $this->path,
            $this->query,
            $this->headers,
            $this->rawBody,
            $this->clientIp,
            [...$this->attributes, $key => $value],
        );
    }
}
