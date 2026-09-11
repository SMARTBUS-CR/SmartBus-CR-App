# Pull Request Template

## Description


## Type of Change

- [ ] New Flutter feature
- [ ] Bug fix
- [ ] Refactoring or maintenance
- [ ] UI/UX
- [ ] API Gateway integration
- [ ] Configuration or tooling
- [ ] Documentation

## Main Changes


## Validation

### Commands Run

- [ ] `flutter pub get`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `flutter build apk --debug` (if applicable)

### Functional Flow

### Test Environment

- **Device/emulator:** <!-- Android/iOS model and version -->
- **Flutter/Dart:** <!-- relevant output from `flutter --version` -->
- **Configuration:** <!-- Render, local Gateway, `--dart-define`, etc. -->

## Modified API Contracts

| Method | Gateway Route | Purpose |
|--------|----------------------------|-----------|
| POST | `/auth/login` | Authenticate the user |
| GET | `/auth/user` | Get the authenticated user |
| POST | `/auth/logout` | Log out |


## Screenshots or Evidence

<!-- Add relevant screenshots, video, logs, or links. For visual changes, include before/after evidence when useful. -->

## Request/Response

<!-- Include only contract changes. Do not add tokens, passwords, or personal data. -->

**POST `/auth/login`**

```json
{
	"email": "user@example.com",
	"password": "********"
}
```

## Notes and Risks


-