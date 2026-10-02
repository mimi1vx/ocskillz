---
description: Write or rewrite text in ASD-STE100 Simplified Technical English style
---

Load the `ste-english` skill and use it for this request.

Resolve the target from the argument below:
- Nothing given → style mode: write all further answers in STE style for the rest of the session.
- An existing file path → rewrite and audit mode on that file. Give the output in chat. Edit the file only
  if the user asks.
- Any other text → rewrite and audit mode on that text.

Target: $ARGUMENTS
