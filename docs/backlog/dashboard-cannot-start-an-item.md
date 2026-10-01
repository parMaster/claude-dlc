---
worth: yes
where: plugins/planning/scripts/backlog-dashboard.html
added: 2026-10-01
---
# the backlog dashboard can't start work on an item

The dashboard is view-only. Wanted: pick an item, hit "Start this item" in its expanded row, and get a new
session working that item (`/planning:backlog <slug>`).

The blocker is the way back: no documented channel lets an HTML overlay page tell agterm anything.
`agtermctl session overlay result` only reports a program overlay's exit code, and the agterm docs shipped
with its skill don't describe the HTML overlay at all, so an undocumented bridge is possible but unconfirmed.

Routes, cheapest first:

- **Native picker beside the page.** A second agterm custom command lists the items in `agtermctl pick` and,
  on Enter, opens a session running `claude "/planning:backlog <slug>"`. Only documented features; the start
  action sits next to the dashboard, not in it.
- **Copy button.** The expanded row gets a button that puts `/planning:backlog <slug>` on the clipboard.
  Small; unchecked whether the overlay's web view allows clipboard writes.
- **Local server.** The opener starts a throwaway localhost server that serves the page and takes a "start"
  request, then spawns the session. A true one-click button, at the cost of a background process to start,
  lock down and clean up.
- **Ask upstream** for a page-to-app hook in agterm (a GitHub Discussion); with one, the button is trivial.

Pick the route first; the picker is the one that works today. Spawning should go through `spawn-session`,
which is due to move to the `agterm` plugin.
