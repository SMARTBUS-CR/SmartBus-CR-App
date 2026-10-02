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
| `passenger/passenger_home_screen.dart` | RF-08 (mapa principal), RF-09 (búsqueda) |
| `passenger/route_search_screen.dart` | RF-09 |
| `passenger/passenger_account_screen.dart` | Perfil del pasajero ("Mi Cuenta"): datos guardados al instante + refresco con `fetchCurrentUser()`; 401 → login; sin red → "Reintentar" |
| `passenger/bus_tracking_screen.dart` | RF-10 (ubicación en vivo), RF-11 (ETA), RF-12 (alertas) |
| `driver/driver_home_screen.dart` | RF-13 (ruta asignada del día) |
| `driver/driver_account_screen.dart` | Perfil del conductor ("Mi Cuenta"), solo lectura: aviso "contacta al administrador"; misma carga/401/"Reintentar" que el pasajero |
| `widgets/profile_details.dart` | Vista de perfil compartida (pasajero y conductor): datos guardados + `fetchCurrentUser()`, 401 → login, "Reintentar" |
| `widgets/smartbus_header.dart` | Header de todas las pantallas internas: degradado del tema por rol (`SmartBusUserType`), ola, ruta, pin y bus dibujados en código; variante `compact` para pantallas con mapa |
| `driver/trip_screen.dart` | RF-14 (inicio/fin de recorrido), RF-15 (envío GPS) |

## 3. Qué es placeholder vs. qué ya está "conectable"
- **Placeholder puro** (solo UI, sin lógica): mapas (`Container` gris),
  listas de rutas, ETA fijo, estado del bus.
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
1. Sustituir los `Container` grises por `flutter_map` + tiles de OpenStreetMap
   (paquete `flutter_map` + `latlong2`), como está definido en el documento
   de arquitectura (OSM + OpenRouteService).
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
| `registerPassenger({name, email, password, passwordConfirmation})` | `POST /auth/register/passenger?include=roles` | `AuthSession` con rol `passenger` (queda con la sesión iniciada) |
| `sendResetCode(email)` | `POST /auth/password/forgot` | `String`: mensaje del backend para mostrar |
| `resetPassword({email, code, password, passwordConfirmation})` | `POST /auth/password/reset` | `String`: mensaje del backend. Cierra la sesión en todos los dispositivos → volver a login |
| `fetchCurrentUser()` | `GET /auth/user?include=roles` | `AuthUser` actualizado (también lo guarda) |
| `restoreSession()` | `GET /auth/user?include=roles` | `AuthUser?`: `null` si no hay sesión, el token venció o el rol no está permitido. Sin red devuelve el usuario guardado |
| `logout()` | `POST /auth/logout` | — Siempre borra la sesión local, aunque falle el servidor |

**Roles permitidos:** solo `passenger` y `driver` (`AuthUser.isAllowedInApp`).
Si `login`, `registerPassenger` o `restoreSession` reciben otro rol
(`super-admin`, `company-admin`), se cierra la sesión en el servidor y se borra
la local.

### Errores (`ApiException`)

Todos los métodos lanzan `ApiException`. `e.message` siempre está en español y
listo para mostrar.

| `e.type` | Cuándo | Qué hacer en la pantalla |
|---|---|---|
| `badCredentials` | `login` con correo o contraseña incorrectos | Mostrar `e.message` |
| `roleNotAllowed` | La cuenta no es de pasajero ni conductor | Mostrar `e.message` ("Esta aplicación es solo para pasajeros y conductores.") |
| `validation` | 422: datos inválidos (`registerPassenger`, `sendResetCode`, `resetPassword`) | Mostrar `e.fieldErrors['email']`, `['password']`, `['name']`, `['code']` debajo de cada campo |
| `badRequest` | 400: código de recuperación incorrecto o vencido | Mostrar `e.message` (viene del backend) |
| `tooManyRequests` | 429: demasiados intentos (Auth: 5 por minuto en login/forgot/reset) | Pedir que espere |
| `unauthorized` | 401: el token venció | Volver a login |
| `noConnection` / `timeout` | Sin red o la respuesta tardó demasiado | Ofrecer reintentar |
| `serviceUnavailable` / `serverError` / `unknown` | Falla del backend o del Gateway | Mostrar `e.message` |

Ejemplo (registro):

```dart
try {
  final session = await AuthService().registerPassenger(
    name: name,
    email: email,
    password: password,
    passwordConfirmation: confirmation,
  );
  Navigator.pushReplacementNamed(context, homeRouteForUser(session.user)!);
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
