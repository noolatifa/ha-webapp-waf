<?php
header('Content-Type: application/json');
header('Cache-Control: no-store');
$noms = ['10.0.1.2' => 'app1', '10.0.2.2' => 'app2'];
$out = ['app' => $noms[$_SERVER['SERVER_ADDR'] ?? ''] ?? gethostname()];
mysqli_report(MYSQLI_REPORT_OFF);
$c = mysqli_init();
$c->options(MYSQLI_OPT_CONNECT_TIMEOUT, 2);
if (@$c->real_connect('db', 'dvwa', getenv('DB_PASSWORD'), 'dvwa')) {
    $id = $c->query('SELECT @@server_id')->fetch_row()[0];
    $out['db_active'] = ($id == 1) ? 'db1' : 'db2';
} else { $out['db_active'] = null; }
$out['db'] = [];
$csv = @file_get_contents('http://10.0.3.4:8404/stats;csv', false, stream_context_create(['http' => ['timeout' => 1]]));
if ($csv) { foreach (explode("\n", $csv) as $ligne) { $f = explode(",", $ligne);
    if (($f[0] ?? '') === 'mariadb' && in_array($f[1] ?? '', ['db1', 'db2'])) { $out['db'][$f[1]] = $f[17]; } } }
echo json_encode($out);
