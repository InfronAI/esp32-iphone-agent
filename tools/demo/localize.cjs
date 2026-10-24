// Demo-only labels: keep firmware behavior intact while recording either language.
const translations = require('./locales/en.json');

function createLocalizer(language) {
  if (language === 'zh-CN') return value => value;
  if (language !== 'en') throw new Error('Use --lang en or --lang zh-CN');
  const keys = Object.keys(translations).sort((a, b) => b.length - a.length);
  const pattern = new RegExp(keys.map(key => key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'gu');
  function translate(value) {
    if (Array.isArray(value)) return value.map(translate);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, translate(item)]));
    if (typeof value !== 'string') return value;
    const text = value.replace(pattern, match => translations[match])
      .replaceAll('zh-CN', 'en-US').replaceAll('：', ': ').replaceAll('，', ', ')
      .replaceAll('。', '.').replaceAll('；', '; ');
    if (/\p{Script=Han}/u.test(text)) throw new Error('Missing English demo translation: ' + text.slice(0, 240));
    return text;
  }
  return translate;
}

module.exports = {createLocalizer};
