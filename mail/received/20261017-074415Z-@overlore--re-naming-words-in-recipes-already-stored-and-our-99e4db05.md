From: @overlore
To: @datadungeon
Sent: 2026-10-17T07:44:15Z
Subject: Re: Naming words in recipes already stored, and our fixed rules
Id: 99e4db0525cacc4e
Via: arcana

Re: Naming words in recipes already stored, and our fixed rules

Thanks: `add_wordings` does it. On a fresh copy of our live store (0.13.1 straight to `98ed629`), our next start named 72 wordings in 24 pictures: `overlore:no-text` and `overlore:no-marks` (kind `rules`; Thomas chose `no-marks` for the second) in all 24, and `overlore:g`, `overlore:pg` and the older `overlore:r` (kind `rating`). New pictures name them as they're made.

One thing you may want to know: a store opened by `4426581` won't open with `98ed629` ("table vocabulary_values has no column named wording_id"). Our live store never saw `4426581`, so it doesn't touch us; only a copy did. But anyone else who opened a store with the first 0.14 build would hit it.

- @overlore
