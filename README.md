# Caja Chica

Cliente Flutter del Web Service de EFSISCONT (`assets/ws/ws.php`).

## Menu y mantenimiento de conexiones

El menu lateral de la aplicacion permite abrir **Mantenimiento > Conexiones**.
Las empresas se crean, editan, prueban, anulan y eliminan en el almacenamiento
local del dispositivo; no se consultan ni se guardan en la tabla `conecciones`.
Para probar la conexión o consultar orígenes y enviar vouchers, Flutter envía
temporalmente al Web Service `assets/ws/ws.php` el host, base de datos, usuario,
contraseña y tipo configurados. El Web Service abre esa conexión directamente y
no persiste las credenciales. El formulario admite MYSQL, SQL y ACCESS.

El endpoint predeterminado es
`http://localhost/proyectos/efsiscont_v2/assets/ws/ws.php`. En un teléfono,
`localhost` apunta al propio teléfono: reemplácelo por la IP del equipo que
ejecuta XAMPP y permita el acceso desde la red local. Si el servicio se publica
fuera de la red local, configure `WS_TOKEN` y use HTTPS.
En ese caso, configure el mismo valor en `AppConfig.wsToken` para que la app
envíe el encabezado de autorización.
El menu **Mantenimiento > Centros de costo** permite consultar, crear, editar y
eliminar centros de costo en la empresa SISCONT seleccionada. Requiere una
conexion activa y guarda los cambios en `mdh_cc` de la base de esa empresa.

La opcion **Caja** del menu permite mantener hasta dos cajas locales abiertas
al mismo tiempo: una en PEN y otra en USD. En cada caja se pueden agregar
fondos, registrar gastos con concepto, monto y fecha, cerrar y consultar el
historial. El historial lista conjuntamente cajas abiertas y cerradas; al
expandir una caja se consultan sus movimientos y se puede preparar el envio de
sus comprobantes por Excel/WhatsApp o a una conexion externa SISCONT. Los
registros y sus totales se guardan en el dispositivo y no se envian a SISCONT.

En **Mantenimiento** se configura localmente el origen de gasto de Caja
(predeterminado `01`) y los tipos de movimiento. El tipo **EFECTIVO** se crea
automáticamente y no se puede eliminar; todos los tipos usan la cuenta
contable fija `60002` para ingresos y gastos. Esta configuración todavía no
se envía a SISCONT.
El formulario de Caja ofrece los tipos configurados en un selector antes del
concepto y conserva el nombre elegido en el registro local.
En **Caja > Tipo de cambio** se registra el valor diario y se consulta su
historial. Al iniciar cada día sin un valor guardado se crea automáticamente
con 1.000. Al convertir un comprobante a otra moneda, ese valor se propone
cuando el documento no trae un tipo de cambio distinto.
Al registrar un movimiento de Caja o guardar una salida por comprobante, la app
consulta SUNAT solo si el tipo de cambio del día es 1.000 o menor; si ya es
mayor que 1, no realiza la consulta. La operación usa el tipo de cambio de venta
publicado en SUNAT mediante el Web Service PHP. Si SUNAT no está disponible, el
movimiento continúa y la app informa que no pudo actualizarlo.
Caja permite una apertura por moneda, con monto inicial (por defecto 0.00).
Se puede elegir cuál de las cajas abiertas está seleccionada para registrar
movimientos o cerrarla; el cierre calcula el saldo como apertura + ingresos -
gastos y guarda la sesión en el historial. Cada cierre recibe un voucher
correlativo que inicia en 1 y se reinicia al cambiar de mes. Aperturas,
movimientos, cierres y vouchers son locales al dispositivo.
Tomar una foto o seleccionar una imagen/PDF requiere una Caja abierta. Al
guardar el comprobante revisado se descuenta una sola vez su total; se elige
el tipo/cuenta de gasto. Si su moneda difiere de Caja, se convierte usando el
campo TC del comprobante. Reimportar el mismo documento actualiza su salida en
vez de duplicarla; si ya pertenece a un cierre, se conserva en esa caja y se
recalcula el saldo histórico.
Además del registro por foto, galería o PDF, **Registrar compra manual**
permite ingresar una compra/salida sin adjuntar archivo. Se registra con tipo
de documento peruano **00 - Otros**, y al guardar se descuenta el total de la
Caja abierta con el tipo/cuenta de gasto elegido.
La pantalla **Proveedores locales** permite crear, buscar, editar y eliminar
proveedores con documento, nombre, dirección, teléfono, correo, centro de
costos y concepto de gasto predeterminados. Se guarda solo en el dispositivo.
Al seleccionar un proveedor en el formulario de compra, se aplican sus
asignaciones guardadas. Si el proveedor de una compra manual o de un documento
adjunto coincide con el registro local por RUC o nombre, su centro de costos y
concepto de gasto se preseleccionan automáticamente. Los proveedores de
comprobantes guardados también se agregan o actualizan automáticamente. Cada
ingreso manual de Caja solicita
nombre y documento del cliente; al guardar el ingreso, crea o actualiza el
cliente local y vincula sus datos al movimiento.

## Que incluye

- **Login**: usuario y contrasena, con sesion recordada en el dispositivo.
- **Identidad visual**: `assets/images/logotipo.png` aparece en el login y en
  los encabezados internos; la barra superior principal queda sin logotipo.
  `assets/images/icon.png` se usa para los iconos de Android y del navegador.
- **Navbar superior**: replica `app/Views/includes/sup.php` (logo, Escritorio,
  CONTABILIDAD, INFORMES, TABLAS, MANTENIMIENTO, selector de base de datos,
  boton verde ELEGIR y Salir) sobre fondo `#f4f6f9`.
- **VOUCHER**: replica `app/Views/pages/voucher.php`. Panel teal "INGRESO DE
  VOUCHER", barra reactiva (Origen / Periodo / Numero / Fecha), tabla compacta
  de 16 columnas con seleccion de fila y teclado, totales en moneda local y
  dolares, y botones clasicos OK / EDITAR / Cancela / Repli.
- **DATOS VOUCHER**: replica `#datosVoucherModal` (teal `#4ec5be`, labels azul
  marino, radios Local/Dolares, divisor y pie Grabar / Cancelar).
- **Conexiones**: altas, ediciones, pruebas y estados guardados localmente;
  las credenciales se envían al Web Service solo al operar con SISCONT.
- **Enviar a SISCONT**: desde el reporte, elige una conexion activa y un origen
  contable y envia los comprobantes del rango a `mdh_vou` por la operacion
  `grabarvoucher` del Web Service PHP. Genera una línea DEBE por producto
  detectado (o por base contable), una línea para IGV incluso cuando su importe
  es `0.00`, líneas para otros tributos cuando aplican y una línea HABER para
  la cuenta por pagar. Valida fecha, número, cuadre y un mínimo de tres líneas
  antes de empezar el envío. La línea de IGV en cero es una convención interna
  del asiento y no representa crédito fiscal; la operación debe conservar su
  clasificación tributaria correspondiente.
- **Reporte**: muestra directamente la rendición de la Caja abierta actual (o
  el último cierre si no hay cajas abiertas), incluye el gráfico de productos
  más comprados (con opción de desglosar por proveedores y gastos), y filtros
  por centro de costos y rango de fechas opcional. También permite exportar por
  WhatsApp o enviar a SISCONT.
- Cada comprobante conserva su fecha de registro (primera captura) y su fecha
  del documento. Reporte abre por defecto la rendición de la Caja abierta
  actual (o el último cierre si no hay cajas abiertas); el usuario puede activar
  el rango de fechas para consultar otras compras. Los filtros y la fecha
  contable `FECHA` de SISCONT usan la fecha de registro; `FECHAD` mantiene la
  fecha del documento. En Reporte se puede filtrar por todas las cajas o por
  una caja específica, abierta o cerrada; este filtro también se aplica al
  Excel/WhatsApp y al envío a SISCONT.
  El Excel conserva
  intacta la hoja `Compras` de 60 columnas y agrega una hoja `Control` con las
  dos fechas y los estados independientes de WhatsApp y SISCONT.
- Los estados de envío son independientes por canal. Tras compartir el Excel
  se confirma si se envió por WhatsApp; SISCONT se marca enviado al completar
  todas las líneas. Antes de reenviar se puede incluir los ya enviados o
  limitarse a los pendientes.
- El formulario del comprobante muestra el detalle de productos detectado por
  IA en una tabla de solo lectura con encabezados; la cabecera del voucher se
  muestra antes del detalle. Si la suma del detalle difiere de las bases, el
  asiento conserva las líneas de productos y agrega una línea de ajuste visible
  en la misma cuenta de gasto; la pantalla de confirmación muestra el voucher y
  el importe del ajuste antes de enviarlo.
- Al volver a importar el mismo comprobante, se actualiza el registro existente
  por RUC/proveedor, tipo y numero de documento; los duplicados guardados se
  depuran al iniciar la aplicacion.
- **Configuracion**: sesion, empresa, URL del servidor, token, estado del
  servicio y cierre de sesion.

## Piel grafica

Todo sale de `lib/src/theme/tema.dart`, con los valores literales del CSS del
sistema original:

| Elemento | Valor |
| --- | --- |
| Fondo del contenido | `#f4f6f9` |
| Panel principal | `#5cbdb9` |
| Modal de datos | `#4ec5be` |
| Cabecera de tabla | `#9bd3d0` |
| Fila seleccionada | `#0d6efd` con texto blanco |
| Hover de fila | `#f0f8f7` |
| Selector Origen | fondo `#0d6efd`, borde `#0a58ca` |
| Etiquetas del modal | `#003366` |
| Controles | 24px, borde `#999`, sin radio |
| Botones clasicos | fondo `#d1d5db`, borde `#333`, sombra `2px 2px 4px` |
| Pie del modal | `#f0f0f0` con separadores `#999` |
| Tipografia de tabla | 11.5px, filas de 18px |

## Arranque

```bash
flutter pub get
flutter run
```

## Login

Al abrir la app aparece el login con la piel de `/voucher`: panel teal
`#5cbdb9` con borde `#333`, barra gris con el logo del sistema, titulo
"Siscont Gestión Contable", labels en negrita, controles de 24px,
casilla "Recordar mi sesion" y botones clasicos (Ingresar al Sistema /
Servidor).

El logo es `assets/images/logo_navbar.png`, convertido desde
`assets/images/login.avif` del PHP (271x53, el mismo de `sup.php`).

- Valida contra `op=login` del WS (alias `op=verificar`). La clave se acepta en
  texto plano o como hash bcrypt.
- Con **Recordar mi sesion** marcado se guardan usuario, contrasena, id y nombre
  de la empresa en `SharedPreferences`; la proxima vez la app entra directo.
- Sin marcarlo, la sesion vive solo en memoria y se pierde al cerrar la app.
- **Configuracion > Cerrar sesion** (o el menu Salir de la navbar) borra lo
  guardado.
- La empresa se puede cambiar desde la navbar, en Configuracion o desde el menu
  de la conexion.

> La contrasena queda en texto plano en las preferencias del dispositivo. En un
> equipo compartido no marques "Recordar mi sesion".

## URL del servidor

La app Flutter apunta al servicio de produccion en
`https://siscont.solutions.net.pe/assets/ws/ws.php`. El sitio PHP construye sus
enlaces y redirecciones con rutas relativas y detecta su URL base desde la
peticion, sin depender de `localhost` ni de la carpeta XAMPP.

Si el servicio ya lleva token configurado (`WS_TOKEN` en `ws.php`), escribelo en
Ajustes: se envia como `Authorization: Bearer <token>`.

## Uso del cliente desde codigo

```dart
import 'package:efsiscont_flutter/src/api/efsiscont_api.dart';

final api = EfsiscontApi(baseUrl: 'https://siscont.solutions.net.pe');

final ingreso = await api.login(usuario: 'DEMO', clave: 'DEMO');
print(ingreso.id);
print(ingreso.nombre);
print(ingreso.empresaPorDefecto);
print(ingreso.empresas);

final conexiones = await api.listarConexiones();
final empresas = await api.listarEmpresas();
final origenes = await api.listarOrigenes(conexion: 1);

final voucher = await api.mostrarVoucher(
  conexion: 1,
  origen: '01',
  voucher: '17',
  periodo: '01',
);

print(voucher.totales.debeSoles);
print(voucher.detalle.length);

final nueva = await api.guardarConexion(
  nombre: 'MIEMPRESA',
  host: 'localhost',
  data: 'mi_base',
  usuario: 'root',
  pass: '',
  tipo: 'MYSQL',
);

await api.anularConexion(nueva.id);
```

Todos los errores del servicio llegan como `ApiException` (mensaje, codigo HTTP
y operacion). `ApiException.esDeRed` indica si fue un fallo de red.

## Estructura

```
lib/
  main.dart
  src/
    config.dart                  URL base, token y sesion persistidos
    app_state.dart               sesion + empresa activa (ChangeNotifier)
    theme/
      tema.dart                  paleta, medidas y widgets base del CSS original
    api/
      efsiscont_api.dart         cliente HTTP con todas las operaciones
      api_exception.dart
    models/
      conexion.dart              Conexion, Empresa
      sesion.dart                Sesion (usuario, empresa, lista de empresas)
      voucher.dart               Origen, VoucherLinea, VoucherTotales, Voucher
    pages/
      login_page.dart
      voucher_page.dart          INGRESO DE VOUCHER
      conexiones_page.dart
      conexion_form_page.dart
      ajustes_page.dart
    widgets/
      navbar_sup.dart            barra superior (sup.php)
      panel_voucher.dart         panel teal, barra de titulo y pie clasico
      tabla_voucher.dart         tabla compacta de 16 columnas
      datos_voucher_modal.dart   modal DATOS VOUCHER
      dialogo_servidor.dart      URL/token antes de ingresar
      sin_conexion.dart
```

## Pruebas

```bash
flutter test

# Pruebas contra el WS real (se omiten si no hay servidor)
flutter test test/ws_integration_test.dart \
  --dart-define=WS_BASE_URL=https://siscont.solutions.net.pe \
  --dart-define=WS_USUARIO=DEMO \
  --dart-define=WS_CLAVE=DEMO
```

## Lectura de comprobantes con IA

La app no guarda claves de IA. Al adjuntar una foto o un PDF, el archivo se
envía a la operación `analizaradjunto` del WS (`assets/ws/ws.php`), que guarda
el adjunto en el servidor y lo analiza con la IA configurada allí (Groq, con
respaldo local/Gemini según `app/Models/comprobantepdf.php`). La respuesta se
convierte al formulario de compras y el usuario revisa/corrige antes de guardar.

Requisitos en el servidor:

- Configurar la clave de Groq en el backend (por ejemplo `GROQ_API_KEY`); no en
  `lib/src/config.dart` ni en la app compilada.
- PHP con permiso de escritura en `assets/subidas/vouchers` y límite de subida
  de al menos 8 MB (`upload_max_filesize`/`post_max_size`).
- El análisis puede tardar; el cliente espera hasta 180 segundos.

Si el backend no puede leer el comprobante, la app ofrece llenarlo a mano sin
perder el archivo adjunto.

## Notas de plataforma

- Android ya tiene `INTERNET` y `usesCleartextTraffic` habilitados para HTTP.
- iOS ya tiene `NSAllowsArbitraryLoads` para HTTP.
- Si el sistema PHP no tiene `WS_TOKEN`, el servicio queda abierto: cualquiera
  con la URL puede listar conexiones (incluidas sus contrasenas). Protegelo
  antes de exponerlo a internet.
