# Secure Task Manager (Flutter + Node.js)

## Backend (PowerShell, from `backend/`)

```powershell
npm install                       # picks up Prisma 6 (the rc version was removed)
docker compose up -d              # PostgreSQL, wait until `docker compose ps` says healthy
npx prisma migrate dev --name init
npm run dev                       # API on http://localhost:3000
curl.exe http://localhost:3000/health
node scripts/verify-token-flow.js # rotation / reuse / logout / logout-all checks (section 19a)
```

Automated tests (use a separate `task_manager_test` database):

```powershell
npm run test:db:prepare           # creates task_manager_test and applies migrations
npm test
```

## Flutter (from `mobile/`)

```powershell
flutter pub add http flutter_riverpod flutter_secure_storage
flutter pub add --dev mocktail
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1   # Android emulator
```
