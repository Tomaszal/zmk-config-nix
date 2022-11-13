# Build configured ZMK binaries using Nix

Build ZMK binaries locally using Nix instead of GitHub Actions.

Example usage: https://github.com/Tomaszal/naked60bmp

## Updating the West manifest

```bash
# 1. Enter development shell
nix develop
# 2. Initialise the West project
west init -l config
# 3. Update West modules
west update
# 4. Generate the new manifest
WEST_MANIFEST=$(nix run .#updateWestManifest) && echo "$WEST_MANIFEST" >west-manifest.json
```
