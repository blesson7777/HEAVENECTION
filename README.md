# HEAVENECTION

HEAVENECTION is a full-stack staff telecalling operations platform built to manage lead distribution, live calling workflows, follow-ups, salary tracking, training, and mobile app releases from one system.

This repository contains:
- a Django-based admin and API backend
- a Flutter Android staff app
- a custom operations dashboard for supervisors
- internal tooling for app release management

## Why This Project Matters

The system is designed for real calling teams where managers need to:
- distribute leads quickly
- track staff activity and work time
- monitor follow-up performance
- review salary and incentive workflows
- train staff inside the product
- publish mobile app updates without separate tooling

It is a business-focused product with both operational depth and day-to-day workflow design.

## Product Surfaces

### 1. Admin Web
Used by supervisors and operations teams to:
- import and assign leads
- monitor live staff activity
- review work quality and work-time patterns
- manage follow-ups and interested leads
- process salary workflows and incentives
- publish app releases for staff devices

### 2. Staff Mobile App
Used by staff to:
- sign in and receive assigned leads
- place calls and mark outcomes
- manage follow-ups
- view working hours and earning details
- access training content
- receive in-app update prompts

### 3. Developer Release Center
Used internally to:
- upload APK builds
- mark active app versions
- distribute updates to staff devices

## Key Highlights

- End-to-end lead lifecycle from import to follow-up
- Live staff monitoring dashboard
- Work-time and activity review logic
- Salary control, payment history, and incentive support
- Training center for staff onboarding
- PDF reporting for staff performance
- In-app Android update delivery
- CSV, Excel, and VCF import support

## Tech Stack

| Layer | Technology |
| --- | --- |
| Backend | Django, Django REST Framework |
| Database | PostgreSQL |
| Mobile App | Flutter |
| Deployment | Railway |
| Reporting | ReportLab |
| Spreadsheet Import/Export | openpyxl |

## Repository Structure

```text
backend/        Django apps, APIs, models, views, business rules
docs/           Operating notes and training guides
staff_app/      Flutter Android application
static/         CSS, JS, assets, PWA files
templates/      Admin web templates
manage.py       Django entry point
```

## Architecture Snapshot

```text
Staff App (Flutter)
        |
        v
 Django REST APIs
        |
        v
Business Logic + Workflow Services
        |
        v
 PostgreSQL
        ^
        |
Admin Web Dashboard (Django templates + JS)
```

## What A Recruiter Should Notice

- This is not a sample CRUD app. It combines web operations, mobile workflow, reporting, release management, and business rules in one product.
- The project includes both product thinking and implementation: lead flow, staff monitoring, salary control, follow-up handling, training delivery, and supervisor tooling.
- The codebase shows hands-on work across backend, frontend, mobile, reporting, and deployment.

## Local Setup

### Backend

1. Create and activate a Python virtual environment.
2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Create your environment file:

```bash
copy .env.example .env
```

4. Run migrations:

```bash
python manage.py migrate
```

5. Start the backend:

```bash
python manage.py runserver
```

### Mobile App

1. Move into the Flutter app:

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

APK output:

```text
staff_app/build/app/outputs/flutter-apk/app-release.apk
```

## Environment

Use [.env.example](.env.example) as the reference for required configuration.

Main groups include:
- Django app settings
- database connection
- admin bootstrap settings
- email settings
- deployment host configuration

## Deployment

Railway deployment notes are documented in [RAILWAY_DEPLOY.md](RAILWAY_DEPLOY.md).

The current deployment setup uses:
- Railway web deployment
- PostgreSQL
- Django migrations during deploy
- persistent storage for uploaded files and app releases

## Additional Documentation

- [docs/admin-operating-guide.md](docs/admin-operating-guide.md)
- [docs/staff-training-note.md](docs/staff-training-note.md)
- [RAILWAY_DEPLOY.md](RAILWAY_DEPLOY.md)

## Platform Notes

- The mobile app is primarily designed for Android calling workflows.
- iOS support is limited because core call handling behavior depends on Android device capabilities.

## Repository Readiness Notes

This repository is now structured to be easier for public reading, but before broadly sharing it you should still review:
- branding assets you want visible publicly
- whether you want to add a license
- whether any internal screenshots or production URLs should stay private

## Repository

GitHub: [blesson7777/HEAVENECTION](https://github.com/blesson7777/HEAVENECTION)
