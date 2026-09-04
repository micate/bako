# Bako repository instructions

## Local macOS installation

- Never copy an unsigned or `CODE_SIGNING_ALLOWED=NO` build into `/Applications`.
- Bako embeds Sparkle. On a machine without a valid Apple code-signing identity, an
  ad-hoc signed Release app with Library Validation enabled crashes in `dyld` while
  loading `Sparkle.framework` because the components have no matching Team ID.
- For a local ad-hoc `/Applications/Bako.app` installation, keep Hardened Runtime
  enabled and sign the outer app with the
  `com.apple.security.cs.disable-library-validation` entitlement. The existing
  `Config/Bako-Debug.entitlements` contains this entitlement and may be used for a
  local-only build/signing override.
- A public Release must instead use a consistent Developer ID identity, Hardened
  Runtime, notarization, and stapling. Do not treat the local entitlement workaround
  as a distributable release procedure.
- Before reporting a local installation complete, verify the complete bundle with
  `codesign --verify --deep --strict`, launch the installed app from `/Applications`,
  confirm that its process remains alive, and check that no new Bako crash report was
  created.
