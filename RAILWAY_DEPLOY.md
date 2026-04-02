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
- `DJANGO_ALLOWED_HOSTS=your-app.up.railway.app,healthcheck.railway.app`
- `DJANGO_CSRF_TRUSTED_ORIGINS=https://your-app.up.railway.app`
- `DJANGO_MEDIA_ROOT=/data/media`
- `DATABASE_URL=${{Postgres.DATABASE_URL}}`
- `POSTGRES_CONN_MAX_AGE=60`
- `POSTGRES_SSLMODE=require`

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
- run `python manage.py collectstatic --noinput` on service start
- serve Django with `gunicorn`
- use `/health/` for Railway health checks

## Custom domain

If you attach a custom domain, update both:
- `DJANGO_ALLOWED_HOSTS`
- `DJANGO_CSRF_TRUSTED_ORIGINS`

## First login

After deploy, open:
- `/login/` for admin web
- `/developer/login/` for release publishing

## Staff mobile app note

For phones outside your local USB setup, the mobile app base URL must point to the Railway domain instead of `http://127.0.0.1:8000`.
