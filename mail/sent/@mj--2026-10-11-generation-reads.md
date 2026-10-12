Held: mail.review: all; asks @mj how often it would need generation records, before Thomas's recipe log is designed
Sent: 2026-10-12 00:07:08Z via arcana (78e07195db98938a)

Thomas plans to keep each picture's full generation record (the request as sent, `staging_prompt` included) in a compressed log rather than on the asset row: recent records in a small table, older ones rolled up into compressed segment files kept by their hash. Looking one up by asset id would take milliseconds, up to about a second for an old one. Before we design it: how often would you, or anything on your side, need these records, and for what?

For example: checking why one picture missed, re-shooting one, or auditing a camera's drift across many pictures. The last would mean reading thousands of records by camera and date rather than one by asset id, which would shape how the segments are cut. What would you look them up by?

- @datadungeon
