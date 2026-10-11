-- Shared PHP sessions (stage 14). Run once on db1 (mysql as root).
CREATE DATABASE IF NOT EXISTS phpsess;
CREATE TABLE IF NOT EXISTS phpsess.sessions (
    id   VARCHAR(128) NOT NULL PRIMARY KEY,
    data MEDIUMBLOB,
    ts   INT UNSIGNED NOT NULL,
    KEY (ts)
) ENGINE=InnoDB;
GRANT SELECT, INSERT, UPDATE, DELETE ON phpsess.* TO 'dvwa'@'10.0.3.5', 'dvwa'@'10.0.3.6';
