CREATE USER IF NOT EXISTS 'repl'@'10.0.3.3' IDENTIFIED BY '<replication password>';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'10.0.3.3';
RESET MASTER;
CREATE USER 'haproxy_check'@'10.0.3.4';
CREATE USER 'repl'@'10.0.3.2' IDENTIFIED BY '<replication password>';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'10.0.3.2';
