export default defineNuxtConfig({
  modules: [
    '@nuxt/ui',
    '@nuxt/eslint',
    '@nuxthub/core',
    'nuxt-auth-utils',
    '@pinia/nuxt',
    '@pinia/colada-nuxt'
  ],
  devtools: {
    enabled: true
  },
  css: ['~/assets/main.css'],
  future: { compatibilityVersion: 4 },
  compatibilityDate: '2025-08-07',
  hub: {
    db: 'sqlite'
  },
  // Allow overriding GitHub OAuth endpoints via env for CodeValid test infrastructure.
  // NUXT_OAUTH_GITHUB_AUTHORIZATION_URL, NUXT_OAUTH_GITHUB_TOKEN_URL, NUXT_OAUTH_GITHUB_API_URL
  runtimeConfig: {
    oauth: {
      github: {
        authorizationURL: '',
        tokenURL: '',
        apiURL: ''
      }
    }
  },
  // Development config
  eslint: {
    config: {
      stylistic: {
        quotes: 'single',
        commaDangle: 'never'
      }
    }
  }
})
