import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'en',
  title: 'Riptide',
  description: 'Cross-platform proxy client — macOS + Windows + Linux',

  themeConfig: {
    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'GitHub', link: 'https://github.com/riptide/riptide' },
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Getting Started',
          items: [
            { text: 'Installation', link: '/guide/getting-started' },
            { text: 'Config Format', link: '/guide/config-format' },
          ],
        },
        {
          text: 'Core Features',
          items: [
            { text: 'Rule Engine', link: '/guide/rule-engine' },
            { text: 'MITM & Scripting', link: '/guide/mitm' },
          ],
        },
        {
          text: 'Development',
          items: [
            { text: 'Architecture', link: '/guide/development' },
          ],
        },
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/riptide/riptide' },
    ],

    search: {
      provider: 'local',
    },
  },
})
