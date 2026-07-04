# Common Code Patterns

## 1. Landmark-Based Iterative List Navigation
When attempting to scroll to a specific index in a lazily rendered `ListView.builder` that is completely unloaded from memory (e.g. hundreds of items away), you cannot simply use `animateTo` or `Scrollable.ensureVisible` reliably. 

**Pattern**:
1. Make an initial mathematical guess of the target offset (`index * estimated_item_height`).
2. `jumpTo` that estimate.
3. Pause for a frame (`await Future.delayed(const Duration(milliseconds: 100))`) so the layout engine renders items at the new offset.
4. Scan the currently rendered items to find any known item (a "landmark") and determine its true index.
5. Calculate the exact distance from the landmark to the target index.
6. Apply a clamped adjustment offset and jump again.
7. Repeat until the target item physically renders, then lock on and call `Scrollable.ensureVisible()`.
