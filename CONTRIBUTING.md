# Contributing to the CopilotKit Flutter SDK

Thank you for your interest in contributing. This guide explains how to
report problems, how to set up the repository, and how to get a change from
your machine into `main`.

## How can I contribute?

You can report a bug, ask for a feature, improve the docs, or send a code
change. Talk to the maintainers before you start significant work on a new
or existing feature: open an issue first, so you know that the change fits
the SDK and that nobody is already working on it.

## Found a bug?

Open an [issue](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/new)
that describes what you did, what you expected, and what happened instead.
Include the Flutter version, the platform, and a log or a stack trace if you
have one. A pull request with a fix is even better.

## Missing a feature?

Open an [issue](https://github.com/VGVentures/copilotkit_flutter_sdk/issues/new)
that describes the feature and the problem it solves. If it's a feature of
another CopilotKit SDK, such as the React Native SDK, link to its docs.

## Contributing to documentation

The docs live in this repository, next to the code they describe:

- `README.md` gets you from a fresh clone to the demo app.
- Each package's `README.md` shows how to use that package.
- Doc comments in `lib/` are the API reference.
- `docs/adr/` records architecture decisions, and `docs/intent/` records the
  intent behind larger refactors.

A docs change goes through the same pull request process as a code change.

## How do I make a code contribution?

Follow these steps to get a change from a fresh clone into a merged pull
request.

### Step 1: Clone the repository

Clone the repository and open its root folder:

```sh
git clone https://github.com/VGVentures/copilotkit_flutter_sdk.git
cd copilotkit_flutter_sdk
```

### Step 2: Prepare the development environment

Install these tools first:

- [FVM](https://fvm.app). The Flutter version is pinned in `.fvmrc`, so every
  `flutter` and `dart` command runs through `fvm`.
- [Very Good CLI](https://cli.vgv.dev), to run the tests of every package.
- Node.js 20 or later, for the spell checker and the local Copilot Runtime.

Then install the pinned Flutter version and fetch the dependencies of every
package in the workspace:

```sh
fvm install
fvm flutter pub get
```

To run the example app against a local runtime, follow the quick start in
[`README.md`](README.md#quick-start).

### Step 3: Create a branch

Create a branch from `main`. Name it after the type of change and a short
description, for example `feat/tool-renderer`, `fix/stop-race` or
`docs/flutter-readme`:

```sh
git checkout -b <type>/<short-description>
```

### Step 4: Make your changes

Read [`AGENTS.md`](AGENTS.md) before you change code. It holds the project
conventions: the architecture, the layout of each package, and the rules for
code, tests and doc comments. They apply to every change, whether an agent or
a person writes it.

### Step 5: Run the checks

CI runs these checks on every pull request, and each one blocks the merge.
Run them from the repository root before you push:

1. Analyze the whole workspace:

   ```sh
   fvm flutter analyze
   ```

2. Check the formatting:

   ```sh
   fvm dart format --set-exit-if-changed .
   ```

3. Run every package's tests. Each package needs 100% line coverage:

   ```sh
   very_good test --coverage --min-coverage 100 --recursive
   ```

4. Check the spelling. Add project terms to
   `.github/.cspell/project_words.txt`:

   ```sh
   npx cspell --config .github/cspell.json '**/*.{md,dart,yml,yaml}'
   ```

5. If you changed code that `build_runner` generates, regenerate it in
   `packages/copilotkit` and in `example`, and commit the result:

   ```sh
   fvm dart run build_runner build
   ```

CI also builds the example app for the web with WebAssembly.

To check the runtime contract from the command line, send a request to a
running runtime. Add `--via-client true` to send the same request through
`CopilotKitClient`:

```sh
cd packages/copilotkit
fvm dart run tool/round_trip.dart --url http://localhost:8200/api/copilotkit
```

### Step 6: Commit your changes

Stage the changes that belong together and commit them with a message in
the format described in [Commit messages](#commit-messages):

```sh
git add <files>
git commit -m "<type>(<package>): <subject>"
```

Keep each commit to one logical change.

### Step 7: Push your branch

Push the branch to the repository:

```sh
git push origin <branch-name>
```

### Step 8: Open a pull request

Open a pull request against `main`:

1. Give it a title in the commit message format. A CI check rejects titles
   that don't follow it.
2. In the description, explain what changed and why, link the issue it
   fixes, and list anything you want the reviewer to look at.
3. Wait for a maintainer to review it, and push changes for their comments.

Ship multi-step work as a stack of small pull requests with
[`gh stack`](https://github.com/github/gh-stack), one pull request per step.
Each pull request is reviewed on its own and builds on the one below it.

## Commit messages

Commits and pull request titles follow
[Conventional Commits](https://www.conventionalcommits.org):

```text
<type>(<package>): <subject>
```

For example:

```text
fix(copilotkit): keep the partial reply when a run is stopped
```

The scope is the package the change is in: `copilotkit`,
`copilotkit_flutter`, `json_utils` or `example`. Leave it out when a change
spans the repository.

### Types

Use one of these types:

- **feat:** A new feature.
- **fix:** A bug fix.
- **docs:** A change to the documentation only.
- **style:** A change that doesn't affect the meaning of the code, such as
  formatting.
- **refactor:** A code change that neither fixes a bug nor adds a feature.
- **perf:** A code change that improves performance.
- **test:** New tests, or fixes to existing tests.
- **chore:** A change to the build, the CI, or the tooling.

### Breaking changes

If your change can break code that works today, add `!` after the scope and
a `BREAKING CHANGE:` line with the migration steps:

```text
refactor(copilotkit)!: replace RunErrorEvent with a core RunError

BREAKING CHANGE: RunErrorEvent is no longer exported.
onError now receives a RunError, with the same message and code.
```

Put the same `!` in the pull request title.

## Need help?

Open an [issue](https://github.com/VGVentures/copilotkit_flutter_sdk/issues)
with your question, or ask the maintainers in your pull request.
