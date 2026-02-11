-- Financial Management System Database Schema
-- MySQL 8.0+
-- Created: 2026-02-11

SET FOREIGN_KEY_CHECKS = 0;
SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";

-- ============================================================================
-- CORE AUTHENTICATION & AUTHORIZATION TABLES
-- ============================================================================

-- Users table
CREATE TABLE IF NOT EXISTS `users` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `uuid` CHAR(36) NOT NULL UNIQUE,
  `username` VARCHAR(100) NOT NULL UNIQUE,
  `email` VARCHAR(255) NOT NULL UNIQUE,
  `password_hash` VARCHAR(255) NOT NULL,
  `first_name` VARCHAR(100) NOT NULL,
  `last_name` VARCHAR(100) NOT NULL,
  `phone` VARCHAR(20) DEFAULT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `email_verified_at` TIMESTAMP NULL DEFAULT NULL,
  `two_factor_enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `two_factor_secret` VARCHAR(255) DEFAULT NULL,
  `two_factor_backup_codes` TEXT DEFAULT NULL,
  `password_changed_at` TIMESTAMP NULL DEFAULT NULL,
  `last_login_at` TIMESTAMP NULL DEFAULT NULL,
  `last_login_ip` VARCHAR(45) DEFAULT NULL,
  `failed_login_attempts` INT NOT NULL DEFAULT 0,
  `locked_until` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_username` (`username`),
  INDEX `idx_email` (`email`),
  INDEX `idx_is_active` (`is_active`),
  INDEX `idx_uuid` (`uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Roles table
CREATE TABLE IF NOT EXISTS `roles` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(50) NOT NULL UNIQUE,
  `display_name` VARCHAR(100) NOT NULL,
  `description` TEXT DEFAULT NULL,
  `is_system` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Permissions table
CREATE TABLE IF NOT EXISTS `permissions` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(100) NOT NULL UNIQUE,
  `display_name` VARCHAR(150) NOT NULL,
  `module` VARCHAR(50) NOT NULL,
  `description` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_name` (`name`),
  INDEX `idx_module` (`module`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Role Permissions (Many-to-Many)
CREATE TABLE IF NOT EXISTS `role_permissions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `role_id` INT UNSIGNED NOT NULL,
  `permission_id` INT UNSIGNED NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_role_permission` (`role_id`, `permission_id`),
  FOREIGN KEY (`role_id`) REFERENCES `roles`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`permission_id`) REFERENCES `permissions`(`id`) ON DELETE CASCADE,
  INDEX `idx_role_id` (`role_id`),
  INDEX `idx_permission_id` (`permission_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- User Roles (Many-to-Many)
CREATE TABLE IF NOT EXISTS `user_roles` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `role_id` INT UNSIGNED NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_user_role` (`user_id`, `role_id`),
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`role_id`) REFERENCES `roles`(`id`) ON DELETE CASCADE,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_role_id` (`role_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sessions table
CREATE TABLE IF NOT EXISTS `sessions` (
  `id` VARCHAR(128) NOT NULL PRIMARY KEY,
  `user_id` BIGINT UNSIGNED DEFAULT NULL,
  `ip_address` VARCHAR(45) DEFAULT NULL,
  `user_agent` TEXT DEFAULT NULL,
  `payload` TEXT NOT NULL,
  `last_activity` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_last_activity` (`last_activity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- INCOME MANAGEMENT TABLES
-- ============================================================================

-- Income Sources (Clients, Platforms, Employers)
CREATE TABLE IF NOT EXISTS `income_sources` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `type` ENUM('freelance', 'gig', 'fulltime', 'contract', 'other') NOT NULL,
  `platform` VARCHAR(100) DEFAULT NULL COMMENT 'For gig work: Uber, DoorDash, etc.',
  `contact_name` VARCHAR(255) DEFAULT NULL,
  `contact_email` VARCHAR(255) DEFAULT NULL,
  `contact_phone` VARCHAR(20) DEFAULT NULL,
  `address` TEXT DEFAULT NULL,
  `tax_id` VARCHAR(50) DEFAULT NULL COMMENT 'EIN or SSN',
  `payment_terms` TEXT DEFAULT NULL,
  `hourly_rate` DECIMAL(10,2) DEFAULT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_type` (`type`),
  INDEX `idx_is_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Income Transactions
CREATE TABLE IF NOT EXISTS `income_transactions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `income_source_id` BIGINT UNSIGNED NOT NULL,
  `transaction_date` DATE NOT NULL,
  `description` VARCHAR(255) NOT NULL,
  `gross_amount` DECIMAL(12,2) NOT NULL,
  `net_amount` DECIMAL(12,2) NOT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'USD',
  `payment_method` ENUM('cash', 'check', 'bank_transfer', 'paypal', 'stripe', 'platform', 'other') NOT NULL,
  `invoice_number` VARCHAR(100) DEFAULT NULL,
  `is_paid` TINYINT(1) NOT NULL DEFAULT 0,
  `paid_at` TIMESTAMP NULL DEFAULT NULL,
  `is_recurring` TINYINT(1) NOT NULL DEFAULT 0,
  `recurring_frequency` ENUM('weekly', 'biweekly', 'monthly', 'quarterly', 'yearly') DEFAULT NULL,
  `project_name` VARCHAR(255) DEFAULT NULL,
  `hours_worked` DECIMAL(6,2) DEFAULT NULL,
  `tips` DECIMAL(10,2) DEFAULT 0.00,
  `commission` DECIMAL(10,2) DEFAULT 0.00,
  `platform_fees` DECIMAL(10,2) DEFAULT 0.00,
  `tax_category` VARCHAR(50) DEFAULT NULL,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`income_source_id`) REFERENCES `income_sources`(`id`) ON DELETE RESTRICT,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_income_source_id` (`income_source_id`),
  INDEX `idx_transaction_date` (`transaction_date`),
  INDEX `idx_is_paid` (`is_paid`),
  INDEX `idx_tax_category` (`tax_category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Paystubs
CREATE TABLE IF NOT EXISTS `paystubs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `income_source_id` BIGINT UNSIGNED NOT NULL,
  `pay_period_start` DATE NOT NULL,
  `pay_period_end` DATE NOT NULL,
  `pay_date` DATE NOT NULL,
  `gross_pay` DECIMAL(12,2) NOT NULL,
  `net_pay` DECIMAL(12,2) NOT NULL,
  `federal_tax` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `state_tax` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `social_security` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `medicare` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `other_deductions` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `deduction_details` JSON DEFAULT NULL,
  `hours_regular` DECIMAL(6,2) DEFAULT NULL,
  `hours_overtime` DECIMAL(6,2) DEFAULT NULL,
  `file_path` VARCHAR(500) DEFAULT NULL,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`income_source_id`) REFERENCES `income_sources`(`id`) ON DELETE RESTRICT,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_income_source_id` (`income_source_id`),
  INDEX `idx_pay_date` (`pay_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- EXPENSE MANAGEMENT TABLES
-- ============================================================================

-- Expense Categories
CREATE TABLE IF NOT EXISTS `expense_categories` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED DEFAULT NULL COMMENT 'NULL for system categories',
  `parent_id` INT UNSIGNED DEFAULT NULL,
  `name` VARCHAR(100) NOT NULL,
  `description` TEXT DEFAULT NULL,
  `is_tax_deductible` TINYINT(1) NOT NULL DEFAULT 0,
  `is_system` TINYINT(1) NOT NULL DEFAULT 0,
  `sort_order` INT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`parent_id`) REFERENCES `expense_categories`(`id`) ON DELETE SET NULL,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_parent_id` (`parent_id`),
  INDEX `idx_is_tax_deductible` (`is_tax_deductible`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Expenses
CREATE TABLE IF NOT EXISTS `expenses` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `category_id` INT UNSIGNED NOT NULL,
  `income_source_id` BIGINT UNSIGNED DEFAULT NULL COMMENT 'Link to related income source',
  `expense_date` DATE NOT NULL,
  `description` VARCHAR(255) NOT NULL,
  `amount` DECIMAL(12,2) NOT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'USD',
  `payment_method` ENUM('cash', 'credit_card', 'debit_card', 'bank_transfer', 'check', 'other') NOT NULL,
  `vendor` VARCHAR(255) DEFAULT NULL,
  `is_recurring` TINYINT(1) NOT NULL DEFAULT 0,
  `recurring_frequency` ENUM('weekly', 'biweekly', 'monthly', 'quarterly', 'yearly') DEFAULT NULL,
  `is_tax_deductible` TINYINT(1) NOT NULL DEFAULT 0,
  `tax_percentage` DECIMAL(5,2) DEFAULT NULL COMMENT 'Percentage of expense that is deductible',
  `tags` JSON DEFAULT NULL,
  `receipt_path` VARCHAR(500) DEFAULT NULL,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`category_id`) REFERENCES `expense_categories`(`id`) ON DELETE RESTRICT,
  FOREIGN KEY (`income_source_id`) REFERENCES `income_sources`(`id`) ON DELETE SET NULL,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_category_id` (`category_id`),
  INDEX `idx_income_source_id` (`income_source_id`),
  INDEX `idx_expense_date` (`expense_date`),
  INDEX `idx_is_tax_deductible` (`is_tax_deductible`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- MILEAGE & GAS TRACKING
-- ============================================================================

-- Vehicles
CREATE TABLE IF NOT EXISTS `vehicles` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `make` VARCHAR(50) NOT NULL,
  `model` VARCHAR(50) NOT NULL,
  `year` YEAR NOT NULL,
  `vin` VARCHAR(17) DEFAULT NULL,
  `license_plate` VARCHAR(20) DEFAULT NULL,
  `color` VARCHAR(30) DEFAULT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `purchase_date` DATE DEFAULT NULL,
  `purchase_price` DECIMAL(12,2) DEFAULT NULL,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_is_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Mileage Logs
CREATE TABLE IF NOT EXISTS `mileage_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `vehicle_id` INT UNSIGNED NOT NULL,
  `income_source_id` BIGINT UNSIGNED DEFAULT NULL,
  `log_date` DATE NOT NULL,
  `starting_location` VARCHAR(255) NOT NULL,
  `ending_location` VARCHAR(255) NOT NULL,
  `odometer_start` DECIMAL(10,2) NOT NULL,
  `odometer_end` DECIMAL(10,2) NOT NULL,
  `miles_driven` DECIMAL(10,2) GENERATED ALWAYS AS (`odometer_end` - `odometer_start`) STORED,
  `purpose` VARCHAR(255) NOT NULL,
  `is_business` TINYINT(1) NOT NULL DEFAULT 1,
  `deduction_rate` DECIMAL(5,2) DEFAULT NULL COMMENT 'IRS rate at time of trip',
  `calculated_deduction` DECIMAL(10,2) GENERATED ALWAYS AS (`miles_driven` * `deduction_rate`) STORED,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`vehicle_id`) REFERENCES `vehicles`(`id`) ON DELETE RESTRICT,
  FOREIGN KEY (`income_source_id`) REFERENCES `income_sources`(`id`) ON DELETE SET NULL,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_vehicle_id` (`vehicle_id`),
  INDEX `idx_income_source_id` (`income_source_id`),
  INDEX `idx_log_date` (`log_date`),
  INDEX `idx_is_business` (`is_business`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Gas Logs
CREATE TABLE IF NOT EXISTS `gas_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `vehicle_id` INT UNSIGNED NOT NULL,
  `income_source_id` BIGINT UNSIGNED DEFAULT NULL,
  `purchase_date` DATE NOT NULL,
  `location` VARCHAR(255) DEFAULT NULL,
  `gallons` DECIMAL(6,2) NOT NULL,
  `price_per_gallon` DECIMAL(6,2) NOT NULL,
  `total_cost` DECIMAL(10,2) GENERATED ALWAYS AS (`gallons` * `price_per_gallon`) STORED,
  `odometer_reading` DECIMAL(10,2) DEFAULT NULL,
  `is_business` TINYINT(1) NOT NULL DEFAULT 1,
  `payment_method` ENUM('cash', 'credit_card', 'debit_card', 'other') NOT NULL,
  `receipt_path` VARCHAR(500) DEFAULT NULL,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`vehicle_id`) REFERENCES `vehicles`(`id`) ON DELETE RESTRICT,
  FOREIGN KEY (`income_source_id`) REFERENCES `income_sources`(`id`) ON DELETE SET NULL,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_vehicle_id` (`vehicle_id`),
  INDEX `idx_income_source_id` (`income_source_id`),
  INDEX `idx_purchase_date` (`purchase_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TAX MANAGEMENT TABLES
-- ============================================================================

-- Tax Settings
CREATE TABLE IF NOT EXISTS `tax_settings` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `tax_year` YEAR NOT NULL,
  `filing_status` ENUM('single', 'married_joint', 'married_separate', 'head_of_household') NOT NULL DEFAULT 'single',
  `federal_rate` DECIMAL(5,4) NOT NULL,
  `state` VARCHAR(2) DEFAULT NULL,
  `state_rate` DECIMAL(5,4) NOT NULL DEFAULT 0.0000,
  `self_employment_rate` DECIMAL(5,4) NOT NULL DEFAULT 0.1530,
  `irs_mileage_rate` DECIMAL(5,2) NOT NULL,
  `standard_deduction` DECIMAL(10,2) DEFAULT NULL,
  `quarterly_estimated_tax` DECIMAL(10,2) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  UNIQUE KEY `unique_user_year` (`user_id`, `tax_year`),
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_tax_year` (`tax_year`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tax Records
CREATE TABLE IF NOT EXISTS `tax_records` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `tax_year` YEAR NOT NULL,
  `quarter` TINYINT UNSIGNED DEFAULT NULL COMMENT '1-4 for quarterly, NULL for annual',
  `total_income` DECIMAL(12,2) NOT NULL,
  `total_deductions` DECIMAL(12,2) NOT NULL,
  `taxable_income` DECIMAL(12,2) GENERATED ALWAYS AS (`total_income` - `total_deductions`) STORED,
  `federal_tax_owed` DECIMAL(12,2) NOT NULL,
  `state_tax_owed` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  `self_employment_tax` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  `total_tax_owed` DECIMAL(12,2) GENERATED ALWAYS AS (`federal_tax_owed` + `state_tax_owed` + `self_employment_tax`) STORED,
  `tax_paid` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  `payment_date` DATE DEFAULT NULL,
  `is_estimated` TINYINT(1) NOT NULL DEFAULT 1,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_tax_year` (`tax_year`),
  INDEX `idx_quarter` (`quarter`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- DOCUMENT MANAGEMENT
-- ============================================================================

-- Documents
CREATE TABLE IF NOT EXISTS `documents` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `document_type` ENUM('w2', 'w4', 'i9', '1099', 'contract', 'receipt', 'invoice', 'paystub', 'tax_return', 'other') NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `description` TEXT DEFAULT NULL,
  `file_name` VARCHAR(255) NOT NULL,
  `file_path` VARCHAR(500) NOT NULL,
  `file_size` BIGINT UNSIGNED NOT NULL COMMENT 'Size in bytes',
  `mime_type` VARCHAR(100) NOT NULL,
  `is_encrypted` TINYINT(1) NOT NULL DEFAULT 0,
  `tax_year` YEAR DEFAULT NULL,
  `income_source_id` BIGINT UNSIGNED DEFAULT NULL,
  `expense_id` BIGINT UNSIGNED DEFAULT NULL,
  `tags` JSON DEFAULT NULL,
  `uploaded_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`income_source_id`) REFERENCES `income_sources`(`id`) ON DELETE SET NULL,
  FOREIGN KEY (`expense_id`) REFERENCES `expenses`(`id`) ON DELETE SET NULL,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_document_type` (`document_type`),
  INDEX `idx_tax_year` (`tax_year`),
  INDEX `idx_income_source_id` (`income_source_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- NOTIFICATION & ALERT SYSTEM
-- ============================================================================

-- Alerts
CREATE TABLE IF NOT EXISTS `alerts` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `alert_type` ENUM('expense_threshold', 'tax_payment', 'quarterly_tax', 'income_drop', 'recurring_expense', 'custom') NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `message` TEXT NOT NULL,
  `threshold_value` DECIMAL(12,2) DEFAULT NULL,
  `trigger_date` DATE DEFAULT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `is_recurring` TINYINT(1) NOT NULL DEFAULT 0,
  `recurring_frequency` ENUM('daily', 'weekly', 'monthly', 'quarterly', 'yearly') DEFAULT NULL,
  `email_notification` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_alert_type` (`alert_type`),
  INDEX `idx_is_active` (`is_active`),
  INDEX `idx_trigger_date` (`trigger_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Notifications
CREATE TABLE IF NOT EXISTS `notifications` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `alert_id` BIGINT UNSIGNED DEFAULT NULL,
  `type` VARCHAR(50) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `message` TEXT NOT NULL,
  `data` JSON DEFAULT NULL,
  `is_read` TINYINT(1) NOT NULL DEFAULT 0,
  `read_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  FOREIGN KEY (`alert_id`) REFERENCES `alerts`(`id`) ON DELETE SET NULL,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_is_read` (`is_read`),
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- REPORTING SYSTEM
-- ============================================================================

-- Reports
CREATE TABLE IF NOT EXISTS `reports` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `report_type` ENUM('income_summary', 'expense_summary', 'tax_summary', 'schedule_c', 'quarterly_tax', 'mileage_deduction', 'profit_loss', 'custom') NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `description` TEXT DEFAULT NULL,
  `date_from` DATE NOT NULL,
  `date_to` DATE NOT NULL,
  `filters` JSON DEFAULT NULL,
  `file_path` VARCHAR(500) DEFAULT NULL,
  `file_format` ENUM('pdf', 'csv', 'xlsx') NOT NULL,
  `generated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_report_type` (`report_type`),
  INDEX `idx_generated_at` (`generated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- AUDIT & LOGGING
-- ============================================================================

-- Audit Logs
CREATE TABLE IF NOT EXISTS `audit_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED DEFAULT NULL,
  `event` VARCHAR(100) NOT NULL,
  `event_type` ENUM('create', 'read', 'update', 'delete', 'login', 'logout', 'failed_login', 'permission_change', 'export', 'other') NOT NULL,
  `model_type` VARCHAR(100) DEFAULT NULL,
  `model_id` BIGINT UNSIGNED DEFAULT NULL,
  `old_values` JSON DEFAULT NULL,
  `new_values` JSON DEFAULT NULL,
  `ip_address` VARCHAR(45) DEFAULT NULL,
  `user_agent` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE SET NULL,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_event` (`event`),
  INDEX `idx_event_type` (`event_type`),
  INDEX `idx_created_at` (`created_at`),
  INDEX `idx_model` (`model_type`, `model_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Login History
CREATE TABLE IF NOT EXISTS `login_history` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED DEFAULT NULL,
  `username` VARCHAR(100) DEFAULT NULL,
  `ip_address` VARCHAR(45) NOT NULL,
  `user_agent` TEXT DEFAULT NULL,
  `status` ENUM('success', 'failed', 'locked') NOT NULL,
  `failure_reason` VARCHAR(255) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE SET NULL,
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_ip_address` (`ip_address`),
  INDEX `idx_status` (`status`),
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- SYSTEM SETTINGS
-- ============================================================================

-- Settings
CREATE TABLE IF NOT EXISTS `settings` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `user_id` BIGINT UNSIGNED DEFAULT NULL COMMENT 'NULL for global settings',
  `category` VARCHAR(50) NOT NULL,
  `key` VARCHAR(100) NOT NULL,
  `value` TEXT NOT NULL,
  `type` ENUM('string', 'integer', 'boolean', 'json', 'float') NOT NULL DEFAULT 'string',
  `is_public` TINYINT(1) NOT NULL DEFAULT 0,
  `description` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE,
  UNIQUE KEY `unique_user_category_key` (`user_id`, `category`, `key`),
  INDEX `idx_user_id` (`user_id`),
  INDEX `idx_category` (`category`),
  INDEX `idx_key` (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Rate Limiting
CREATE TABLE IF NOT EXISTS `rate_limits` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `identifier` VARCHAR(255) NOT NULL COMMENT 'IP or user ID',
  `action` VARCHAR(100) NOT NULL,
  `attempts` INT UNSIGNED NOT NULL DEFAULT 1,
  `reset_at` TIMESTAMP NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_identifier_action` (`identifier`, `action`),
  INDEX `idx_identifier` (`identifier`),
  INDEX `idx_reset_at` (`reset_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Backups
CREATE TABLE IF NOT EXISTS `backups` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `backup_type` ENUM('full', 'partial', 'manual', 'scheduled') NOT NULL,
  `file_name` VARCHAR(255) NOT NULL,
  `file_path` VARCHAR(500) NOT NULL,
  `file_size` BIGINT UNSIGNED NOT NULL,
  `is_encrypted` TINYINT(1) NOT NULL DEFAULT 1,
  `compression_type` VARCHAR(20) DEFAULT 'gzip',
  `status` ENUM('pending', 'processing', 'completed', 'failed') NOT NULL DEFAULT 'pending',
  `error_message` TEXT DEFAULT NULL,
  `created_by` BIGINT UNSIGNED DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed_at` TIMESTAMP NULL DEFAULT NULL,
  FOREIGN KEY (`created_by`) REFERENCES `users`(`id`) ON DELETE SET NULL,
  INDEX `idx_created_at` (`created_at`),
  INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- SEED DEFAULT ROLES AND PERMISSIONS
-- ============================================================================

-- Insert default roles
INSERT INTO `roles` (`name`, `display_name`, `description`, `is_system`) VALUES
('super_admin', 'Super Administrator', 'Full system access with all permissions', 1),
('admin', 'Administrator', 'Administrative access with user management', 1),
('financial_manager', 'Financial Manager', 'Full access to financial data and reports', 1),
('accountant', 'Accountant', 'View financial data and generate reports', 1),
('standard_user', 'Standard User', 'Basic user with personal financial management', 1),
('readonly', 'Read Only', 'Read-only access to assigned data', 1);

-- Insert default permissions
INSERT INTO `permissions` (`name`, `display_name`, `module`) VALUES
-- User Management
('users.view', 'View Users', 'users'),
('users.create', 'Create Users', 'users'),
('users.edit', 'Edit Users', 'users'),
('users.delete', 'Delete Users', 'users'),
-- Role Management
('roles.view', 'View Roles', 'roles'),
('roles.create', 'Create Roles', 'roles'),
('roles.edit', 'Edit Roles', 'roles'),
('roles.delete', 'Delete Roles', 'roles'),
-- Income Management
('income.view', 'View Income', 'income'),
('income.create', 'Create Income', 'income'),
('income.edit', 'Edit Income', 'income'),
('income.delete', 'Delete Income', 'income'),
-- Expense Management
('expenses.view', 'View Expenses', 'expenses'),
('expenses.create', 'Create Expenses', 'expenses'),
('expenses.edit', 'Edit Expenses', 'expenses'),
('expenses.delete', 'Delete Expenses', 'expenses'),
-- Tax Management
('tax.view', 'View Tax Records', 'tax'),
('tax.create', 'Create Tax Records', 'tax'),
('tax.edit', 'Edit Tax Records', 'tax'),
('tax.delete', 'Delete Tax Records', 'tax'),
-- Reports
('reports.view', 'View Reports', 'reports'),
('reports.create', 'Generate Reports', 'reports'),
('reports.export', 'Export Reports', 'reports'),
-- Documents
('documents.view', 'View Documents', 'documents'),
('documents.upload', 'Upload Documents', 'documents'),
('documents.delete', 'Delete Documents', 'documents'),
-- Settings
('settings.view', 'View Settings', 'settings'),
('settings.edit', 'Edit Settings', 'settings'),
-- Audit Logs
('audit.view', 'View Audit Logs', 'audit'),
-- Backups
('backup.create', 'Create Backups', 'backup'),
('backup.restore', 'Restore Backups', 'backup');

SET FOREIGN_KEY_CHECKS = 1;
COMMIT;
