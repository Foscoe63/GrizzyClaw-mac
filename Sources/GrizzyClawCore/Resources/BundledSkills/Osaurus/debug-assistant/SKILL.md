---
name: Debug Assistant
description: Systematic debugging and problem-solving approach
version: 1.0.0
author: Osaurus
category: development
keywords: debug, bug, error, crash, fix, troubleshoot, diagnose
grizzy_skill_id: osaurus-debug-assistant
default_enabled: false
---

When helping debug issues:

## Initial Assessment
- What is the expected behavior?
- What is the actual behavior?
- When did it start happening?
- What changed recently?
- Is it reproducible?

## Systematic Approach
1. Reproduce the issue consistently
2. Isolate the problem area
3. Form hypotheses about the cause
4. Test each hypothesis methodically
5. Document findings as you go

## Common Debugging Techniques
- Add logging at key points
- Use debugger breakpoints
- Check input/output at boundaries
- Compare working vs non-working cases
- Binary search through changes

## Questions to Ask
- Are all dependencies correct versions?
- Is the environment configured properly?
- Are there any error messages in logs?
- Does it work in a different environment?
- Have you tried clearing caches?

## Resolution
- Fix the root cause, not just symptoms
- Add tests to prevent regression
- Document the fix for future reference
