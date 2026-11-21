/* A responsive, demand-rendered WebGL room. All coordinates use Y up, Z toward the viewer. */
(() => {
  "use strict";
  const stage = document.getElementById("room-stage");
  const canvas = document.getElementById("room-canvas");
  if (!stage || !canvas) return;
  const clamp = n => Math.max(0, Math.min(1, n));
  const mix = (a, b, t) => a + (b - a) * t;
  function ramp(n, a, b) {
    const t = clamp((n-a)/(b-a));
    return t*t*(3-2*t);
  }
  const add = (a,b) => a.map((n,i) => n+b[i]);
  const sub = (a,b) => a.map((n,i) => n-b[i]);
  const scale = (a,s) => a.map(n => n*s);
  const lerp = (a,b,t) => a.map((n,i) => mix(n,b[i],t));
  const dot = (a,b) => a.reduce((n,v,i) => n+v*b[i],0);
  const normal = a => scale(a,1/(Math.hypot(...a)||1));
  const cross = (a,b) => [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
  const rad = Math.PI / 180;
  const tau = Math.PI * 2;
  function basis(yaw, pitch, roll) {
    const y=yaw*rad, p=pitch*rad, r=roll*rad;
    const look=[Math.sin(y)*Math.cos(p),Math.sin(p),Math.cos(y)*Math.cos(p)];
    const right=normal(cross([0,1,0],look)), up=cross(look,right);
    return [add(scale(right, Math.cos(r)),scale(up, Math.sin(r))),
      add(scale(up,Math.cos(r)),scale(right,-Math.sin(r))), look];
  }
  const straight = basis(0,0,0);
  const opening = basis(0,9,0);
  const closing = basis(-43,13,-15);
  let progress=0, override=null, frame=0, draw=null, renderer="poster", hitAreas=[];
  const lit = () => override === null ? ramp(progress,.28,.36) : Number(override);
  function schedule() {
    if (!frame && draw) frame=requestAnimationFrame(() => {frame=0; draw();});
  }
  function setState(position, manual) {
    const next=clamp(Number(position)||0);
    const light=typeof manual === "boolean" ? manual : null;
    const changed=next!==progress || light!==override;
    progress=next; override=light;
    stage.dataset.fallback=lit()>=.5 ? "on" : "off";
    if (changed) schedule();
  }
  function hit(event) {
    if (progress>.62) return false;
    const b=canvas.getBoundingClientRect(), x=(event.clientX-b.left)/b.width, y=(event.clientY-b.top)/b.height;
    return hitAreas.some(p => x>p.x && x<p.x+p.w && y>p.y && y<p.y+p.h);
  }
  canvas.addEventListener("click", e => {
    if (hit(e)) window.dispatchEvent(new CustomEvent("nultra-lamp-toggle"));
  });
  canvas.addEventListener("pointermove", e => {canvas.style.cursor=hit(e) ? "pointer" : "";}, {passive:true});
  window.NultraRoom={setState,getState:() => ({progress,lit:lit(),renderer,hitAreas:hitAreas.map(a=>({...a}))})};
  window.dispatchEvent(new CustomEvent("nultra-room-ready"));

  const vertex = `
    attribute vec3 aPos,aNorm;
    attribute vec2 aUV;
    uniform mat3 uModel,uView;
    uniform vec3 uOrigin,uFocus,uRest;
    uniform vec2 uHalf,uOffset;
    uniform float uScale,uPerspective,uRestScale;
    varying vec3 w,n,rest;
    varying vec2 uv;
    void main(){
      w=uOrigin+uModel*(aPos*uScale); n=uModel*aNorm; uv=aUV;
      rest=uRest+uModel*(aPos*uRestScale);
      vec3 view=uView*(w-uFocus);
      float projection=max(.25,1.-view.z*uPerspective/9.);
      gl_Position=vec4(view.xy/uHalf+uOffset*projection,-view.z*.12,projection);
    }`;
  const fragment = `
    precision highp float;
    varying vec3 w,n,rest;
    varying vec2 uv;
    uniform vec3 uColor,uLamp,uEye,uPlate;
    uniform vec2 uPixels;
    uniform float uType,uLit,uFade,uOpen,uDetail,uStudio,uBake,uMount,uCadScale;
    uniform sampler2D sHome,sOff,sOn,sDetail,sDarkRoom,sLightRoom;
    float hash(vec2 p){return fract(sin(dot(p,vec2(41.3,289.1)))*4317.23);}
    void main(){
      vec3 N=normalize(n), V=normalize(uEye-w), color=uColor;
      vec3 L=normalize(vec3(-3.8,4.2,4.6)), H=normalize(V+L);
      float key=max(0.,dot(N,L)), spec=0., sheen=0.;
      vec3 lampDelta=uLamp-w; float lightDist=dot(lampDelta,lampDelta);
      float lampI=uLit/(.65+lightDist);
      float lampN=max(0.,dot(N,normalize(lampDelta)));
      vec3 ambient=vec3(.39,.46,.47);
      float kind=uType;
      if(uBake>.5){
        // Parallax comes from the actual meshes. The paired path-traced atlases
        // store global illumination at each receiving surface point.
        float row=0., tile=.5;
        vec2 plane=vec2(rest.x+2.15,rest.y-1.)/13.6;
        if(uBake>1.5){
          vec3 d=rest-vec3(.22,.86,0.);
          row=.9375;tile=.5625;
          plane=vec2(dot(d,vec3(.9816272,0.,.1908090)),dot(d,vec3(.029849,.98768834,-.153560)))/3.82;
        }else if(kind>.5){
          if(kind<1.5&&N.y>.5){row=.5;tile=.1875;plane.y=(.17-rest.z)/13.6;}
          else{row=.6875;tile=.25;plane.y=(rest.y+.76)/13.6;}
        }
        vec2 q=.5+vec2(plane.x,plane.y/tile);
        q=clamp(q,vec2(.001),vec2(.999));
        q.y=1.-(row+(1.-q.y)*tile)/1.5;
        vec3 dark=texture2D(sDarkRoom,q).rgb, light=texture2D(sLightRoom,q).rgb;
        vec3 radiance=mix(dark,light,uLit);
        if(kind<.5){
          vec2 margin=abs(w.xy-uPlate.xy+vec2(.024,.031))-vec2(34.,55.)*uCadScale;
          float shadow=1.-smoothstep(-.013,.065,length(max(margin,vec2(0.)))+min(max(margin.x,margin.y),0.));
          radiance*=1.-.50*shadow*uMount;
        }
        gl_FragColor=vec4(radiance,uFade);return;
      }
      vec3 R=reflect(-V,N);
      float lampEdge=exp(-19.*(1.-max(0.,dot(R,normalize(uLamp-w)))))*uLit;
      if(kind<3.5){ // The titanium side rail catches the window and the live lamp.
        float strip=exp(-abs(R.x+.59)*6.)+.74*exp(-abs(R.x-.77)*15.);
        float horizon=smoothstep(-.16,.23,R.y);
        color*=.22+.42*horizon+strip*1.12;
        color+=vec3(.23,.23,.212)*smoothstep(.62,.96,R.y)+vec3(.47,.32,.16)*lampEdge;
        spec=.70; sheen=81.;
      } else if(kind<5.5){ // Screen light beneath the cover glass.
        vec3 home=texture2D(sHome,uv).rgb;
        vec2 anchor=vec2(.50,.474);
        float zoom=mix(.11,1.,uOpen);
        vec2 inner=(uv-anchor)/zoom+anchor;
        vec3 app=mix(texture2D(sOff,inner).rgb,texture2D(sOn,inner).rgb,uLit);
        vec2 sheet=inner+vec2(0.,1.-uDetail);
        app=mix(app,texture2D(sDetail,sheet).rgb,step(sheet.y,1.)*step(.001,uDetail)*uLit);
        float radius=mix(.082,.030,uOpen);
        vec2 inset=abs((inner-.5)*vec2(.462,1.))-vec2(.231,.5)+radius;
        float dist=length(max(inset,0.))+min(max(inset.x,inset.y),0.)-radius;
        float mask=1.-smoothstep(-.003,.003,dist);
        vec3 screen=mix(home,app,mask*smoothstep(0.,.4,uOpen));
        float glass=.018+.050*pow(1.-abs(dot(N,V)),2.5);
        float softbox=.17+.54*smoothstep(-.5,1.2,uv.x+uv.y*.68);
        screen=mix(screen,vec3(.65,.72,.73)*softbox,glass)+vec3(.15,.102,.055)*lampEdge;
        gl_FragColor=vec4(screen,uFade);return;
      } else {spec=.24;sheen=38.;} // Porcelain switch and satin polymer.
      vec3 illum=ambient+vec3(.72,.67,.57)*key+vec3(.11,.16,.17)*max(0.,N.y);
      illum+=vec3(.98,.55,.24)*lampI*(.10+.75*lampN);
      vec3 result=color*illum+vec3(.98,.86,.70)*spec*pow(max(0.,dot(N,H)),sheen+1.);
      if(kind>5.5 && kind<6.5){
        vec3 studio=color*(.81+.23*key)+.10*pow(max(0.,dot(N,H)),22.);
        result=mix(result,studio,uStudio);
      }
      vec2 pixel=gl_FragCoord.xy/uPixels;
      float vignette=1.-.15*dot((pixel-.53)*1.25,(pixel-.53)*1.25);
      result*=mix(vignette,1.,uStudio);
      result+=(hash(gl_FragCoord.xy)-.5)*.006;
      gl_FragColor=vec4(result,uFade);
    }`;

  // Geometry is created once. A vertex is position, normal, and UV.
  const vertexAt=(p,n,uv=[0,0]) => [...p,...n,...uv];
  function box(size) {
    const h=size.map(n=>n/2), vertices=[], indices=[];
    for(let axis=0;axis<3;axis++) for(const side of [-1,1]) {
      const a=(axis+1)%3,b=(axis+2)%3, start=vertices.length/8, normal=[0,0,0];
      normal[axis]=side;
      for(const [x,y] of [[-1,-1],[1,-1],[1,1],[-1,1]]) {
        const p=[0,0,0];p[axis]=side*h[axis];p[a]=x*h[a];p[b]=y*h[b];
        vertices.push(...vertexAt(p,normal));
      }
      indices.push(start,start+1,start+2,start,start+2,start+3);
    }
    return {vertices,indices};
  }
  function lathe(profile,steps=80) {
    const vertices=[],indices=[];
    for(let j=0;j<profile.length;j++){
      const [r,y]=profile[j], a=profile[Math.max(0,j-1)], b=profile[Math.min(profile.length-1,j+1)];
      for(let i=0;i<=steps;i++) {
        const t=i/steps*tau, c=Math.cos(t),s=Math.sin(t);
        const n=normal([(b[1]-a[1])*c,a[0]-b[0],(b[1]-a[1])*s]);
        vertices.push(...vertexAt([r*c,y,r*s],n,[i/steps,j/(profile.length-1)]));
        if(i<steps && j<profile.length-1){
          const k=j*(steps+1)+i;indices.push(k,k+steps+1,k+1,k+1,k+steps+1,k+steps+2);
        }
      }
    }
    return {vertices,indices};
  }
  function phoneLayer(w,h,r,sections,withFace) {
    const vertices=[], indices=[], ring=[];
    const sides=8, count=(sides+1)*4;
    for(let corner=0;corner<4;corner++){
      const cx=[1,-1,-1,1][corner]*(w/2-r),cy=[1,1,-1,-1][corner]*(h/2-r);
      for(let k=0;k<=sides;k++){
        const t=(corner+k/sides)*Math.PI/2;
        ring.push([cx,cy,Math.cos(t),Math.sin(t)]);
      }
    }
    for(let j=0;j<sections.length;j++){
      const [z,inset,front]=sections[j];
      ring.forEach(([cx,cy,x,y],k)=>{
        const p=[cx+(r-inset)*x,cy+(r-inset)*y,z];
        vertices.push(...vertexAt(p,normal([x*(1-front),y*(1-front),front]),[p[0]/w+.5,p[1]/h+.5]));
        if(j<sections.length-1){
          const i=j*count+k,next=j*count+(k+1)%count;
          indices.push(i,next,i+count,next,next+count,i+count);
        }
      });
    }
    if(withFace){
      const first=(sections.length-1)*count, mid=vertices.length/8;
      vertices.push(...vertexAt([0,0,sections[sections.length-1][0]],[0,0,1],[.5,.5]));
      for(let k=0;k<count;k++)indices.push(mid,first+k,first+(k+1)%count);
    }
    return {vertices,indices};
  }
  function decodeCAD(bytes) {
    const view=new DataView(bytes), decoded=[];
    if(view.getUint32(0)!==0x4e435231)throw new Error("Invalid enclosure geometry");
    let cursor=4;
    for(let part=0;part<4;part++){
      const n=view.getUint32(cursor,true), nf=view.getUint32(cursor+4,true);cursor+=8;
      const positions=Array.from(new Int16Array(bytes,cursor,n*3),v=>v/100);cursor+=n*6;
      const source=new Uint16Array(bytes,cursor,nf);cursor+=nf*2;
      const vertices=[],indices=[];
      // CAD faces have intentional sharp junctions. Keep their geometric normals
      // as in the offline renderer; do not average across the molded rim.
      for(let i=0;i<nf;i+=3){
        const points=[0,1,2].map(j=>positions.slice(source[i+j]*3,source[i+j]*3+3));
        const N=normal(cross(sub(points[1],points[0]),sub(points[2],points[0])));
        for(const p of points){indices.push(vertices.length/8);vertices.push(...vertexAt(p,N));}
      }
      decoded.push({vertices,indices});
    }
    return decoded;
  }
  function imageAt(url) {
    return new Promise((resolve,reject)=>{
      const im=new Image(); im.onload=()=>resolve(im);im.onerror=reject;im.src=url;
    });
  }
  function homeArtwork(icon) {
    const pic=document.createElement("canvas");pic.width=562;pic.height=1218;
    const c=pic.getContext("2d");
    // Smooth, overlapping graphite folds on the dedicated device's home screen.
    const paper=document.createElement("canvas");paper.width=188;paper.height=406;
    const wc=paper.getContext("2d"),art=wc.createImageData(paper.width,paper.height);
    for(let y=0;y<paper.height;y++)for(let x=0;x<paper.width;x++){
      const u=x/paper.width,v=y/paper.height, wave=.19+.20*Math.sin(u*3.0+.18)+.15*u;
      const cut=v-wave, second=v-(.51+.29*Math.cos(u*2.5-.35));
      const key=Math.exp(-Math.abs(cut)*10.5)*(cut>0?.9:.29);
      const rim=Math.exp(-Math.abs(cut)*160)*.23;
      const fold=Math.exp(-Math.abs(second)*12)*(second>0?.59:.18);
      const tone=key+fold+rim+.16*(1-v);
      const i=(y*paper.width+x)*4;
      art.data[i]=14+tone*74;art.data[i+1]=23+tone*83;art.data[i+2]=24+tone*73;art.data[i+3]=255;
    }
    wc.putImageData(art,0,0);c.drawImage(paper,0,0,562,1218);
    c.fillStyle="#f4f7ee";c.font="600 25px Arial";c.fillText("9:41",48,50);
    c.fillRect(486,34,29,12);c.fillRect(517,38,3,5);
    for(let i=0;i<4;i++) c.fillRect(451+i*6,46-(i+1)*3,4,(i+1)*3);
    const d=111,x=(562-d)/2,y=585;
    if(icon){c.save();c.beginPath();c.roundRect(x,y,d,d,24);c.clip();c.drawImage(icon,x,y,d,d);c.restore();}
    c.fillStyle="#fff";c.font="500 26px Arial";c.textAlign="center";c.fillText("Nultra",281,y+d+38);
    c.fillStyle="rgba(215,226,221,.13)";c.beginPath();c.roundRect(79,1025,404,107,35);c.fill();
    for(const [i,tint] of ["#45775d","#587d6b","#626d74"].entries()){
      const cx=157+i*124,cy=1078;c.fillStyle=tint;c.beginPath();c.roundRect(cx-33,cy-33,66,66,17);c.fill();
      c.strokeStyle="#eef1e8";c.fillStyle="#eef1e8";c.lineWidth=3.8;c.lineCap="round";c.lineJoin="round";
      c.beginPath();
      if(i===0){c.moveTo(cx-13,cy-14);c.quadraticCurveTo(cx-15,cy+6,cx+11,cy+15);c.lineTo(cx+16,cy+9);c.lineTo(cx+8,cy+4);c.lineTo(cx+4,cy+8);c.quadraticCurveTo(cx-3,cy+5,cx-8,cy-5);c.lineTo(cx-5,cy-9);c.lineTo(cx-9,cy-16);c.closePath();c.fill();}
      if(i===1){c.ellipse(cx,cy-1,17,12,0,0,tau);c.fill();c.beginPath();c.moveTo(cx-11,cy+6);c.lineTo(cx-15,cy+15);c.lineTo(cx-3,cy+10);c.fill();}
      if(i===2){c.roundRect(cx-17,cy-10,34,23,5);c.stroke();c.beginPath();c.arc(cx,cy+1,6,0,tau);c.stroke();}
    }
    c.fillStyle="rgba(255,255,255,.82)";c.beginPath();c.roundRect(190,1185,182,7,4);c.fill();
    return pic;
  }
  // A capped higher-resolution framebuffer avoids multisample edge seams in the
  // enclosure's thin coplanar CAD triangles, with one depth sample per pixel.
  const gl=canvas.getContext("webgl",{alpha:true,antialias:false,depth:true,premultipliedAlpha:false,powerPreference:"low-power",preserveDrawingBuffer:false});
  let posterCanvas, posterContext;
  const posters=new Map();
  function requestPoster(key,src) {
    if(!posters.has(key)){
      posters.set(key,null);
      imageAt(src).then(im=>{posters.set(key,im);schedule();}).catch(()=>{});
    }
    return posters.get(key);
  }
  function poster() {
    renderer="poster"; stage.dataset.renderer=renderer;
    const rect=stage.getBoundingClientRect(), w=rect.width,h=rect.height;
    if(!w||!h)return;
    const m=w<h, format=m?"tall":"wide";
    hitAreas=m?[{x:.069,y:.322,w:.53,h:.54},{x:.57,y:.422,w:.43,h:.297},{x:.524,y:.269,w:.16,h:.145}]
      :[{x:.399,y:.187,w:.218,h:.712},{x:.696,y:.240,w:.216,h:.468},{x:.625,y:.258,w:.067,h:.167}];
    if(!posterCanvas){
      posterCanvas=document.createElement("canvas");posterCanvas.className="room-poster-canvas";
      posterCanvas.setAttribute("aria-hidden","true");
      stage.insertBefore(posterCanvas,canvas);posterContext=posterCanvas.getContext("2d");
    }
    const context=posterContext;if(!context)return;
    const ratio=Math.min(1.4,window.devicePixelRatio||1,1440/w);
    if(posterCanvas.width!==Math.round(w*ratio)||posterCanvas.height!==Math.round(h*ratio)){
      posterCanvas.width=Math.round(w*ratio);posterCanvas.height=Math.round(h*ratio);
    }
    context.setTransform(ratio,0,0,ratio,0,0);context.clearRect(0,0,w,h);
    const roomImage=name=>requestPoster(name+format,"assets/room/"+name+"-"+format+".webp?v=3");
    const open=roomImage("open");
    if(!open)return;
    const app=override===null?ramp(progress,.055,.20):1,light=lit();
    const off=app>0 ? roomImage("off") : null;
    const on=light>0 ? roomImage("lit") : null;
    const detail=light>0&&progress>.375 ? roomImage("detail") : null;
    const surface=progress>.52 ? requestPoster("surface","assets/product/frames/000.webp") : null;
    const target=document.querySelector(".model-wrap")?.getBoundingClientRect();
    const plateX=(m?.603:.657)*w, plateY=.34*h;
    const targetW=target?.width||w*.74;
    const targetX=target?.width?target.left-rect.left+target.width/2:w*.65;
    const targetY=target?.height?target.top-rect.top+target.height/2:h*.5;
    const travel=ramp(progress,.47,.935), toSurface=surface?ramp(progress,.60,.89):0;
    const installedHeight=(m?.126:.152)*h;
    const finalHeight=targetW*(753/1056);
    const zoom=Math.exp(Math.log(Math.max(1,finalHeight/installedHeight))*travel);
    const centerX=mix(plateX,targetX,travel),centerY=mix(plateY,targetY,travel);
    context.save();
    context.translate(centerX,centerY);context.scale(zoom,zoom);context.translate(-plateX,-plateY);
    function plate(im,opacity){
      if(im&&opacity>0){context.globalAlpha=opacity;context.drawImage(im,0,0,w,h);}
    }
    plate(open,1-toSurface);plate(off,app*(1-toSurface));
    plate(on,light*(1-toSurface));plate(detail,ramp(progress,.39,.49)*light*(1-toSurface));
    context.restore();
    if(surface&&toSurface){
      const imageW=installedHeight*zoom*1056/753;
      context.globalAlpha=toSurface;
      context.drawImage(surface,centerX-imageW/2,centerY-imageW*864/2112,imageW,imageW*864/1056);
      context.globalAlpha=1;
    }
    stage.dataset.posterReady="";
  }
  window.addEventListener("resize",schedule,{passive:true});
  if(!gl||gl.getParameter(gl.MAX_TEXTURE_SIZE)<1920){draw=poster;poster();return;}
  function compile(kind,source){
    const shader=gl.createShader(kind);gl.shaderSource(shader,source);gl.compileShader(shader);
    if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(shader));
    return shader;
  }
  function start() {
    const program=gl.createProgram();
    for(const [kind,source] of [[gl.VERTEX_SHADER,vertex],[gl.FRAGMENT_SHADER,fragment]])gl.attachShader(program,compile(kind,source));
    gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(program));
    gl.useProgram(program);gl.enable(gl.DEPTH_TEST);gl.enable(gl.BLEND);gl.blendFuncSeparate(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA,gl.ONE,gl.ONE_MINUS_SRC_ALPHA);
    const names=["uModel","uView","uOrigin","uFocus","uHalf","uOffset","uScale","uPerspective","uColor","uLamp","uEye","uPlate","uType","uLit","uFade","uOpen","uDetail","uStudio","uPixels","uRest","uRestScale","uBake","uMount","uCadScale"];
    const uniforms=Object.fromEntries(names.map(key=>[key,gl.getUniformLocation(program,key)]));
    const attrs=["aPos","aNorm","aUV"].map(name=>gl.getAttribLocation(program,name));
    attrs.forEach(i=>gl.enableVertexAttribArray(i));
    const mat=(key,value)=>gl.uniformMatrix3fv(uniforms[key],false,value);
    const scalar=(key,value)=>gl.uniform1f(uniforms[key],value);
    const vec=(key,value)=>gl.uniform3fv(uniforms[key],value);
    const vec2=(key,value)=>gl.uniform2fv(uniforms[key],value);
    const library={};
    function mesh(name,{vertices,indices}) {
      if(vertices.length/8>65535) throw new Error("Room mesh exceeds unsigned short range");
      const verts=gl.createBuffer(),faces=gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER,verts);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(vertices),gl.STATIC_DRAW);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,faces);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,new Uint16Array(indices),gl.STATIC_DRAW);
      library[name]={verts,faces,count:indices.length};
    }
    function tex(unit,target,name){
      const tex=gl.createTexture();gl.activeTexture(gl.TEXTURE0+unit);gl.bindTexture(gl.TEXTURE_2D,tex);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,true);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,target);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      gl.uniform1i(gl.getUniformLocation(program,name),unit);
    }
    for(const [name,size] of [["volume",[.011,.123,.052]],["silent",[.012,.065,.050]],["power",[.013,.18,.051]]])
      mesh(name,box(size));
    const PW=.835,PH=1.75;
    mesh("body",phoneLayer(PW,PH,.121,[[-.068,.013,.16],[-.066,.003,.05],[-.057,0,0],[.030,0,0],[.041,.004,.3],[.045,.013,.75]],true));
    mesh("bezel",phoneLayer(PW-.015,PH-.015,.115,[[.045,.002,1],[.051,.009,1]],true));
    mesh("screen",phoneLayer(PW-.052,PH-.052,.094,[[.052,0,1]],true));
    mesh("notch",phoneLayer(.245,.057,.025,[[.053,0,1]],true));
    const colors={
      metal:[.445,.482,.464], bezel:[.034,.043,.043], notch:[.019,.025,.026],
      face:[.81,.825,.79], ink:[.105,.113,.102], carrier:[.32,.35,.33], shell:[.245,.270,.251]
    };
    let size, geometryReady=false, observer, furniture;
    function measure() {
      const rect=stage.getBoundingClientRect();
      if(!rect.width || !rect.height) return;
      const width=rect.width,height=rect.height, aspect=width/height;
      const target=stage.closest("section")?.querySelector(".model-wrap") || document.querySelector(".model-wrap");
      const end=target?.getBoundingClientRect();
      const endWidth=end?.width || Math.min(width*.65,height);
      const ox=end?.width ? ((end.left-rect.left+end.width/2)/width-.5)*2 : .2;
      const oy=end?.height ? 1-(end.top-rect.top+end.height/2)*2/height : 0;
      size={width,height,aspect,ox,oy,endWidth};
      const dpr=Math.min(Math.max(1.35,window.devicePixelRatio||1),1.55,1536/width,1280/height);
      const w=Math.max(1,Math.round(width*dpr)),h=Math.max(1,Math.round(height*dpr));
      if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h;gl.viewport(0,0,w,h);}
    }
    function paint() {
      if(!size||!geometryReady)return;
      const {aspect,ox,oy,endWidth,height}=size;
      const t=progress, narrow=1-ramp(aspect,.72,1.34), half=2.18;
      // Set projected positions in the wide shot; preserve depth and perspective
      // while keeping the three products distinct on narrow portrait screens.
      function at(x,y,z) {
        const v=(1-2*y)*half, c=opening[1][1], s=opening[2][1];
        const worldY=(v*(1-z*c/9)+z*s)/(c+v*s/9);
        return [(2*x-1)*half*aspect*(1-(worldY*s+z*c)/9),worldY,z];
      }
      const plate=at(mix(.657,.603,narrow),mix(.34,.34,narrow),0);
      const sizeLamp=mix(1.03,.65,narrow);
      const lamp=at(mix(.797,.78,narrow),mix(.70,.711,narrow),.074+.775*sizeLamp);
      const phone=at(mix(.505,.327,narrow),mix(.545,.593,narrow),2.45);
      const sizePhone=mix(1.20,.91,narrow);
      const sizeCAD=mix(.00565,.0048,narrow);
      const depart=ramp(t,.47,.95);
      const easeCamera=ramp(t,.47,.935);
      const basisNow=basis(-43*easeCamera,mix(9,13,easeCamera),-15*easeCamera);
      const [right,up,look]=basisNow;
      const cadCenter=add(scale(closing[0],10.05063),scale(closing[1],.32020));
      const dest=add(plate,scale(cadCenter,sizeCAD));
      const focus=lerp([0,0,0],dest,easeCamera);
      const slice=91.36181*sizeCAD*height/endWidth;
      const halfH=Math.exp(mix(Math.log(half),Math.log(slice),easeCamera));
      const offset=[ox*easeCamera,oy*easeCamera], perspective=1-easeCamera;
      const phoneBasis=basis(mix(-13,-44,depart),mix(3,8,depart),mix(-6,-27,depart));
      const currentPhone=add(phone,[-depart*(2+aspect),-.42*depart,1.4*depart]);
      const roomAlpha=1-ramp(t,.74,.94);
      const phoneAlpha=1-ramp(t,.59,.76);
      const atLamp=add(lamp,[0,1.16*sizeLamp,0]);
      const viewMatrix=[right[0],up[0],look[0],right[1],up[1],look[1],right[2],up[2],look[2]];
      scalar("uOpen",override===null?ramp(t,.055,.20):1);scalar("uDetail",ramp(t,.385,.48));scalar("uLit",lit());
      scalar("uMount",1-ramp(t,.47,.68));scalar("uCadScale",sizeCAD);
      scalar("uStudio",ramp(t,.72,.96));scalar("uPerspective",perspective);
      mat("uView",viewMatrix);vec2("uPixels",[canvas.width,canvas.height]);
      vec2("uHalf",[halfH*aspect,halfH]);vec2("uOffset",offset);
      vec("uFocus",focus);vec("uEye",add(focus,scale(look,9)));vec("uPlate",plate);vec("uLamp",atLamp);
      gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
      function drawMesh(name,pos,type,color,scaleFactor=1,axes=straight) {
        const item=library[name];if(!item)return;
        gl.bindBuffer(gl.ARRAY_BUFFER,item.verts);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,item.faces);
        attrs.forEach((attrib,i)=>gl.vertexAttribPointer(attrib,i===2?2:3,gl.FLOAT,false,32,[0,12,24][i]));
        mat("uModel",axes.flat());vec("uOrigin",pos);vec("uColor",colors[color]);
        scalar("uScale",scaleFactor);scalar("uType",type);
        gl.drawElements(gl.TRIANGLES,item.count,gl.UNSIGNED_SHORT,0);
      }
      function project(world){
        const q=sub(world,focus), f=Math.max(.25,1-dot(q,look)*perspective/9);
        return [.5+(dot(q,right)/(halfH*aspect*f)+offset[0])*.5,
          .5-(dot(q,up)/(halfH*f)+offset[1])*.5];
      }
      function region(corners){
        const xy=corners.map(project),xx=xy.map(p=>p[0]), yy=xy.map(p=>p[1]);
        return {x:Math.min(...xx)-.008,y:Math.min(...yy)-.008,w:Math.max(...xx)-Math.min(...xx)+.016,h:Math.max(...yy)-Math.min(...yy)+.016};
      }
      function place(parent,axes,offset,factor=1) {
        return offset.reduce((v,val,i)=>add(v,scale(axes[i],val*factor)),parent);
      }
      if(roomAlpha>.001){
        scalar("uFade",roomAlpha);
        for(const item of furniture){
          const origin=add(lamp,scale(item.pos,sizeLamp));
          if(item.name==="wall"||item.name==="end")origin[2]-=depart*1.12;
          vec("uRest",item.pos);scalar("uRestScale",item.scale);
          scalar("uBake",item.layer);
          const surface=item.name==="wall"||item.name==="end"?0:item.name==="stone"?1:2;
          drawMesh(item.name,origin,surface,"face",item.scale*sizeLamp,item.axes);
        }
      }
      scalar("uBake",0);
      if(phoneAlpha>.001){
        scalar("uFade",phoneAlpha);
        for(const [part,kind,color] of [["body",3,"metal"],["bezel",6,"bezel"],["screen",5,"bezel"]]){
          drawMesh(part,currentPhone,kind,color,sizePhone,phoneBasis);
        }
        const p=(x,y,z)=>place(currentPhone,phoneBasis,[x,y,z],sizePhone);
        drawMesh("notch",p(0,.831,0),6,"notch",sizePhone,phoneBasis);
        drawMesh("silent",p(-.419,.435,-.012),3,"metal",sizePhone,phoneBasis);
        for(const y of [.25,.095])drawMesh("volume",p(-.419,y,-.012),3,"metal",sizePhone,phoneBasis);
        drawMesh("power",p(.418,.183,-.012),3,"metal",sizePhone,phoneBasis);
      }
      scalar("uFade",1);
      gl.enable(gl.CULL_FACE);
      for(const [name,color] of [["cad2","carrier"],["cad3","shell"],["cad0","face"],["cad1","ink"]])
        drawMesh(name,plate,6,color,sizeCAD);
      gl.disable(gl.CULL_FACE);
      hitAreas=[region([[-PW/2,-PH/2,0],[-PW/2,PH/2,0],[PW/2,-PH/2,0],[PW/2,PH/2,0]].map(p=>place(currentPhone,phoneBasis,p,sizePhone))),
        region([[-.68,0,0],[.68,1.74,0]].map(p=>add(lamp,scale(p,sizeLamp)))),
        region([[-35,-57,20],[35,57,20]].map(p=>add(plate,scale(p,sizeCAD))))];
      if(stage.dataset.renderer!=="webgl"){renderer="webgl";stage.dataset.renderer=renderer;}
    }
    const run=()=>{
      measure();schedule();
    };
    window.addEventListener("resize",run,{passive:true});
    if("ResizeObserver" in window){
      observer=new ResizeObserver(run);observer.observe(stage);
      const target=document.querySelector(".model-wrap");if(target)observer.observe(target);
    }
    const imagePath=file=>new URL("assets/phone/"+file,document.baseURI).href;
    const resources=[...["app-icon.webp","dashboard.webp","switch-off.webp","switch-controls.webp"].map(file=>imageAt(imagePath(file))),
      ...["off","on"].map(s=>imageAt("assets/room/lighting-"+s+".webp")),
      fetch("assets/room/furniture.json").then(r=>{if(!r.ok)throw new Error("Room geometry unavailable");return r.json();}),
      fetch(new URL("assets/room/switch.bin",document.baseURI)).then(r=>{if(!r.ok)throw new Error("Enclosure unavailable");return r.arrayBuffer();})];
    Promise.all(resources).then(([icon,dash,patch,detail,dark,light,scene,cad])=>{
      const off=document.createElement("canvas");off.width=dash.width;off.height=dash.height;
      const ctx=off.getContext("2d");ctx.drawImage(dash,0,0);ctx.drawImage(patch,20,430,257,128);
      [homeArtwork(icon),off,dash,detail].forEach((im,i)=>tex(i,im,["sHome","sOff","sOn","sDetail"][i]));
      tex(4,dark,"sDarkRoom");tex(5,light,"sLightRoom");
      for(const [name,[kind,data]] of Object.entries(scene.meshes))
        mesh(name,kind==="box"?box(data):lathe(data,128));
      furniture=[];
      for(const [layer,entries] of [[1,scene.architecture],[2,scene.objects]]){
        for(const [name,,pos,scale=1,yaw=0,count=1,spacing=0] of entries){
          for(let i=0;i<count;i++)furniture.push({name,pos:add(pos,[i*spacing,0,0]),scale,axes:basis(yaw,0,0),layer});
        }
      }
      decodeCAD(cad).forEach((m,i)=>mesh("cad"+i,m));
      geometryReady=true;draw=paint;run();
    }).catch(()=>{draw=poster;poster();});
  }
  function init(){try{start();}catch(error){draw=poster;poster();}}
  canvas.addEventListener("webglcontextlost",e=>{e.preventDefault();draw=poster;poster();});
  canvas.addEventListener("webglcontextrestored",init);
  init();
})();
