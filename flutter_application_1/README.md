# FieldCheck

Supervisión inteligente de servicios de limpieza en campo.

Una sola aplicación Flutter con dos roles:

- **Supervisor** (móvil, Android): registra sus visitas con validación geográfica, checklist y fotos, **funcionando sin conexión**.
- **Coordinador** (web): ve todo el histórico en un panel con KPIs, mapa de cobertura, filtros y exportación a CSV.

El reto es el modo *offline-first*: el supervisor trabaja en zonas sin cobertura y todo lo que registra debe llegar al servidor después, sin pérdidas y sin duplicados.

## Stack

| Capa | Tecnología |
|---|---|
| UI | Flutter 3.47 / Dart 3.13 |
| Autenticación | Firebase Auth |
| Base de datos | Cloud Firestore |
| Archivos | Firebase Storage |
| Almacenamiento local | Hive CE |
| Estado | Provider (MVVM) |
| GPS / cámara | geolocator, image_picker |
| Red | connectivity_plus |
| Mapa | flutter_map (OpenStreetMap) |

## Arquitectura

Feature-first sobre MVVM:

```
lib/
  core/         # logger, tema, widgets comunes, inyección de dependencias, reloj
  domain/       # modelos, contratos, servicios de negocio (sin Flutter ni Firebase)
  data/         # implementaciones: Firestore, Storage, Hive, repositorios
  features/     # auth, sync, supervisor, coordinator
```

El dominio no depende de Firebase ni de `dart:io`. Eso es lo que permite testear toda la lógica offline (geofence, cola, reintentos, idempotencia) con dobles en memoria, sin emulador ni credenciales.

El flujo de toda operación de campo sigue siempre los mismos cuatro pasos:

```text
1. validar        geofence, estado de la visita, datos obligatorios
2. guardar local  Hive: la UI lee de acá, nunca de la red
3. encolar        SyncQueueStore: la subida pendiente queda registrada
4. sincronizar    best-effort: si no hay red, no importa
```

Ningún método falla por falta de conexión. La cola garantiza que un item solo se elimina después de que el servidor confirme la escritura, y cada item se escribe usando su propio UUID como ID de documento, así un reintento sobrescribe en vez de duplicar.

## Requisitos

- Flutter 3.47.5 o superior (Dart 3.13.4)
- Java 17 o superior para compilar Android
- Un proyecto de Firebase

## Configuración de Firebase

El proyecto **no incluye credenciales**. Sin ellas la app arranca y muestra la pantalla de configuración con estos pasos; el resto de la app (tests, análisis, build web) funciona igual.

### 1. Crear el proyecto

1. Entra a [Firebase Console](https://console.firebase.google.com) y crea un proyecto.
2. Añade una app **Android** con:
   - **Application ID**: `com.fieldcheck.app`
   - **Nickname**: `FieldCheck`

### 2. Habilitar los servicios

En *Authentication → Sign-in method*, activa **Correo/contraseña**.
En *Firestore Database*, crea la base de datos (modo producción) y en *Storage*, activa el bucket.

### 3. Descargar el archivo de configuración

- Android: descarga **`google-services.json`** y cópialo en
  `flutter_application_1/android/app/google-services.json`.

  Sin este archivo, Gradle falla con un error de plugin de Google Services.
- Web (opcional, para probar el panel del coordinador en Chrome):
  *Project settings → General → Your apps → SDK setup and configuration → Web*,
  copia el bloque de configuración y pégalo en el `firebase_options.dart`
  generado, o créalo a mano con esos valores.

### 4. Instalar y arrancar

```bash
flutter pub get
flutter run                 # Android (requiere google-services.json)
flutter run -d chrome      # panel del coordinador (no requiere google-services.json)
```

Sin `google-services.json`, `flutter run` en Android no compila. El build web sí funciona y sirve para revisar el panel del coordinador.

### 5. Reglas de Firestore

La app necesita estas colecciones:

| Colección | Contenido | Escritura |
|---|---|---|
| `usuarios/{uid}` | Perfil y rol (`supervisor` / `coordinador`) | El rol se resuelve en tiempo de lectura, no en el token |
| `centros_costo/{id}` | Centro, geofence y checklist | Coordinador |
| `visitas/{id}` | Visita con check-in, check-out, checklist | Supervisor (vía cola) |
| `novedades/{id}` | Novedad reportada | Supervisor (vía cola) |
| `evidencias/{id}` | Metadatos de la foto (la imagen vive en Storage) | Supervisor (vía cola) |

El ID de cada documento es el UUID que genera el cliente, nunca un
autoincremental: es lo que hace idempotente el reintento de subida.

Si se agrega un filtro compuesto en las consultas del panel, hay que crear el
índice correspondiente en Firestore; el panel ya aplica los criterios en memoria
para no depender de esa configuración.

## Pruebas y análisis

```bash
flutter analyze lib test
flutter test
flutter build web --release
```

La suite corre sin credenciales de Firebase ni emulador: todo el flujo offline
se verifica con dobles en memoria (`test/helpers/fakes.dart`) sobre el
`SyncService` real.

## Exportación de reportes

El panel del coordinador exporta a **CSV con punto y coma y BOM UTF-8**, el
formato que abre directamente Excel en configuración regional española (donde la
coma es separador decimal). El archivo se genera con exactamente las listas que
se ven en pantalla, sin volver a consultar: el reporte y la vista no pueden
divergir.

## Notas de producción

- **Mapa**: usa teselas de OpenStreetMap, con la atribución requerida. En
  producción conviene un proveedor de teselas contratado.
- **Geofence**: el radio de tolerancia es configurable por centro de costo;
  100 m es el valor inicial.
- **Conectividad**: `connectivity_plus` informa de la interfaz de red, no de
  Internet real. Por eso una subida que falla por timeout se trata como estado
  offline (se reintenta), en lugar de marcarse como error definitivo.