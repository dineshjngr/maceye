# Contributing to MacEye

Thank you for wanting to help. This page explains how to report problems, suggest ideas and send changes.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting a bug

1. Search the [existing issues](https://github.com/dineshjngr/maceye/issues) first.
2. Open a new issue with the **Bug report** form.
3. Include your macOS version, your Mac type (Apple silicon or Intel), the MacEye version, and the steps that lead to the problem.

Please remove personal information from screenshots and logs before you attach them.

Do not report security problems in public issues. See [SECURITY.md](SECURITY.md).

## Suggesting a feature

Open an issue with the **Feature request** form. Describe the problem you want solved before the solution you have in mind. Small, focused ideas are easier to accept.

## Setting up

You need a Mac with macOS 15 or later and Xcode 16 or later. No developer account and no extra tools are required.

```sh
git clone https://github.com/dineshjngr/maceye.git
cd maceye
Scripts/test.sh     # automated checks
./build.sh run      # build and open the app
```

You can also open `MacEye.xcodeproj` in Xcode. The project uses folder-synchronised groups, so a new Swift file placed in `MacEye/`, `MacEyeWidget/` or `Shared/` is picked up without editing the project file.

## Developer tools

The app has a few helpers for testing without clicking through it:

| How | What it does |
|---|---|
| `MacEye --status` | Prints the monitor readings and settings checks, then exits. |
| `MacEye --render-preview out.png` | Draws every theme and mood into one picture, then exits. |
| `MACEYE_SIM=orbit` or `MACEYE_SIM=shake` | Environment variable. Replaces the real pointer with a pretend one that circles or shakes. |
| `MACEYE_DUMP_DIR=/some/folder` | Environment variable. Every two seconds, writes the live state and a picture of each pair of eyes into that folder. |

Example:

```sh
open --env MACEYE_SIM=orbit --env MACEYE_DUMP_DIR=/tmp/maceye-dump build/Release/MacEye.app
```

## Making a change

1. Fork the repository and create a branch from `main`.
2. Keep the change focused. One topic per pull request.
3. Follow the style of the code around you:
   - Swift 5 language mode, four-space indentation.
   - Plain names, and comments that explain why, not what.
   - No third-party dependencies without discussing it in an issue first.
4. Keep the app offline. MacEye must not open network connections. Changes that add networking, analytics or tracking will not be accepted.
5. Never commit signing certificates, provisioning profiles, team identifiers, tokens or other secrets.
6. If you change drawing code, keep `EyeRenderer` (Core Graphics) and `EyeLayers` (Core Animation) looking the same. `Scripts/test.sh` compares them.
7. Add or update checks in `Tests/main.swift` when you can.
8. Run `Scripts/test.sh` and `./build.sh` before you open the pull request.
9. Add a line to the **Unreleased** section of [CHANGELOG.md](CHANGELOG.md).
10. If you change how the app looks, run `Scripts/make-previews.sh` to refresh the README pictures.

## Pull requests

- Fill in the pull request template.
- Say what you tested and on which macOS version.
- Screenshots or short recordings help for visual changes. Check them for personal information first.
- A maintainer will review when they can. This is a spare-time project, so please be patient.

## Privacy when contributing

Your commits are public. If you do not want your email address in the history, use your GitHub no-reply address:

```sh
git config user.email "ID+USERNAME@users.noreply.github.com"
```

You can find the exact address in your GitHub email settings.

## Licence

By contributing, you agree that your contributions are released under the [MIT License](LICENSE).
