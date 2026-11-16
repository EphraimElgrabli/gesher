# Contributing

Gesher is experimental and maintained. Thank you for helping.

## Bug reports

Bug reports are welcome, especially when a macOS update breaks something: Gesher relies on
frameworks Apple can change in any update. [Open a bug report](https://github.com/EphraimElgrabli/gesher/issues/new?template=bug_report.yml)
with your macOS version, the app, what you asked for, what happened, and the output of
`gesher doctor`. Remove personal data (names, notes, events) from anything you paste.

## Ideas and questions

Feature requests go in [issues](https://github.com/EphraimElgrabli/gesher/issues/new?template=feature_request.yml);
questions, setups and show-and-tell go in [Discussions](https://github.com/EphraimElgrabli/gesher/discussions).

## Pull requests

Pull requests are welcome, but they are reviewed slowly. For anything larger than a small fix, open an
issue first so we can agree on the approach. Before you start:

- [AGENTS.md](AGENTS.md): the rules, the operation pattern every app follows, and the checklist for
  adding an app. It is written for both people and coding agents.
- [docs/architecture.md](docs/architecture.md): how the pieces fit together.
- `make check`: lint, tests and a release build. It must pass on every commit.
- Never test against your real data: use isolated stores or `QA-gesher-*` fixtures (AGENTS.md, rule 2).

By contributing you agree that your contribution is licensed under the [GPL-3.0](LICENSE).

## Security

Please don't report vulnerabilities in public issues: see [SECURITY.md](SECURITY.md).
