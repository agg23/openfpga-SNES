# MSU-1 build prerequisites

Use an existing Quartus Prime Lite 21.1 installation with Cyclone V support,
Python 3, Bash and util-linux `flock`. Set `QUARTUS_SH` to `quartus_sh` and run
`bash tools/build_msu1.sh --check-tools` before building a profile.

The current [review guide](MSU1-STANDARD.md) documents the experimental standard
profiles, recorded historical results, and present validation limits. This
repository does not distribute a toolchain or vendor simulation models.
