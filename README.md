# HEAVENECTION

HEAVENECTION is a telecalling management system for assigning leads, tracking calling activity, monitoring work time, managing training, and handling salary workflows.

## Modules

- Admin web for operations, staff management, leads, follow-ups, callbacks, working hours, and payroll
- Staff mobile app for calling leads, updating customer remarks, viewing training, and checking work summary
- Developer release center for publishing new mobile app updates

## Tech Stack

- Backend: Django + Django REST Framework
- Database: PostgreSQL
- Admin panel: Custom Django web pages
- Mobile app: Flutter
- Hosting: Railway

## Main Features

- Staff sign in with phone number or email
- Lead import from CSV, Excel, and VCF
- Automatic lead allocation and callback prioritization
- Call workflow with remark marking
- Follow-up lead management and export
- Working-hour tracking and activity monitoring
- Learning center with training lessons and videos
- Salary calculation, payment tracking, and payment history
- In-app mobile update delivery

## Project Structure

```text
backend/        Django backend, APIs, business logic
staff_app/      Flutter mobile application
templates/      Admin web templates
static/         Web styles, scripts, images, PWA assets
media/          Uploaded files and release assets
```

## Local Setup

### Backend

1. Create and activate a Python virtual environment.
2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Configure environment variables in `.env`.
4. Run migrations:

```bash
python manage.py migrate
```

5. Start the server:

```bash
python manage.py runserver
```

### Mobile App

1. Open the Flutter app folder:

```bash
cd staff_app
```

2. Install packages:

```bash
flutter pub get
```

3. Run the app:

```bash
flutter run
```

4. Build a release APK:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://heavenection-production.up.railway.app
```

The built APK will be created at:

```text
staff_app/build/app/outputs/flutter-apk/app-release.apk
```

## Railway Deployment

Railway deployment notes are available in [RAILWAY_DEPLOY.md](RAILWAY_DEPLOY.md).

This project uses:

- PostgreSQL
- a persistent volume for uploaded files
- Railway web deployment with Django migrations before deploy

## Environment Variables

Use [.env.example](.env.example) as the reference for required settings.

Important groups:

- Django security and host settings
- PostgreSQL connection
- bootstrap admin account
- email settings

## Admin Access

The system includes:

- admin web login
- developer release login
- salary and follow-up management pages
- staff profile and document review pages

## Mobile App Notes

The Android app currently depends on Android phone and call-related features for the calling workflow. It is intended for Android phones and is not designed as a full iPhone-compatible version.

## Repository

- GitHub: [blesson7777/HEAVENECTION](https://github.com/blesson7777/HEAVENECTION)

