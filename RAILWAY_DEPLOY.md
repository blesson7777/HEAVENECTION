# Railway Deployment

This project is ready to deploy on Railway as a Django web service.

## Services to create

1. Create a Railway project.
2. Add a PostgreSQL service.
3. Add a Volume and mount it at `/data`.
4. Deploy this GitHub repository as the web service.

## Why the volume is required

This app stores uploaded files on disk:
- staff Aadhaar and passbook files
- company logo
- APK release uploads for the in-app updater

Without a volume, those files will be lost on redeploy.

## Railway environment variables

Set these on the web service:

- `DJANGO_SECRET_KEY`
- `DJANGO_DEBUG=false`
- `DJANGO_ALLOWED_HOSTS=api.heavenection.com,heavenection-production.up.railway.app,heavenection.com,www.heavenection.com,healthcheck.railway.app`
- `DJANGO_CSRF_TRUSTED_ORIGINS=https://api.heavenection.com,https://heavenection-production.up.railway.app,https://heavenection.com,https://www.heavenection.com`
- `DJANGO_MEDIA_ROOT=/data/media`
- `DATABASE_URL=${{Postgres.DATABASE_URL}}`
- `POSTGRES_CONN_MAX_AGE=60`
- `POSTGRES_SSLMODE=require`

Initial admin bootstrap:
- `BOOTSTRAP_ADMIN_NAME=HEAVENECTION Admin`
- `BOOTSTRAP_ADMIN_PHONE=your-phone-number`
- `BOOTSTRAP_ADMIN_EMAIL=your-email@example.com`
- `BOOTSTRAP_ADMIN_PASSWORD=your-strong-password`

Optional email settings:
- `EMAIL_HOST`
- `EMAIL_PORT`
- `EMAIL_HOST_USER`
- `EMAIL_HOST_PASSWORD`
- `EMAIL_USE_TLS=true`
- `DEFAULT_FROM_EMAIL`

## Runtime behavior

`railway.json` is configured to:
- run `python manage.py migrate --noinput` before deploy
- run `python manage.py bootstrap_admin_from_env` before deploy
- run `python manage.py collectstatic --noinput` on service start
- serve Django with `gunicorn`
- use `/health/` for Railway health checks

## First login

After the first successful deploy and admin bootstrap, open:
- `/login/` for admin web
- `/developer/login/` for release publishing

Admin users can also use the developer portal.

## Staff mobile app

The staff app already supports a production API base URL using a Flutter dart define.

Build the production APK with:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.heavenection.com
```

If you want your live users to receive that build through the in-app updater:

1. Build the APK with `https://api.heavenection.com` as the primary URL.
2. Open `https://heavenection-production.up.railway.app/developer/login/`.
3. Upload the APK on `/developer/releases/`.
4. Mark that release active.

## Custom domain

Current live-safe setup:
- primary app endpoint is `https://api.heavenection.com`
- legacy Railway fallback can stay on `https://heavenection-production.up.railway.app`
- website/admin can use:
  - `https://heavenection.com`
  - `https://www.heavenection.com`

To add the API subdomain on Railway:

1. Open the `HEAVENECTION` web service.
2. Go to `Settings -> Networking -> Public Networking -> + Custom Domain`.
3. Add `api.heavenection.com`.
4. Railway will show the exact CNAME target to use in DNS.
5. In your DNS provider, create:

```text
Type: CNAME
Name: api
Value: <the Railway target shown for api.heavenection.com>
TTL: Auto
```

6. Wait for Railway to show the green check for the new custom domain.

Once `api.heavenection.com` is verified, build future APKs with:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.heavenection.com
```
