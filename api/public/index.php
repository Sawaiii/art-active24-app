<?php

declare(strict_types=1);

use App\Config;
use App\Container;
use App\Http\Request;
use App\Kernel;

// Ошибки PHP никогда не уходят клиенту: в них могут быть пути, DSN и пароли.
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

require dirname(__DIR__) . '/vendor/autoload.php';

// Встроенный сервер PHP (разработка): статика и папки с index.html — как Apache с DirectoryIndex.
if (PHP_SAPI === 'cli-server') {
    $static = __DIR__ . parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    if (is_file($static)) {
        return false;
    }
    if (is_dir($static) && is_file($static . '/index.html')) {
        header('Content-Type: text/html; charset=utf-8');
        readfile($static . '/index.html');
        return true;
    }
}

try {
    $config = Config::fromEnvironment(dirname(__DIR__) . '/.env');
    $request = Request::fromGlobals($config->list('TRUSTED_PROXIES'));
    (new Kernel(new Container($config)))->handle($request)->send();
} catch (\Throwable $e) {
    // Сбой до Kernel (конфигурация, подключение к БД): деталь — в лог сервера, клиенту — общий ответ.
    error_log('[mobile-api] ' . $e::class . ': ' . $e->getMessage() . ' at ' . $e->getFile() . ':' . $e->getLine());
    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo '{"success":false,"data":null,"error":{"code":"server_error","message":"Сервис временно недоступен"}}';
}
