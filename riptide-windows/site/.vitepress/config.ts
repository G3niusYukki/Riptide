import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'en',
  title: 'Riptide Windows',
  description: 'Riptide Windows proxy client documentation',

  themeConfig: {
    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'Platform', link: '/platform/windows' },
      { text: 'Build', link: '/build/' },
      { text: 'GitHub', link: 'https://github.com/riptide/riptide' },
    ],

    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Getting Started', link: '/guide/getting-started' },
          { text: 'Development', link: '/guide/development' },
        ],
      },
      {
        text: 'Platform',
        items: [
          { text: 'Windows', link: '/platform/windows' },
        ],
      },
      {
        text: 'Build',
        items: [
          { text: 'Build & Release', link: '/build/' },
        ],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/riptide/riptide' },
    ],

    search: {
      provider: 'local',
    },
  },
})
