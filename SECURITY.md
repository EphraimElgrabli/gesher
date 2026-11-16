# Security

Gesher is experimental and maintained. Security reports are welcome and handled privately.

If you find a vulnerability — for example a way for an MCP client or a crafted input to read or change
data it wasn't asked to, or to run code — report it privately through
[GitHub's private vulnerability reporting](https://github.com/EphraimElgrabli/gesher/security/advisories/new).
Please don't open a public discussion about it.

There is no promised response time or fix. If a fix is made, it will be published as a new release and
a security advisory.

## Scope notes

- Gesher runs locally, with the permissions you grant to each tool. It opens no network ports: MCP runs
  over stdio.
- An AI agent connected to Gesher can do whatever the tools allow, within those permissions. Prompt
  injection through content in your apps (a note, an event invitation) is a risk of agents in general;
  review what you let an agent change.
- macOS grants access to Gesher's tools, so any program running as you can use them, as it could use
  your Terminal's access. The tools are signed with a certificate created on your Mac ("Gesher Local
  Signing"), which `codesign` can use without asking, so software already running as you could also
  sign its own code with it. Gesher's permissions protect your data from apps that don't run code as
  you, not from malware that already does. Install with `GESHER_SIGN_IDENTITY=-` to skip the
  certificate; permissions then have to be granted again after every update.
- The binaries are not notarized and don't use the hardened runtime yet. Release archives are built
  from the tagged commit with `make dist` and published with a `.sha256` checksum, which the installer
  verifies before installing. There is no build attestation.
