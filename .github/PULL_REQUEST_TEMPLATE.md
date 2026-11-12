
# Pull Request Template

## Description

<!-- Briefly describe the purpose of this Pull Request and the problem it solves. -->

## Type of Change

- [ ] New Flutter feature
- [ ] Bug fix
- [ ] Refactoring or maintenance
- [ ] UI/UX
- [ ] API Gateway integration
- [ ] Configuration or tooling
- [ ] Documentation

## Main Changes

<!-- List the main changes implemented. -->

-
-
-

## Validation

### Commands Run

- [ ] `flutter pub get`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `flutter build apk --debug` (if applicable)

### Functional Flow

<!-- Describe the steps to validate the implemented functionality. -->

1.
2.
3.

### Test Environment

- **Device/emulator:** <!-- Android/iOS model and version -->
- **Flutter/Dart:** <!-- Relevant output from flutter --version -->
- **Configuration:** <!-- Render, local Gateway, --dart-define, etc. -->

## Modified API Contracts

| Method | Gateway Route | Purpose |
|--------|---------------|---------|
| POST | `/auth/login` | Authenticate the user |
| GET | `/auth/user` | Get the authenticated user |
| POST | `/auth/logout` | Log out |

### Application Screenshots

| Screenshot 1 | Screenshot 2 | Screenshot 3 |
|:---:|:---:|:---:|
| ![Screenshot 1](IMAGE_URL) | ![Screenshot 2](IMAGE_URL) | ![Screenshot 3](IMAGE_URL) |



## Request/Response

<!-- Include only contract changes. Do not add tokens, passwords, or personal data. -->

**POST `/auth/login`**

Request:

```json
{
  "email": "user@example.com",
  "password": "********"
}
```

Response:

```json
{
  "message": "Example response"
}
```

## Notes and Risks

<!-- Mention dependencies, known limitations, risks, or additional considerations. -->

-
