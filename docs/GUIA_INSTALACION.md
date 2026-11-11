# SmartBus App (Flutter): guía de instalación

Pasos para instalar y  correr la app en **Windows**. En macOS y Linux los pasos son equivalentes.

> Al terminar los pasos 1 a 5 se puede **iniciar sesión, registrarse como pasajero y ver el mapa**. El paso 6 solo hace falta para probar el GPS y el bus en vivo.

---

## 1. Instalar las herramientas

| # | Herramienta | Versión | Descarga |
|---|---|---|---|
| 1 | **Git** | cualquiera reciente | <https://git-scm.com> |
| 2 | **Flutter SDK** | stable **3.47+** (trae Dart 3.13+) | <https://docs.flutter.dev/get-started/install> |
| 3 | **JDK** | **17** exacto (no 21 ni 11) | <https://adoptium.net> (Temurin 17) |
| 4 | **Android Studio** | reciente | <https://developer.android.com/studio> |
| 5 | **VS Code** (opcional) | con las extensiones *Flutter* y *Dart* | <https://code.visualstudio.com> |

### Flutter
1. Descomprímelo en una ruta **sin espacios**, por ejemplo `C:\flutter`.
2. Agrega `C:\flutter\bin` a la variable de entorno `PATH`.
3. Abre una terminal nueva y verifica con `flutter --version`.

### JDK 17
Verifica con `java -version`; debe decir `17.x`. Si tienes varias versiones de Java instaladas, indícale a Flutter cuál usar:

```powershell
flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-17..."
```

### Android SDK
En **Android Studio → More Actions → SDK Manager**, marca:

- **SDK Platforms:** Android **34**, 35 y 36.
  > **Android 34 es obligatorio**, aunque la app compile contra uno más nuevo, porque lo pide `flutter_secure_storage`.
- **SDK Tools:**
  - Android SDK Build-Tools
  - Android SDK Command-line Tools (latest)
  - Android SDK Platform-Tools
  - NDK (Side by side)
  - CMake

---

## 2. Verificar la instalación

```powershell
flutter doctor
flutter doctor --android-licenses   # responde "y" a todo
```

Deben salir en ✓ **Flutter**, **Android toolchain** y el editor. La línea de Xcode solo importa en Mac.

---

## 3. Descargar el proyecto

```powershell
git clone <URL-del-repo> SmartBus-CR-App
cd SmartBus-CR-App
flutter pub get
```

---

## 4. Preparar un dispositivo

### Opción A: teléfono Android (recomendada, porque la app usa GPS)
1. **Ajustes → Acerca del teléfono** → toca 7 veces **"Número de compilación"** para activar las Opciones de desarrollador.
2. En **Opciones de desarrollador**, activa **Depuración por USB** y **Permanecer activo**.
3. Conecta el teléfono por USB y acepta el diálogo **"¿Permitir depuración USB?"**.

### Opción B: emulador
En Android Studio → **Device Manager**, crea un dispositivo con **API 34 o superior** y arráncalo.

### Verificar
```powershell
flutter devices
```
El teléfono o el emulador debe aparecer en la lista con su **ID**.

---

## 5. Correr la app

```powershell
flutter run
# Si hay varios dispositivos:
flutter run -d <ID-de-flutter-devices>
```

Por defecto la app usa el Gateway de desarrollo en Render (`https://smartbus-api-gateway-dev.onrender.com/api`).

- El **primer login puede tardar entre 30 y 40 segundos** porque el servidor gratuito de Render está "despertando". Es normal.
- En VS Code: **Run → Start Debugging** y elige **"SmartBus (dev - Render)"**.

---

## 6. (Opcional) Probar el GPS y el bus en vivo

El servicio GPS **todavía no está desplegado** en Render, así que para probarlo hay que correr el backend en tu PC. Además de lo anterior necesitas:

- **PHP** y **Composer**.
- Los repos `smartbus-api-gateway` y `smartbus-gps-tracking`. En cada uno: `composer install`, copiar `.env.example` a `.env`, `php artisan key:generate` y `php artisan migrate`.

Resumen:

```powershell
# Terminal 1: servicio GPS
cd smartbus-gps-tracking
php artisan serve --port=8000

# Terminal 2: API Gateway (en su .env: GPS_SERVICE_URL='http://localhost:8000')
cd smartbus-api-gateway
php artisan config:clear
php artisan serve --port=8001

# Terminal 3: hace que "localhost:8001" del teléfono llegue a tu PC (repetir si reconectas el USB)
adb reverse tcp:8001 tcp:8001

# Correr la app con el GPS apuntando al Gateway local
flutter run -d <ID> --dart-define=GPS_GATEWAY_URL=http://localhost:8001/api
```

Con un emulador, en vez de `adb reverse` usa `http://10.0.2.2:8001/api`.

El tiempo real (Reverb) y los requisitos del viaje de prueba están en la **sección 5 del `README.md`** del proyecto.

---

## Errores comunes

| Síntoma | Solución |
|---|---|
| `flutter devices` dice *"not authorized"* | Acepta el diálogo de depuración USB en el teléfono. Si no aparece: Opciones de desarrollador → *Revocar autorizaciones de depuración USB* y vuelve a conectar. |
| El build falla por `compileSdk` o `flutter_secure_storage` | Instala **Android 34** en el SDK Manager. |
| El build falla con un error de Java o `jvmTarget` | Usa **JDK 17** (`java -version`). |
| *"Lost connection to device"* | Ajustes → Apps → SmartBus → Batería → **Sin restricciones**, y activa **Permanecer activo**. |
| El login tarda mucho la primera vez | Render está despertando; espera hasta 60 s. |
| La pantalla Recorrido dice *"No se encontró el recurso"* (404) | El GPS no está desplegado en Render; sigue el paso 6. |
