---
version: alpha
name: DcentWallpapers Material
summary: Calm, technical Material 3 interface for managing live wallpapers.
colors:
  primary: "#A8C7FA"
  on-primary: "#0B1D33"
  secondary: "#BBC6D8"
  tertiary: "#D0BCFF"
  surface: "#111318"
  surface-container: "#1D2027"
  surface-container-high: "#272A31"
  on-surface: "#E2E2E9"
  on-surface-variant: "#C2C6D0"
  outline: "#8C9099"
  error: "#FFB4AB"
typography:
  display:
    fontFamily: "Noto Sans"
    fontSize: 2.25rem
    fontWeight: 600
    lineHeight: 1.15
  title:
    fontFamily: "Noto Sans"
    fontSize: 1.375rem
    fontWeight: 600
    lineHeight: 1.25
  body:
    fontFamily: "Noto Sans"
    fontSize: 1rem
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Noto Sans"
    fontSize: 0.875rem
    fontWeight: 600
    lineHeight: 1.4
rounded:
  sm: 8px
  md: 12px
  lg: 16px
  xl: 28px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
components:
  primary-action:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.lg}"
    padding: 12px
  library-card:
    backgroundColor: "{colors.surface-container}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.lg}"
    padding: 16px
  selected-card:
    backgroundColor: "{colors.surface-container-high}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.lg}"
    padding: 16px
---

## Overview

DcentWallpapers should feel like a focused Material 3 desktop utility: quiet surfaces, clear hierarchy, strong keyboard support, and enough technical detail to make storage and renderer state trustworthy.

> The current product surface is the KDE Wallpaper Configure page rather than a separate desktop application. These tokens remain the visual reference; current behavior and layout are documented in [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md).

## Colors

Use the dark palette by default because live-wallpaper previews are image-heavy. The blue primary color signals the current action without competing with wallpaper thumbnails. Purple tertiary is reserved for optional features such as playlists and Workshop discovery. Error colors are used for drive, permission, or renderer failures only.

## Typography

Use the system Noto Sans family when available, with KDE/system fallback. Large titles identify the current workspace; labels are compact but never below 14px in interactive controls.

## Layout

Use a navigation rail on wide windows and collapse it into a top bar below 900px. Keep a persistent search field and status line. The main library is a virtualized grid; the preview/details pane is optional and can become a bottom sheet on narrow windows.

## Elevation & Depth

Prefer tonal surfaces over shadows. Use one elevated container for the preview pane and a subtle outline for cards. Avoid gradients behind thumbnails so wallpaper colors remain accurate.

## Shapes

Use 16px cards, 28px primary buttons, and 12px fields. Thumbnail corners follow the card shape. Focus rings must remain visible against every surface.

## Components

The primary action is Apply/Test. Test is visually lower emphasis and always offers rollback. Library cards show path health, free space, and ownership. Wallpaper cards show a thumbnail, title, type badge, Workshop ID, and a clear selected state.

## Do's and Don'ts

- Do show exactly which library and renderer will be used before applying.
- Do preserve the last known-good wallpaper when a renderer fails.
- Do expose offline/local Workshop mode clearly.
- Do support keyboard navigation, reduced motion, and high-DPI scaling.
- Don't hide permission failures behind an empty library.
- Don't run multiple wallpaper engines silently.
- Don't use a full-screen preview that blocks access to Stop or Diagnostics.
