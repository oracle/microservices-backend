# Workflows

## dependency-checks

Validates PRs touching `docs-source/site/` or `data-refactoring-advisor/`, including
Dependabot updates. Each project runs only when its files change; changes to the
workflow itself and manual runs validate both projects.

The docs job uses Node 22 for a locked install, typecheck, and production build.
The advisor job uses Python 3.12 to install requirements, check dependency
compatibility, compile source, and run unit tests covering SQL parsing, community
detection, configuration loading, and the Streamlit landing page. Database and
LLM integration require separate testing with live services.

## obaas-base-image

This workflow takes the GraalVM image from Oracle Container Registry, scans for vulnerabilities, applies the latest OS patches, and stages the new image in ghcr.io for use with the OBaaS Platform.

### Workflow

1. Download the latest, patched GraalVM OBaaS image from the ghcr.io

    a. If no image exists in ghcr.io, download the latest GraalVM image from Oracle Container Registry and stage in ghcr.io
2. Run Trivy Vulnerability scanner against the ghcr.io image

    a. If Trivy does not find any vulnerabilities, **end workflow**

    b. If Trivy reports vulnerabilities, attempt to apply OS patches
3. Compare exiting ghcr.io image with attempt of patched image

    a. If existing image is same as patched image (no OS updates), **end workflow**
4. Push newly patched image as latest
