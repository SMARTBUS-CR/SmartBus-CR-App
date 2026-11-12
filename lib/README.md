# SmartBus – Starter de placeholders (Pasajero + Conductor)

Este kit es solo la **carpeta `lib/`** para copiar dentro de tu proyecto Flutter
ya inicializado (un solo repo para ambas apps, como lo tienen planteado).

## 1. Cómo integrarlo
1. Copia el contenido de `lib/` de este zip encima de tu `lib/` actual
   (o mergea manualmente si ya tienes archivos).
2. Agrega a tu `pubspec.yaml`:
   ```yaml
   dependencies:
     http: ^1.2.0
   ```
3. Corre `flutter pub get` y luego `flutter run`.
4. La app abre directo en `LoginScreen`. Como todavía no hay login real
   conectado, el login trae un selector temporal "Pasajero / Conductor"
   (ver `_DevRole` en `auth/login_screen.dart`) solo para elegir a qué
   interfaz navegar después de iniciar sesión y poder previsualizar ambos
   flujos. Bórralo cuando el backend devuelva el rol real.

## 2. Qué mapea cada pantalla (según tus RF)

| Pantalla | Requerimientos cubiertos |
|---|---|
| `auth/login_screen.dart` | RF-07 (login pasajero), base para RF-13 conductor |
| `auth/register_screen.dart` | Registro de pasajero (issue #12): ruta `/register`, auto-login → `/passenger/home` |
| `auth/verify_email_screen.dart` | Verificación del correo con código de 6 dígitos: ruta `/verify-email` (`VerifyEmailArgs`), reenvío con espera de 60 s; al verificar inicia sesión → home del rol |
| `auth/register_screen.dart` | Registro de pasajero (issue #12): ruta `/register` → `/verify-email` (sin sesión hasta verificar el correo) |
| `passenger/passenger_home_screen.dart` | RF-08 (mapa principal), RF-09 (búsqueda) |
| `passenger/route_search_screen.dart` | RF-09 |
| `passenger/passenger_account_screen.dart` | Perfil del pasajero ("Mi Cuenta"): datos guardados al instante + refresco con `fetchCurrentUser()`; 401 → login; sin red → "Reintentar". Entradas "Editar perfil" y "Cambiar contraseña". Botón "Eliminar cuenta" con confirmación (solo UI: aún no llama al backend) |
| `passenger/edit_profile_screen.dart` | Editar nombre y correo (`updateProfile`): solo envía lo que cambió; cambiar el correo pide la contraseña actual y luego verificar el nuevo correo con código |
| `passenger/change_password_screen.dart` | Cambiar contraseña (`changePassword`): actual + nueva (requisitos en vivo) + confirmación |
| `passenger/passenger_account_screen.dart` | Perfil del pasajero ("Mi Cuenta"): datos guardados al instante + refresco con `fetchCurrentUser()`; 401 → login; sin red → "Reintentar". "Eliminar cuenta" (soft delete): confirmación con la contraseña actual → `deleteAccount()` → login sin poder volver atrás |
| `widgets/delete_account_dialog.dart` | Diálogo "¿Eliminar tu cuenta?": pide la contraseña, envía la solicitud y se queda abierto si la contraseña es incorrecta, hay 429 o no hay red; 401 → login, 403 → "Acción no permitida" |
| `passenger/bus_tracking_screen.dart` | RF-10 (ubicación en vivo), RF-11 (ETA), RF-12 (alertas) |
| `driver/driver_home_screen.dart` | RF-13 (ruta asignada del día) |
| `driver/driver_account_screen.dart` | Perfil del conductor ("Mi Cuenta"), solo lectura: aviso "contacta al administrador"; misma carga/401/"Reintentar" que el pasajero |
| `widgets/profile_details.dart` | Vista de perfil compartida (pasajero y conductor): datos guardados + `fetchCurrentUser()`, 401 → login, "Reintentar" |
| `widgets/smartbus_header.dart` | Header de todas las pantallas internas: degradado del tema por rol (`SmartBusUserType`), ola, ruta, pin y bus dibujados en código; variante `compact` para pantallas con mapa |
| `driver/trip_screen.dart` | RF-14 + RF-15: inicia el viaje en el Dashboard, envía el GPS y al finalizar lo completa (secciones 8 y 9). Desde la pestaña, sin viaje, busca el que está en curso |

## 3. Qué es placeholder vs. qué ya está "conectable"
- **Placeholder puro** (solo UI, sin lógica): listas de rutas, ETA.
- **Mapa del pasajero (real):** inicio del pasajero con MapLibre + OpenFreeMap
  (ver la sección 6).
- **Seguimiento del bus en vivo (real):** "Rastreando tu bus" con la posición
  del bus en tiempo real (ver la sección 7). Se abre desde el chip
  **"Buses en curso"** del inicio, eligiendo ruta y bus (sección 9).
- **Viajes reales del Dashboard (real):** el conductor ve e inicia sus viajes
  del día; el pasajero elige un bus en curso (sección 9). Sin `DEMO_TRIP_ID`.
- **Autenticación real (ya conectada al API Gateway):**
  - `core/config/api_config.dart` — URL única del Gateway (`--dart-define`).
  - `core/network/api_client.dart` — cliente HTTP reutilizable; adjunta el
    token `Bearer` automáticamente y traduce errores a `ApiException`.
  - `core/storage/secure_session_store.dart` — token + usuario en
    `flutter_secure_storage` (nunca la contraseña).
  - `features/auth/services/auth_service.dart` — `login` / `registerPassenger`
    / `sendResetCode` / `resetPassword` / `fetchCurrentUser` / `restoreSession`
    / `logout` (ver el contrato en la sección 5).
  - `features/auth/models/` — `AuthUser` + `AuthRole` (parseo JSON:API).
  - `features/auth/role_home.dart` — rol del backend → ruta de inicio.

  Flujo: `LoginScreen` → `AuthService().login()` → Gateway `POST /auth/login`
  → guarda token/usuario → navega según `homeRouteForUser(session.user)`.
  Al reabrir la app, `SplashScreen` llama `restoreSession()`.

## 4. Siguientes pasos sugeridos
1. Dibujar el trazo de la ruta y sus paradas sobre el mapa: los datos ya
   llegan en `RoutePattern.geometry` y `RoutePattern.stops` (sección 9).
2. Conectar el ETA (RF-16).
1. Dibujar rutas, paradas y buses sobre el mapa del pasajero (sección 6).
2. Conectar `bus_tracking_screen.dart` a WebSockets (Laravel Reverb + Laravel
   Echo) para las posiciones en tiempo real, y al microservicio de IA para el
   ETA (RF-16).
3. Definir manejo de estado (Provider, Riverpod o Bloc) antes de que crezcan
   las pantallas — con `setState` alcanza solo para esta etapa.
4. Agregar los nuevos microservicios en `ApiConfig` (`trips`, `gps`, `eta`, …)
   reutilizando el mismo `ApiClient`.

## 5. Contrato de `AuthService`

Las pantallas **solo** llaman a estos métodos: las rutas, el parseo JSON:API,
el token y la traducción de errores ya están resueltos. Todo pasa por el API
Gateway (`/auth/*`).

| Método | Endpoint (Gateway) | Devuelve |
|---|---|---|
| `login({email, password})` | `POST /auth/login?include=roles` | `AuthSession` (guarda token + usuario) |
| `registerPassenger({name, email, password, passwordConfirmation})` | `POST /auth/register/passenger?include=roles` | `PendingVerification` (`email`, `message`). **No inicia sesión**: el backend envía un código de 6 dígitos al correo → seguir con `verifyEmail` |
| `verifyEmail({email, code})` | `POST /auth/email/verify?include=roles` | `AuthSession` (guarda token + usuario, igual que `login`) |
| `resendVerificationCode(email)` | `POST /auth/email/resend` | `String`: mensaje del backend (siempre el mismo, exista o no el correo). Máx. 3 por minuto |
| `sendResetCode(email)` | `POST /auth/password/forgot` | `String`: mensaje del backend para mostrar |
| `resetPassword({email, code, password, passwordConfirmation})` | `POST /auth/password/reset` | `String`: mensaje del backend. Cierra la sesión en todos los dispositivos → volver a login |
| `fetchCurrentUser()` | `GET /auth/user?include=roles` | `AuthUser` actualizado (también lo guarda) |
| `updateProfile({name?, email?, currentPassword?})` | `PATCH /auth/user?include=roles` | `ProfileUpdate`. Solo pasajeros; enviar solo lo que cambió (`currentPassword` obligatorio si cambia el correo). Solo nombre → guarda el usuario. Correo → el backend lo deja sin verificar: **borra la sesión local** y `requiresEmailVerification = true` → ir a `/verify-email` (`resendOnOpen: true`). Máx. 5 por minuto |
| `changePassword({currentPassword, password, passwordConfirmation})` | `PUT /auth/user/password` | `String`: mensaje del backend. Solo pasajeros; sigue la sesión en este dispositivo, el backend cierra las demás. Máx. 5 por minuto |
| `restoreSession()` | `GET /auth/user?include=roles` | `AuthUser?`: `null` si no hay sesión, el token venció o el rol no está permitido. Sin red devuelve el usuario guardado |
| `logout()` | `POST /auth/logout` | — Siempre borra la sesión local, aunque falle el servidor |
| `deleteAccount({currentPassword})` | `DELETE /auth/user` (body `current_password`, `confirm_deletion: true`) | `String`: mensaje del backend. Soft delete solo para pasajeros: el backend revoca todos los tokens y la app borra la sesión local. 422 → `fieldErrors['current_password']`; 401 también borra la sesión; 403 si la cuenta no es solo de pasajero o el correo no está verificado |

**Roles permitidos:** solo `passenger` y `driver` (`AuthUser.isAllowedInApp`).
Si `login`, `verifyEmail` o `restoreSession` reciben otro rol
(`super-admin`, `company-admin`), se cierra la sesión en el servidor y se borra
la local.

### Errores (`ApiException`)

Todos los métodos lanzan `ApiException`. `e.message` siempre está en español y
listo para mostrar.

| `e.type` | Cuándo | Qué hacer en la pantalla |
|---|---|---|
| `badCredentials` | `login` con correo o contraseña incorrectos | Mostrar `e.message` |
| `emailNotVerified` | 403 `email_not_verified`: `login` con contraseña correcta pero correo sin verificar | Ofrecer verificar: `resendVerificationCode` + pantalla `/verify-email` (`VerifyEmailArgs(email, resendOnOpen: true)`) |
| `roleNotAllowed` | La cuenta no es de pasajero ni conductor | Mostrar `e.message` ("Esta aplicación es solo para pasajeros y conductores.") |
| `validation` | 422: datos inválidos (`registerPassenger`, `verifyEmail`, `sendResetCode`, `resetPassword`) | Mostrar `e.fieldErrors['email']`, `['password']`, `['name']`, `['code']` debajo de cada campo |
| `badRequest` | 400: código (de recuperación o de verificación) incorrecto, vencido o con demasiados intentos | Mostrar `e.message` (viene del backend) |
| `tooManyRequests` | 429: demasiados intentos (Auth: 5 por minuto en login/forgot/reset) | Pedir que espere |
| `unauthorized` | 401: el token venció | Volver a login |
| `noConnection` / `timeout` | Sin red o la respuesta tardó demasiado | Ofrecer reintentar |
| `serviceUnavailable` / `serverError` / `unknown` | Falla del backend o del Gateway | Mostrar `e.message` |

Ejemplo (registro):

```dart
try {
  final pending = await AuthService().registerPassenger(
    name: name,
    email: email,
    password: password,
    passwordConfirmation: confirmation,
  );
  // Sin sesión todavía: verificar el correo con el código enviado.
  Navigator.pushReplacementNamed(
    context,
    '/verify-email',
    arguments: VerifyEmailArgs(email: pending.email, message: pending.message),
  );
} on ApiException catch (e) {
  if (e.type == ApiErrorType.validation) {
    setState(() {
      emailError = e.fieldErrors['email']?.first;
      passwordError = e.fieldErrors['password']?.first;
    });
  } else {
    showError(e.message);
  }
}
```

## 6. Mapa del pasajero (MapLibre + OpenFreeMap)

`PassengerHomeScreen` muestra un mapa interactivo a pantalla completa, con una
distribución inspirada en Google Maps y la identidad de SmartBus.

| Pieza | Archivo |
|---|---|
| Configuración (estilos, centro por defecto, atribución) | `core/config/map_config.dart` |
| Ubicación del dispositivo (permiso, posición, ajustes) | `core/location/location_service.dart` |
| Mapa nativo (MapLibre) + marcador del usuario | `features/passenger/map/passenger_map.dart` |
| Búsqueda, resultados, accesos rápidos, aviso de ubicación, botones, panel inferior | `features/passenger/map/map_overlay.dart` |

**Proveedores:**

| Modo | Proveedor | Por defecto | Notas |
|---|---|---|---|
| Calles (`MapMode.streets`) | [OpenFreeMap](https://openfreemap.org), estilo Liberty | `https://tiles.openfreemap.org/styles/liberty` | Gratis, sin API key, sin límite de uso, **apto para producción**. Incluye lugares, negocios y zonas |
| Satélite (`MapMode.satellite`) | Esri World Imagery | `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}` | Alta resolución (casas y calles, hasta zoom 19), sin API key. ⚠️ **Solo desarrollo / demo** |

> ⚠️ **Satélite antes de producción:** la imagen de Esri está bajo el *Esri Master
> License Agreement*, que pide una cuenta de ArcGIS para apps en producción.
> Opciones (solo `--dart-define`, sin cambiar código):
> - Crear una cuenta (plan gratis) de ArcGIS Location Platform y usar su URL con token.
> - O usar la capa **gratis y legal para producción** de EOX (Sentinel-2 2016, CC BY 4.0),
>   de menor resolución (se ven barrios, no casas):
>   `--dart-define=MAP_SATELLITE_TILES_URL=https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/g/{z}/{y}/{x}.jpg --dart-define=MAP_SATELLITE_MAX_ZOOM=14 "--dart-define=MAP_SATELLITE_ATTRIBUTION=Sentinel-2 cloudless 2016 por EOX IT Services GmbH"`

- **Diseño:** el mapa es **siempre claro** (Liberty, con lugares y negocios) y
  la barra de búsqueda es **blanca** (`MapOverlayColors.searchBar`); los
  accesos rápidos y los botones de satélite / mi ubicación usan el **verde del
  header de pasajero** (`MapOverlayColors.smartBus`); el panel inferior
  ("Hola, \<nombre\>") es **blanco** (`MapOverlayColors.sheet`). Los botones
  van pegados a la derecha, encima de la línea de la licencia. No cambia si el teléfono está en modo
  claro u oscuro. No se usa el estilo oscuro de
  OpenFreeMap porque no muestra lugares ni negocios.
- **Si se usa EOX para el satélite:** solo sirve la capa de **2016**. Las de 2018
  en adelante prohíben el uso comercial (CC BY-NC-SA) y la de 2017 no tiene
  imagen de Costa Rica a zoom alto.
- **Búsqueda:** "¿A dónde vas?" se escribe en el mismo lugar (sin abrir otra
  pantalla) y por ahora muestra "Búsqueda de rutas: próximamente".

Se pueden cambiar sin tocar código (por ejemplo, otro estilo o un OpenFreeMap
propio, ya que el servicio público no tiene SLA):

```
flutter run \
  --dart-define=MAP_STYLE_URL=https://tiles.openfreemap.org/styles/bright \
  --dart-define=MAP_SATELLITE_TILES_URL=https://.../{z}/{y}/{x}.jpg
```

**Reglas:**
- La atribución (`MapConfig.attributionFor(mode)`) es obligatoria (licencias de
  OpenStreetMap / OpenMapTiles y de EOX, CC BY 4.0). Está **siempre visible**,
  discreta (texto pequeño, sin fondo). **No eliminarla.**
- Sin permiso de ubicación (o con el GPS apagado) el mapa abre en San José y
  muestra un aviso; el botón "mi ubicación" vuelve a pedir el permiso o abre los
  ajustes.
- Para agregar rutas, paradas o buses, usar `PassengerMapHandle` (no depender
  de MapLibre desde la pantalla), así los tests siguen usando un mapa falso.

**Tests:** el mapa nativo no corre en tests de widgets; `PassengerHomeScreen`
recibe un `mapBuilder` y un `LocationService` falsos
(`test/features/passenger/passenger_home_screen_test.dart`). El mapa real se
verifica a mano en un dispositivo.

## 7. Seguimiento del bus en vivo (pasajero)

"Rastreando tu bus" (`passenger/bus_tracking_screen.dart`, ruta
`/passenger/tracking`, argumento obligatorio: el UUID del viaje, que llega desde
"Buses en curso") muestra el bus de
un viaje moviéndose en el mapa, sin recargar.

### Piezas

| Pieza | Archivo |
|---|---|
| Pantalla: mapa, bus, ubicación del pasajero, panel de estado | `features/passenger/bus_tracking_screen.dart` |
| Pin del bus en el mapa (`showBus`, `BusMarker`; ícono dibujado en la app, sin assets) | `features/passenger/map/passenger_map.dart` |
| Lógica: GET + eventos + frescura + reconexión | `features/trip_tracking/services/live_trip_tracker.dart` |
| Canal del viaje (`private-trip.{id}`, evento `BusLocationUpdated`) | `features/trip_tracking/services/trip_live_feed.dart` |
| Cliente WebSocket (protocolo Pusher de Reverb) | `core/realtime/pusher_connection.dart` |
| Modelos: `TripTracking`, `BusPosition`, `BusLocationUpdate`, `TripStatus`, `TrackingFreshness` | `features/trip_tracking/models/trip_tracking.dart` |
| Llamadas HTTP (`latestForTrip`, `authorizeChannel`) | `features/trip_tracking/services/gps_location_service.dart` |

### Cómo funciona

```
abrir "Rastreando tu bus"
  → GET  /gps/trips/{id}/location             estado del viaje + posición actual
  → WebSocket a Reverb (wss://<gateway>/app/<KEY>)
  → POST /gps/broadcasting/auth               el Gateway valida el token y firma
  → suscribe private-trip.{id}
  → cada BusLocationUpdated: mueve el bus (solo si es más nuevo que el actual)
  → 15 s sin posiciones: repite el GET  →  status completed / cancelled = fin
  → se cae la conexión: reconecta sola y repite el GET
  → salir de la pantalla: cierra la conexión
```

1. **Al abrir**, `GET /gps/trips/{id}/location` trae el estado del viaje y la
   última posición, para mostrar el bus antes del primer evento.
2. **En vivo:** cada `BusLocationUpdated` mueve el marcador. Los eventos pueden
   llegar desordenados en redes móviles: se queda siempre la posición con el
   **mayor `recorded_at`** y se ignoran las viejas o repetidas.
3. **Viaje terminado (regla de los 15 s):** el conductor envía su posición cada
   ~5 s, así que **15 s sin posiciones** ya es raro. Entonces la app repite el
   `GET`: si `status` es `completed` o `cancelled`, muestra "Viaje finalizado" /
   "Viaje cancelado" y sale del canal. Así el fin del viaje se ve en
   **~15–20 s**, sin que el Dashboard tenga que avisar nada. Si el bus solo está
   sin señal (un túnel), se pregunta **como máximo cada 15 s**. Mientras las
   posiciones llegan normalmente **no se hace ninguna consulta**.
4. **Reconexión:** si se cae el WebSocket, reconecta solo (espera 1, 2, 5, 10 y
   30 s entre intentos) y al volver repite el `GET`, porque **Reverb no guarda
   historial**: lo enviado mientras estaba desconectado se perdió.
5. **Sin tiempo real** (sin `REVERB_APP_KEY` o sin conexión al WebSocket): la
   pantalla igual funciona consultando la posición cada 15 s.

La frescura se calcula con el **reloj de este teléfono** (desde que se recibió
la posición), no con el `recorded_at` del teléfono del conductor, que puede
tener la hora desfasada. `recorded_at` solo se usa para ordenar.

### Qué ve el pasajero

| Estado | Texto | Marcador |
|---|---|---|
| Cargando | "Buscando tu bus…" | — |
| Viaje programado | "El viaje aún no inicia" | — |
| En curso, sin ninguna posición todavía | "Esperando la ubicación del bus" | — |
| Posición de los últimos 30 s | "En vivo · Actualizado hace 4 s · 38 km/h" | verde |
| Posición de hace 30 s – 5 min | "Señal débil · Última ubicación hace 2 min" | gris |
| Posición de hace más de 5 min | "Sin señal del bus" | gris |
| Terminado / cancelado | "Viaje finalizado" / "Viaje cancelado" | — |
| No existe (404) | "No encontramos este viaje" | — |

**En el mapa:** el bus es un **pin con ícono de bus** (verde en vivo, gris con
señal débil o sin señal) cuya **punta** marca su posición. El pasajero se ve
como su **punto verde con halo de precisión**, igual que en el inicio. Si están
en el mismo lugar, el punto queda justo en la punta del pin: se distinguen los
dos. La ubicación del pasajero solo se muestra si ya dio el permiso (lo pide el
inicio); esta pantalla no lo vuelve a pedir y sin él muestra solo el bus.
| Falla la primera carga | "No se pudo cargar el viaje" + **Reintentar** | — |
| Sin tiempo real | aviso "Conectando en tiempo real…" | (se actualiza cada 15 s) |

Los umbrales de 30 s y 5 min son los mismos del servicio GPS
(`TrackingFreshness.liveSeconds` / `staleSeconds`).

### Por qué WebSocket

- **El bus se mueve solo:** con HTTP la app tendría que preguntar una y otra vez
  "¿dónde está el bus?". Con el WebSocket la conexión queda abierta y el
  servidor **empuja** cada posición apenas el conductor la envía.
- **Costo:** 100 pasajeros preguntando cada 5 s serían 1 200 peticiones por
  minuto al Gateway, al GPS y a la base de datos (el Gateway limita a 60 por
  minuto y Render gratis no aguanta eso). Con WebSocket cada posición se envía
  **una vez** y Reverb la reparte a todos.
- **Seguridad:** el canal es **privado**. Para suscribirse, la app pide la firma
  a `POST /gps/broadcasting/auth` por el Gateway, que valida el token. El GPS
  solo autoriza viajes programados o en curso.
- **Por qué también el `GET`:** Reverb no guarda historial. El `GET` cubre la
  posición inicial, lo perdido al reconectar y la detección del fin del viaje.

### Por qué un cliente WebSocket propio

Reverb (Laravel) habla el **protocolo de Pusher**. El paquete
`pusher_channels_flutter` está hecho para el servicio comercial de Pusher y no
permite apuntar a un servidor propio como Reverb. El protocolo es chico
(conectar, autorizar el canal, suscribirse, responder `ping`, reconectar), así
que `PusherConnection` lo implementa con el `WebSocket` que ya trae Dart
(`dart:io`), **sin paquetes nuevos**.

### Por qué el Dashboard no avisa "viaje terminado"

El Dashboard es el dueño de `trips` y es quien inicia y termina el viaje. Se
evaluó que emitiera un evento `TripTrackingEnded` por el WebSocket, pero se
**descartó**: obligaba al Dashboard a conectarse al Reverb del GPS y compartir
sus credenciales. La regla de los 15 s da el mismo resultado (con ~15–20 s de
demora) sin tocar el Dashboard ni el GPS.

- **Inicio del viaje:** no necesita aviso. La primera posición que llega por el
  canal ya pasa la pantalla de "El viaje aún no inicia" a "En vivo".
- **Si algún día se necesita el aviso instantáneo:** que la app del conductor,
  después de terminar el viaje en el Dashboard, llame a un endpoint del GPS que
  verifique en la base que el viaje terminó y emita el evento. La pantalla del
  pasajero ya sabe reaccionar a un viaje terminado.

### Configuración

`REVERB_APP_KEY`, `REVERB_HOST`, `REVERB_PORT` y `REVERB_SCHEME` (ver la
tabla de `--dart-define` y la sección 5.7 del
[README raíz](../README.md)). En Render solo hace falta `REVERB_APP_KEY`, y la
de -dev ya es el valor por defecto (`ApiConfig._devReverbAppKey`).

### Tests

| Qué | Archivo |
|---|---|
| Protocolo Pusher: suscripción firmada, eventos, ping, reconexión, error 4001 | `test/core/realtime/pusher_connection_test.dart` |
| Tracker: orden de eventos, frescura, regla de 15 s, reconexión, sin tiempo real, 404 | `test/features/trip_tracking/live_trip_tracker_test.dart` |
| Lectura de `trip-trackings` y de `BusLocationUpdated` | `test/features/trip_tracking/trip_tracking_test.dart` |
| Pantalla: cada estado y el marcador | `test/features/passenger/bus_tracking_screen_test.dart` |

## 8. Envío de GPS del conductor (Recorrido)

`TripLocationSender` envía la posición cada `GPS_INTERVAL_SECONDS` (5 s) con
`latitude`, `longitude`, `speed_kmh`, `accuracy_meters` (precisión del GPS del
teléfono, si la reporta) y `recorded_at`.

| Respuesta del GPS | Qué hace la app |
|---|---|
| `201` guardada / `202` (`broadcast_only`, `duplicate`, `stale`) | Cuenta como enviada |
| Sin red, timeout, 5xx, 429 | La deja en cola y reintenta en el siguiente envío |
| `409` el viaje no está en curso | **Deja de enviar**: "El viaje no está en curso: todavía no se ha iniciado o ya terminó." |
| `403` no es el conductor asignado | **Deja de enviar**: "No eres el conductor asignado a este viaje." |
| `404` el viaje no existe | **Deja de enviar**: "No se encontró el viaje." |
| `401` sesión vencida | **Deja de enviar**: "Tu sesión expiró. Inicia sesión nuevamente." |
| Otro 4xx (datos inválidos) | Descarta esa lectura y sigue |

En los casos que **dejan de enviar**, reintentar cada 5 s no sirve de nada: la
pantalla muestra el motivo (`TripTrackingState.rejected`) y un botón
**Reintentar** para cuando se corrija.

"Iniciar recorrido" primero inicia el viaje en el Dashboard y "Finalizar
recorrido" lo completa (sección 9), así el GPS ya no responde `409` por un
viaje sin iniciar.

Tests: `test/features/trip_tracking/trip_location_sender_test.dart`.

## 9. Viajes reales del Dashboard (`ops`)

La app llega al Dashboard por el Gateway con el prefijo **`ops`**
(`ApiConfig.opsBaseUrl`, `--dart-define=OPS_GATEWAY_URL=...`; por defecto el
mismo Gateway). Todo pasa por `OperationsService`
(`features/operations/services/operations_service.dart`); los modelos están en
`features/operations/models/operations_models.dart`.

| Método | Endpoint (Gateway) | Token | Quién |
|---|---|---|---|
| `driverTrips({serviceDate, status})` | `GET ops/driver/trips` | Sí | Conductor |
| `startTrip(id)` | `POST ops/trips/{id}/start` | Sí | Conductor asignado |
| `completeTrip(id)` | `POST ops/trips/{id}/complete` | Sí | Conductor asignado |
| `routes()` | `GET ops/routes` | No | Pasajero |
| `routesWithPatterns()` | `GET ops/routes?include=patterns` (rutas + sentidos + paradas en **una** petición; ver §10) | No | Pasajero |
| `routePatterns(routeId)` | `GET ops/routes/{id}/patterns` (trazo + paradas) | No | Pasajero |
| `ongoingTrips(patternId)` | `GET ops/route-patterns/{id}/trips` (solo `in_progress`, sin datos del conductor) | No | Pasajero |

### Conductor

1. **Inicio** muestra los viajes de hoy (ruta, destino, horas, estado) y,
   arriba, cualquier viaje de otro día que siga **en curso** (cruzó la
   medianoche o nadie lo finalizó). Los viajes son **diarios**: el Dashboard
   crea uno por fecha a partir de los horarios fijos.
2. **Iniciar recorrido** (viaje `scheduled`): `startTrip` → el viaje queda
   `in_progress` → empieza el envío de GPS. Si el Dashboard lo rechaza (409:
   aún no es hora, otro viaje en curso…), se muestra el mensaje y no se envía nada.
3. **Continuar recorrido** (viaje ya `in_progress`, p. ej. se cerró la app):
   solo reanuda el GPS. La pestaña **Recorrido** sin viaje busca el que está en
   curso.
4. **Finalizar recorrido**: detiene el GPS y llama `completeTrip`. Si falla,
   ofrece **Reintentar** (el GPS ya está detenido).

### Pasajero

Chip **"Buses en curso"** → lista de rutas → la ruta muestra cada recorrido
(sentido) con:
- sus **buses en curso** (unidad, placa, hora de salida) → **Ver en vivo** abre
  "Rastreando tu bus" con ese viaje;
- **Ver ruta**: vuelve al mapa del inicio con esa ruta y ese sentido dibujados
  (§10);
- **Ver paradas**: las paradas en orden con los minutos desde el inicio, aunque
  no haya buses en camino.

Un viaje terminado desaparece de la lista (el Dashboard solo devuelve los
`in_progress`).

### Tests

| Qué | Archivo |
|---|---|
| URLs, filtros y lectura JSON:API (trazo `[lng, lat]`, paradas ordenadas, snapshot) | `test/features/operations/operations_service_test.dart` |
| Inicio del conductor y Recorrido: iniciar, continuar, rechazo, finalizar, reintentar | `test/features/driver/trip_screen_test.dart` |
| Buses en curso: ruta → buses → en vivo, sin buses, ver paradas, ver ruta en el mapa, reintentar | `test/features/passenger/buses_in_progress_screen_test.dart` |

## 10. Rutas en el mapa del pasajero

El panel inferior del inicio lista las **rutas cercanas** y, al elegir una,
dibuja su recorrido y sus paradas sobre el mapa.

### Piezas

| Pieza | Archivo |
|---|---|
| Rutas + sentidos + paradas (una petición) | `OperationsService.routesWithPatterns()` |
| Filtro de cercanía (Dart puro, haversine) | `features/operations/services/nearby_routes_filter.dart` |
| Lista de rutas y panel de la ruta elegida | `features/passenger/map/route_sheet.dart` |
| Dibujo en el mapa (`showRoute`, `clearRoute`, `fitBounds`, `onStopTap`) | `features/passenger/map/passenger_map.dart` |

### Datos

`GET ops/routes?include=patterns&page[size]=100` devuelve las rutas en `data`
y sus sentidos (`route-patterns`) en `included`. Cada ruta los enlaza en
`relationships.patterns.data`; si una ruta no trae esa relación, se usa el
`route_id` del patrón. Se ignoran otros tipos de `included` (p. ej. `companies`).

- `route_geometry` (GeoJSON `LineString`, `[lng, lat]`) **puede ser `null`**: hoy
  en -dev solo DEMO-CITY tiene trazo. Sin trazo, la línea une las paradas en
  orden (`RoutePattern.path`); se dibuja igual (línea continua) y el panel
  avisa "Trazado aproximado".
- Una ruta tiene **varios sentidos**. Si dos van al mismo `headsign` (SJ-PV va
  tres veces a "San José"), la etiqueta agrega la variante del nombre:
  "Hacia San José por Vara Blanca" (`TransitRoute.directionLabel`).

### Qué ve el pasajero

| Situación | Lista |
|---|---|
| Con ubicación | **Rutas cercanas**: rutas con al menos una parada a ≤ **1000 m** (`NearbyRoutesFilter.defaultRadiusMeters`), de la más cercana a la más lejana. Cada fila: código, nombre, "Hacia {destino}" y "{parada más cercana} · 230 m" |
| Ninguna cerca | "No hay rutas cerca de ti" + **Ver todas las rutas** |
| Sin permiso / GPS apagado | **Todas las rutas**, sin distancia; se pueden elegir igual |
| Cargando / error | "Buscando rutas…" / mensaje + **Reintentar** |

Al elegir una ruta:
1. Se dibuja el sentido con la parada más cercana al pasajero (sin ubicación:
   el primero). Línea continua con **degradado** de turquesa (salida,
   `verdeTurquesa`) a azul (llegada, `azulPrincipal`), con halo, borde blanco
   y **flechas** en el sentido del recorrido. Salida y llegada son círculos
   rellenos grandes; las paradas intermedias, blancas y numeradas. La parada
   elegida lleva un halo.
2. La cámara encuadra todo el sentido (y al pasajero, si está a ≤ 1000 m de
   alguna parada), dejando libre la barra de búsqueda y el panel.
3. El panel baja (32 % de la pantalla) y muestra: nombre, **un chip por
   sentido**, "N paradas · distancia · ~min" y, sin trazo, "Trazado
   aproximado".
4. **Paradas (N)**: todas las paradas del sentido como línea de tiempo
   (Salida → … → Llegada, con "+12 min"). Tocar una en la lista o en el mapa la
   resalta y muestra "Parada 2 de 5" y los minutos desde el inicio; desde la
   lista, además, el mapa se centra en ella.
5. Cambiar de sentido, cerrar (✕) o el botón atrás de Android borran el dibujo
   anterior.

### Buses en vivo sobre la ruta

Con una ruta elegida, el mapa muestra también los **buses que van en ese
sentido ahora** (el conductor tocó "Iniciar recorrido"), moviéndose en tiempo
real, y el panel los lista en "Buses en vivo".

- `RouteLiveBuses` (`features/trip_tracking/services/route_live_buses.dart`):
  pide `GET ops/route-patterns/{id}/trips` (solo `in_progress`) y crea un
  `LiveTripTracker` por viaje, el mismo de "Rastreando tu bus" (GET +
  `BusLocationUpdated`). Cada **30 s** vuelve a preguntar al Dashboard: aparecen
  los viajes nuevos y se quitan los que ya no corren. Un viaje que el GPS da por
  terminado desaparece en el momento.
- Mapa: un pin por bus (`PassengerMapHandle.showBuses`), verde si la posición
  es reciente (≤ 30 s) y gris si es vieja (señal débil). Tocar el pin o
  **Ver en vivo** abre "Rastreando tu bus".
- Panel: "Unidad 12 · ABC-123" + "En vivo · hace 5 s" / "Señal débil · hace
  2 min" / "Esperando ubicación". Sin buses: "No hay buses en curso en este
  sentido."
- Cambiar de sentido sigue a los buses del nuevo sentido; cerrar la ruta los
  quita y corta sus conexiones.
- **Tiempo real:** igual que "Rastreando tu bus", usa `REVERB_APP_KEY` (por
  defecto la de -dev en Render). Sin key funciona preguntando cada 15 s. Cada
  bus abre su propia conexión (son pocos por sentido).

**Desde "Buses en curso" → Ver ruta:** las dos pantallas se cierran con un
`RouteSelection` y el inicio dibuja esa ruta con ese sentido.

### Por qué el filtro corre en el teléfono

Una sola petición trae todas las rutas, sentidos y paradas, y alcanza para un
catálogo pequeño o mediano. Si crece, el Dashboard ya filtra por distancia
(`GET ops/stops?filter[near]=lat,lng,radius_m`, máx. 2000 m): solo cambiarían
`OperationsService` y la entrada de `NearbyRoutesFilter`; la lista y el mapa
quedan igual.

### Detalles del mapa

- Las capas de la ruta se agregan **antes** que las del usuario y el bus, así
  el punto del pasajero queda encima de la línea.
- Los números de parada usan las fuentes de OpenFreeMap
  (`MapConfig.glyphsUrl`, `Noto Sans Bold`); el estilo satélite también las
  declara, porque sin `glyphs` MapLibre no dibuja texto.
- Al cambiar calles ↔ satélite se vuelve a dibujar la ruta elegida.

### Tests

| Qué | Archivo |
|---|---|
| Filtro: dentro, fuera, justo en el radio, orden, lista vacía, varios sentidos, paradas sin coordenadas | `test/features/operations/nearby_routes_filter_test.dart` |
| `include=patterns`: enlace por relación y por `route_id`, con y sin trazo, `directionLabel` | `test/features/operations/operations_service_test.dart` |
| GeoJSON dibujado: línea real / aproximada, ids, números y tipo de parada (salida, intermedia, llegada), parada resaltada | `test/features/passenger/route_features_test.dart` |
| AC1–AC9 con mapa falso y `FakeOperations` | `test/features/passenger/passenger_home_screen_test.dart` (grupo *Route visualization*) |
| Buses en vivo: un tracker por viaje, altas / bajas al refrescar, viaje terminado, error, dispose | `test/features/trip_tracking/route_live_buses_test.dart` |
| Buses en vivo en el inicio: pines, lista, cambio de sentido, cerrar, abrir seguimiento, señal débil | `test/features/passenger/passenger_home_screen_test.dart` (grupo *Live buses on the route*) |
