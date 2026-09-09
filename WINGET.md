# WinGet Publishing

The local build creates a portable package for WinGet. You can upload the zip to
a GitLab Release, then submit the manifest manually with `wingetcreate`.

## Required setup

- A GitHub account that can fork `microsoft/winget-pkgs` and create pull requests.

Keep the GitHub token outside the repository. Use an environment variable or
`wingetcreate`'s local token storage.

## Release

Push a semantic-version tag:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

The manual release flow is:

1. Build `babae.exe` and package it with `babae.ps1` and `LICENSE`.
2. Upload the zip to the GitLab Generic Package Registry.
3. Create a GitLab Release.
4. Submit the initial manifest with `wingetcreate submit`, or update the existing
   package with `wingetcreate update --submit`.

WinGet validation and Microsoft review remain part of the pull-request process.
The first release may require correcting the generated SHA256 in the starter
manifest if the package metadata changes before submission.

## Local build

```powershell
.\build.ps1 -Version 0.1.0
```

The script requires the .NET SDK and updates the starter manifest hash when the
matching version directory exists.
