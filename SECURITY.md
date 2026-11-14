# Security policy

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could expose user data or allow code execution.

Use GitHub's private vulnerability reporting on this repository:

1. Open the **Security** tab.
2. Choose **Report a vulnerability**.
3. Describe the issue and the affected version.

If private reporting is unavailable, contact the maintainer through the address on the GitHub profile.

## Scope

Meet&See is a local-only application. Relevant reports include:

- A path that escapes the configured search scope.
- A way to read protected files without the user's TCC grant.
- A command-injection or argument-injection path in the bundled helper.
- A crash or memory-safety issue in the Rust helper.
- A leak of Contacts data outside the in-process index.

Do not include real contacts, file contents, or full personal paths in a report. Use synthetic examples where possible.

## Supported versions

Security fixes target the latest release. Older releases are not maintained.
