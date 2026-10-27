# Security Policy

## Supported versions

The CopilotKit Flutter SDK is in beta. Only the latest release on the `main`
branch receives security fixes.

## Reporting a vulnerability

Please do not report security vulnerabilities in a public issue, discussion, or
pull request.

Report them privately through GitHub's
[private vulnerability reporting](https://github.com/VGVentures/copilotkit_flutter_sdk/security/advisories/new).
Include:

- A description of the vulnerability and its impact.
- The steps to reproduce it, or a proof of concept.
- The affected package (`copilotkit` or `copilotkit_flutter`) and version.

We aim to acknowledge a report within a few business days, keep you updated as
we investigate, and credit you in the fix if you want to be named.

## Scope

This policy covers the code in this repository. Vulnerabilities in CopilotKit
itself, the Copilot Runtime, or the AG-UI protocol belong to those projects;
report them to their maintainers.

The runtime in `example/tool/` is a local demo and is not meant to be exposed
to untrusted networks.
