# Contexto Técnico y Arquitectura: Supervisión Inteligente de Servicios en Campo

## 1. Resumen del Proyecto
El proyecto es una solución tecnológica multiplataforma diseñada para mejorar el control, seguimiento y trazabilidad de las actividades de supervisión en campo[cite: 1]. El sistema mitiga la asimetría de información y asegura que las visitas a los centros de costo se realicen de manera verificable[cite: 1]. 

Se desarrollará un único código base multiplataforma estructurado para dos roles:
*   **Supervisor (Vista Móvil):** Permite registrar check-in/out con geolocalización, completar checklists de actividades, registrar novedades con evidencia fotográfica y operar sin conexión a Internet (offline-first)[cite: 1].
*   **Coordinador (Vista Web/Escritorio):** Panel centralizado para asignar visitas, visualizar mapas geográficos, consultar historiales, recibir alertas de novedades y exportar reportes[cite: 1].

## 2. Decisiones de Arquitectura de Software
*   **Patrón de Diseño:** MVVM (Model-View-ViewModel).
*   **Estructura de Carpetas:** Feature-First (organizado por módulos funcionales: `auth`, `visits`, `offline_sync`, `dashboard`).
*   **Enfoque de Red:** Offline-First. La aplicación móvil debe permitir el flujo completo sin conexión y sincronizar los datos automáticamente al restablecerse la red[cite: 1].

## 3. Stack Tecnológico Definido
*   **Framework Frontend:** Flutter (Lenguaje: Dart) para compilación a iOS, Android y Web.
*   **Backend as a Service (BaaS):** Firebase (Operado directamente desde Flutter con Dart).
    *   *Firebase Auth:* Autenticación basada en roles.
    *   *Cloud Firestore:* Base de datos NoSQL con persistencia offline nativa.
    *   *Firebase Storage:* Almacenamiento en la nube para evidencias fotográficas.
*   **Backend Serverless (Opcional):** Firebase Cloud Functions. Uso de TypeScript/Node.js o Python exclusivamente para tareas automatizadas de lado del servidor (ej. envío de alertas por correo ante novedades de prioridad alta).
*   **Base de Datos Local (Cola Offline):** Hive o Isar para gestionar la cola de subida de imágenes y metadatos no sincronizados temporalmente.
*   **Gestión de Estado:** Provider o GetX.

### Paquetes Clave de Flutter
*   `geolocator`: Para obtener latitud, longitud y hora exacta en el check-in/out[cite: 1].
*   `image_picker`: Restringido a `ImageSource.camera` para forzar fotos en tiempo real y evitar fraudes con imágenes de la galería[cite: 1].
*   `flutter_map` y `latlong2`: Para renderizar la información geográfica interactiva en el panel del coordinador[cite: 1].
*   `connectivity_plus`: Para detectar transiciones entre el estado offline y online.
*   `path_provider`: Para guardar las fotos temporalmente en el almacenamiento del dispositivo local.
*   `pdf` y `excel`: Para la exportación de reportes tabulares desde el panel web[cite: 1].

## 4. Estrategia de Funcionamiento Offline (Core del Reto)
Dado que la conectividad limitada es el desafío técnico central[cite: 1], se implementará el siguiente flujo:
1.  **Almacenamiento Local:** Si el dispositivo no tiene Internet, el estado de las actividades y las rutas locales de las fotografías se guardan en la base de datos local (Hive) bajo el estado `pending_sync`[cite: 1].
2.  **Listener de Red:** `connectivity_plus` escuchará constantemente los cambios de red.
3.  **Cola de Sincronización (Sync Queue):** Al recuperar la conexión a Internet[cite: 1], un servicio en segundo plano ejecutará automáticamente lo siguiente:
    *   Itera sobre la cola de registros pendientes de sincronización[cite: 1].
    *   Sube los archivos de imagen a Firebase Storage y obtiene la URL de acceso.
    *   Construye el documento JSON (incluyendo la URL de la evidencia) y lo envía a Cloud Firestore.
    *   Elimina el registro de la cola local para prevenir la duplicidad de datos[cite: 1].
    *   Maneja los errores y reintentos en caso de intermitencia[cite: 1].

## 5. Modelos de Datos Base (Colecciones NoSQL)
*   **Users:** `id`, `nombre`, `rol` (`supervisor` | `coordinador`), `estado`.
*   **CentrosCosto:** `id`, `nombre`, `latitud`, `longitud`, `radio_tolerancia` (para geofencing).
*   **Visitas:** `id`, `supervisorId`, `centroCostoId`, `checkIn` (timestamp, lat/lng), `checkOut` (timestamp, lat/lng), `actividadesCumplidas` (array), `estado` (`pendiente` | `en_progreso` | `completada`)[cite: 1].
*   **Novedades:** `id`, `visitaId`, `centroCostoId`, `descripcion`, `prioridad` (`alta` | `media` | `baja`), `evidenciaUrl`, `estado` (`abierta` | `resuelta`), `notificado` (boolean)[cite: 1].

## 6. Funcionalidades Críticas de Interfaz
*   **Panel Web (Coordinador):** Dashboard con indicadores en tiempo real de cumplimiento, mapa geográfico de cobertura, alertas de novedades y módulo de reportes[cite: 1].
*   **App Móvil (Supervisor):** Interfaz fluida, validación de visitas por coordenadas y formulario rápido para registro de actividades cumplidas/no cumplidas y novedades[cite: 1].

## 7. Desviaciones respecto al documento original
Esta sección registra las decisiones que difieren del planteamiento inicial y el motivo de cada una. `Context.md` sigue siendo la fuente de verdad: el código se ajusta aquí, no al revés.

### 7.1 Base de datos local: Isar → `hive_ce`
La sección 3 decía "Hive **o** Isar". Se eligió la rama de Hive porque **Isar no es viable con la versión de Dart del proyecto**: la resolución estable disponible (`isar 3.1.0+1`) declara `sdk: >=2.17.0 <3.0.0`, incompatible con Dart 3.13.4 (SDK constraint `^3.13.4`). Forzar Isar exigiría fijar un SDK anterior y perder el resto del toolchain actual.

Se usa `hive_ce` (Community Edition), que mantiene la API de Hive y sigue mantenido activamente. Consecuencias aceptadas:
*   Sin code generation: los items se guardan como cadenas JSON mediante un almacén propio (`JsonAlmacen`), lo que evita `build_runner`.
*   Las cajas se indexan por clave `"microsSinceEpoch-id"` para que `watch()` entregue en orden FIFO; un box auxiliar mapea id → clave de almacenamiento.

### 7.2 Exportación de reportes: `csv` + `file_saver` en lugar de `excel`/`pdf`
La sección 3 mencionaba `pdf` y `excel`. Se optó por **CSV**, porque el requisito real es que el coordinador pueda abrir el reporte en una hoja de cálculo y filtrarlo, no generar un documento con formato fijo:
*   `csv` con perfil Excel: separador `;` y BOM UTF-8. El separador es punto y coma porque en configuración regional española la coma es el separador decimal y rompería las columnas numéricas.
*   `file_saver` para la descarga: una sola implementación para navegador (web) y nativo, evitando mantener `dart:io` con tres archivos por plataforma.
*   El paquete `excel` no se usa: escribir un `.xlsx` exige hablar el formato OOXML (zip + XML) a mano, y el resultado no aporta nada frente a un CSV bien formado para este caso.

### 7.3 `flutter_localizations` como dependencia obligatoria
`DateFormat(..., 'es')` lanza `LocaleDataException` sin los datos de localización cargados, y `showDateRangePicker` (filtro de fechas del panel) requiere `GlobalMaterialLocalizations`. Por eso el SDK se añade a `dependencies` y `main()` llama a `initializeDateFormatting('es')` antes de construir la app. No es unaucherencia de estilo: sin esto la app falla al arrancar.

### 7.4 Identificadores generados en el cliente
El documento original no especifica el origen de los ids. Se usa un UUID generado en el cliente como ID de documento en Firestore y como nombre del objeto en Storage. Es lo que hace idempotente el reintento de la cola: reintentar sobrescribe en lugar de duplicar, que es el requisito de "prevención de duplicidad" de la sección 4.

### 7.5 Firebase no incluye credenciales
No hay `google-services.json` ni `firebase_options.dart` en el repositorio, y no deben añadirse (son secretos). En su lugar, `main.dart` captura `FirebaseNoConfiguradoException` y muestra una pantalla con los pasos de configuración. Consecuencia práctica: el build web, `flutter analyze` y toda la suite de tests funcionan sin credenciales; el APK de Android requiere el archivo, tal como se documenta en `README.md`.

### 7.6 Filtros del panel aplicados en memoria
El panel del coordinador obtiene un snapshot y aplica `FiltroConsulta` en memoria en lugar de componer consultas con múltiples `where`. Motivo: los índices compuestos de Firestore hay que crearlos a mano en la consola y una app que no arranca sin esa configuración manual es frágil para una demostración. El costo es traer el histórico completo del supervisor; si el volumen lo justificara, el cambio es local a `FirestoreConsultaRepository`.

---
**Instrucción para la IA:** Asume el rol de Tech Lead. Genera código estructurado y modular basado en estos lineamientos. Inicia definiendo los modelos de datos y el servicio de sincronización offline (`SyncService`), ya que representan el núcleo técnico para resolver el reto planteado.