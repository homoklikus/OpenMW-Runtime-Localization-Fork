# Building on Windows

This document describes the intended Windows build path for the
**OpenMW — Runtime Localization Fork**.

The fork is based on OpenMW 0.51.0 and adds no Windows-specific third-party
dependencies. The runtime-localization changes are C++/Lua engine changes and
are intended to use the same MSVC dependency environment as upstream OpenMW
0.51.0.

## Validation status

The Linux build of this fork has been tested directly.

The Windows build should be treated as requiring independent validation before
publishing binaries. The instructions below intentionally reuse the upstream
OpenMW toolchain rather than introducing a fork-specific dependency system.

## Prerequisites

Use the development environment appropriate for OpenMW 0.51.0, including:

- a 64-bit Visual Studio C++ toolchain,
- CMake,
- Git,
- the third-party libraries required by OpenMW.

Visual Studio 2022 with the **Desktop development with C++** workload is a
practical MSVC environment for building the source.

Upstream project:

https://github.com/OpenMW/openmw

Upstream development environment documentation:

https://wiki.openmw.org/index.php?title=Development_Environment_Setup

OpenMW also maintains dependency-build infrastructure for its supported
platforms. Use dependency versions compatible with the OpenMW 0.51.0 source
base.

## Clone

From PowerShell:

```powershell
git clone https://github.com/homoklikus/OpenMW-Runtime-Localization-Fork.git
Set-Location OpenMW-Runtime-Localization-Fork
```

## Configure

Open an x64 Visual Studio developer environment or otherwise make the MSVC
toolchain available to CMake.

The following configuration mirrors the reduced Linux runtime build by disabling
applications that are not needed for testing the engine fork:

```powershell
$InstallDir = Join-Path $PWD "install"

cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_INSTALL_PREFIX="$InstallDir" `
  -DOPENMW_USE_SYSTEM_MYGUI=OFF `
  -DBUILD_LAUNCHER=OFF `
  -DBUILD_WIZARD=OFF `
  -DBUILD_MWINIIMPORTER=OFF `
  -DBUILD_OPENCS=OFF `
  -DBUILD_ESSIMPORTER=OFF `
  -DBUILD_BSATOOL=OFF `
  -DBUILD_ESMTOOL=OFF `
  -DBUILD_NIFTEST=OFF `
  -DBUILD_NAVMESHTOOL=OFF `
  -DBUILD_BULLETOBJECTTOOL=OFF
```

If your OpenMW dependency environment requires a CMake toolchain file, prefix
path or additional variables, add the same arguments that are required by the
corresponding upstream OpenMW 0.51.0 build.

Do not guess dependency paths: use the paths supplied by the dependency
environment you installed.

## Build

```powershell
cmake --build build --config RelWithDebInfo --parallel
```

## Install

```powershell
cmake --install build --config RelWithDebInfo
```

With the prefix above, the runtime files are installed below:

```text
install\
```

## Incremental rebuild

After source changes:

```powershell
cmake --build build --config RelWithDebInfo --parallel
cmake --install build --config RelWithDebInfo
```

## Running

Do not assume that copying only `openmw.exe` is sufficient.

A Windows OpenMW runtime also needs the appropriate runtime libraries and
resources from the matching build/dependency environment. For redistributable
packages, follow the upstream OpenMW deployment/packaging approach for the same
source generation.

The localization layer is separate from the engine and is not part of the
Windows binary package unless you intentionally distribute your own compatible
localization content separately.

## Recommended validation

Before publishing a Windows build of this fork, verify at least:

1. OpenMW reaches the main menu without missing DLL errors.
2. A normal unlocalized game starts successfully.
3. A synthetic runtime-localization layer can populate `content.translations`.
4. Dialogue topic display names remain separate from canonical topic IDs.
5. INFO response localization works.
6. `Choice`, `Say` subtitles and `MessageBox` display strings work.
7. Record-name setters work for several representative record types.
8. `refreshDerivedLocalization()` updates GMST-derived display names.
9. Existing saves load.
10. A build without any localization layer behaves like ordinary OpenMW 0.51.0
    for the modified paths.

See [API.md](API.md) and [ARCHITECTURE.md](ARCHITECTURE.md).

## Troubleshooting

### CMake cannot find third-party libraries

Resolve the dependency environment as an upstream OpenMW build issue first. The
fork does not add a new dependency bundle.

### Generator or architecture mismatch

Remove the build directory and configure again:

```powershell
Remove-Item -Recurse -Force build
```

Then rerun CMake from an x64 toolchain environment.

### Record the exact build revision

```powershell
git status -sb
git log --oneline -5
```

Keep the commit SHA together with any test binary you distribute.
