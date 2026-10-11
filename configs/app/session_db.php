<?php
class DbSessionHandler implements SessionHandlerInterface {
    private $db;
    public function open($path, $name): bool {
        $this->db = new PDO('mysql:host=127.0.0.1;dbname=phpsess', 'dvwa', getenv('DB_PASSWORD'),
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        return true;
    }
    public function close(): bool { $this->db = null; return true; }
    public function read($id): string|false {
        $s = $this->db->prepare('SELECT data FROM sessions WHERE id = ?');
        $s->execute([$id]);
        $d = $s->fetchColumn();
        return $d === false ? '' : $d;
    }
    public function write($id, $data): bool {
        return $this->db->prepare('REPLACE INTO sessions (id, data, ts) VALUES (?, ?, ?)')
                        ->execute([$id, $data, time()]);
    }
    public function destroy($id): bool {
        return $this->db->prepare('DELETE FROM sessions WHERE id = ?')->execute([$id]);
    }
    public function gc($max): int|false {
        $s = $this->db->prepare('DELETE FROM sessions WHERE ts < ?');
        $s->execute([time() - $max]);
        return $s->rowCount();
    }
}
session_set_save_handler(new DbSessionHandler(), true);
