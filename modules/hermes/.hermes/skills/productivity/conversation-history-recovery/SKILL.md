---
name: conversation-history-recovery
description: Use when recovering prior conversation context.
metadata:
  hermes:
    editorial_name: Conversation History Recovery
    editorial_description: Recover earlier discussion context without overclaiming memory.
    requires_tools:
      - terminal
---

# Conversation History Recovery

Recover what the user was referring to from locally available Hermes history before asking them to repeat it.

## Procedure

1. Search stored message text for the user's exact distinctive phrase and its stable components. For Hermes state backed by SQLite, inspect the schema first when needed, then query `messages` and group matches by `session_id`.
2. If the phrase may come from voice input or contains an unusual proper noun, search plausible component variants separately rather than treating the transcription as authoritative. Prefer nearby wording, creator names, platform terms, and topic nouns over speculative spelling corrections.
3. Rank candidate sessions by recency and relevance. Inspect the complete user/assistant turns around each match, not only the matching row; the intended referent often appears in an adjacent turn while the current phrase appears only in the new request.
4. Check session titles only as a navigation aid. Do not treat an automatically generated title as evidence of what the earlier conversation contained.
5. Report the strongest recovered candidate in plain language and state the confidence boundary. If one candidate clearly fits, ask whether that is the topic the user means; if none fits, ask for one discriminating detail such as the platform, creator, work title, or requested action.
6. Once confirmed, continue from the recovered task rather than making the user reconstruct the whole conversation.

## Rules and pitfalls

- Never claim to remember an earlier exchange solely because the current request itself appears in history; that is circular evidence and does not recover the missing context.
- Do not reject a close candidate merely because one unusual word differs; voice transcription commonly distorts names, so compare the surrounding intent and entities.
- Do not equate “no exact text match” with “no relevant history.” Search recent neighboring sessions and semantic components before concluding that context is unavailable.
- Preserve uncertainty explicitly: separate an exact historical match, a likely transcription variant, and a guess.
- Keep the recovery answer concise. Surface the likely topic first, then mention any limitation only if it affects confidence.
