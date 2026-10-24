// Generate shared web/iOS task examples: node hardware/tools/task_examples.cjs
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../..');
const items=JSON.parse(fs.readFileSync(path.join(root,'shared/task-examples.json'),'utf8'));
const suffix='只查看，不修改任何设置，不发送信息或进行购买；完成后停止。';
for(const item of items){if(item.phone)item.goal+=suffix;if(Buffer.byteLength(item.goal)>1024)throw Error('Goal too long: '+item.id);}
const quote=s=>JSON.stringify(s);
let swift='// Generated from shared/task-examples.json by hardware/tools/task_examples.cjs.\nimport Foundation\n\nenum CloudTaskExample: String, CaseIterable, Identifiable {\n    case '+items.map(x=>x.id).join(', ')+'\n    var id: Self { self }\n    static var phoneExamples: [Self] { allCases.filter { $0 != .describeScreen } }\n    private var metadata: (title: String, symbol: String, detail: String, goal: String) {\n        switch self {\n';
for(const x of items)swift+='        case .'+x.id+': return ('+[x.title,x.symbol,x.detail,x.goal].map(quote).join(', ')+')\n';
swift+='        }\n    }\n    var title: String { metadata.title }\n    var symbol: String { metadata.symbol }\n    var detail: String { metadata.detail }\n    var goal: String { metadata.goal }\n}\n';
fs.writeFileSync(path.join(root,'ios/IPhoneAgent/Cloud/TaskExamples.swift'),swift);
const page=path.join(root,'hardware/hid_bridge/src/cloud/control_page.h');
let html=fs.readFileSync(page,'utf8');
const marker='// BEGIN TASK EXAMPLES\nconst taskExamples='+JSON.stringify(items.map(x=>({id:x.web_id,title:x.title,detail:x.detail,goal:x.goal})))+';\n// END TASK EXAMPLES';
if(html.includes('// BEGIN TASK EXAMPLES'))html=html.replace(/\/\/ BEGIN TASK EXAMPLES[\s\S]*?\/\/ END TASK EXAMPLES/,marker);
else html=html.replace("(()=>{'use strict';", "(()=>{'use strict';\n"+marker);
fs.writeFileSync(page,html);
console.log(`Generated ${items.length} web and ${items.filter(x=>x.phone).length} phone examples.`);
