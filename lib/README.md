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
| `passenger/passenger_home_screen.dart` | RF-08 (mapa principal), RF-09 (búsqueda) |
| `passenger/route_search_screen.dart` | RF-09 |
| `passenger/bus_tracking_screen.dart` | RF-10 (ubicación en vivo), RF-11 (ETA), RF-12 (alertas) |
| `driver/driver_home_screen.dart` | RF-13 (ruta asignada del día) |
| `driver/trip_screen.dart` | RF-14 (inicio/fin de recorrido), RF-15 (envío GPS) |

## 3. Qué es placeholder vs. qué ya está "conectable"
- **Placeholder puro** (solo UI, sin lógica): mapas (`Container` gris),
  listas de rutas, ETA fijo, estado del bus.
- **Ya alineado al contrato real**: `models/user.dart` y `core/api_client.dart`
  reflejan exactamente el JSON de tu `SmartBus Authentication API`
  (`/login`, `/register/passenger`, `/user`, `/logout`). Cuando quieran
  conectar el login de verdad, solo hay que llamar `AuthApi().login(...)`
  desde `login_screen.dart` y redirigir según `AppUser.isDriver` /
  `isPassenger` (usando el arreglo `roles` que devuelve el backend), en vez
  del selector temporal `_DevRole`.

## 4. Siguientes pasos sugeridos
1. Borrar el selector temporal `_DevRole` / `_buildDevRoleToggle` de
   `login_screen.dart` una vez el login real decida el rol.
2. Sustituir los `Container` grises por `flutter_map` + tiles de OpenStreetMap
   (paquete `flutter_map` + `latlong2`), como está definido en el documento
   de arquitectura (OSM + OpenRouteService).
3. Conectar `bus_tracking_screen.dart` a WebSockets (Laravel Reverb + Laravel
   Echo) para las posiciones en tiempo real, y al microservicio de IA para el
   ETA (RF-16).
4. Definir manejo de estado (Provider, Riverpod o Bloc) antes de que crezcan
   las pantallas — con `setState` alcanza solo para esta etapa de mockups.
5. Mover `ApiConfig.baseUrl` a `--dart-define` para separar ambientes
   dev/staging/producción.
