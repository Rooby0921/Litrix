# Sidebar Glass Tuning (mac-native style)

This app now renders both side panels using native glass material (`NSGlassEffectView` on macOS 26+, `NSVisualEffectView` fallback).

## Where to tune

Open `Settings → General → View`:

- `Sidebar Desktop Blend`
  Controls how much the sidebar moves toward window background color.
  - `0.00`: almost fully transparent glass (desktop shows through more).
  - `1.00`: more opaque / closer to solid window background.
- `Sidebar Tint Opacity`
  Controls extra accent tint intensity on top of glass.
  - Lower values look closer to default macOS.
  - Higher values create a stronger color atmosphere.

## Recommended ranges

- Native balanced look: `Desktop Blend 0.14 ~ 0.24`, `Tint 0.04 ~ 0.10`
- More minimal/translucent: `Desktop Blend 0.08 ~ 0.15`, `Tint 0.00 ~ 0.05`
- More solid/contrast: `Desktop Blend 0.25 ~ 0.40`, `Tint 0.08 ~ 0.16`

## Persistence

Both values are saved in app settings and restored automatically at next launch.
