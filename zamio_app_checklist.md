# ZamIO Capture App — Checklist

See also: [TestPlanOrder.md](../TestPlanOrder.md) for capture/upload visual checks and backend cross-verification.

Legend: [ ] todo, [~] partial, [x] done

MVP
- [x] Foreground recording loop (Android), background audio (iOS)
- [x] AAC-ADTS mono 16 kHz 10s chunks, A/B rotation
- [x] Multipart upload to `/api/music-monitor/stream/upload/` with `file`
- [x] Include `station_id`, `chunk_id`, `started_at`, `duration_seconds`
- [x] Token auth header (`Authorization: Token …`)
- [x] Delete local file only on 2xx response
- [x] Pending-files scan and upload on app start

Reliability & Offline
- [ ] Persistent queue with exponential backoff
- [ ] Retry on connectivity restore and on schedule
- [ ] Start-on-boot option (Android)
- [ ] Heartbeat ping with last upload time and backlog depth

Config & Security
- [x] Enrollment/login → store `station_id`, and scoped token (device ID later)
- [ ] Remote config (chunk length, bitrate, endpoints)
- [ ] HTTPS only; token rotation support

Observability
- [ ] Local error log viewer, export
- [ ] Basic metrics (uploads attempted/succeeded, avg latency)

QA
- [ ] 24h uninterrupted capture test on Android
- [ ] Airplane mode tests for offline queue/idempotency
- [ ] Time drift: verify server reconciliation with `started_at`/`chunk_id`

Stretch (Post-MVP)
- [ ] Overlapped capture or stream-based slicing
- [ ] Light normalization/AGC (or ensure server-side normalization)
- [ ] Remote commands: pause/resume, restart
