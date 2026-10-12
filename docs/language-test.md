# Language acceptance tests (1.4.12)

NDISafe Desk offers exactly English, Kinyarwanda and French. English is the
default, independent of the PC's language. Previously saved unsupported language
choices fall back to English. Explicit French and Kinyarwanda selections persist.
The existing other-language source files are retained but are not selectable.

Kinyarwanda currently translates 607 of the 762 master keys. Remaining advanced
help text uses the existing English fallback. Native-speaker review is still
needed before treating the new translations as final.

## Manual checks

1. On a fresh install with Windows set to French, verify the app starts in English.
2. In Settings > Language, verify exactly three choices and no separate Default.
3. Select Kinyarwanda, restart the app and verify it remains selected.
4. Check connection, password, file transfer, update and privacy-pause controls.
5. Switch to French and verify the support window follows the selection.
6. During support, verify pause/resume labels and the failure warning in both
   languages. Follow privacy-pause-test.md before entering confidential data.
7. Upgrade an installation with a saved German or Chinese selection; verify
   English is displayed and selected.
8. Check long translated labels at narrow window sizes and increased text scaling.
