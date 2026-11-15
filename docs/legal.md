# Legal notes

Plain-language notes on what Gesher is and is not. They are not legal advice.

## Not affiliated with Apple

Gesher is an independent open-source project. It is not affiliated with, authorized, endorsed or
sponsored by Apple Inc.

Apple, Mac, macOS, iCloud, Apple silicon, Siri, Reminders, Calendar, Contacts, Notes, Maps, Weather,
Freeform and other names of Apple products are trademarks of Apple Inc., registered in the U.S. and other
countries. Siri® and Freeform® are registered trademarks of Apple Inc. Gesher uses them only to say which apps it works with, as in "works with Apple Reminders".
The project's name, logo and icons are its own and are not derived from Apple artwork.

## What the project contains

- **Only original code**, licensed under the [GNU GPL v3](../LICENSE). There are no third-party
  dependencies.
- **No Apple code, binaries, headers or artwork.** Gesher does not copy or redistribute any part of
  macOS. At run time it loads frameworks and app binaries that are already installed on the user's own
  Mac, the same way any macOS program loads system libraries.
- **No security circumvention.** Gesher does not bypass macOS privacy controls, System Integrity
  Protection or code signing, and does not claim entitlements it doesn't have. Access to Reminders,
  Calendar, Contacts and protected files is requested through macOS's standard permission prompts, and
  the user decides. Features that macOS reserves for Apple-entitled apps (such as contact notes) are reported as unavailable, not worked around.

## Private interfaces

Gesher uses private frameworks Apple doesn't document for third-party use. Apple doesn't support these
interfaces, and a macOS update may change or break them. Your use of macOS remains subject to Apple's
macOS Software License Agreement; you are responsible for using Gesher in line with the terms that apply
to you.

## No warranty

Gesher is provided "as is", without warranty of any kind, as stated in sections 15 and 16 of the GPL.
It reads and changes data in apps that sync through iCloud; use it at your own risk and keep backups.
