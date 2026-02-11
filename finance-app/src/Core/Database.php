<?php

declare(strict_types=1);

namespace App\Core;

use PDO;
use PDOException;
use PDOStatement;

/**
 * Database Connection Manager
 * Handles PDO database connections with prepared statements
 */
class Database
{
    private ?PDO $connection = null;
    private Config $config;

    public function __construct(Config $config)
    {
        $this->config = $config;
    }

    /**
     * Get PDO connection instance
     */
    public function getConnection(): PDO
    {
        if ($this->connection === null) {
            $this->connect();
        }

        return $this->connection;
    }

    /**
     * Establish database connection
     */
    private function connect(): void
    {
        $host = $this->config->get('database.host');
        $port = $this->config->get('database.port');
        $dbname = $this->config->get('database.name');
        $charset = $this->config->get('database.charset');

        $dsn = "mysql:host={$host};port={$port};dbname={$dbname};charset={$charset}";

        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_PERSISTENT => false,
            PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES {$charset}",
        ];

        try {
            $this->connection = new PDO(
                $dsn,
                $this->config->get('database.user'),
                $this->config->get('database.password'),
                $options
            );
        } catch (PDOException $e) {
            throw new PDOException("Database connection failed: " . $e->getMessage());
        }
    }

    /**
     * Execute a SELECT query
     */
    public function select(string $query, array $params = []): array
    {
        $stmt = $this->execute($query, $params);
        return $stmt->fetchAll();
    }

    /**
     * Execute a SELECT query and return single row
     */
    public function selectOne(string $query, array $params = []): ?array
    {
        $stmt = $this->execute($query, $params);
        $result = $stmt->fetch();
        return $result ?: null;
    }

    /**
     * Execute an INSERT query
     */
    public function insert(string $query, array $params = []): int
    {
        $this->execute($query, $params);
        return (int) $this->connection->lastInsertId();
    }

    /**
     * Execute an UPDATE query
     */
    public function update(string $query, array $params = []): int
    {
        $stmt = $this->execute($query, $params);
        return $stmt->rowCount();
    }

    /**
     * Execute a DELETE query
     */
    public function delete(string $query, array $params = []): int
    {
        $stmt = $this->execute($query, $params);
        return $stmt->rowCount();
    }

    /**
     * Execute a raw query
     */
    public function execute(string $query, array $params = []): PDOStatement
    {
        try {
            $stmt = $this->getConnection()->prepare($query);

            foreach ($params as $key => $value) {
                if (is_int($key)) {
                    $key += 1; // PDO params are 1-indexed
                    $stmt->bindValue($key, $value, $this->getPdoType($value));
                } else {
                    $stmt->bindValue($key, $value, $this->getPdoType($value));
                }
            }

            $stmt->execute();

            return $stmt;
        } catch (PDOException $e) {
            throw new PDOException("Query execution failed: " . $e->getMessage() . "\nQuery: {$query}");
        }
    }

    /**
     * Begin a transaction
     */
    public function beginTransaction(): bool
    {
        return $this->getConnection()->beginTransaction();
    }

    /**
     * Commit a transaction
     */
    public function commit(): bool
    {
        return $this->getConnection()->commit();
    }

    /**
     * Rollback a transaction
     */
    public function rollback(): bool
    {
        return $this->getConnection()->rollBack();
    }

    /**
     * Check if in transaction
     */
    public function inTransaction(): bool
    {
        return $this->getConnection()->inTransaction();
    }

    /**
     * Get the PDO type for a value
     */
    private function getPdoType(mixed $value): int
    {
        return match (true) {
            is_int($value) => PDO::PARAM_INT,
            is_bool($value) => PDO::PARAM_BOOL,
            is_null($value) => PDO::PARAM_NULL,
            default => PDO::PARAM_STR,
        };
    }

    /**
     * Close the connection
     */
    public function close(): void
    {
        $this->connection = null;
    }

    /**
     * Execute multiple queries (for migrations/setup)
     */
    public function executeBatch(string $sql): void
    {
        $this->getConnection()->exec($sql);
    }
}
