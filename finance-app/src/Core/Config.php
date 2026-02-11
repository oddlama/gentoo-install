<?php

declare(strict_types=1);

namespace App\Core;

/**
 * Configuration Manager
 * Handles application configuration from environment and config files
 */
class Config
{
    private array $config = [];

    public function __construct()
    {
        $this->loadFromEnvironment();
        $this->loadConfigFiles();
    }

    /**
     * Get configuration value
     */
    public function get(string $key, mixed $default = null): mixed
    {
        $keys = explode('.', $key);
        $value = $this->config;

        foreach ($keys as $k) {
            if (!isset($value[$k])) {
                return $default;
            }
            $value = $value[$k];
        }

        return $value;
    }

    /**
     * Set configuration value
     */
    public function set(string $key, mixed $value): void
    {
        $keys = explode('.', $key);
        $config = &$this->config;

        foreach ($keys as $k) {
            if (!isset($config[$k]) || !is_array($config[$k])) {
                $config[$k] = [];
            }
            $config = &$config[$k];
        }

        $config = $value;
    }

    /**
     * Check if configuration key exists
     */
    public function has(string $key): bool
    {
        $keys = explode('.', $key);
        $value = $this->config;

        foreach ($keys as $k) {
            if (!isset($value[$k])) {
                return false;
            }
            $value = $value[$k];
        }

        return true;
    }

    /**
     * Get all configuration
     */
    public function all(): array
    {
        return $this->config;
    }

    /**
     * Load configuration from environment variables
     */
    private function loadFromEnvironment(): void
    {
        $this->config = [
            'app' => [
                'name' => $this->env('APP_NAME', 'Financial Management System'),
                'env' => $this->env('APP_ENV', 'production'),
                'debug' => $this->env('APP_DEBUG', 'false') === 'true',
                'url' => $this->env('APP_URL', 'http://localhost'),
                'timezone' => $this->env('APP_TIMEZONE', 'America/New_York'),
                'key' => $this->env('APP_KEY', ''),
            ],
            'database' => [
                'host' => $this->env('DB_HOST', 'localhost'),
                'port' => (int) $this->env('DB_PORT', '3306'),
                'name' => $this->env('DB_NAME', 'finance_db'),
                'user' => $this->env('DB_USER', 'root'),
                'password' => $this->env('DB_PASS', ''),
                'charset' => $this->env('DB_CHARSET', 'utf8mb4'),
            ],
            'session' => [
                'lifetime' => (int) $this->env('SESSION_LIFETIME', '7200'),
                'secure' => $this->env('SESSION_SECURE', 'true') === 'true',
                'httponly' => $this->env('SESSION_HTTPONLY', 'true') === 'true',
                'samesite' => $this->env('SESSION_SAMESITE', 'strict'),
            ],
            'csrf' => [
                'token_name' => $this->env('CSRF_TOKEN_NAME', 'csrf_token'),
                'token_lifetime' => (int) $this->env('CSRF_TOKEN_LIFETIME', '3600'),
            ],
            'rate_limit' => [
                'enabled' => $this->env('RATE_LIMIT_ENABLED', 'true') === 'true',
                'max_requests' => (int) $this->env('RATE_LIMIT_MAX_REQUESTS', '60'),
                'window' => (int) $this->env('RATE_LIMIT_WINDOW', '60'),
            ],
            '2fa' => [
                'enabled' => $this->env('2FA_ENABLED', 'true') === 'true',
                'issuer' => $this->env('2FA_ISSUER', 'Financial Management System'),
            ],
            'mail' => [
                'enabled' => $this->env('MAIL_ENABLED', 'false') === 'true',
                'host' => $this->env('MAIL_HOST', ''),
                'port' => (int) $this->env('MAIL_PORT', '587'),
                'username' => $this->env('MAIL_USERNAME', ''),
                'password' => $this->env('MAIL_PASSWORD', ''),
                'encryption' => $this->env('MAIL_ENCRYPTION', 'tls'),
                'from' => [
                    'address' => $this->env('MAIL_FROM_ADDRESS', 'noreply@example.com'),
                    'name' => $this->env('MAIL_FROM_NAME', 'Financial Management System'),
                ],
            ],
            'upload' => [
                'max_size' => (int) $this->env('UPLOAD_MAX_SIZE', '10485760'),
                'allowed_types' => explode(',', $this->env('UPLOAD_ALLOWED_TYPES', 'pdf,jpg,jpeg,png,doc,docx,xls,xlsx')),
                'encrypt' => $this->env('UPLOAD_ENCRYPT', 'true') === 'true',
            ],
            'tax' => [
                'federal_rate' => (float) $this->env('TAX_FEDERAL_RATE', '0.22'),
                'state_rate' => (float) $this->env('TAX_STATE_RATE', '0.05'),
                'self_employment_rate' => (float) $this->env('TAX_SELF_EMPLOYMENT_RATE', '0.153'),
                'year' => (int) $this->env('TAX_YEAR', date('Y')),
                'irs_mileage_rate' => (float) $this->env('IRS_MILEAGE_RATE', '0.67'),
            ],
            'backup' => [
                'enabled' => $this->env('BACKUP_ENABLED', 'true') === 'true',
                'encrypt' => $this->env('BACKUP_ENCRYPT', 'true') === 'true',
                'retention_days' => (int) $this->env('BACKUP_RETENTION_DAYS', '30'),
            ],
            'logging' => [
                'level' => $this->env('LOG_LEVEL', 'warning'),
                'path' => $this->env('LOG_PATH', 'storage/logs/app.log'),
                'audit_enabled' => $this->env('AUDIT_LOG_ENABLED', 'true') === 'true',
            ],
            'security' => [
                'hsts_enabled' => $this->env('SECURITY_HSTS_ENABLED', 'true') === 'true',
                'csp_enabled' => $this->env('SECURITY_CSP_ENABLED', 'true') === 'true',
                'frame_options' => $this->env('SECURITY_FRAME_OPTIONS', 'DENY'),
                'xss_protection' => $this->env('SECURITY_XSS_PROTECTION', '1'),
                'ip_whitelist' => array_filter(explode(',', $this->env('IP_WHITELIST', ''))),
                'max_login_attempts' => (int) $this->env('MAX_LOGIN_ATTEMPTS', '5'),
                'login_lockout_duration' => (int) $this->env('LOGIN_LOCKOUT_DURATION', '900'),
            ],
            'password' => [
                'min_length' => (int) $this->env('PASSWORD_MIN_LENGTH', '12'),
                'require_uppercase' => $this->env('PASSWORD_REQUIRE_UPPERCASE', 'true') === 'true',
                'require_lowercase' => $this->env('PASSWORD_REQUIRE_LOWERCASE', 'true') === 'true',
                'require_numbers' => $this->env('PASSWORD_REQUIRE_NUMBERS', 'true') === 'true',
                'require_special' => $this->env('PASSWORD_REQUIRE_SPECIAL', 'true') === 'true',
                'rotation_days' => (int) $this->env('PASSWORD_ROTATION_DAYS', '90'),
            ],
        ];
    }

    /**
     * Load configuration from PHP files
     */
    private function loadConfigFiles(): void
    {
        $configPath = dirname(__DIR__, 2) . '/config';

        if (!is_dir($configPath)) {
            return;
        }

        $files = glob($configPath . '/*.php');

        foreach ($files as $file) {
            $key = basename($file, '.php');
            $config = require $file;

            if (is_array($config)) {
                $this->config[$key] = array_merge($this->config[$key] ?? [], $config);
            }
        }
    }

    /**
     * Get environment variable
     */
    private function env(string $key, mixed $default = null): mixed
    {
        return $_ENV[$key] ?? getenv($key) ?: $default;
    }
}
