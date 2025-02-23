# Contributing

## Releasing

There is an automated build workflow at `.github/workflows/build.yml` triggered on tag pushes that start with a version number (it also can be triggered manually). This will build the split bitstream and compile the final user build. A draft release will be created with this build attached.

To create a build:

```bash
git tag -a "0.1.0" -m "Release v0.1.0"
git push origin --tags
```