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
    uniform vec3 uOrigin,uFocus;
    uniform vec2 uHalf,uOffset;
    uniform float uScale,uPerspective;
    varying vec3 w,n;
    varying vec2 uv;
    void main(){
      w=uOrigin+uModel*(aPos*uScale); n=uModel*aNorm; uv=aUV;
      vec3 view=uView*(w-uFocus);
      float projection=max(.25,1.-view.z*uPerspective/9.);
      gl_Position=vec4(view.xy/uHalf+uOffset*projection,-view.z*.12,projection);
    }`;
  const fragment = `
    precision highp float;
    varying vec3 w,n;
    varying vec2 uv;
    uniform vec3 uColor,uLamp,uEye,uPlate;
    uniform vec2 uPixels;
    uniform vec2 uRing;
    uniform float uType,uLit,uFade,uOpen,uDetail,uStudio,uMount,uCadScale,uFacePixel;
    uniform sampler2D sHome,sOff,sOn,sDetail,sDarkRoom,sLightRoom;
    float hash(vec2 p){return fract(sin(dot(p,vec2(41.3,289.1)))*4317.23);}
    void main(){
      vec3 N=normalize(n), V=normalize(uEye-w), color=uColor;
      vec3 L=normalize(mix(vec3(2.8,4.3,4.6),vec3(-3.8,4.2,4.6),uStudio)), H=normalize(V+L);
      float key=max(0.,dot(N,L)), spec=0., sheen=0.;
      vec3 lampDelta=uLamp-w; float lightDist=dot(lampDelta,lampDelta);
      float lampI=uLit/(.65+lightDist);
      float lampN=max(0.,dot(N,normalize(lampDelta)));
      vec3 ambient=vec3(.47,.465,.455);
      float kind=uType;
      if(kind<.5){
        vec3 dark=texture2D(sDarkRoom,uv).rgb, light=texture2D(sLightRoom,uv).rgb;
        // Mix luminous energy; a half-lit lamp casts half its final illumination.
        vec3 radiance=sqrt(mix(dark*dark,light*light,uLit));
        vec2 extent=vec2(34.,56.)*uCadScale;
        vec2 edge=abs(w.xy-uPlate.xy+vec2(.012,.025))-extent+vec2(.025);
        float d=length(max(edge,0.))+min(max(edge.x,edge.y),0.)-.025;
        float contact=.26*(1.-smoothstep(-.002,.018,d))+.20*(1.-smoothstep(-.018,.073,d));
        radiance*=1.-contact*uMount;
        gl_FragColor=vec4(radiance,uFade);return;
      }
      vec3 R=reflect(-V,N);
      float lampEdge=exp(-19.*(1.-max(0.,dot(R,normalize(uLamp-w)))))*uLit;
      if(kind<3.5){
        // Broad window and narrow strip-card reflections describe the rounded
        // titanium chamfers; the reflected interior supplies lower frequencies.
        vec2 q=clamp(vec2(.54+.42*R.x,.49+.39*R.y),.01,.99);
        vec3 env=mix(texture2D(sDarkRoom,q).rgb,texture2D(sLightRoom,q).rgb,uLit);
        float windowLight=smoothstep(-.13,.28,R.y)*(.40+.60*smoothstep(.08,.85,-R.x));
        float strip=exp(-abs(R.x+.66)*12.)+.75*exp(-abs(R.y-.090)*27.);
        float rim=pow(1.-abs(dot(N,V)),3.);
        vec3 titanium=color*(.34+.82*windowLight)+env*.20+vec3(.36,.34,.30)*strip;
        titanium+=vec3(.25,.225,.195)*rim+vec3(.16,.085,.032)*lampEdge;
        gl_FragColor=vec4(titanium,uFade);return;
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
        float glass=.012+.035*pow(1.-abs(dot(N,V)),3.);
        float softbox=.12+.62*smoothstep(.25,1.2,uv.x+uv.y*.68);
        screen=mix(screen,vec3(.81,.82,.84)*softbox,glass)+vec3(.1,.064,.033)*lampEdge;
        vec2 bar=abs((uv-vec2(.5,.015))*vec2(.462,1.))-vec2(.087,.002);
        float indicator=1.-smoothstep(-.0004,.0014,length(max(bar,0.))+min(max(bar.x,bar.y),0.)-.0011);
        screen=mix(screen,vec3(.84),indicator*uOpen);
        gl_FragColor=vec4(screen,uFade);return;
      } else if(kind>6.5){
        float fresnel=.035+.40*pow(1.-abs(dot(N,V)),3.);
        float glint=exp(-abs(R.x+.57)*11.)+.57*smoothstep(.45,1.,R.y);
        gl_FragColor=vec4(color+vec3(.64,.65,.68)*glint*fresnel+vec3(.18,.09,.04)*lampEdge,uFade);return;
      } else {spec=.24;sheen=38.;}
      vec3 illum=ambient+vec3(.72,.68,.63)*key+vec3(.125,.13,.14)*max(0.,N.y);
      illum+=vec3(.98,.55,.24)*lampI*(.10+.75*lampN);
      vec3 result=color*illum+vec3(.98,.86,.70)*spec*pow(max(0.,dot(N,H)),sheen+1.);
      if(kind>5.5 && kind<6.5){
        vec3 studio=color*(.81+.23*key)+.10*pow(max(0.,dot(N,H)),22.);
        result=mix(result,studio,uStudio);
        if(kind>6.1){
          // Integrate the measured CAD annulus over a pixel. At room scale
          // the physical groove is narrower than one framebuffer sample.
          vec2 local=(w.xy-uPlate.xy)/uCadScale;
          float radius=length(local), h=max(.10,uFacePixel*.64);
          float groove=smoothstep(-h,h,radius-uRing.x)-smoothstep(-h,h,radius-uRing.y);
          float lightEdge=.5+.5*dot(local/max(radius,.01),normalize(L.xy));
          result+=groove*(.40*lightEdge-.31);
        }
      }
      vec2 pixel=gl_FragCoord.xy/uPixels;
      float vignette=1.-.15*dot((pixel-.53)*1.25,(pixel-.53)*1.25);
      result*=mix(vignette,1.,uStudio);
      result+=(hash(gl_FragCoord.xy)-.5)*.006;
      gl_FragColor=vec4(result,uFade);
    }`;

  // Geometry is created once. A vertex is position, normal, and UV.
  const vertexAt=(p,n,uv=[0,0]) => [...p,...n,...uv];
  const halfOpening=2.18;
  // Unproject a point in the photographed opening composition onto a plane of
  // known depth. The camera then revisits these same points in three dimensions.
  function at(x,y,z,aspect) {
    const v=(1-2*y)*halfOpening, c=opening[1][1], s=opening[2][1];
    const worldY=(v*(1-z*c/9)+z*s)/(c+v*s/9);
    return [(2*x-1)*halfOpening*aspect*(1-(worldY*s+z*c)/9),worldY,z];
  }
  function photoLayout(aspect,tall,photoAspect) {
    const sx=Math.min(1,aspect/photoAspect),sy=Math.min(1,photoAspect/aspect);
    const left=(1-sx)*.73,top=(1-sy)*.46;
    const source=(x,y)=>[left+x*sx,top+y*sy];
    const screen=(x,y)=>[(x-left)/sx,(y-top)/sy];
    const lamp=tall?[.72,.59]:[.77,.54];
    const lampBounds=tall?[.551,.544,.888,.712]:[.653,.444,.89,.79];
    return {source,screen,lamp,lampBounds};
  }
  function roomSurface(aspect,layout,tall) {
    const vertices=[],indices=[],cols=48,rows=36;
    for(let j=0;j<=rows;j++) for(let i=0;i<=cols;i++){
      const x=mix(-.34,1.34,i/cols),y=mix(-.21,1.21,j/rows);
      const [u,v]=layout.source(x,y);
      const cabinetEdge=tall?.384:.40, horizon=tall?.706:.747;
      const base=.88*ramp(v,horizon-.004,horizon+.117)*ramp(u,cabinetEdge-.018,cabinetEdge+.017);
      const lx=(u-layout.lamp[0])/(tall?.169:.119),bottom=tall?.633:.624;
      const curve=Math.sqrt(Math.max(0,1-lx*lx));
      const top=bottom-(tall?.09:.181)*curve;
      const shade=(1-ramp(Math.abs(lx),.93,1.055))*ramp(v,top-.012,top+.012)*(1-ramp(v,bottom,bottom+.018));
      const foot=(1-ramp(Math.abs(lx),.30,.37))*ramp(v,bottom-.027,bottom+.005)
        *(1-ramp(v,horizon+.038,horizon+.073));
      const corner=tall?.344:.372;
      const leftWall=.65*Math.max(0,(corner-u)/corner);
      const z=.072+Math.max(leftWall,base,shade*(.43+.27*curve),foot*.57);
      vertices.push(...vertexAt(at(x,y,z,aspect),[0,0,1],[u,1-v]));
      if(i<cols&&j<rows){
        const a=j*(cols+1)+i,b=a+cols+1;
        indices.push(a,b,a+1,a+1,b,b+1);
      }
    }
    return {vertices,indices};
  }
  function phoneLayer(w,h,r,sections,withFace) {
    const vertices=[], indices=[], ring=[];
    const sides=12, count=(sides+1)*4;
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
  function finishFace(mesh) {
    // The CAD top is planar except for the recessed circular button. Some
    // of its original slender triangles meet at T-junctions. Use its exact
    // exterior convex boundary and separately filter the groove at small scale.
    const points=[];
    let front=-Infinity;
    for(let i=2;i<mesh.vertices.length;i+=8)front=Math.max(front,mesh.vertices[i]);
    for(let i=0;i<mesh.vertices.length;i+=8){
      if(Math.abs(mesh.vertices[i+2]-front)<.005)points.push(mesh.vertices.slice(i,i+2));
    }
    const unique=[...new Map(points.map(p=>[p.join(","),p])).values()].sort((a,b)=>a[0]-b[0]||a[1]-b[1]);
    const radii=unique.map(([x,y])=>Math.hypot(x,y)).filter(r=>r>10&&r<20).sort((a,b)=>a-b);
    let split=1;
    for(let i=2;i<radii.length;i++)if(radii[i]-radii[i-1]>radii[split]-radii[split-1])split=i;
    const mean=a=>a.reduce((s,v)=>s+v,0)/a.length;
    const ring=[mean(radii.slice(0,split)),mean(radii.slice(split))];
    function chain(points){
      const out=[];
      for(const p of points){
        while(out.length>1){
          const a=out[out.length-2],b=out[out.length-1];
          if((b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])>0)break;
          out.pop();
        }
        out.push(p);
      }
      return out.slice(0,-1);
    }
    const boundary=chain(unique).concat(chain(unique.reverse()));
    const vertices=boundary.flatMap(([x,y])=>vertexAt([x,y,front+.012],[0,0,1]));
    const indices=[];
    for(let i=1;i<boundary.length-1;i++)indices.push(0,i,i+1);
    return {vertices,indices,ring};
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
      art.data[i]=20+tone*109;art.data[i+1]=21+tone*103;art.data[i+2]=24+tone*99;art.data[i+3]=255;
    }
    wc.putImageData(art,0,0);c.drawImage(paper,0,0,562,1218);
    c.fillStyle="#f7f6f3";c.font="600 25px Arial";c.fillText("9:41",48,50);
    c.fillRect(486,34,29,12);c.fillRect(517,38,3,5);
    for(let i=0;i<4;i++) c.fillRect(451+i*6,46-(i+1)*3,4,(i+1)*3);
    const d=111,x=(562-d)/2,y=585;
    if(icon){c.save();c.beginPath();c.roundRect(x,y,d,d,24);c.clip();c.drawImage(icon,x,y,d,d);c.restore();}
    c.fillStyle="#fff";c.font="500 26px Arial";c.textAlign="center";c.fillText("Nultra",281,y+d+38);
    c.fillStyle="rgba(215,226,221,.13)";c.beginPath();c.roundRect(79,1025,404,107,35);c.fill();
    for(const [i,tint] of ["#3f9061","#627f8f","#77777b"].entries()){
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
  // Multisampling resolves thin metal edges and the subpixel CAD button relief.
  const gl=canvas.getContext("webgl",{alpha:true,antialias:true,depth:true,premultipliedAlpha:false,powerPreference:"low-power",preserveDrawingBuffer:false});
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
    hitAreas=m?[{x:.055,y:.337,w:.55,h:.55},{x:.55,y:.54,w:.35,h:.18},{x:.55,y:.245,w:.175,h:.145}]
      :[{x:.393,y:.20,w:.23,h:.738},{x:.65,y:.44,w:.24,h:.35},{x:.628,y:.27,w:.07,h:.168}];
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
    const roomImage=name=>requestPoster(name+format,"assets/room/"+name+"-"+format+".webp?v=4");
    const open=roomImage("open");
    if(!open)return;
    const app=override===null?ramp(progress,.055,.20):1,light=lit();
    const off=app>0 ? roomImage("off") : null;
    const on=light>0 ? roomImage("lit") : null;
    const detail=light>0&&progress>.375 ? roomImage("detail") : null;
    const surface=progress>.52 ? requestPoster("surface","assets/product/frames/000.webp") : null;
    const target=document.querySelector(".model-wrap")?.getBoundingClientRect();
    const plateX=(m?.644:.66)*w, plateY=(m?.314:.35)*h;
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
  if(!gl||gl.getParameter(gl.MAX_TEXTURE_SIZE)<2048){draw=poster;poster();return;}
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
    const names=["uModel","uView","uOrigin","uFocus","uHalf","uOffset","uScale","uPerspective","uColor","uLamp","uEye","uPlate","uType","uLit","uFade","uOpen","uDetail","uStudio","uPixels","uMount","uCadScale","uFacePixel","uRing"];
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
      const verts=library[name]?.verts||gl.createBuffer(),faces=library[name]?.faces||gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER,verts);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(vertices),gl.STATIC_DRAW);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,faces);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,new Uint16Array(indices),gl.STATIC_DRAW);
      library[name]={verts,faces,count:indices.length};
    }
    const textures=[];
    function tex(unit,target,name){
      const texture=textures[unit]||(textures[unit]=gl.createTexture());
      gl.activeTexture(gl.TEXTURE0+unit);gl.bindTexture(gl.TEXTURE_2D,texture);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,true);
      gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,target);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
      gl.uniform1i(gl.getUniformLocation(program,name),unit);
    }
    const PW=.835,PH=1.75;
    mesh("body",phoneLayer(PW,PH,.126,[[-.079,.015,0],[-.077,.006,0],[-.070,0,0],[.024,0,0],[.032,.001,.19],[.042,.007,.52],[.047,.017,.92]],true));
    mesh("bezel",phoneLayer(PW-.022,PH-.022,.118,[[.045,.001,.40],[.049,.003,.79],[.052,.008,1]],true));
    mesh("screen",phoneLayer(PW-.056,PH-.056,.103,[[.0525,0,1]],true));
    mesh("island",phoneLayer(.225,.054,.027,[[.053,0,1],[.0545,.001,1]],true));
    mesh("lens",phoneLayer(.021,.021,.0105,[[.055,0,1]],true));
    mesh("lensDot",phoneLayer(.007,.007,.0035,[[.0555,0,1]],true));
    mesh("speaker",phoneLayer(.102,.0055,.00275,[[.0502,0,1]],true));
    for(const [name,length] of [["volume",.119],["action",.074],["power",.172],["seam",.010]])
      mesh(name,phoneLayer(.058,length,Math.min(.024,length/2),[[-.002,0,0],[.004,0,.44],[.006,.0015,.86]],true));
    const colors={
      metal:[.55,.535,.515], button:[.46,.45,.43], joint:[.07,.069,.068],
      bezel:[.020,.020,.024], notch:[.008,.009,.012], lens:[.025,.032,.055], glint:[.12,.15,.20],
      face:[.818,.809,.79], ink:[.11,.108,.106], carrier:[.34,.335,.33], shell:[.256,.252,.25]
    };
    let size, geometryReady=false, observer, activePhoto="", requestedPhoto="", photoAspect=16/9;
    const photoCache=new Map();
    function choosePhoto(format) {
      if(requestedPhoto===format)return;
      requestedPhoto=format;
      if(!photoCache.has(format))photoCache.set(format,Promise.all(["off","on"].map(
        state=>imageAt("assets/room/interior-"+state+"-"+format+".webp"))));
      photoCache.get(format).then(([dark,light])=>{
        if(requestedPhoto!==format)return;
        photoAspect=dark.naturalWidth/dark.naturalHeight;
        activePhoto=format;tex(4,dark,"sDarkRoom");tex(5,light,"sLightRoom");
        measure();schedule();
      }).catch(()=>{if(requestedPhoto===format){draw=poster;poster();}});
    }
    function measure() {
      const rect=stage.getBoundingClientRect();
      if(!rect.width || !rect.height) return;
      const width=rect.width,height=rect.height, aspect=width/height;
      const target=stage.closest("section")?.querySelector(".model-wrap") || document.querySelector(".model-wrap");
      const end=target?.getBoundingClientRect();
      const endWidth=end?.width || Math.min(width*.65,height);
      const ox=end?.width ? ((end.left-rect.left+end.width/2)/width-.5)*2 : .2;
      const oy=end?.height ? 1-(end.top-rect.top+end.height/2)*2/height : 0;
      const format=aspect<1?"tall":"wide";
      const sourceAspect=activePhoto===format?photoAspect:format==="tall"?9/16:16/9;
      const layout=photoLayout(aspect,format==="tall",sourceAspect);
      if(!size||size.aspect!==aspect||size.sourceAspect!==sourceAspect)
        mesh("interior",roomSurface(aspect,layout,format==="tall"));
      size={width,height,aspect,ox,oy,endWidth,layout,sourceAspect};
      choosePhoto(format);
      const dpr=Math.min(Math.max(1.35,window.devicePixelRatio||1),1.55,1536/width,1280/height);
      const w=Math.max(1,Math.round(width*dpr)),h=Math.max(1,Math.round(height*dpr));
      if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h;gl.viewport(0,0,w,h);}
    }
    function paint() {
      if(!size||!geometryReady||!activePhoto)return;
      const {aspect,ox,oy,endWidth,height,layout}=size;
      const t=progress, narrow=1-ramp(aspect,.72,1.34), half=halfOpening;
      const plate=at(mix(.66,.644,narrow),mix(.35,.314,narrow),0,aspect);
      const lampPos=layout.screen(...layout.lamp);
      const lamp=at(lampPos[0],lampPos[1],.72,aspect);
      const phone=at(mix(.502,.32,narrow),mix(.567,.612,narrow),2.45,aspect);
      const sizePhone=mix(1.24,.92,narrow);
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
      const phoneBasis=basis(mix(-25,-44,depart),mix(3,8,depart),mix(-5,-27,depart));
      const currentPhone=add(phone,[-depart*(4.25+1.5*aspect),-.85*depart,.65*depart]);
      const roomAlpha=1-ramp(t,.74,.94);
      const phoneAlpha=1-ramp(t,.59,.76);
      const viewMatrix=[right[0],up[0],look[0],right[1],up[1],look[1],right[2],up[2],look[2]];
      scalar("uOpen",override===null?ramp(t,.055,.20):1);scalar("uDetail",ramp(t,.385,.48));scalar("uLit",lit());
      scalar("uMount",1-ramp(t,.47,.68));scalar("uCadScale",sizeCAD);
      scalar("uFacePixel",2*halfH/(canvas.height*sizeCAD));
      scalar("uStudio",ramp(t,.72,.96));scalar("uPerspective",perspective);
      mat("uView",viewMatrix);vec2("uPixels",[canvas.width,canvas.height]);
      vec2("uHalf",[halfH*aspect,halfH]);vec2("uOffset",offset);
      vec("uFocus",focus);vec("uEye",add(focus,scale(look,9)));vec("uPlate",plate);vec("uLamp",lamp);
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
        drawMesh("interior",[0,0,-depart*1.12],0,"face");
      }
      scalar("uFade",1);
      gl.enable(gl.CULL_FACE);
      for(const [name,color] of [["cad2","carrier"],["cad3","shell"],["cad0","face"],["cad1","ink"]])
        drawMesh(name,plate,6,color,sizeCAD);
      // The closing camera stays in front of this convex, outermost plane.
      // Fill all of its samples before drawing the nearer handset.
      gl.depthFunc(gl.ALWAYS);
      drawMesh("frontFinish",plate,6.25,"face",sizeCAD);
      gl.depthFunc(gl.LESS);
      gl.disable(gl.CULL_FACE);
      if(phoneAlpha>.001){
        scalar("uFade",phoneAlpha);
        for(const [part,kind,color] of [["body",3,"metal"],["bezel",7,"bezel"],["screen",5,"bezel"]]){
          drawMesh(part,currentPhone,kind,color,sizePhone,phoneBasis);
        }
        const p=(x,y,z)=>place(currentPhone,phoneBasis,[x,y,z],sizePhone);
        drawMesh("island",p(0,.782,0),7,"notch",sizePhone,phoneBasis);
        drawMesh("lens",p(.074,.782,0),7,"lens",sizePhone,phoneBasis);
        drawMesh("lensDot",p(.071,.786,0),7,"glint",sizePhone,phoneBasis);
        drawMesh("speaker",p(0,.852,0),7,"notch",sizePhone,phoneBasis);
        for(const side of [-1,1]){
          const sideAxes=[scale(phoneBasis[2],-side),phoneBasis[1],scale(phoneBasis[0],side)];
          const button=(name,y,material)=>drawMesh(name,p(side*(PW/2+.0008),y,-.022),material==="joint"?7:3,material,sizePhone,sideAxes);
          if(side<0){button("action",.47,"button");button("volume",.28,"button");button("volume",.11,"button");}
          else button("power",.185,"button");
          button("seam",.61,"joint");button("seam",-.57,"joint");
        }
      }
      const [x0,y0,x1,y1]=layout.lampBounds;
      const lampCorners=[[x0,y0],[x1,y0],[x0,y1],[x1,y1]].map(([x,y])=>at(...layout.screen(x,y),.63,aspect));
      hitAreas=[region([[-PW/2,-PH/2,0],[-PW/2,PH/2,0],[PW/2,-PH/2,0],[PW/2,PH/2,0]].map(p=>place(currentPhone,phoneBasis,p,sizePhone))),
        region(lampCorners),
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
    measure();
    const resources=[...["app-icon.webp","dashboard.webp","switch-off.webp","switch-controls.webp"].map(file=>imageAt(imagePath(file))),
      fetch(new URL("assets/room/switch.bin",document.baseURI)).then(r=>{if(!r.ok)throw new Error("Enclosure unavailable");return r.arrayBuffer();})];
    Promise.all(resources).then(([icon,dash,patch,detail,cad])=>{
      const off=document.createElement("canvas");off.width=dash.width;off.height=dash.height;
      const ctx=off.getContext("2d");ctx.drawImage(dash,0,0);ctx.drawImage(patch,20,430,257,128);
      [homeArtwork(icon),off,dash,detail].forEach((im,i)=>tex(i,im,["sHome","sOff","sOn","sDetail"][i]));
      const parts=decodeCAD(cad);
      parts.forEach((m,i)=>mesh("cad"+i,m));
      const finish=finishFace(parts[0]);
      mesh("frontFinish",finish);vec2("uRing",finish.ring);
      geometryReady=true;draw=paint;run();
    }).catch(()=>{draw=poster;poster();});
  }
  function init(){try{start();}catch(error){draw=poster;poster();}}
  canvas.addEventListener("webglcontextlost",e=>{e.preventDefault();draw=poster;poster();});
  canvas.addEventListener("webglcontextrestored",init);
  init();
})();
