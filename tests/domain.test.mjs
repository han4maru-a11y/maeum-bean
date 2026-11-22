import test from 'node:test';import assert from 'node:assert/strict';import{readFileSync}from'node:fs';import{kstDate,todayQuestion,stage,distribution}from'../src/domain.mjs';
const qs=JSON.parse(readFileSync(new URL('../public/questions.json',import.meta.url)));
test('KST midnight boundary',()=>{assert.equal(kstDate(new Date('2026-11-20T14:59:59Z')),'2026-11-20');assert.equal(kstDate(new Date('2026-11-20T15:00:00Z')),'2026-11-21')});
test('weekday question categories',()=>{for(let i=0;i<7;i++){const date=`2026-11-${String(16+i).padStart(2,'0')}`;assert.equal(todayQuestion(qs,date).category,['날씨','색깔','랜덤','신호등','계절','밸런스','한 주의 말'][i])}});
test('weekly variants change except Sunday',()=>{assert.notEqual(todayQuestion(qs,'2026-11-16').prompt,todayQuestion(qs,'2026-11-23').prompt);assert.equal(todayQuestion(qs,'2026-11-15').prompt,todayQuestion(qs,'2026-11-22').prompt)});
test('growth stages and target completion',()=>{assert.equal(stage(0,30),'씨앗');assert.equal(stage(8,30),'새싹');assert.equal(stage(15,30),'줄기');assert.equal(stage(23,30),'꽃');assert.equal(stage(30,30),'열매')});
test('categorical aggregation does not score feelings',()=>{assert.deepEqual(distribution([{kind:'basic',category:'날씨',answer:'비'},{kind:'basic',category:'날씨',answer:'비'},{kind:'theme',category:'날씨',answer:'맑음'}],'날씨'),[{name:'비',count:2}])});
