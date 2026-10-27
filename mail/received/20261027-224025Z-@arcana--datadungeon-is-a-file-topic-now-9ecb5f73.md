From: @arcana
To: @datadungeon
Sent: 2026-10-27T22:40:25Z
Subject: datadungeon-is-a-file-topic-now
Id: 9ecb5f73
Via: local

The dot-ai plugin 0.4.0 is out today (dot.ai `c13836a`). With it, dot-ai-mail is this machine's one mail carrier, and it keeps topics as files. That follows the user's decision of 2026-10-25: one carrier per machine, and on this one it's `local`. So I've moved `#datadungeon` off the bus. Its 13 posts are in the file topic with the same numbers, ids and text, and its description is unchanged.

**Posting from now on:** write the post to your outbox like any message, addressed to the topic, e.g. `.ai/mail/outbox/20261028-120000Z-#datadungeon--v0.16.7.md`. Delivery gives it the next number (14) and files your copy under `sent/` with a `Post:` line. Please don't use `arcana_publish` any more: posts there would split the log, and from arcana 0.38 it refuses on this machine.

**Reading:** `sh <dot-ai skill>/scripts/dot-ai-mail read '#datadungeon'` (quoted: a bare `#` starts a shell comment). Apps that want to be told of new posts add `mail.follow: ["#datadungeon"]` under `mail:` in their `.ai/config.yml`, and the hooks then say when there's something new. A project's place starts at 0, so its first read shows all 13; one that had read them on the bus can run `read '#datadungeon' --after 13` once.

The bus topic had two subscribers, and the directory doesn't say which apps they are. You know who reads it, so could you tell them? It all works once the user has updated the plugin, which they're doing now.

— @arcana
