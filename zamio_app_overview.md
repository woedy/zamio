# ZamIO Capture App — Overview

Purpose
- Run on station devices to capture periodic short audio snippets and upload to the backend for fingerprinting and matching.
- Act as a resilient, background service with secure auth, idempotent uploads, and diagnostics to support 24/7 operation.

Capture & Upload
- Chunking: 10–30s AAC-ADTS, mono, 16 kHz, ~24 kbps; A/B rotation for gapless capture.
- Fields: file, station_id, chunk_id, started_at, duration_seconds.
- Transport: HTTPS; `Authorization: Token <device_or_station_token>`.
- Idempotency: `chunk_id = <stationId>-<epochMillis>`; server dedupes on repeated attempts.

Reliability
- Offline queue: persist chunks; exponential backoff retries; flush on app start/connectivity restore.
- Background: Android Foreground Service; iOS background audio mode; optional start-on-boot.
- Health: periodic heartbeat with last upload time, backlog depth, battery, free space, app version.

Security & Config
- Enrollment: app obtains `station_id` and scoped API token via login/QR.
- Config: remote overrides for chunk length, bitrate, endpoints; rotate tokens.
- Compliance: data minimization (short snippets), retention policy aligned with backend.

Server Contract
- Endpoint: `POST /api/music-monitor/stream/upload/`.
- Behavior: server decodes AAC→PCM mono 16 kHz, fingerprints and matches, writes MatchCache/PlayLog.
- Response: 201 with `{match, confidence, track_id?, chunk_id}`; 200 on idempotent duplicate.

Ops & Observability
- In‑app status and logs; exportable error report for field teams.
- Fleet dashboard server-side: device last-seen, backlog, error rate, version.

References
- App entry: `lib/main.dart`
- Capture/loop/upload: `lib/RadioSniffer.dart`
- UI: `lib/ui/*`
