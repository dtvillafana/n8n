# Enterprise Differences

This build does not use license entitlements to restrict locally available features.

## License Behavior

- Positive Boolean feature entitlements are treated as enabled, regardless of the installed license.
- The inverse `feat:apiDisabled` entitlement is treated as disabled so it cannot remove Public API access.
- The `feat:showNonProdBanner` entitlement retains its original behavior because it controls license messaging rather than feature access.
- License-derived limits for users, active workflows, variables, workflow history, team projects, Insights history, and workflows with evaluations are treated as unlimited.
- License activation, renewal, certificate storage, plan reporting, and certificate diagnostics retain their original behavior.
- Purchased or externally supplied service balances, including AI credits and AI Gateway budgets, are not synthesized.
- Operator configuration, environment feature flags, permissions, authentication policy, and required external service configuration continue to apply.
- Evaluation concurrency remains controlled by operator configuration and existing runtime defaults because it is an execution-capacity safeguard, not a feature-access gate.

## Feature Implementation Changes

No enterprise feature implementation was changed. Ungating is confined to the shared license availability and license-derived capacity boundaries.
