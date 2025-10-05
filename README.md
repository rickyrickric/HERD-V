
# HERD-V (Hierarchical Clustering) Mobile App

A Flutter mobile app prototype for livestock (cattle) monitoring, clustering, and recommendations.

## Features

- CSV import and sample CSV included (`sample.csv`).
- Manual animal entry form.
- Local caching of last dataset.
- Client-side clustering (k-means for UI-only mode) and optional backend support for hierarchical (Ward) clustering.
- Cluster insights with scatter plot and bar chart, per-cluster summary, and automated recommendations.
- Export recommendations as CSV.
- Toggleable Dark Mode (persistent preference).

## What's included

- `lib/main.dart` — Flutter app UI and client-side logic.
- `sample.csv` — sample cattle dataset for quick testing.
- `backend/app.py` — optional Flask backend implementing Ward hierarchical clustering (if you want server-side clustering and dendrograms).
- `tools/check_csv.py` — small utility to validate imported CSV files.

## Quick start (prerequisites)

- Flutter SDK installed and set up (desktop: https://flutter.dev/docs/get-started).
- Android SDK + AVD (for emulator) or a connected Android device.
- Python 3.12+ (if you want to run the backend) and `pip install -r backend/requirements.txt`.

### Run the app on an Android emulator

1. Start an Android emulator (or connect a device):

```powershell
flutter emulators --launch Pixel_6
```

2. Run the app (release mode recommended to avoid DVS issues):

```powershell
cd e:/applications/cattleapp
flutter run -d emulator-5554 --release
```

### Run the backend (optional)

```powershell
cd e:/applications/cattleapp/backend
python -m venv .venv312
.\.venv312\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

## Notes about pushing to GitHub

- I can't create a GitHub repo on your account for you here, but you can run these commands locally to push the project to GitHub once you've created a repo named `HERD-V`:

```powershell
cd e:/applications/cattleapp
git init
git add .
git commit -m "Initial commit: HERD-V app"
# Create a remote repository on GitHub (or use gh cli):
# gh repo create <your-username>/HERD-V --public --source=. --remote=origin
# then
git branch -M main
git remote add origin https://github.com/<your-username>/HERD-V.git
git push -u origin main
```

If you'd like, I can prepare a ready-to-run GitHub repo description and the exact `gh` command to create the remote if you give me your desired GitHub username and whether the repo should be public or private. Otherwise follow the steps above locally.

## Contact / Support

- If you want me to open a pull request template, CI (GitHub Actions) to run `flutter analyze`, or a CONTRIBUTING guide, tell me which you'd like and I will add them.
