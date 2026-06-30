import js from '@eslint/js'
import stylistic from '@stylistic/eslint-plugin'
import eslintConfigPrettier from 'eslint-config-prettier/flat'
import perfectionist from 'eslint-plugin-perfectionist'
import prettierRecommended from 'eslint-plugin-prettier/recommended'
import promise from 'eslint-plugin-promise'
import globals from 'globals'
import tseslint from 'typescript-eslint'
import { defineConfig } from 'eslint/config'

export default defineConfig([
  {
    ignores: ['node_modules', 'vendor/**', '../deps', '../priv'],
  },
  {
    extends: [
      js.configs['recommended'],
      ...tseslint.configs.strictTypeChecked,
      ...tseslint.configs.stylisticTypeChecked,
      stylistic.configs.customize({
        indent: 2,
        quotes: 'single',
        semi: true,
        jsx: false,
      }),
      promise.configs['flat/recommended'],
      prettierRecommended,
      perfectionist.configs['recommended-natural'],
      eslintConfigPrettier,
    ],
    files: ['js/**/*.{ts,js}'],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
      parserOptions: {
        project: ['./tsconfig.json'],
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      'no-unused-vars': 'off', // handled by @typescript-eslint/no-unused-vars
      // The CRT/ping readouts intentionally interpolate numbers (latency, mbps,
      // color channels); the rule still flags any/null/undefined/object - the
      // real sources of silent drift. allowNumber is an option, not a disable.
      '@typescript-eslint/restrict-template-expressions': [
        'error',
        { allowNumber: true },
      ],
      curly: 'error',
      'func-style': ['error', 'declaration'],
      'no-else-return': 'error',
      'perfectionist/sort-imports': [
        'error',
        {
          groups: [
            ['value-builtin', 'value-external'],
            'type-internal',
            'value-internal',
            ['type-parent', 'type-sibling', 'type-index'],
            ['value-parent', 'value-sibling', 'value-index'],
            'ts-equals-import',
            'unknown',
          ],
          environment: 'node',
        },
      ],
      'perfectionist/sort-objects': 'off',
      'perfectionist/sort-modules': 'off', // keep logical (not alphabetical) declaration order
    },
  },
])
