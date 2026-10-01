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

---
**Instrucción para la IA:** Asume el rol de Tech Lead. Genera código estructurado y modular basado en estos lineamientos. Inicia definiendo los modelos de datos y el servicio de sincronización offline (`SyncService`), ya que representan el núcleo técnico para resolver el reto planteado.