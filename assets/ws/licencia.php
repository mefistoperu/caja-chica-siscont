<?php
/**
 * Proxy local para el servicio de licencias de nubesiscont.com.
 *
 * El servidor remoto no envia cabeceras CORS, por lo que Flutter Web no puede
 * consultarlo directamente desde el navegador. Este script hace la peticion
 * desde PHP (servidor a servidor) y devuelve la respuesta con CORS habilitado.
 *
 * Uso:
 *   GET /proyectos/efsiscont_flutter_v2/assets/ws/licencia.php?correo=...&pcorreo=...
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Accept, Content-Type');
header('Content-Type: application/json; charset=utf-8');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$correo = isset($_GET['correo']) ? trim((string) $_GET['correo']) : '';
$clave  = isset($_GET['pcorreo']) ? (string) $_GET['pcorreo'] : '';

if ($correo === '' || $clave === '') {
    http_response_code(400);
    echo json_encode(array('error' => 'Faltan el correo o la contrasena.'));
    exit;
}

$url = 'http://nubesiscont.com/llavesweb/index.php?' . http_build_query(array(
    'correo'  => $correo,
    'pcorreo' => $clave,
));

$respuesta = false;
$codigoHttp = 0;
$error = '';

if (function_exists('curl_init')) {
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
    curl_setopt($ch, CURLOPT_TIMEOUT, 20);
    curl_setopt($ch, CURLOPT_HTTPHEADER, array('Accept: application/json'));
    $respuesta = curl_exec($ch);
    $codigoHttp = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    if ($respuesta === false) {
        $error = curl_error($ch);
    }
    curl_close($ch);
} else {
    $contexto = stream_context_create(array(
        'http' => array(
            'timeout' => 20,
            'header'  => "Accept: application/json\r\n",
        ),
    ));
    $respuesta = @file_get_contents($url, false, $contexto);
    if ($respuesta === false) {
        $error = 'No se pudo acceder al servicio remoto.';
    }
}

if ($respuesta === false || $respuesta === '') {
    http_response_code(502);
    echo json_encode(array(
        'error' => 'No se pudo conectar con el servidor de licencias.',
        'detalle' => $error,
    ));
    exit;
}

http_response_code($codigoHttp > 0 ? $codigoHttp : 200);
echo $respuesta;
