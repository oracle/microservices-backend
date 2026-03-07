import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

const config: Config = {
  title: 'Oracle Backend for Microservices and AI',
  tagline: 'A comprehensive microservices platform for AI microservices with Oracle AI Database',
  favicon: 'img/favicon-32x32.png',

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  url: 'https://oracle.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/microservices-backend/obaas',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'oracle', // Usually your GitHub org/user name.
  projectName: 'microservices-backend', // Usually your repo name.

  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          // Please change this to your repo.
          // Remove this to remove the "edit this page" links.
          // editUrl:
          //   'https://github.com/oracle/microservices-backend/tree/main/docs-source/site/',
        },
        gtag: {
          trackingID: 'G-2EVY167E00',
          anonymizeIP: true,},
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Replace with your project's social card
    image: 'img/logo.png',
    navbar: {
      title: 'Oracle Backend for Microservices and AI',
      logo: {
        alt: 'Oracle Backend for Microservices and AI Logo',
        src: 'img/logo_home.png',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'tutorialSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
          type: 'docsVersionDropdown',
          versions: ['current', '2.0.0']
        },
        {
          href: 'https://github.com/oracle/microservices-backend',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Introduction',
              to: '/docs/intro',
            },
            {
              label: 'Setup',
              to: '/docs/setup',
            },
            {
              label: 'Deploy',
              to: '/docs/deploy/overview',
            },
            {
              label: 'Observability',
              to: '/docs/observability',
            },
          ],
        },
        {
          title: 'Community',
          items: [
            {
              label: 'Stack Overflow',
              href: 'https://stackoverflow.com/questions/tagged/oracle',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'Oracle Blogs',
              href: 'https://blogs.oracle.com/',
            },
            {
              label: 'Oracle LiveLabs',
              href: 'https://livelabs.oracle.com/pls/apex/r/dbpm/livelabs/home'
            },
            {
              label: 'GitHub',
              href: 'https://github.com/oracle/microservices-backend',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()}, Oracle and/or its affiliates. Built with ❤️ using Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
