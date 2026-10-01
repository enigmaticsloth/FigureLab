// Generated fixtures only. The runner reloads this suite with the same isolated
// store so startup is exercised with real IndexedDB and legacy backups present.
(async () => {
  const post=value=>window.webkit.messageHandlers.testResult.postMessage(value);
  const check=(ok,message)=>{if(!ok)throw new Error(message);post({log:'PASS: '+message});};
  const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
  const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const fail=async(fn,fragment)=>{
    let error;try{await fn();}catch(e){error=e;}
    check(error && error.message.includes(fragment),'Rejects '+fragment);
  };
  const save=async(file,blob)=>{
    const base64=await new Promise(resolve=>{const r=new FileReader();r.onload=()=>resolve(r.result.split(',')[1]);r.readAsDataURL(blob);});
    post({file,base64});
  };
  const normalized=data=>data.tabs.map(t=>({name:t.name,doc:{...t.doc,shapes:t.doc.shapes.map(s=>{
    const copy={...s};delete copy.id;delete copy.group;
    if(copy.asset)copy.asset=data.assets[copy.asset];return copy;
  })}}));
  try{
    await pause(200);
    check(autosaveReady && tabs.length===1 && !doc.shapes.length && !Object.keys(assets).length,'Launch starts with one empty canvas and no old images');
    const stage=localStorage.getItem('project-test-stage');
    if(stage==='indexeddb'){
      // Just waiting, zooming, or rendering the empty page must preserve backup.
      view.z*=1.2;render();await pause(1300);
      const data=await readAutosave();
      check(data?.tabs[0].name==='Saved session' && data.tabs[0].doc.shapes[0].text==='復原測試','Blank startup does not overwrite previous IndexedDB work');
      check(await tryRestoreAutosave(),'Manual recovery opens IndexedDB backup');
      check(tabs.length===1 && doc.shapes[0].text==='復原測試','Recovery replaces only the untouched launch tab');
      clearTimeout(saveTimer);autosaveReady=false;
      await new Promise((resolve,reject)=>{
        const tx=autosaveDBPromise.then(db=>{
          const transaction=db.transaction('state','readwrite');transaction.objectStore('state').clear();
          transaction.oncomplete=resolve;transaction.onerror=()=>reject(transaction.error);
        });tx.catch(reject);
      });
      localStorage.setItem('figurelab-autosave',JSON.stringify({doc:{w:100,h:100,ppi:300,bg:'#fff',shapes:[
        {id:'legacy',type:'rect',x:5,y:5,w:30,h:30,fill:'#f00',stroke:'#000',sw:1,opacity:1}
      ]},assets:{}}));
      localStorage.setItem('project-test-stage','legacy');location.reload();return;
    }
    if(stage==='legacy'){
      await pause(1100);
      check(!(await readSaved(await autosaveDB(),'session')),'Launch does not create a blank backup over legacy storage');
      check(await tryRestoreAutosave(),'Legacy localStorage backup remains manually recoverable');
      check(doc.shapes[0].type==='rect','Legacy backup restores editable shape, not pixels');
      post({passed:true});return;
    }
    const canvas=document.createElement('canvas');canvas.width=400;canvas.height=320;
    const ctx=canvas.getContext('2d');ctx.fillStyle='#1a67c9';ctx.fillRect(0,0,400,320);
    ctx.fillStyle='#ed5236';ctx.fillRect(200,0,200,320);
    const source=canvas.toDataURL('image/png');
    const text={id:'text',type:'text',x:10,y:105,w:200,h:30,size:19,family:'sans',bold:true,italic:false,color:'#222',text:'中文 All stages',opacity:1};
    const image={id:'image',type:'image',asset:'original',x:10,y:10,w:100,h:80,rot:0,opacity:1,group:'panel'};
    const fixture={v:2,activeTab:1,assets:{original:source},tabs:[
      {name:'第一頁',doc:{w:200,h:160,ppi:300,bg:'#ffffff',shapes:[{...image}]}},
      {name:'預覽頁',doc:{w:320,h:240,ppi:300,bg:'#ffffff',shapes:[{...image},{...text,group:'panel'},
        {...image,id:'hidden',hidden:true,x:180,group:undefined}]}}
    ]};
    openProjectData(fixture);
    check(tabs.length===2 && activeTab===1,'Open replaces launch page and restores all tabs and active tab');
    const ts=doc.shapes.find(s=>s.type==='text');startTextEdit(ts.id);txtEdit.value='中文 All stages 空格後';
    txtEdit.dispatchEvent(new Event('input',{bubbles:true}));
    const payload=projectSnapshot();
    check(!editingTextId && payload.tabs[1].doc.shapes[1].text==='中文 All stages 空格後','Saving commits in-progress text including spaces and Unicode');
    $('expWidth').value='5';$('expDpi').value='150';$('expDetail').checked=false;
    const pending=createProjectFile(payload);
    ts.text='Changed after save started';switchTab(0);
    const blob=await pending, bytes=await blobBytes(blob);
    const decoded=await readProjectFile(new File([blob],'預覽頁.sloth',{type:'application/x-figurelab-sloth'}));
    check(equal(decoded,payload),'PNG round-trip preserves all tabs, originals, groups, hidden layers, Unicode and active page');
    const dv=new DataView(bytes.buffer);
    check(dv.getUint32(16)===1280 && dv.getUint32(20)===960,'Preview keeps source detail and ignores unrelated export settings');
    const chunks=pngChunks(bytes), custom=chunks.find(c=>c.type==='flAB');
    check(custom && bytes[custom.dataStart+PROJECT_MAGIC.length+1]===1,'Project metadata uses compressed private PNG chunk');
    const url=URL.createObjectURL(blob), im=await new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=reject;i.src=url;});
    canvas.width=im.naturalWidth;canvas.height=im.naturalHeight;ctx.drawImage(im,0,0);URL.revokeObjectURL(url);
    check(equal([...ctx.getImageData(60,60,1,1).data],[26,103,201,255]),'PNG remains independently decodable with the expected preview pixels');
    await save('editable-project.sloth',blob);
    check(equal(await readProjectFile(new File([blob],'older.figurelab.png',{type:'image/png'})),payload),'Previous .figurelab.png projects remain readable');
    const initial=projectSnapshot(), before=clone(initial);
    openProjectData(decoded);
    check(tabs.length===4 && activeTab===3,'Opening a project appends all pages without replacing current work');
    const combined=projectSnapshot();
    check(equal(normalized(combined).slice(0,2),normalized(before)),'Opening does not mutate any existing tab or image');
    check(equal(normalized(combined).slice(2),normalized(payload)),'Opened project restores editable geometry and original pixels');
    check(new Set(tabs.flatMap(t=>t.doc.shapes.map(s=>s.id))).size===tabs.flatMap(t=>t.doc.shapes).length,'All opened objects get collision-free IDs');
    check(doc.shapes[0].group===doc.shapes[1].group && doc.shapes[0].asset!==tabs[0].doc.shapes[0].asset,'Group relationships survive while asset IDs are isolated');
    const plainParts=[bytes.subarray(0,8),...chunks.filter(c=>c.type!=='flAB').map(c=>bytes.subarray(c.start,c.end))];
    const plain=new Blob(plainParts,{type:'image/png'});
    await fail(()=>readProjectFile(plain),'一般 PNG');
    const damaged=bytes.slice();damaged[custom.dataStart+15]^=1;
    await fail(()=>readProjectFile(new Blob([damaged])),'檢查碼');
    await fail(()=>readProjectFile(new Blob([bytes.subarray(0,-8)])),'不完整');
    await fail(()=>openProjectData({v:2,tabs:[{doc:{w:0,h:1,shapes:[]}}]}),'畫布資料');
    await fail(()=>openProjectData({...fixture,assets:{}}),'缺少原圖');
    await fail(()=>openProjectData({doc:{w:100,h:100,shapes:[{type:'path'}]}}),'座標');
    check(tabs.length===4,'Invalid files do not mutate the workspace');
    const compressor=window.CompressionStream;
    let raw;
    try{window.CompressionStream=undefined;raw=await projectPNG(await blobBytes(plain),payload);}
    finally{window.CompressionStream=compressor;}
    check(equal(await readProjectFile(raw),payload),'Uncompressed fallback is also lossless');
    const legacy=await readProjectFile(new Blob([JSON.stringify(fixture)],{type:'application/json'}));
    check(equal(legacy,fixture),'Old v2 JSON remains readable');
    openProjectData({doc:fixture.tabs[0].doc,assets:fixture.assets},'舊版單頁');
    check(tabs.at(-1).name==='舊版單頁' && doc.shapes.length===1,'Old single-document JSON remains editable');

    // Exercise the actual Save button, including its async/finally path.
    let downloaded;const originalDownload=download;
    download=(name,blob)=>{downloaded={name,blob};};
    try{
      $('btnSave').click();
      for(let i=0;i<200 && !downloaded;i++)await pause(50);
      check(downloaded?.name.endsWith('.sloth') && downloaded.blob.type==='application/x-figurelab-sloth' && !$('btnSave').disabled,'Save button emits a .sloth project with its own MIME type and re-enables itself');
      check((await readProjectFile(downloaded.blob)).tabs.length===5,'Save button includes every open tab');
    }finally{download=originalDownload;}

    const inputFiles=new DataTransfer();
    inputFiles.items.add(new File([blob],'renamed.png',{type:'image/png'}));
    $('fileProj').files=inputFiles.files;$('fileProj').dispatchEvent(new Event('change'));
    for(let i=0;i<100 && tabs.length===5;i++)await pause(20);
    check(tabs.length===7 && doc.shapes.some(s=>s.type==='text'),'Open file input detects project data even after the PNG is renamed');
    const dropped=new DataTransfer();dropped.items.add(new File([blob],'drop.sloth',{type:''}));
    $('stage').dispatchEvent(new DragEvent('drop',{dataTransfer:dropped,clientX:300,clientY:300}));
    for(let i=0;i<100 && tabs.length===7;i++)await pause(20);
    check(tabs.length===9 && doc.shapes.some(s=>s.type==='text'),'Dropping a .sloth project with no MIME type restores layers instead of flattening the image');
    const nativeData=await new Promise(resolve=>{const r=new FileReader();r.onload=()=>resolve(r.result.split(',')[1]);r.readAsDataURL(blob);});
    check(await window.flOpenProject(nativeData,"測試 'quoted' 檔名.sloth"),'Native Finder-open bridge accepts project bytes');
    check(tabs.length===11 && equal(normalized(projectSnapshot()).slice(-2),normalized(payload)),'Finder-open bridge restores the complete editable project');

    const transparent=clone(payload);transparent.tabs[1].doc.transparent=true;
    const transparentBlob=await createProjectFile(transparent);
    const transparentURL=URL.createObjectURL(transparentBlob);
    const transparentImage=await new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=reject;i.src=transparentURL;});
    ctx.clearRect(0,0,canvas.width,canvas.height);ctx.drawImage(transparentImage,0,0);URL.revokeObjectURL(transparentURL);
    check(ctx.getImageData(1200,900,1,1).data[3]===0,'Project PNG preserves a transparent canvas background');
    const empty={v:2,activeTab:0,tabs:[{name:'Blank',doc:{w:100,h:80,ppi:300,bg:'#ffffff',shapes:[]}}],assets:{}};
    check(equal(await readProjectFile(await createProjectFile(empty)),empty),'Blank documents can also be saved and reopened');

    // Seed a real previous session, then test startup after a full page reload.
    clearTimeout(saveTimer);
    doc={w:320,h:240,ppi:300,bg:'#fff',shapes:[{...text,text:'復原測試'}]};
    tabs=[{id:'backup',name:'Saved session',doc,view:{x:0,y:0,z:1},sel:[],undoStack:[],redoStack:[]}];
    activeTab=0;assets={};sel=[];undoStack=[];redoStack=[];render();scheduleAutosave();await pause(1300);
    check((await readSaved(await autosaveDB(),'session'))?.tabs[0].name==='Saved session','Edited work still autosaves');
    localStorage.setItem('project-test-stage','indexeddb');location.reload();
  }catch(error){post({log:'FAIL: '+error.message+'\n'+error.stack,passed:false});}
})();
