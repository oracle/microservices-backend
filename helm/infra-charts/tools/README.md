# OBaaS Helm Tools

Utility scripts for managing OBaaS Helm chart dependencies and container images for air-gapped or private registry deployments.

## Scripts

### download-dependencies.sh

Downloads all Helm chart dependencies for both `obaas` and `obaas-prereqs` charts.

```bash
./download-dependencies.sh
```

**Prerequisites:** `helm` CLI must be installed.
**Note:** Files should be committed to repository

---

### generate-images-list.sh

Extracts container images from a running OBaaS deployment. Useful for discovering all images used by the deployed application.

```bash
# All namespaces (default)
./generate-images-list.sh

# Single namespace
./generate-images-list.sh obaas

# Multiple namespaces
./generate-images-list.sh obaas obaas-prereqs

# Custom output file
./generate-images-list.sh -o images.txt obaas
```

**Options:**
| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-A, --all` | Get images from all namespaces (default if no namespace specified) |
| `-o, --output FILE` | Output file (default: `./image_lists/k8s_images_<appVersion>.txt`) |

**Prerequisites:** `kubectl` CLI must be installed and configured with cluster access.

**Output:** `image_lists/k8s_images_<appVersion>.txt` - List of unique container images (e.g., `image_lists/k8s_images_2.0.0.txt`). The version is extracted from the `appVersion` field in `obaas/Chart.yaml`.

---

### mirror-images.sh

Mirrors container images from public registries to a private registry. Supports dry-run mode for validation.

```bash
# Mirror images to a private registry
./mirror-images.sh myregistry.example.com

# Dry run (show what would be done)
./mirror-images.sh myregistry.example.com --dry-run

# Use custom images file
./mirror-images.sh myregistry.example.com -f ./images.txt

# Mirror images for a different platform (default: linux/amd64)
./mirror-images.sh myregistry.example.com --platform linux/arm64

# Export linux/amd64 images while off VPN
./mirror-images.sh myregistry.example.com -f ./images.txt --platform linux/amd64 --export-only --archive-dir /tmp/obaas-images

# Import and push the exported images while on VPN
./mirror-images.sh myregistry.example.com --import-only --archive-dir /tmp/obaas-images
```

**Options:**
| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-n, --dry-run` | Show what would be done without mirroring |
| `-f, --file FILE` | Path to images file (default: `./image_lists/k8s_images_<appVersion>.txt`) |
| `-p, --platform PLATFORM` | Target platform for images (default: `linux/amd64`) |
| `--export-only` | Pull, tag, and save images to `--archive-dir` without pushing |
| `--import-only` | Load images from `--archive-dir`, push them without pulling, and clean up imported archives after success |
| `--archive-dir DIR` | Directory used by `--export-only` and `--import-only` |

**Prerequisites:**
- `docker` or `podman` must be installed
- Authenticated to source registries for normal or `--export-only` mode
- Authenticated to the target registry for normal or `--import-only` mode

**Behavior:**
- Automatically strips known registry prefixes (docker.io, registry.k8s.io, quay.io, ghcr.io, gcr.io, container-registry.oracle.com, *.ocir.io)
- Skips images already in the target registry
- Skips OKE public images (`oke-public`)
- Cleans up local images after pushing to save disk space
- `--export-only` writes tar archives plus `manifest.tsv`; the manifest records source image, target image, archive file, and platform.
- Successful `--import-only` runs remove the imported tar archives and manifest, then remove `--archive-dir` when it is empty.

**Split VPN workflow:**

When public registries are reachable only off VPN and the private registry is reachable only on VPN, run:

```bash
# Off VPN: pull public linux/amd64 images and save them locally
./mirror-images.sh myregistry.example.com \
  -f ./images.txt \
  --platform linux/amd64 \
  --export-only \
  --archive-dir /tmp/obaas-images

# On VPN: load local archives and push to the private registry
./mirror-images.sh myregistry.example.com \
  --import-only \
  --archive-dir /tmp/obaas-images
```

---

## Data Files

### image_lists/k8s_images_\<appVersion\>.txt

Auto-generated file from `generate-images-list.sh` containing images discovered from a running Kubernetes cluster. The filename includes the `appVersion` from the Helm chart (e.g., `image_lists/k8s_images_2.0.0.txt`).

---

## Typical Workflow for Air-Gapped Deployments

1. **Download Helm dependencies:**
   ```bash
   ./download-dependencies.sh
   ```

2. **Mirror images to private registry:**
   ```bash
   # Login to registries
   docker login container-registry.oracle.com
   docker login myregistry.example.com

   # Mirror using generated list (auto-detects k8s_images_<appVersion>.txt)
   ./mirror-images.sh myregistry.example.com
   ```

3. **Deploy with private registry:**
   Use the example values files in `obaas/examples/values-private-registry.yaml` and `obaas-prereqs/examples/values-private-registry.yaml` to configure the Helm charts to use your private registry.
