# Локальна розробка

Бекенд і БД запускаються у Docker, фронтенд (`own-delivery-courier-app`) — нативно через Vite.

## Що потрібно встановити

| Інструмент | Версія | Перевірка |
|-----------|--------|-----------|
| Docker + Docker Compose v2 | будь-яка актуальна | `docker compose version` |
| Node.js | 24 (див. `.nvmrc`) | `node -v` |

> Якщо використовуєш nvm: `nvm use` у директорії `own-delivery-courier-app` автоматично підхопить версію з `.nvmrc`.

---

## Перший запуск (одноразово)

### 1. Налаштувати `.env` для інфраструктури

```bash
cd own-delivery-infra
cp .env.example .env
```

Відкрий `.env` і встанови:
- `MSSQL_SA_PASSWORD` — будь-який пароль для SQL Server (мінімум 8 символів, з великою літерою і цифрою)
- `Jwt__Key` — рядок мінімум 32 символи (наприклад, згенерований `openssl rand -base64 32`)

### 2. Встановити права на директорію БД

SQL Server всередині контейнера працює від імені системного користувача з UID 10001. Без цього крок БД не стартує:

```bash
sudo chown -R 10001:0 own-delivery-infra/volumes/mssql
```

### 3. Встановити залежності courier-app

```bash
cd own-delivery-courier-app
npm install
```

---

## Запуск для розробки

### Крок 1 — Запустити бекенд і БД

```bash
cd own-delivery-infra

docker compose \
  -f docker/docker-compose.yml \
  -f docker/docker-compose.dev.yml \
  --env-file .env \
  up --build db backend
```

При першому запуску Docker стягне образи і скомпілює бекенд — займає 2-4 хвилини. При наступних запусках шари кешовані, старт ~30 секунд.

Контейнер готовий коли побачиш у логах:
```
own-delivery-backend | dotnet watch 🚀 Started
own-delivery-backend |       Now listening on: http://[::]:8080
own-delivery-backend |       Application started. Press Ctrl+C to shut down.
```

Swagger: [http://localhost:8095/swagger](http://localhost:8095/swagger)

### Крок 2 — Запустити фронтенд

В окремому терміналі:

```bash
cd own-delivery-courier-app
npm run dev
```

Vite dev server: [http://localhost:5190](http://localhost:5190)

---

## Зупинка

```bash
# Зупинити контейнери (дані БД зберігаються)
cd own-delivery-infra
docker compose -f docker/docker-compose.yml -f docker/docker-compose.dev.yml --env-file .env down

# Зупинити і повністю видалити дані БД
./scripts/dev-backend-stop.sh --clean
```

---

## Як влаштовано підключення

```
npm run dev  →  Vite :5190
                  │
                  │ axios baseURL = VITE_API_URL (з .env)
                  ▼
         Docker backend :8095
                  │
                  ▼
         SQL Server :1433
         (own-delivery-infra/volumes/mssql/)
```

`VITE_API_URL` задається у `own-delivery-courier-app/.env`:
- При запуску бекенду в Docker: `VITE_API_URL=http://localhost:8095` (за замовчуванням)
- При запуску бекенду нативно (`dev-backend-start.sh`): `VITE_API_URL=http://localhost:5134`

---

## Гаряче перезавантаження

| Що змінюєш | Що робити |
|-----------|-----------|
| Код бекенду (`.cs`) | `dotnet watch` підхоплює автоматично; при структурних змінах (сигнатури, enum) — авто-перезапуск без підтвердження |
| Код фронтенду (`.vue`, `.ts`) | Vite HMR підхоплює автоматично |
| `docker-compose.*.yml` | Зупинити та перезапустити `docker compose up` |
| Нова EF-міграція | Перезапустити контейнер бекенду — `dotnet ef database update` виконується при старті |

---

## Часті проблеми

**БД не стартує / `own-delivery-db` unhealthy**
```bash
# Перевір права на директорію
ls -la own-delivery-infra/volumes/mssql
# Має бути власник 10001, а не raid3r81
sudo chown -R 10001:0 own-delivery-infra/volumes/mssql
```

**`npm run dev` не з'єднується з бекендом (CORS / Network Error)**
- Переконайся що контейнер бекенду запущений: `docker ps | grep backend`
- Перевір `own-delivery-courier-app/.env` — `VITE_API_URL` має вказувати на правильний порт

**Порт 8080 або 1433 вже зайнятий**
```bash
# Змінити порти у own-delivery-infra/.env
BACKEND_PORT=8096
```
