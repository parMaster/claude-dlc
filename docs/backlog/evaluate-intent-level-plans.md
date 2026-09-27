---
worth: yes
added: 2026-09-27
---
# evaluate intent-level plans after real use

planning 2.0 moved plans from code to intent (Goal, Decisions, Traps, DoD) and cut review to one pass.
Try it on side projects first, then on main-job work, and collect feedback against these three questions:

1. **What did the implementer have to guess?** Anything it asked or got wrong because the plan didn't
   say probably belongs in Traps or Decisions — adjust `plan`'s investigation step or template.
2. **Were the review findings real?** Each should have changed what got built; "nothing to flag" should
   come up often. Padding means `plan-review.md` needs tightening again.
3. **Was the plan worth thinking through?** It should hold attention for up to ~10 minutes. Skimming
   means it's too long, too vague, or missing a diagram where a flow changes.

Fallback if the format fails on main-job work: tag `planning-v1.24.1`.
