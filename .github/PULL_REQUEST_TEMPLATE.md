# Pull Request Template

## Description

<!-- Describe the purpose of this PR. What problem does it solve? What is the context? -->

## Type of Change

- [ ] New Flutter feature
- [ ] Bug fix
- [ ] Refactoring or maintenance
- [ ] UI/UX
- [ ] API Gateway integration
- [ ] Configuration or tooling
- [ ] Documentation

## Main Changes

<!-- List the main files or components modified and what changed in each. -->

- 
- 
- 

## Validation

### Commands Run

- [ ] `flutter pub get`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `flutter build apk --debug` (if applicable)

New or updated tests:
- 
- 

### Functional Flow

<!-- Describe step by step how to manually test this feature or fix. -->

1. 
2. 
3. 

### Test Environment

- **Device/emulator:** <!-- Android/iOS model and version -->
- **Flutter/Dart:** <!-- Relevant output from flutter --version -->
- **Configuration:** <!-- Render, local Gateway, --dart-define, etc. -->

## Modified API Contracts

<!-- If this PR changes any endpoints, request bodies, or response formats, document them here. -->

No backend changes.

| Method | Gateway Route | Purpose |
|--------|---------------|---------|
| | | |

## Application Screenshots

<!-- Replace the placeholders below with your actual image URLs. You can add or remove rows as needed. -->

<table>
  <tr>
    <td align="center"><img width="400" height="800" alt="Screenshot 1" src="URL_IMAGEN_1" /></td>
    <td align="center"><img width="400" height="800" alt="Screenshot 2" src="URL_IMAGEN_2" /></td>
  </tr>
  <tr>
    <td align="center"><img width="400" height="800" alt="Screenshot 3" src="URL_IMAGEN_3" /></td>
    <td align="center"><img width="400" height="800" alt="Screenshot 4" src="URL_IMAGEN_4" /></td>
  </tr>
</table>

## Request/Response

<!-- Include examples of the requests and responses used or modified in this PR. -->

```json
// Example response