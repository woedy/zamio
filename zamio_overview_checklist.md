# Zamio Overview & Checklist

Purpose
- Capture periodic radio studio audio, upload short snippets to server for fingerprinting and matching, enabling accurate royalty payments to music artists in Ghana.

Current Capabilities (MVP state)
- Recording: 10s chunked capture with A/B file rotation; immediate next-chunk start then background upload to minimize gaps.
- Format: AAC (ADTS) mono, 16 kHz sample rate, ~24 kbps bitrate (server must decode to PCM for fingerprinting).
- Upload: Multipart POST with fields `audio_file`, `station_id` (hardcoded), `timestamp`.
- Reliability: Delete files only on successful upload; scan temp dir at startup/stop to upload any pending `.aac` files.
- UI: Simple start/stop service screen with recording status.
- Permissions: Requests microphone and storage.

Known Gaps / Risks
- Background execution: No Android Foreground Service/iOS Background Audio yet; recording may stop in background.
- Offline handling: No persistent queue with retry/backoff beyond basic pending-file scan.
- Security: Using HTTP without authentication; no TLS or auth tokens.
- Config: `backendUrl` and `station_id` are hardcoded; no enrollment or remote config.
- Time sync: Relies on device time; no server time or deterministic chunk IDs.
- Observability: No heartbeat/health metrics or remote diagnostics.

MVP Next (Must-Haves)
- [ ] Background recording: Android Foreground Service (persistent notification) and iOS Background Audio capability.
- [ ] Offline queue + retries: Persist chunks to app storage; exponential backoff; retry on connectivity restore; process on app start.
- [ ] Idempotency: Deterministic `chunk_id` (e.g., `stationId-epochMillis`) to dedupe retries server-side.
- [ ] Security: Migrate to HTTPS; attach auth (per-station token/JWT) to uploads; rotate tokens.
- [ ] Config & enrollment: Replace hardcoded `station_id` with onboarding (login/QR); store `device_id`, `station_id`, `app_version`, `os`.
- [ ] Health heartbeat: Periodic ping with last upload time, battery, free space, app version for fleet monitoring.

Product/Tech Details to Align With Backend
- [ ] Server decodes AAC to mono PCM 16 kHz and feeds fingerprint engine.
- [ ] Handle chunk boundaries: server-side overlap/windowing to avoid misses; client ensures gapless rotation.
- [ ] Payout audit: Store match logs (track, time, confidence, source chunk ID) to support royalty audits.
- [ ] Retention policy: Define minimal retention of raw audio; ensure DPA compliance.

Post-MVP Enhancements
- [ ] Overlap or stream-based slicing for extra robustness (requires concurrent recording or audio stream processing).
- [ ] Light AGC/normalization (or ensure server-side normalization).
- [ ] Remote config: Adjust chunk length, bitrate, endpoints from server.
- [ ] Connectivity awareness: Use `connectivity_plus` to trigger immediate retries when network returns.
- [ ] Remote commands: Pause/resume, restart, and configuration push from server.
- [ ] Status & logs screen: Local error log viewer and export for field technicians.
- [ ] Admin dashboard (server): Device fleet status, last-seen times, backlog depth, error rates.
- [ ] Analytics: Upload success rate, average latency, matching rate.

Testing & QA
- [ ] Simulate background behavior on Android with Foreground Service; verify uninterrupted 24/7 capture.
- [ ] Airplane mode tests for queueing and retry logic; confirm idempotency on server.
- [ ] Time drift tests; prefer server timestamps or reconcile with `chunk_index`.
- [ ] Corrupt upload handling; ensure retries and backoff without data loss.

Security & Compliance
- [ ] TLS everywhere (HTTPS backend URL).
- [ ] AuthN/AuthZ: Per-station credentials; least-privilege scope.
- [ ] Data minimization: Only short snippets; strict retention on server.
- [ ] Consent and legal: Station/operator consent; Ghana data protection compliance; audit logs.

Open Questions
- [ ] Target fingerprint engine and expected input format? (Chromaprint/Echoprint/custom)
- [ ] Required minimum match duration and confidence threshold for payout events?
- [ ] Station onboarding flow (self-serve vs. admin provisioned)?
- [ ] Device management needs (remote updates, alerts)?

References (Code Pointers)
- Recording/loop/upload: `lib/RadioSniffer.dart`
- App entry: `lib/main.dart`

