export const beans=[['pea','완두콩'],['kidney','강낭콩'],['black','검은콩'],['mung','녹두콩'],['peanut','땅콩']];
export const kstDate=(date=new Date())=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
export const dayNumber=(date)=>Math.floor((Date.parse(date+'T00:00:00Z')-Date.parse('2026-01-01T00:00:00Z'))/86400000);
export function todayQuestion(questions,date=kstDate()){const dow=new Date(date+'T00:00:00Z').getUTCDay();const list=questions.filter(q=>q.weekday===dow&&q.category!=='테마'&&q.active!==false).sort((a,b)=>a.id.localeCompare(b.id));return list.length?list[((dayNumber(date)%list.length)+list.length)%list.length]:null;}
export function stage(growth,target){return growth>=target?'열매':growth>=target*.75?'꽃':growth>=target*.5?'줄기':growth>=target*.25?'새싹':'씨앗';}
export function distribution(records,category){const counts={};records.filter(r=>r.category===category&&r.kind==='basic').forEach(r=>counts[r.answer]=(counts[r.answer]||0)+1);return Object.entries(counts).map(([name,count])=>({name,count}));}
export const messages=['오늘도 네 마음을 들여다봐 줘서 고마워!','조금 느려도 괜찮아. 너만의 속도가 있으니까.','오늘 하루도 충분히 잘해냈어!','네 마음은 언제나 소중해.','어떤 마음이든 여기에 머물러도 괜찮아.','필요하다면 믿을 만한 어른에게 기대도 좋아.','너의 이야기를 너의 속도로 들려줘.','지금의 마음을 알아차린 것만으로도 충분해.'];
/** @type {Record<string,string>} */
export const emoji={'맑음':'☀️','흐림':'☁️','비':'🌧️','눈':'❄️','번개':'⚡','무지개':'🌈','빨간불':'🔴','노란불':'🟡','초록불':'🟢','봄':'🌸','여름':'🌻','가을':'🍂','겨울':'☃️'};
