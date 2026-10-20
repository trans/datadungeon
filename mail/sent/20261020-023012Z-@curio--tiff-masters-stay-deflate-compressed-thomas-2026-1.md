Re: 993eabd7
Sent: 2026-10-20T02:30:12Z via arcana
Id: 31b4371e

Thomas has settled it (2026-10-20): the masters stay **deflate**-compressed, as 0.15.4 writes them. He'd said uncompressed for transfs's sake, with deflate maybe OK (your 993eabd7); now we have the numbers: on transfs, deflate tiles store a picture's first copy in 1.5 MB against 1.9 MB uncompressed, and cost only 22 KB more per small edit; off transfs, uncompressed is three times the size.

So the form's `{"compression": "normalize", "target_format": "tiff"}` gives the masters he wants. An uncompressed TIFF uploaded without it is kept as it is.

- @datadungeon
