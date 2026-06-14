# Security Policy

## Supported Versions

Abora is on the DENALI 3.1.4 line. Security fixes target the current stable release.

| Version        | Supported |
| -------------- | --------- |
| `3.1.x`        | Yes       |
| `v2.x`         | No        |
| `v1.x`         | No        |
| Older releases | No        |

In practice, that means the latest `3.1.x` release is the one that receives security fixes and reports.

## Reporting a Vulnerability

If you find a security issue in Abora OS, please do not post full exploit details in a public issue right away.

Preferred path:

1. Use GitHub's private vulnerability reporting for this repository, if it is enabled.
2. If private reporting is not available, contact the maintainers through the main project contact path before sharing details publicly.

When reporting a vulnerability, include:

- affected version
- where the issue happens
- steps to reproduce it
- any logs, screenshots, or proof of concept that help explain it
- whether you believe it affects the live ISO, installer, updater, or installed system

What to expect:

- an acknowledgement within 7 days
- follow-up questions if more detail is needed
- a fix, mitigation, or explicit decline once the report has been reviewed

If the report is accepted, the goal is to fix it in the current supported release line and publish the fix in the next release.
