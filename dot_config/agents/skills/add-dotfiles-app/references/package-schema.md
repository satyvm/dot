# Package inventory schema

Each logical application has one stable `id` and one feature:

```yaml
- id: example
  feature: cli
  os: [darwin, linux]       # optional; both when omitted
  arch: [amd64, arm64]      # optional; both when omitted
  providers:
    apt: example            # Debian/Ubuntu system package
    brew:
      darwin: example
      linux: owner/tap/example
    cask:
      darwin: example
    mise: {name: example, version: "1.2.3"}
    npm: {name: example, version: "1.2.3"}
    uv: {name: example, version: "1.2.3"}
    cargo: {name: example, version: "1.2.3"}
    sourceApp:
      url: https://github.com/example/example.git
      version: "1.2.3"
      commit: 0123456789abcdef0123456789abcdef01234567
      target: app
      artifact: target/release/osx/Example.app
      app: Example.app
  homebrew:                 # required for a third-party Brew formula
    tap: owner/tap
    trust: formula
```

Only include providers the application actually uses. `apt` is a string because
the repository supports the common Debian/Ubuntu package name. If those names
diverge in the future, extend the generic renderer and schema together instead
of adding a special-case install command.

`sourceApp` is for a macOS app whose Homebrew cask cannot be installed. It is
limited to `os: [darwin]` and the `gui-all` feature. Pin both the upstream
release version and its 40-character commit, and describe the `make` target,
resulting app bundle path, and installed app name. The generic macOS source-app
renderer installs the bundle in `~/Applications`.

Feature behavior:

| Feature | Selection |
|---|---|
| `base` | Every host-managed preset |
| `cli` | CLI feature |
| `developer` | Developer feature |
| `ai` | AI feature |
| `ai-local` | AI plus local proxy mode |
| `gui-minimum` | macOS minimum and all GUI tiers |
| `gui-all` | macOS all GUI tier |
| `hardening` | Linux hardening feature |

The `container` preset is image-provisioned. Inventory entries still describe
its logical packages, but host apt/Brew/developer installers are excluded.
