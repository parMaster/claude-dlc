---
worth: later
where: plugins/statusline/scripts/statusline.sh:57
added: 2026-10-19
---
# cache countdown is stuck at 5m under the new keep-alive

Claude Code 2.1.303 gives interactive sessions a 5m prompt cache TTL instead of 1h. It keeps the cache
warm with hidden pings that don't show up in the transcript. The pings stopped about 55m into an 80m
break, and the cache went cold 5m later. So a 5m session shows `cache 5m` nearly all the time, then
`cache cold`, which makes the countdown a hot/cold label in practice. Sessions still on 2.1.283 get 1h,
where the countdown still means something.

Open question: after a week of watching, is 5m plus keep-alive the steady behavior, and are the 1h
sessions gone? If yes, replace the countdown with a plain hot/cold label. The idle time from `/usage`
is another option worth weighing.
