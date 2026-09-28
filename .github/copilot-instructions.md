# Copilot code review instructions

When reviewing pull requests in this repository:

- Flag any suppressed lint rule or scanner skip that lacks a reason next to the code.
- Images must be referenced by digest (`@sha256:`), never by tag, in Terraform and in workflows.
- Pull request workflows must not request `id-token: write` or read AWS secrets.
- Actions must be pinned by full commit SHA with the version in a comment.
- The ECS task must stay non-root, read-only root filesystem, no public IP, with all capabilities dropped.
- New Terraform behaviour needs an assertion in a `.tftest.hcl` file that runs against the mocked provider.
- Only fictional names and AWS documentation example account IDs may appear; no real IDs, ARNs, IPs or emails.
- Verify conventional commit format in PR titles.
