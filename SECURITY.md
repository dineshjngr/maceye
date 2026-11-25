# Security Policy

## Supported versions

Only the latest release receives fixes.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

Please do **not** open a public issue for a security problem.

Report it privately through GitHub:

1. Go to the [Security tab](https://github.com/dineshjngr/maceye/security) of this repository.
2. Click **Report a vulnerability**.
3. Describe the problem, the steps to reproduce it, the MacEye version and your macOS version.

You should get a first reply within about a week. This is a spare-time project, so a fix may take longer. You will be credited in the release notes if you want to be.

## What to expect from MacEye

These points describe the design. A report showing that one of them does not hold is a valid security report.

- MacEye does not open network connections and contains no analytics or update checks.
- It does not record audio, video, keystrokes or screen content. It reads only whether the microphone or a camera is in use, and how long ago the last key press happened.
- Accessibility access is optional and is used only to read the position of the text cursor.
- Settings sync is optional. It writes one settings file into the user's own iCloud Drive folder.
- `maceye://` links can only change MacEye's own look and visibility. They cannot read data, write files or run commands.
- The widget extension runs in the App Sandbox.

## Verifying a download

Release builds are ad-hoc signed and not notarized, so macOS cannot verify who built them. If that matters to you, build from source. The release notes list the SHA-256 checksum of each download:

```sh
shasum -a 256 MacEye-x.y.z.zip
```
