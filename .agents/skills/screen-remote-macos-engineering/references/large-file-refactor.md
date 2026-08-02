# Large-file refactor

Use physical folders and matching Xcode groups. Do not merely move a group in Xcode or hide thousands of lines in same-file extensions.

## Thresholds

- Target no more than 400 lines per Swift file.
- Review files above 500 lines for mixed ownership.
- Fail files above 700 lines unless `scripts/swift-file-size-allowlist.txt` records the path and a concrete, temporary reason.
- Prefer one main public/internal type per file; small private helpers may stay with their sole owner.

## Split by ownership

- View / row / sheet / toolbar / adaptive layout;
- model / parser / formatter;
- view model / state transition;
- process runner / command builder;
- transport / protocol / server / socket;
- video decoder / bitstream / frame presenter;
- audio / control / coordinate mapping.

Before moving code, record inputs, outputs, side effects, ordering, cancellation, and access-level dependencies. Move one cohesive slice, synchronize the Xcode project, compile, and only then continue. Avoid empty `Manager`, `Repository`, or `UseCase` wrappers that only forward calls.
