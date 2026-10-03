import { defineConfig } from 'vitepress'

const repo = 'https://github.com/otabekoff/preview-cam'
const developer = 'https://github.com/otabekoff'
const donate = 'https://taps.uz/uzhandy'

// Published to GitHub Pages at https://otabekoff.github.io/preview-cam/
export default defineConfig({
  title: 'Preview Cam',
  description:
    'A floating, frameless webcam overlay for Windows with shapes, transparency, click-through and a virtual camera for OBS.',
  lang: 'en-US',
  base: '/preview-cam/',
  cleanUrls: true,
  lastUpdated: true,
  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: '/preview-cam/logo.svg' }]],

  themeConfig: {
    logo: '/logo.svg',
    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'Download', link: '/download' },
      { text: 'Privacy', link: '/privacy' },
      { text: 'Developer', link: developer },
      { text: '♥ Donate', link: donate },
    ],
    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Getting started', link: '/guide/getting-started' },
          { text: 'Using it with OBS', link: '/guide/obs' },
          { text: 'Settings and hotkeys', link: '/guide/settings' },
          { text: 'Troubleshooting', link: '/guide/troubleshooting' },
        ],
      },
      {
        text: 'Project',
        items: [
          { text: 'Download', link: '/download' },
          { text: 'Privacy policy', link: '/privacy' },
          { text: 'Code signing policy', link: '/code-signing' },
          { text: 'Developer: Otabek Sadiridinov', link: developer },
          { text: '♥ Support the project', link: donate },
        ],
      },
    ],
    socialLinks: [{ icon: 'github', link: repo }],
    editLink: {
      pattern: `${repo}/edit/main/website/:path`,
      text: 'Edit this page on GitHub',
    },
    search: { provider: 'local' },
    footer: {
      message:
        `Released under the MIT License. Developed by <a href="${developer}">Otabek Sadiridinov</a> · <a href="${donate}">♥ Support the project</a>`,
      copyright: 'Copyright © 2026 Otabek Sadiridinov',
    },
  },
})
