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
| `driver/trip_screen.dart` | RF-14 (inicio/fin de recorrido), RF-15 (envío GPS) |

## 3. Qué es placeholder vs. qué ya está "conectable"
- **Placeholder puro** (solo UI, sin lógica): mapa de seguimiento del bus
  (`Container` gris), listas de rutas, ETA fijo, estado del bus.
- **Mapa del pasajero (real):** inicio del pasajero con MapLibre + OpenFreeMap
  (ver la sección 6).
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
