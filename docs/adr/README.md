# Architecture decision records

Architecture decision records follow the *Fundamentals of Software Architecture* (2nd ed.) format.
Records are never deleted; a replaced decision is marked Superseded and links to its successor.

| Number | Title | Status |
| --- | --- | --- |
| [0001](0001-distroless-multi-stage-image.md) | Multi-stage build onto a distroless Node.js runtime | Accepted |
| [0002](0002-two-stacks-registry-and-service.md) | Separate Terraform stacks for the registry and the service | Accepted |
| [0003](0003-private-tasks-with-vpc-endpoints.md) | Private tasks with VPC endpoints instead of a NAT gateway | Accepted |
| [0004](0004-rolling-with-circuit-breaker-by-default.md) | Rolling deployments with the circuit breaker and alarms by default | Accepted |
| [0005](0005-codedeploy-blue-green-as-an-option.md) | Blue/green through CodeDeploy as an option | Accepted |
| [0006](0006-build-once-deploy-by-digest.md) | Build once, scan, push by digest, deploy that digest | Accepted |
| [0007](0007-arm64-tasks.md) | ARM64 (Graviton) tasks | Accepted |
