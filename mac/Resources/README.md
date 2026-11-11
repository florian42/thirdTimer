# Bell sound

Third Timer rings a bell to suggest a break (one strike) and to end a break
(two strikes). The build script copies `bell.m4a` from this folder into the
app. Without it, the app falls back to the macOS system sound "Tink".

## Source

`bell.m4a` is "Tibetan bowl struck #3" by Joseph Sardin, from BigSoundBank:
https://bigsoundbank.com/tibetan-bowl-struck-3-s2554.html

It is published as CC0 (public domain), so it may be redistributed here.
No attribution is required; the credit is a courtesy.

The original is a 9-second, 48 kHz, 24-bit mono WAV. For the app it was cut
to 7.6 seconds, where the bowl has rung out, faded over the last 0.8 seconds,
and encoded as 96 kbit/s AAC at 44.1 kHz. Nothing else was changed.

To use a different sound, replace the file with a `bell.m4a`, `bell.wav`,
`bell.mp3` or `bell.aiff` and run `./install.sh` again.
