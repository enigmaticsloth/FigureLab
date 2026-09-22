(async () => {
  const post = value => window.webkit.messageHandlers.testResult.postMessage(value);
  const check = (value, message) => { if(!value) throw new Error(message); post({log:'PASS: '+message}); };
  const pause = ms => new Promise(resolve => setTimeout(resolve,ms));
  const frame = () => new Promise(resolve => requestAnimationFrame(resolve));
  const save = async (file,blob) => {
    const base64 = await new Promise(resolve => { const r=new FileReader(); r.onload=()=>resolve(r.result.split(',')[1]); r.readAsDataURL(blob); });
    post({file,base64});
  };
  try {
    await pause(150);
    const data=window.testProject;
    assets=data.assets;
    doc=clone(data.tabs[data.activeTab || 0].doc);
    tabs=[{id:'regression',name:'Regression fixture',doc,view:{x:0,y:0,z:1},sel:[],undoStack:[],redoStack:[]}];
    activeTab=0; sel=[]; imgCache={}; undoStack=[]; redoStack=[];
    await Promise.all(doc.shapes.filter(s=>s.type==='image').map(s=>loadAsset(s.asset)));
    await pause(500);
    fitView(); syncPanel();
    const originalDoc=clone(doc);
    const sources=doc.shapes.filter(s=>s.type==='image');
    check(sources.every(s=>imgCache[s.asset]?.el), 'All original PNG/TIFF assets decode in WebKit');

    const textShape=doc.shapes.find(s=>s.type==='text');
    sel=[textShape.id]; startTextEdit(textShape.id); await pause(20);
    txtEdit.value='All '; txtEdit.dispatchEvent(new Event('input',{bubbles:true}));
    txtEdit.dispatchEvent(new KeyboardEvent('keydown',{key:' ',bubbles:true}));
    txtEdit.dispatchEvent(new KeyboardEvent('keyup',{key:' ',bubbles:true}));
    check(editingTextId===textShape.id && txtEdit.style.display==='block', 'Typing and releasing Space keeps text editing open');
    txtEdit.value+='stages 中文';
    txtEdit.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',isComposing:true,bubbles:true,metaKey:true}));
    check(editingTextId===textShape.id, 'IME composition does not commit the text editor');
    commitTextEdit(); check(textShape.text==='All stages 中文','Text after the space is committed intact');
    undo(); check(byId(textShape.id).text===originalDoc.shapes.find(s=>s.id===textShape.id).text,'Text edit undo restores previous content');

    const nodes=[...shapesLayer.children];
    let detached=0;
    const observer=new MutationObserver(records=>{ detached+=records.reduce((n,r)=>n+r.removedNodes.length,0); });
    observer.observe(shapesLayer,{childList:true});
    const moved=byId(sources[0].id), times=[];
    sel=[moved.id]; render();
    for(let i=0;i<40;i++){
      await frame(); const start=performance.now(); moved.x+=.25; render(); times.push(performance.now()-start);
    }
    const mutations=observer.takeRecords(); observer.disconnect();
    check(nodes.every(n=>n.isConnected && n.parentNode===shapesLayer),'Dragging preserves all SVG shape nodes');
    check(!detached && !mutations.some(r=>r.removedNodes.length),'Dragging does not detach/reinsert SVG shape nodes');
    times.sort((a,b)=>a-b);
    post({log:JSON.stringify({renderMsMedian:times[20],renderMsP95:times[38]})});

    doc=clone(originalDoc); sel=sources.map(s=>s.id); render(); syncPanel();
    const b=boundsOf(sel), orig=Object.fromEntries(sel.map(id=>[id,clone(byId(id))]));
    doGroupResize({handle:'se',origBounds:b,orig},{x:b.x+b.w*1.25,y:b.y+b.h*1.25},false,false);
    check(sel.every(id=>Math.abs(byId(id).w/byId(id).h-orig[id].w/orig[id].h)<1e-8),'Multi-selection aspect ratio regression');

    doc=clone(originalDoc); sel=[]; render(); syncPanel();
    $('expDpi').value='300'; $('expDetail').checked=false;
    check(exportPixels().w===1024,'Exact 300 ppi mode still matches the document print size');
    $('expWidth').value='180';
    check(exportPixels().w===2126,'Custom 180 mm at 300 ppi produces 2126 pixels');
    $('expWidth').value=''; $('expDetail').checked=true;
    const px=exportPixels();
    check(px.w>6000 && px.w*px.h<=64e6+20000,'Detail mode increases real pixel dimensions within the automatic limit');
    post({log:JSON.stringify({exportPixels:px,sourceDimensions:sources.map(s=>({name:s.name,w:imgCache[s.asset].w,h:imgCache[s.asset].h}))})});
    const svgExport=exportSVGString(false);
    check(!svgExport.includes('blob:') && svgExport.includes(assets[sources[0].asset]),'SVG export embeds originals, never display previews');
    const {cnv,ctx,w,h,dpi}=await renderRaster(false);
    check(w===px.w && h===px.h && dpi===px.dpi,'Raster export uses actual detail-mode size and ppi');
    const pngBlob=await new Promise(resolve=>cnv.toBlob(resolve,'image/png'));
    const png=pngWithDPI(await blobBytes(pngBlob),dpi);
    await save('Fig.1-high-resolution.png',new Blob([png],{type:'image/png'}));
    const rgba=ctx.getImageData(0,0,w,h).data;
    const tif=await encodeTIFF(rgba,w,h,dpi,false);
    await save('Fig.1-high-resolution.tif',new Blob([tif],{type:'image/tiff'}));
    cnv.width=cnv.height=1;

    scheduleAutosave(); await pause(1800);
    const stored=await readSaved(await autosaveDB(),'session');
    check(stored?.assetIds.length===sources.length,'20 MB project autosaves without localStorage quota failure');
    const expected=JSON.stringify(doc);
    doc={w:10,h:10,shapes:[]}; assets={}; tabs=[];
    check(await tryRestoreAutosave(),'IndexedDB autosave restores');
    check(JSON.stringify(doc)===expected && Object.keys(assets).length===sources.length,'Restored layout and all source assets match');
    post({passed:true});
  } catch(error) { post({log:'FAIL: '+error.message+'\n'+error.stack,passed:false}); }
})();
