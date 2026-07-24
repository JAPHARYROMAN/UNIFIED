# Main Branch Protection

The local tracked pre-push hook rejects direct pushes to `main`. After a remote
repository is connected, the Release Authority must configure equivalent server-
side protection:

- require pull requests;
- require CODEOWNERS review;
- require Foundation, Local Smoke, and Security checks;
- reject force pushes and branch deletion;
- require linear history and signed commits or verified identities;
- restrict tag creation for `spec-baseline-*` and release tags.

Local hooks are defense in depth and are not a replacement for remote controls.

