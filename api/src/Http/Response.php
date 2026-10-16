<?php

declare(strict_types=1);

namespace App\Http;

/**
 * JSON-ответ в едином конверте: {success, data, error, meta}.
 * Внутри data ключи со значением null опускаются — необязательные поля контракта просто отсутствуют.
 */
final class Response
{
    private const JSON_FLAGS = JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE | JSON_THROW_ON_ERROR;

    /** @param array<string, string> $headers */
    private function __construct(
        public readonly int $status,
        public readonly array $body,
        public readonly array $headers = [],
    ) {
    }

    /** @param array<string, mixed>|null $meta */
    public static function ok(mixed $data, ?array $meta = null, int $status = 200): self
    {
        $body = ['success' => true, 'data' => self::withoutNulls($data), 'error' => null];
        if ($meta !== null) {
            $body['meta'] = $meta;
        }
        return new self($status, $body);
    }

    public static function created(mixed $data): self
    {
        return self::ok($data, null, 201);
    }

    public static function noContent(): self
    {
        return new self(204, []);
    }

    public static function error(HttpError $e): self
    {
        $error = ['code' => $e->errorCode, 'message' => $e->getMessage()];
        if ($e->fields !== []) {
            $error['fields'] = $e->fields;
        }
        return new self($e->status, ['success' => false, 'data' => null, 'error' => $error]);
    }

    public function withHeader(string $name, string $value): self
    {
        return new self($this->status, $this->body, [...$this->headers, $name => $value]);
    }

    public function send(): void
    {
        http_response_code($this->status);
        header('Content-Type: application/json; charset=utf-8');
        header('X-Content-Type-Options: nosniff');
        header('Cache-Control: no-store');
        header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'");
        header('Referrer-Policy: no-referrer');
        foreach ($this->headers as $name => $value) {
            header("{$name}: {$value}");
        }
        if ($this->status !== 204) {
            echo json_encode($this->body, self::JSON_FLAGS);
        }
    }

    private static function withoutNulls(mixed $value): mixed
    {
        if (!is_array($value)) {
            return $value;
        }
        if (array_is_list($value)) {
            return array_map(self::withoutNulls(...), $value);
        }
        $out = [];
        foreach ($value as $key => $item) {
            if ($item !== null) {
                $out[$key] = self::withoutNulls($item);
            }
        }
        return $out;
    }
}
