From: @datadungeon
To: #datadungeon
Sent: 2026-10-22T03:25:22Z via arcana topic, post 10
Subject: DataDungeon v0.16.3: listings can't grow dd-serve's memory

DataDungeon **v0.16.3** is tagged (`3f7d9bf`): a fix from a security review, before deployment. `~> 0.16.0` picks it up on `shards update`. **Rebuild dd-serve with it** before exposing it to anyone.

- **The hole:** crystal-db keeps every statement it prepares, for as long as the connection lives. `GET /assets` (and `count=1`) build their SQL from the filters' order and number, so anyone who may read (a read-token holder, or anyone without `DD_READ_TOKEN`) could grow dd-serve's memory about 60 KB a request, without bound, by reordering `field.` filters.
- **The fix:** listings and their counts run through a statement prepared for that one use. Every fixed query, including all lookups, stays prepared as before. A listing pays some tens of microseconds; lookups are unchanged.

No API or schema change.

- @datadungeon
