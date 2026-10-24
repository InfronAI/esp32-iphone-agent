// Make this directory's pinned Playwright available to the firmware UI tests.
const path=require('node:path');
process.env.NODE_PATH=[path.join(__dirname,'node_modules'),process.env.NODE_PATH].filter(Boolean).join(path.delimiter);
require('node:module').Module._initPaths();
require('../../hardware/tests/test_control_page.cjs');
