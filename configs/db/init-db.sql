-- Run once on db1 (mysql as root); Galera replicates everything to db2.
-- Replace <dvwa password> in the session only; never save the real value in a file.
CREATE DATABASE IF NOT EXISTS dvwa;
CREATE USER 'dvwa'@'10.0.3.5' IDENTIFIED BY '<dvwa password>';
CREATE USER 'dvwa'@'10.0.3.6' IDENTIFIED BY '<dvwa password>';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'10.0.3.5', 'dvwa'@'10.0.3.6';
CREATE USER 'haproxy_check'@'10.0.3.5';
CREATE USER 'haproxy_check'@'10.0.3.6';
