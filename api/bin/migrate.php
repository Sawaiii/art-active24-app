<?php

declare(strict_types=1);

use App\Config;
use App\Db\Database;
use App\Db\Migrator;

require dirname(__DIR__) . '/vendor/autoload.php';

$root = dirname(__DIR__);
$config = Config::fromEnvironment($root . '/.env');
$db = Database::connect(
    Database::resolveDsn($config->get('DB_DSN', 'sqlite:var/app.sqlite') ?? '', $root),
    $config->get('DB_USER'),
    $config->get('DB_PASSWORD'),
);
$applied = (new Migrator($db, $root . '/migrations'))->migrate();
echo $applied === [] ? "Миграции актуальны\n" : 'Применены: ' . implode(', ', $applied) . "\n";
