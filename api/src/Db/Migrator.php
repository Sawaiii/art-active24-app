<?php

declare(strict_types=1);

namespace App\Db;

/**
 * Применяет migrations/{driver}/NNN_name.sql по порядку, учитывая уже применённые в app_migrations.
 */
final class Migrator
{
    public function __construct(
        private readonly Database $db,
        private readonly string $migrationsDir,
    ) {
    }

    /** @return list<string> применённые сейчас миграции */
    public function migrate(): array
    {
        $this->db->exec(
            'CREATE TABLE IF NOT EXISTS app_migrations (name VARCHAR(190) PRIMARY KEY, applied_at VARCHAR(32) NOT NULL)'
        );
        $done = array_column($this->db->all('SELECT name FROM app_migrations'), 'name');
        $dir = $this->migrationsDir . '/' . $this->db->driver();
        $files = glob($dir . '/*.sql') ?: [];
        sort($files);

        $applied = [];
        foreach ($files as $file) {
            $name = basename($file);
            if (in_array($name, $done, true)) {
                continue;
            }
            $sql = (string) file_get_contents($file);
            $this->db->transaction(function () use ($sql, $name): void {
                foreach ($this->splitStatements($sql) as $statement) {
                    $this->db->exec($statement);
                }
                $this->db->insert('app_migrations', ['name' => $name, 'applied_at' => gmdate('c')]);
            });
            $applied[] = $name;
        }
        return $applied;
    }

    /** @return list<string> */
    private function splitStatements(string $sql): array
    {
        $withoutComments = preg_replace('/^\s*--.*$/m', '', $sql) ?? $sql;
        return array_values(array_filter(
            array_map('trim', explode(';', $withoutComments)),
            static fn (string $s) => $s !== '',
        ));
    }
}
