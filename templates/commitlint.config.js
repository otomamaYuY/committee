const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const configPath = path.join(__dirname, '.claude', 'git-conventions.yaml');
const { commit_types } = yaml.load(fs.readFileSync(configPath, 'utf8'));

module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', commit_types],
  },
};
