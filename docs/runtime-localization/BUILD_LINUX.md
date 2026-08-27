# Building on Linux

This document describes a tested Linux build path for the
**OpenMW — Runtime Localization Fork**.

The fork is based on OpenMW 0.51.0 and does not add any new third-party
dependencies beyond those required by upstream OpenMW.

## Tested environment

The runtime-localization changes have been built and tested on:

```text
Debian 13 (x86_64)
CMake
Ninja
GCC toolchain
OpenMW 0.51.0 source base
```

Package names for OpenMW dependencies differ between distributions and can
change over time. Install the normal build dependencies for OpenMW 0.51.0 before
configuring this fork.

Upstream project:

https://github.com/OpenMW/openmw

Upstream development environment documentation:

https://wiki.openmw.org/index.php?title=Development_Environment_Setup

## Clone

```bash
git clone https://github.com/homoklikus/OpenMW-Runtime-Localization-Fork.git
cd OpenMW-Runtime-Localization-Fork
```

The public development branch is `main`.

## Configure

The following configuration was used for the tested runtime-localization build.
It builds the game engine while disabling tools that are not required for
runtime testing.

```bash
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$HOME/OpenMW-RuntimeLocalization-install" \
  -DOPENMW_USE_SYSTEM_MYGUI=OFF \
  -DBUILD_LAUNCHER=OFF \
  -DBUILD_WIZARD=OFF \
  -DBUILD_MWINIIMPORTER=OFF \
  -DBUILD_OPENCS=OFF \
  -DBUILD_ESSIMPORTER=OFF \
  -DBUILD_BSATOOL=OFF \
  -DBUILD_ESMTOOL=OFF \
  -DBUILD_NIFTEST=OFF \
  -DBUILD_NAVMESHTOOL=OFF \
  -DBUILD_BULLETOBJECTTOOL=OFF
```

You may enable the disabled applications and tools if your system has the
corresponding dependencies.

## Build and install

```bash
cmake --build build -j"$(nproc)"
cmake --install build
```

After installation, the main executable is expected under the configured
installation prefix:

```text
$HOME/OpenMW-RuntimeLocalization-install/bin/openmw
```

## Incremental rebuild

After changing the source code:

```bash
cmake --build build -j"$(nproc)"
cmake --install build
```

A full CMake reconfiguration is normally unnecessary unless build options or
dependencies changed.

## Isolated test profile

Using a separate XDG profile avoids mixing test settings and saves with another
OpenMW installation.

```bash
mkdir -p "$HOME/OpenMW-RuntimeLocalization-test/config"
mkdir -p "$HOME/OpenMW-RuntimeLocalization-test/data"

XDG_CONFIG_HOME="$HOME/OpenMW-RuntimeLocalization-test/config" \
XDG_DATA_HOME="$HOME/OpenMW-RuntimeLocalization-test/data" \
"$HOME/OpenMW-RuntimeLocalization-install/bin/openmw"
```

The corresponding OpenMW log is normally written below:

```text
$HOME/OpenMW-RuntimeLocalization-test/config/openmw/
```

## Localization data

The engine fork does not contain localization data.

To test runtime localization, install an external localization layer separately
and configure OpenMW to load it as normal content. The localization layer should
populate the APIs documented in [API.md](API.md).

See [LOCALIZATION_LAYER.md](LOCALIZATION_LAYER.md) for the recommended data
model.

## Troubleshooting

### CMake cannot find a dependency

This normally means the normal OpenMW development dependencies are incomplete or
CMake cannot find their installation prefix.

Resolve the upstream OpenMW dependency first. The runtime-localization fork does
not add a separate dependency stack.

### Reconfigure from a clean build directory

If the CMake cache was created with incompatible dependency paths or generator
settings:

```bash
rm -rf build
```

Then run the configure command again.

### Confirm the source revision

```bash
git status -sb
git log --oneline -5
```

For reproducible testing, record the exact fork commit used for the build.
