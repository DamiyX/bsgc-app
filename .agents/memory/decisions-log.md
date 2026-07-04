# Architectural & UI Decisions

## Avatar Color Generation
**Decision**: Replaced Dart's default `hashCode` implementation with a custom ASCII summation loop for mapping user IDs to avatar colors.
**Reason**: Dart's `hashCode` frequently collides for small strings (like mock user IDs), causing multiple unique users to be assigned the exact same avatar color. ASCII summation guarantees consistent, collision-resistant distribution across UI boundaries.

## Chat Auto-Scrolling
**Decision**: Tied auto-scrolling mechanics directly to the `StreamBuilder` data arrival frame instead of using naive delays.
**Reason**: Relying on fixed `Future.delayed` loops to scroll down after sending a message proved unreliable. Now, the `StreamBuilder` detects the newest message ID; if it's from the current user, it triggers a `addPostFrameCallback` to execute a smooth scroll exactly when the message is laid out.

## Deep Navigation Scanning (Scroll-To-Message)
**Decision**: Built an iterative, landmark-based navigation engine to scroll to old replies.
**Reason**: Naive jumping fails when target indices are thousands of pixels away due to lazy rendering in `ListView.builder`. The engine now jumps to a mathematical estimate, reads currently rendered context keys as landmarks, calculates exact offsets, and iterates until the target is precisely centered.
