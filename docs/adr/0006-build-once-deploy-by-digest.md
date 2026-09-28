# 0006. Build once, scan, push by digest, deploy that digest

## Status

Accepted

## Context

A tag such as `latest` or `v1.4` can point to a different image tomorrow. If the pipeline rebuilds for each stage,
the image that was tested is not the image that runs.

## Decision

The deploy workflow builds the image once in a job with no AWS access. It runs the unit tests (in the build stage),
the smoke test and a Trivy scan, writes an SBOM and saves the image as an artifact. The push job loads that artifact,
refuses it if the image ID differs, pushes it and records the `sha256` digest ECR returns, plus a build provenance
attestation. The deploy job passes `repo@sha256:<digest>` to Terraform. The `image` variable rejects anything that is
not an ECR reference by digest. The repository has immutable tags.

## Consequences

- Every task definition revision names exactly one image; rolling back means redeploying an earlier digest.
- The pipeline needs an artifact of about 55 MB per run (kept for 7 days).
- This repo does not create the OIDC deploy role or the pipeline's IAM policy. That is the subject of
  `github-actions-aws-oidc-lab`.

## Compliance

The Terraform tests `rejects_an_image_referenced_by_tag` and `rejects_an_image_outside_ecr`, the image ID check in
`.github/workflows/deploy.yml`, and `scripts/deploy.sh`, which refuses a reference without a digest.

## Notes

Alternatives considered:

- Deploy by tag: readable, but the task definition does not prove which bytes ran.
- Build again in the push job: faster to write, but the pushed image was never scanned.
