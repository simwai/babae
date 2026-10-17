/** @type {import('lint-staged').Config} */
module.exports = {
  '*.ps1': [
    'pwsh -Command "& { . ./scripts/lint-ps1.ps1 {} }"'
  ],
  '*.md': [
    'prettier --write',
    'markdownlint --fix --config .markdownlint.jsonc'
  ],
  '*.yml': [
    'prettier --write'
  ],
  '*.yaml': [
    'prettier --write'
  ],
  '*.json': [
    'prettier --write'
  ]
};