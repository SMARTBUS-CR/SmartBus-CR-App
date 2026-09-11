# SmartBus – App  (Flutter)

App móvil de SmartBus. Cubre login (contra el API Gateway) y el
envío de la ubicación GPS del autobús durante un recorrido (issue-4).

- **Paquete:** `smartbus_drivers` · applicationId `com.example.smartbus_drivers`
- **Plataformas:** Android (principal) e iOS
- **Backend:** la app **solo** habla con el API Gateway. Ver
  [`lib/core/config/api_config.dart`](lib/core/config/api_config.dart).

---

## 1. Qué instalar 

> Probado en Windows 11. En macOS/Linux los pasos son equivalentes.

| Herramienta | Versión | Notas |
|---|---|---|
| **Git** | cualquiera reciente | |
| **Flutter SDK** | stable reciente (probado con **3.47**, Dart **3.13+**) | Incluye Dart. `pubspec.yaml` pide `sdk: ^3.13.1` |
| **JDK** | **17** (Temurin/OpenJDK) | El build de Android usa Java 17 (`build.gradle.kts`) |
| **Android SDK** | ver abajo | Se puede instalar con Android Studio o solo con `cmdline-tools` |
| **VS Code** o **Android Studio** | — | Editor + debugger. VS Code: extensiones *Flutter* y *Dart* |

### 1.1 Flutter

1. Descarga Flutter stable de <https://docs.flutter.dev/get-started/install> y
   descomprímelo en una ruta **sin espacios** (en esta máquina está en `C:\flutter`).
2. Agrega `C:\flutter\bin` al `PATH`.
3. Verifica: `flutter --version`

### 1.2 JDK 17

- Instala Temurin 17 (<https://adoptium.net>) y asegúrate de que `java -version`
  diga `17.x`.
- Si tienes varias versiones de Java, apunta Flutter a la 17:
  `flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-17..."`

### 1.3 Android SDK

Con **Android Studio**: instala y en *More Actions → SDK Manager* marca:

- **SDK Platforms:** Android 34, 35 y 36 (SDK Platform)
- **SDK Tools:**
  - Android SDK Build-Tools (34 y la última)
  - Android SDK Command-line Tools (latest)
  - Android SDK Platform-Tools
  - NDK (Side by side) — la versión que pida Flutter
  - CMake

Sin Android Studio (solo línea de comandos):

```powershell
# Descarga "Command line tools only" y colócalo en:
#   %LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest\
$sdk = "$env:LOCALAPPDATA\Android\Sdk"
& "$sdk\cmdline-tools\latest\bin\sdkmanager.bat" `
  "platform-tools" `
  "platforms;android-34" "platforms;android-35" "platforms;android-36" `
  "build-tools;34.0.0" "build-tools;36.0.0" `
  "ndk;28.2.13676358" "cmake;3.22.1"
& "$sdk\cmdline-tools\latest\bin\sdkmanager.bat" --licenses
```

> **`android-34` es obligatorio** aunque la app compile contra un SDK más nuevo:
> `flutter_secure_storage` 9.x lo requiere.

### 1.4 Verificar todo

```powershell
flutter doctor
flutter doctor --android-licenses   # acepta todas
```

Debe salir ✓ en *Flutter*, *Android toolchain* y el editor. (iOS/Xcode solo en Mac.)

---

## 2. Preparar el proyecto

```powershell
git clone <URL-del-repo> "SmartBus-CR-App"
cd "SmartBus-CR-App"
flutter pub get
```

`android/local.properties` se genera solo en el primer build (rutas del SDK de
tu máquina, **no** se versiona).

---

## 3. Correr la app

### 3.1 Dispositivo físico (recomendado para GPS)

1. En el teléfono: **Ajustes → Acerca del teléfono** → toca 7 veces "Número de
   compilación" → activa **Opciones de desarrollador**.
2. **Opciones de desarrollador** → activa **Depuración por USB** (y
   **"Permanecer activo"** para que no se corte la sesión de debug).
3. Conecta por USB y acepta el diálogo **"¿Permitir depuración USB?"**.
4. Verifica:
   ```powershell
   flutter devices
   ```

### 3.2 Emulador Android

Android Studio → *Device Manager* → crea un dispositivo (API 34+), arráncalo, y
`flutter devices` debe listarlo.

### 3.3 Ejecutar

```powershell
# Usa el Gateway de desarrollo (Render) para TODO (auth + GPS).
flutter run

# Elegir dispositivo si hay varios:
flutter run -d <id-de-flutter-devices>
```

Por defecto la app apunta a `https://smartbus-api-gateway-dev.onrender.com/api`
(definido en `ApiConfig.gatewayBaseUrl`).

> ⚠️ El servicio **GPS todavía no está desplegado** en Render. Con `flutter run`
> a secas, el login funciona pero el envío de GPS dará 404 / "no encontrado".
> Para probar GPS necesitas backend local — ver sección 5.

### 3.4 Parámetros `--dart-define`

| Define | Default | Para qué |
|---|---|---|
| `API_GATEWAY_URL` | `…-gateway-dev.onrender.com/api` | Base del Gateway (auth y todo lo demás) |
| `GPS_GATEWAY_URL` | = `API_GATEWAY_URL` | Base **solo** para los endpoints de GPS/recorrido |
| `GPS_INTERVAL_SECONDS` | `5` | Cada cuántos segundos se envía la posición |
| `API_LANGUAGE` | `es` | Header `Accept-Language` (`en` \| `es`) |

Ejemplo:
```powershell
flutter run -d android `
  --dart-define=GPS_GATEWAY_URL=http://localhost:8001/api `
  --dart-define=GPS_INTERVAL_SECONDS=20
```

### 3.5 Configuraciones de VS Code

`.vscode/launch.json` ya trae varias (Run → *Start Debugging*):

- **SmartBus (dev - Render)** — todo contra Render.
- **SmartBus (auth Render + GPS local via adb reverse)** — auth en Render, GPS a
  `localhost:8001` (requiere `adb reverse`, ver 5.3).
- **SmartBus (auth Render + GPS local via LAN IP)** — igual pero por IP de red.
- **SmartBus (local - Android emulator / iOS simulator)** — todo local.

---

## 4. Compilar APK

```powershell
flutter build apk --debug       # build\app\outputs\flutter-apk\app-debug.apk
flutter build apk --release     # firma con la debug key por ahora
```

Solo los builds **debug/profile** permiten HTTP en claro (para el backend local);
release es HTTPS-only.

---

## 5. Backend local para probar el GPS (issue-4)

Mientras el microservicio GPS no esté en Render, se corre local. Son 3 repos
hermanos en `C:\Proyectos 2026\`:

| Repo | Rol | Cómo se usa aquí |
|---|---|---|
| `smartbus-authentication` | Servicio de auth | **No hace falta local** — se usa el de Render (`-dev`) |
| `smartbus-api-gateway` | API Gateway | Local en **`:8001`** |
| `smartbus-gps-tracking` | Servicio GPS | Local en **`:8000`** |

Cada repo es Laravel: `composer install`, copiar `.env.example` a `.env`,
`php artisan key:generate`, `php artisan migrate`.

### 5.1 `.env` del Gateway (`smartbus-api-gateway`)

```env
APP_URL=http://localhost:8001
AUTH_SERVICE_URL='https://smartbus-authentication-dev.onrender.com'   # auth remoto
GPS_SERVICE_URL='http://localhost:8000'                               # GPS local (¡puerto 8000!)
```

> Error común: dejar `GPS_SERVICE_URL` apuntando a `:8001` (el propio Gateway) →
> `php artisan serve` es de un solo hilo y se llama a sí mismo → *"Maximum
> execution time of 30 seconds exceeded"* y la app acumula "pendientes".

Tras cambiar el `.env`: `php artisan config:clear`.

### 5.2 Levantar los servicios

```powershell
# Terminal 1 — servicio GPS
cd "smartbus-gps-tracking"
php artisan serve --port=8000

# Terminal 2 — Gateway
cd "smartbus-api-gateway"
php artisan config:clear
php artisan serve --port=8001
```

### 5.3 Conectar el teléfono al Gateway local (USB)

`adb reverse` hace que `localhost:8001` del teléfono llegue a tu PC:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:8001 tcp:8001
```

> Se borra al desconectar el USB — vuelve a correrlo si reconectas.

### 5.4 Correr la app apuntando GPS al Gateway local

```powershell
flutter run -d <id> --dart-define=GPS_GATEWAY_URL=http://localhost:8001/api
```

Luego: **Iniciar recorrido** → aceptar permiso de ubicación (**"Permitir todo el
tiempo"** para que siga enviando con la pantalla bloqueada).

### 5.5 Emulador en vez de teléfono

El emulador ve la PC como `10.0.2.2`:
```powershell
flutter run -d emulator-5554 --dart-define=GPS_GATEWAY_URL=http://10.0.2.2:8001/api
```

---

## 6. Solución de problemas

| Síntoma | Causa / arreglo |
|---|---|
| `flutter devices`: *"Device … is not authorized"* | Acepta el diálogo de depuración USB en el teléfono. Si no aparece: Opciones de desarrollador → *Revocar autorizaciones de depuración USB* y reconecta. |
| `flutter run` termina con **"Lost connection to device"** (pero la app sigue abierta) | Gestión de batería del teléfono corta el VM Service. Ajustes → Apps → SmartBus → Batería → **Sin restricciones**; y Opciones de desarrollador → **Permanecer activo**. La app instalada funciona igual abriéndola desde su ícono. |
| Build Android falla por `compileSdk` / `flutter_secure_storage` | Instala `platforms;android-34` en el SDK Manager. |
| Build falla con error de Java / `jvmTarget` | Usa **JDK 17** (`java -version`), no 21 ni 11. |
| Pantalla Recorrido: *"No se encontró el recurso solicitado"* (404) | El GPS va al Gateway equivocado (uno sin `/gps`). Pasa `--dart-define=GPS_GATEWAY_URL=` al Gateway local. |
| Pantalla Recorrido: *"Sin conexión estable"* y "Pendientes" sube | El Gateway local no responde o tarda demasiado. Revisa `GPS_SERVICE_URL` en su `.env` (debe ser `:8000`), que ambos `php artisan serve` estén arriba, y `adb reverse`. |
| HTTP local no conecta en release | Los builds release son HTTPS-only por diseño; usa `--debug`. |

---

## 7. Estructura

```
lib/
├─ core/
│  ├─ config/api_config.dart      # URLs del Gateway + dart-defines
│  ├─ network/                    # ApiClient (token Bearer, ApiException)
│  └─ storage/                    # token/usuario en flutter_secure_storage
├─ features/
│  ├─ auth/                       # login, splash, sesión, roles
│  ├─ driver/                     # Inicio, Mis rutas, Recorrido, Mi cuenta
│  ├─ passenger/                  # flujo del pasajero (placeholders)
│  └─ trip_tracking/              # issue-4: GpsFix, TripLocationSender, GpsLocationService
└─ widgets/                       # nav bars, botones, placeholders
```

Ver [`lib/README.md`](lib/README.md) para el detalle de qué pantalla cubre cada
requerimiento (RF) y qué está conectado vs. placeholder.
