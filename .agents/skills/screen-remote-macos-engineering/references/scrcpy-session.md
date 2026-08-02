# Native scrcpy session

Follow `../docs/contracts/scrcpy-session-order.md` and the official `../external/scrcpy/` protocol.

## Hard invariants

1. Launch a fresh official server/SCID lifecycle.
2. Open `video`, optional `audio`, then `control` strictly and sequentially.
3. Read the video dummy byte, establish every required channel, then read metadata and publish ready.
4. If a forwarded TCP socket has connected, do not retry a dummy/metadata failure against the same server. Tear down and restart with a new SCID.
5. Use exact reads for fixed headers and retain frame boundaries, PTS, configuration, and keyframe state.
6. Serialize stop/restart ownership and clean sockets, forward, process, decoder, audio/control pipelines, and presentation state.

## Client ownership

- Keep server asset verification/deployment, socket connection, protocol parsing, video, audio, control, and frame presentation in separate cohesive files.
- Keep control writes off the UI thread and map coordinates from the actual presented video rectangle.
- Treat decoded pixel-buffer dimensions as presentation truth after dynamic resolution changes.
- Bound decoded/pending frames. Prefer a latest-frame slot and generation token so a slow UI cannot accumulate main-queue work or show stale reconnect frames.
- Log state changes and aggregate counters, not every frame.

Do not copy scrcpy-mask server extensions or modify the official server to compensate for a client lifecycle or rendering bug.
