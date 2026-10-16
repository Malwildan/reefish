const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const base=process.env.PREVIEW_URL||'http://127.0.0.1:4196';
const owner='11111111-1111-4111-8111-111111111111';
const user={id:owner,aud:'authenticated',role:'authenticated',phone:'+6280000000000',
  app_metadata:{provider:'phone',providers:['phone']},user_metadata:{},created_at:'2026-10-15T00:00:00Z'};
const expires=Math.floor(Date.now()/1000)+3600;
const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
const token=encode({alg:'HS256',typ:'JWT'})+'.'+encode({sub:owner,exp:expires,role:'authenticated'})+'.local-test-signature';
const session={access_token:token,refresh_token:'local-fixture-refresh',token_type:'bearer',expires_at:expires,expires_in:3600,user};
const boat={id:'22222222-2222-4222-8222-222222222222',name:'Kapal QA',engine_hp:15,boat_length_m:7,fuel_type:'solar',home_port:{lat:-8.433,lng:112.683},is_default:true};

(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 let page;
 try{
  const context=await browser.newContext({viewport:{width:430,height:932},permissions:['geolocation'],geolocation:{latitude:-8.433,longitude:112.683}});
  await context.addInitScript(({session})=>{
   if(!localStorage.getItem('journey-qa-initialized')){
    localStorage.setItem('sb-upyahsecuorqghcghflg-auth-token',JSON.stringify(session));
    localStorage.setItem('journey-qa-initialized','1');
   }
  },{session});
  page=await context.newPage();
  const errors=[],layoutErrors=[],tiles=[],submissions=[]; let boatCreated=false,tripCreated=false;
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{if(/overflowed|EXCEPTION CAUGHT BY RENDERING|RenderFlex/i.test(message.text()))layoutErrors.push(message.text());});
  page.on('response',r=>{if(r.url().includes('tile.openstreetmap.org/'))tiles.push(r.status());});
  const profile=()=>({id:owner,name:'Nelayan QA',phone:'6280000000000',role:'nelayan',onboarded:tripCreated,
   next_step:!boatCreated?'boat':tripCreated?'done':'first_trip',boat:boatCreated?boat:null,
   stats:{trip_count:tripCreated?1:0,baseline_fuel_liters:tripCreated?12.5:null,baseline_catch_kg:tripCreated?20:null}});
  await page.route('**/*.supabase.co/**',async route=>{
   const url=new URL(route.request().url());
   const json=(body,status=200)=>route.fulfill({status,contentType:'application/json',body:JSON.stringify(body)});
   if(url.pathname==='/auth/v1/user')return json(user);
   if(url.pathname==='/auth/v1/token')return json(session);
   if(url.pathname==='/auth/v1/logout')return json({});
   const name=url.pathname.split('/').pop();
   if(name==='get_grid_lock_snapshot')return json({version:'journey-fixture',fetched_at:new Date(Date.now()-1000).toISOString(),expires_at:new Date(Date.now()+300000).toISOString(),is_demo:false,locks:[]});
   if(name==='api_me')return json(profile());
   if(name==='api_create_boat'){
    const body=route.request().postDataJSON(); assert.equal(body.p.engine_hp,15);assert.equal(body.p.boat_length_m,7);
    boatCreated=true;return json(boat);
   }
   if(name==='api_post_trip'){
    const body=route.request().postDataJSON();submissions.push(body.p);
    if(submissions.length===1)return json({code:'XX000',message:'UPSTREAM_UNAVAILABLE',hint:'Fixture temporary failure'},503);
    tripCreated=true;return json({trip:{id:'33333333-3333-4333-8333-333333333333',source:body.p.source,fuel_liters:body.p.fuel_liters,catch_kg:body.p.catch_kg,departed_at:body.p.departed_at,returned_at:body.p.returned_at},user:{onboarded:true},replay:false,recommendations:null});
   }
   if(name==='api_list_trips')return json({data:tripCreated?[{id:'33333333-3333-4333-8333-333333333333',source:'onboarding',departed_at:submissions[0].departed_at,fuel_liters:12.5,catch_kg:20}]:[],meta:{page:1,limit:5,total:tripCreated?1:0},summary:{trip_count:tripCreated?1:0,total_catch_kg:tripCreated?20:0,total_fuel_liters:tripCreated?12.5:0}});
   return json({code:'PGRST202',message:'Fixture blocks unhandled API'},404);
  });
  const enable=async()=>{
   await page.waitForSelector('flutter-view',{state:'attached',timeout:120000});
   const toggle=page.locator('flt-semantics-placeholder');await toggle.waitFor({state:'attached',timeout:45000});await toggle.evaluate(e=>e.click());
  };
  const button=name=>page.getByRole('button',{name,exact:true});
  const shot=async name=>{await page.waitForTimeout(400);await page.screenshot({path:path.join(__dirname,name+'.png')});};
  await page.goto(base+'/?screen=departure',{waitUntil:'domcontentloaded',timeout:90000});await enable();
  await button('Pilih Lokasi Saat Ini').click();await button('Edit').waitFor();await page.waitForTimeout(300);
  await button('Simpan').click();await page.getByText('Tempatkan titik ikan?',{exact:true}).waitFor();await page.waitForTimeout(400);
  await page.mouse.click(260,230);await page.waitForTimeout(400);await button('Selesai').click();
  await page.getByText('Kekuatan mesin',{exact:true}).waitFor({timeout:30000});await shot('boat-430');
  const boatInputs=page.locator('input');await boatInputs.nth(0).fill('Kapal QA');await boatInputs.nth(1).fill('15');await boatInputs.nth(2).fill('7');
  await button('Lanjutkan').click();await page.getByText('Catat Perjalanan Melaut',{exact:true}).waitFor();await page.waitForTimeout(400);
  await shot('create-journey-430');
  const fields=page.locator('input');const values=['12.5','20','00','00','01','00'];
  assert.equal(await fields.count(),6);
  for(let i=0;i<values.length;i++){
   const field=fields.nth(i);await field.click();await field.press('ControlOrMeta+A');
   await field.pressSequentially(values[i],{delay:40});await page.waitForTimeout(120);
   assert.equal(await field.inputValue(),values[i],`field ${i} must retain typed value`);
  }
  await page.mouse.click(210,700);await page.waitForTimeout(120);
  for(let i=0;i<values.length;i++)assert.equal(await fields.nth(i).inputValue(),values[i],`field ${i} must retain value after blur`);
  await button('Lanjutkan').click();
  await button('Coba kirim lagi').waitFor();await shot('pending-retry-430');
  assert.equal(submissions.length,1);assert.equal(submissions[0].source,'onboarding');
  await button('Coba kirim lagi').click();
  await page.getByText('Rekomendasi',{exact:true}).waitFor({timeout:30000});await page.waitForTimeout(800);
  assert.equal(submissions.length,2);assert.deepEqual(submissions[0],submissions[1]);
  assert.match(submissions[0].client_trip_id,/^[a-f0-9-]{36}$/);
  assert.ok(!('grid_id' in submissions[0].fishing_points[0]));
  assert.ok(submissions[0].fishing_points[0].started_at == null);
  assert.ok(submissions[0].fishing_points[0].ended_at == null);
  await shot('dashboard-430');
  const text=await page.locator('body').innerText();assert.ok(text.includes('Cuaca belum tersedia'));assert.ok(!text.includes('15 L'));
  await page.setViewportSize({width:360,height:640});await shot('dashboard-360');
  await page.mouse.move(180,100);await page.mouse.wheel(0,600);await page.waitForTimeout(400);await shot('dashboard-scroll-360');
  await page.reload({waitUntil:'domcontentloaded',timeout:90000});await enable();
  await button('Edit').waitFor(); // Restore keeps the map's separately saved departure.
  await page.goto(base+'/?screen=dashboard',{waitUntil:'domcontentloaded',timeout:90000});await enable();
  await page.getByText('Rekomendasi',{exact:true}).waitFor();await shot('dashboard-restored-360');
  assert.equal(submissions.length,2,'Dashboard reload must not submit a trip again');
  assert.deepEqual(errors,[]);
  assert.deepEqual(layoutErrors,[]);
  const report={checkedAt:new Date().toISOString(),previewUrl:base,frames:['194:810','104:80'],
   checks:{focusToBoatToForm:true,boatPrerequisite:true,formSubmission:true,pendingRetrySamePayload:true,dashboard:true,restoreWithoutResubmission:true,compactViewport:true,unknownPredictionsPreserved:true},
   submissions:submissions.length,errors,layoutErrors,tileRequests:tiles.length,tileStatuses:[...new Set(tiles)],
   fixtureNotice:'Auth, boat, trip and grid policy HTTP responses were intercepted locally. No production account, boat or trip was created. Weather/recommendation numbers are not fabricated.',
   nativeAndroid:'not tested'};
  fs.writeFileSync(path.join(__dirname,'verification.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
 }catch(error){if(page){await page.screenshot({path:path.join(__dirname,'failure.png')});fs.writeFileSync(path.join(__dirname,'failure.txt'),await page.locator('body').innerText());}throw error;}
 finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
