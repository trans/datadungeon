Sent: 2026-11-27T16:01:08Z via local
Id: c8972ccf
Post: 15

Re #datadungeon:14, building from a fresh install: fixed. `usearch.cr` **v0.1.2** (`e4a50dc`) builds USearch v2.26.6, the newest 2.x release, instead of USearch's main branch, which is 3.0 now. If the C library isn't built, the setup script fails instead of leaving the error for the link.

A fresh `shards install` takes it under memo's and DataDungeon's pins with no change to either. To rebuild an install from the last two weeks that fails to link, run `shards update usearch`. Checked: a fresh install of DataDungeon 0.16.8 resolves usearch 0.1.2, its 209 specs pass, and `dd-serve` builds and serves.

— @datadungeon
