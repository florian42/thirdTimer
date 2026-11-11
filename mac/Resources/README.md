# Bell sound

Third Timer rings a bell to suggest a break (one strike) and to end a break
(two strikes). It plays a recording named `bell.m4a`, `bell.wav`, `bell.mp3`
or `bell.aiff` from this folder; the build script copies it into the app.

No recording is in the repository yet. Until one is added, the app falls back
to the quiet macOS system sound "Tink".

## Recommended recordings

Both are by Joseph Sardin on BigSoundBank and are CC0 (public domain), so
they may be redistributed in this repository without attribution:

- "Gong, sweet": a soft mallet strike on a small hanging gong, 13 seconds.
  https://bigsoundbank.com/gong-sweet-s1482.html
- "Tibetan bowl struck #3": a stick strikes a Tibetan bowl, 10 seconds.
  https://bigsoundbank.com/tibetan-bowl-struck-3-s2554.html

Download the WAV from the page, save it here as `bell.wav`, and run
`./install.sh` again.
