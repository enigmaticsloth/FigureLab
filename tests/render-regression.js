(async () => {
  const post=value=>window.webkit.messageHandlers.testResult.postMessage(value);
  const check=(ok,message)=>{if(!ok)throw new Error(message);post({log:'PASS: '+message})};
  const load=src=>new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>resolve(im);im.onerror=reject;im.src=src;});
  try {
    await new Promise(r=>setTimeout(r,150));
    $('expDetail').checked=false; $('expDpi').value='300'; $('expWidth').value='';
    const source=document.createElement('canvas');source.width=80;source.height=60;
    const sc=source.getContext('2d');sc.fillStyle='#dc472a';sc.fillRect(0,0,40,60);sc.fillStyle='#417ac4';sc.fillRect(40,0,40,60);
    assets={fixture:source.toDataURL('image/png')};imgCache={};
    const style={opacity:.8,stroke:'#16409d',sw:3,dash:'dash',dl:3.2,dg:2.4,fill:'#cfe0ff',a1:true,a2:true,as:1.2};
    const fixtures=[
      {type:'image',x:25,y:20,w:120,h:90,rot:25,asset:'fixture'},
      {type:'rect',x:30,y:30,w:130,h:80,rx:18,rot:30},
      {type:'ellipse',x:30,y:30,w:130,h:80,rot:30},
      {type:'line',x1:35,y1:30,x2:160,y2:110},
      {type:'path',pts:[{x:20,y:80},{x:80,y:20},{x:135,y:80},{x:160,y:40}],noFill:true},
      {type:'path',pts:[{x:30,y:30,k:1},{x:150,y:30,k:1},{x:130,y:100,k:1}],closed:true},
      {type:'text',x:25,y:35,w:140,h:40,size:22,family:'sans',bold:true,italic:true,color:'#2a2a2a',text:'All stages\n中文',rot:15}
    ];
    for(const [i,shape] of fixtures.entries()){
      doc={w:200,h:150,ppi:300,bg:'#ffffff',transparent:true,shapes:[{id:'fixture'+i,...style,...shape}]};
      sel=[];render();
      const actual=await renderRaster(true);
      if(shape.type==='image'){
        const p=actual.ctx.getImageData(55,52,1,1).data;
        check(p[0]>180 && p[1]<100 && Math.abs(p[3]-204)<=1,'Rotated original image exports with the correct colour and opacity');
        continue; // Nested raster images in SVG-as-image can be blank in WebKit.
      }
      const svgURL=URL.createObjectURL(new Blob([exportSVGString(true,200,150)],{type:'image/svg+xml'}));
      const im=await load(svgURL),expected=document.createElement('canvas');expected.width=200;expected.height=150;
      const ec=expected.getContext('2d');ec.drawImage(im,0,0);URL.revokeObjectURL(svgURL);
      const a=actual.ctx.getImageData(0,0,200,150).data,b=ec.getImageData(0,0,200,150).data;
      let diff=0,ink=0;
      for(let p=0;p<a.length;p+=4){for(let k=0;k<3;k++)diff+=Math.abs(a[p+k]*a[p+3]/255-b[p+k]*b[p+3]/255);diff+=Math.abs(a[p+3]-b[p+3]);if(a[p+3])ink++;}
      const mean=diff/a.length;
      check(ink>100 && mean<3,shape.type+' canvas export matches SVG appearance (mean error '+mean.toFixed(3)+')');
    }
    doc={w:200,h:150,ppi:300,bg:'#ffffff',transparent:true,shapes:[
      {id:'i',type:'image',asset:'fixture',x:0,y:0,w:80,h:60,opacity:1},
      {id:'r',...style,type:'rect',x:10,y:10,w:30,h:30,opacity:1,dash:'solid',fill:'#00ff00'},
      {id:'hidden',...style,type:'rect',x:0,y:0,w:80,h:60,hidden:true,fill:'#000000'}
    ]};
    const result=await renderRaster(true);
    const pixel=(x,y)=>[...result.ctx.getImageData(x,y,1,1).data];
    check(JSON.stringify(pixel(20,20))==='[0,255,0,255]','Export preserves layer order and skips hidden shapes');
    check(pixel(190,140)[3]===0,'Transparent export background is transparent');
    const opaque=await renderRaster(false,true);
    check(opaque.ctx.getImageData(190,140,1,1).data[3]===255,'JPEG mode flattens transparent documents onto the background');

    source.width=6001;source.height=2;source.getContext('2d').fillRect(0,0,6001,2);
    const blob=await new Promise(resolve=>source.toBlob(resolve,'image/png'));
    doc={w:100,h:100,ppi:300,bg:'#ffffff',shapes:[]};
    await importImageFiles([new File([blob],'large-original.png',{type:'image/png'})]);
    check(doc.w===6001 && imgCache[doc.shapes[0].asset].w===6001,'Imports retain originals beyond the former 5000-pixel limit');
    post({passed:true});
  }catch(error){post({log:'FAIL: '+error.message+'\n'+error.stack,passed:false})}
})();
