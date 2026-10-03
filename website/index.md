---
layout: home

hero:
  name: Preview Cam
  text: Your webcam, floating on your desktop
  tagline: A frameless, transparent, always-on-top camera overlay for Windows — see yourself while you record or present.
  image:
    src: /logo.svg
    alt: Preview Cam
  actions:
    - theme: brand
      text: Download for Windows
      link: /download
    - theme: alt
      text: Getting started
      link: /guide/getting-started

features:
  - title: The camera is the window
    details: No title bar, no border, no toolbar. Rectangle, rounded, circle, 16:9 or 4:3 — everything outside the shape is genuinely transparent.
  - title: Stays out of your way
    details: Always on top, drag anywhere to move, drag the edges to resize, or switch on click-through so the mouse passes straight to the application underneath.
  - title: Works with OBS
    details: Opens physical webcams and virtual cameras alike. A built-in “Preview Cam” virtual camera hands the finished, shaped picture to OBS with transparent corners.
  - title: Background removal aware
    details: Cameras that deliver an alpha channel, such as NVIDIA Broadcast with the background removed, appear as a cut-out directly on your desktop.
  - title: A proper desktop utility
    details: System tray, configurable global hotkeys, position presets, multi-monitor and high-DPI support, start with Windows.
  - title: Free and open source
    details: MIT licensed. No accounts, no telemetry, no network access. English, Uzbek and Russian.
---

<div class="showcase">

## See it

<div class="showcase-row">

![Rounded rectangle shape](/screenshots/shape-rounded.png)

![Circle shape](/screenshots/shape-circle.png)

![Hover controls](/screenshots/controls.png)

</div>

<p class="showcase-caption">
  Rounded and circular shapes with truly transparent corners, and the controls
  that appear when the mouse is over the overlay.
</p>

</div>

<div class="credits">
  <h2>Made by Otabek Sadiridinov</h2>
  <p>
    Preview Cam is free and open source. If it is useful to you, you can
    support its development.
  </p>
  <p class="credits-actions">
    <a class="credits-button brand" href="https://taps.uz/uzhandy" target="_blank" rel="noreferrer">♥ Support the project</a>
    <a class="credits-button" href="https://github.com/otabekoff" target="_blank" rel="noreferrer">Developer: github.com/otabekoff</a>
  </p>
</div>

<style scoped>
/* Give the logo real presence in the hero. */
:deep(.VPHero .image-src) {
  width: 260px;
  max-width: 260px;
  max-height: 260px;
}
@media (min-width: 960px) {
  :deep(.VPHero .image-src) {
    width: 320px;
    max-width: 320px;
    max-height: 320px;
  }
}

.showcase {
  max-width: 1152px;
  margin: 64px auto 0;
  padding: 0 24px;
  text-align: center;
}
.showcase h2 {
  margin: 0 0 24px;
  border: 0;
  padding: 0;
  font-size: 24px;
  font-weight: 600;
  line-height: 32px;
}
.showcase img {
  display: block;
  width: 100%;
  border-radius: 12px;
}
.showcase-row {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
  margin-top: 16px;
}
.showcase-row p {
  margin: 0;
}
@media (max-width: 640px) {
  .showcase-row {
    grid-template-columns: 1fr;
  }
}
.showcase-caption {
  margin-top: 12px;
  color: var(--vp-c-text-2);
  font-size: 14px;
}

.credits {
  max-width: 720px;
  margin: 64px auto 0;
  padding: 0 24px;
  text-align: center;
}
.credits h2 {
  margin: 0 0 8px;
  font-size: 24px;
  font-weight: 600;
  line-height: 32px;
}
.credits p {
  margin: 8px 0;
  color: var(--vp-c-text-2);
}
.credits-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 12px;
  margin-top: 20px !important;
}
.credits-button {
  display: inline-block;
  border-radius: 20px;
  padding: 0 20px;
  line-height: 38px;
  font-size: 14px;
  font-weight: 600;
  text-decoration: none;
  color: var(--vp-button-alt-text);
  background-color: var(--vp-button-alt-bg);
}
.credits-button:hover {
  background-color: var(--vp-button-alt-hover-bg);
}
.credits-button.brand {
  color: var(--vp-button-brand-text);
  background-color: var(--vp-button-brand-bg);
}
.credits-button.brand:hover {
  background-color: var(--vp-button-brand-hover-bg);
}
</style>
