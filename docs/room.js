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
  const appReveal = () => override === null ? ramp(progress,.085,.20) : 1;
  const phoneCue = stage.querySelector(".phone-cue");
  function updatePhoneCue(icon, lamp) {
    if (!phoneCue) return;
    const openingApp = progress < .18;
    const contact = openingApp ? .085 : .28;
    phoneCue.hidden = override !== null || progress <= contact-.075 || progress >= contact+.055;
    if (phoneCue.hidden) return;
    const [x,y] = openingApp ? icon : lamp;
    const approach = ramp(progress,contact-.065,contact);
    const release = ramp(progress,contact,contact+.055);
    const style = phoneCue.style;
    style.left = x*100+"%";
    style.top = y*100+"%";
    style.setProperty("--touch-alpha", ramp(progress,contact-.075,contact-.048)*(1-release));
    style.setProperty("--travel", (1-approach)*14+release*4+"px");
    style.setProperty("--press", 1-.24*approach*(1-release));
    style.setProperty("--ring", .35+1.05*release);
    style.setProperty("--ring-alpha", ramp(progress,contact-.005,contact+.007)*(1-release));
  }
  function posterPhoneCue(tall) {
    // Normalized icon and desk-lamp bulb centers in the two opening captures.
    if (tall) updatePhoneCue([.304,.627],[.279,.571]);
    else updatePhoneCue([.496,.585],[.486,.506]);
  }
  function schedule() {
    if (!frame && draw) frame=requestAnimationFrame(() => {frame=0; draw();});
  }
  function setState(position, manual) {
    const next=clamp(Number(position)||0);
    const light=typeof manual === "boolean" ? manual : null;
    const changed=next!==progress || light!==override;
    progress=next; override=light;
    stage.dataset.fallback=lit()>=.5 ? "on" : "off";
    if (!draw) posterPhoneCue(stage.clientWidth < stage.clientHeight);
    if (changed) schedule();
  }
  const switchCallout = stage.querySelector(".switch-callout");
  const switchLabelOpacity = t => ramp(t, .43, .50) * (1 - ramp(t, .69, .74));
  function markSwitch(x, y) {
    if (!switchCallout) return;
    const alpha = switchLabelOpacity(progress);
    if (switchCallout.hidden !== !alpha) switchCallout.hidden = !alpha;
    if (!alpha) return;
    switchCallout.style.left = (x * 100) + "%";
    switchCallout.style.top = (y * 100) + "%";
    switchCallout.style.opacity = String(alpha);
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
  window.NultraRoom={setState,switchLabelOpacity,getState:() => ({progress,lit:lit(),renderer,hitAreas:hitAreas.map(a=>({...a}))})};
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
    uniform vec3 uColor,uLamp,uEye,uPlate,uSocket;
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
        vec2 mountXY=(w.xy-uSocket.xy)/uCadScale;
        vec2 cut=abs(mountXY)-vec2(22.5,45.5);
        if(abs(w.z-uSocket.z)<3.*uCadScale && length(max(cut,0.))+min(max(cut.x,cut.y),0.)<3.)discard;
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
      if(kind>7.5){
        vec3 local=(w-uSocket)/uCadScale;
        float depth=clamp(-local.z/41.,0.,1.);
        float sideAO=(1.-smoothstep(0.,8.,24.-abs(local.x)))+(1.-smoothstep(0.,8.,46.-abs(local.y)));
        float irradiance=(.69+.38*key+.06*max(0.,N.y))*(1.-.28*depth-.105*depth*min(sideAO,1.));
        vec2 grainPlane=abs(N.z)>.65?local.xy:vec2(local.y,local.z);
        float spangle=sin(dot(grainPlane,vec2(.63,.93))+.8*sin(grainPlane.y*.61))*sin(dot(grainPlane,vec2(-.93,.36)));
        float grain=(hash(floor(grainPlane*5.))-.5)*.027+.016*spangle;
        float softbox=pow(max(0.,dot(reflect(-V,N),normalize(vec3(.55,.38,.74)))),7.);
        vec3 steel=color*(irradiance+grain)+vec3(.14,.14,.13)*softbox*(1.-.55*depth);
        steel+=uLit*vec3(.045,.027,.011)*max(0.,dot(N,normalize(uLamp-w)));
        gl_FragColor=vec4(steel,uFade);return;
      }
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
    const mountDepth=20.005*mix(.00565,.0048,1-ramp(aspect,.72,1.34));
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
      const z=mountDepth+Math.max(leftWall,base,shade*(.43+.27*curve),foot*.57);
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
  // Generic single-gang installation hardware. The Nultra enclosure itself
  // comes from switch.bin. The independent steel cavity stays in the wall.
  function deviceBox(){
    const pieces={};
    function face(part,points,N){
      const group=pieces[part]||(pieces[part]={vertices:[],indices:[]});
      const start=group.vertices.length/8;
      for(const p of points)group.vertices.push(...vertexAt(p,N));
      for(let i=1;i<points.length-1;i++)group.indices.push(start,start+i,start+i+1);
    }
    function rim(x,y,r,z){
      const result=[];
      for(let c=0;c<4;c++)for(let j=0;j<=6;j++){
        const a=(c+j/6)*Math.PI/2;
        result.push([[1,-1,-1,1][c]*(x-r)+r*Math.cos(a),
          [1,1,-1,-1][c]*(y-r)+r*Math.sin(a),z]);
      }
      return result;
    }
    function connect(part,out,inner,flat=false){
      for(let i=0;i<out.length;i++){
        const j=(i+1)%out.length,edge=sub(out[j],out[i]),down=sub(inner[i],out[i]);
        const N=flat?[0,0,1]:normal(cross(edge,down));
        face(part,[out[i],out[j],inner[j],inner[i]],N);
      }
    }
    const opening=rim(25.5,48.5,3,0),cutback=rim(25.25,48.25,2.75,-2.4);
    const flange=rim(23.8,46.65,2.2,-2.45),throat=rim(23.35,46.2,2.05,-3.6);
    const rear=rim(22.8,44.2,2.8,-41);
    connect("plasterEdge",opening,cutback);
    connect("boxRim",cutback,flange,true);
    connect("boxRim",flange,throat);
    connect("boxSides",throat,rear);
    face("boxBack",rear,[0,0,1]);
    // Rounded mounting ears with actual through holes. The empty center
    // exposes the dark box behind each folded tab.
    for(const s of [-1,1]){
      const cy=s*41.65,top=[],bore=[],under=[];
      for(let i=0;i<48;i++){
        const a=i*tau/48,x=Math.cos(a),y=Math.sin(a);
        const d=Math.min(7.2/Math.max(.001,Math.abs(x)),5.0/Math.max(.001,Math.abs(y)));
        top.push([x*d,cy+y*d,-2.0]);
        bore.push([x*1.75,cy+y*1.75,-2.0]);under.push([x*1.54,cy+y*1.54,-3.1]);
      }
      connect("boxEars",top,bore,true);connect("boxBore",bore,under);
    }
    // Shallow pressings on the rear and both cheeks. Concentric drawn lips
    // and narrow uncut bridges identify the removable metal knockouts.
    function knockout(origin,U,W,N,r){
      const depths=[[r+1,0],[r+.42,.31],[r+.10,.55],[r-.28,.06],[r-.72,.35],[r-1.04,.53]];
      const ring=(radius,depth)=>Array.from({length:52},(_,i)=>{
        const a=i*tau/52;
        const bridge=Math.cos(3*a)>.974?.18:1;
        return add(add(add(origin,scale(U,radius*Math.cos(a))),scale(W,radius*Math.sin(a))),scale(N,depth*bridge));
      });
      for(let j=0;j<depths.length-1;j++){
        const a=ring(...depths[j]),b=ring(...depths[j+1]);
        for(let i=0;i<a.length;i++){
          const n=(i+1)%a.length;
          const norm=normal(cross(sub(a[n],a[i]),sub(b[i],a[i])));
          face(j===2?"boxStampDark":"boxStamp",[a[i],a[n],b[n],b[i]],dot(norm,N)<0?scale(norm,-1):norm);
        }
      }
      face("boxStamp",ring(...depths[depths.length-1]),N);
    }
    knockout([0,-13,-40.9],[1,0,0],[0,1,0],[0,0,1],11.3);
    knockout([0,19,-40.9],[1,0,0],[0,1,0],[0,0,1],9.25);
    for(const s of [-1,1])knockout([s*22.9,3,-22],[0,0,s],[0,1,0],[-s,0,0],9.1);
    return pieces;
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
    posterPhoneCue(m);
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
    const roomImage=name=>requestPoster(name+format,"assets/room/"+name+"-"+format+".webp?v=5");
    const open=roomImage("open");
    if(!open)return;
    const app=appReveal(),light=lit();
    const off=app>0 ? roomImage("off") : null;
    const on=light>0 ? roomImage("lit") : null;
    const detail=light>0&&progress>.375 ? roomImage("detail") : null;
    const release=progress>.425&&light>.01?roomImage("release"):null;
    const detached=progress>.53?roomImage(light>.5?"detached":"detached-dark"):null;
    if(progress>.47&&progress<=.74){
      // These normalized rectangles come from the CAD projection at each
      // captured camera pose. Follow the visible control in the 2D dissolve.
      const releaseHit=m?{x:.528,y:.314,w:.264,h:.248}:{x:.657,y:.256,w:.119,h:.359};
      const detachedHit=m?{x:.612,y:.400,w:.300,h:.312}:{x:.662,y:.329,w:.146,h:.498};
      const atRelease=release?ramp(progress,.47,.614):0;
      const atDetach=detached?ramp(progress,release ? .610 : .47,.705):0;
      const mounted=hitAreas[2];
      hitAreas[2]=Object.fromEntries(Object.keys(mounted).map(k=>
        [k,mix(mix(mounted[k],releaseHit[k],atRelease),detachedHit[k],atDetach)]));
    }
    const faceBounds = hitAreas[2];
    markSwitch(faceBounds.x + faceBounds.w / 2, faceBounds.y + faceBounds.h / 2);
    const surface=progress>.70?requestPoster("surface","assets/product/frames/000.webp"):null;
    const target=document.querySelector(".model-wrap")?.getBoundingClientRect();
    const targetW=target?.width||w*.74;
    const targetX=target?.width?target.left-rect.left+target.width/2:w*.65;
    const targetY=target?.height?target.top-rect.top+target.height/2:h*.5;
    // The release photographs come from exactly the same camera and 3D
    // geometry as the live scene. Keep the aperture in view through its hold.
    const shotAspect=m?.5:16/9,unit=m?.0048:.00565;
    const half=Math.max(127,103/shotAspect),axes=basis(-28,9,-2);
    const travel=ramp(progress,.81,.95),toSurface=surface?ramp(progress,.856,.902):0;
    // Register three physical faceplate points in both photographs.
    // The incoming model and departing installed-room capture follow exactly
    // the same face plane throughout the dissolve, including its rotation.
    const face=[[-29,-51.5,24],[29,-51.5,24],[-29,51.5,24]];
    const captured=face.map(([x,y,z])=>{
      const p=[x,y,z+92],f=1-dot(p,axes[2])*unit*.34/9;
      return [w*(.5+.5*((m?0:.23)+dot(p,axes[0])/(half*shotAspect*f))),
        h*(.5-.5*(-.045+dot(p,axes[1])/(half*f)))];
    });
    const closingScale=targetW/(2*91.36181);
    const final=face.map(p=>[targetX+(dot(p,closing[0])-10.05063)*closingScale,
      targetY-(dot(p,closing[1])-.32020)*closingScale]);
    const current=captured.map((v,i)=>lerp(v,final[i],travel));
    function register(from) {
      const x=sub(from[1],from[0]),y=sub(from[2],from[0]);
      const X=sub(current[1],current[0]),Y=sub(current[2],current[0]);
      const det=x[0]*y[1]-x[1]*y[0];
      const a=(X[0]*y[1]-Y[0]*x[1])/det, c=(Y[0]*x[0]-X[0]*y[0])/det;
      const b=(X[1]*y[1]-Y[1]*x[1])/det, d=(Y[1]*x[0]-X[1]*y[0])/det;
      context.transform(a,b,c,d,current[0][0]-a*from[0][0]-c*from[0][1],current[0][1]-b*from[0][0]-d*from[0][1]);
    }
    context.save();
    if(travel>0)register(captured);
    if(travel>0&&toSurface<1){
      // Extend the marginal texels as the camera turns. The image always
      // covers the viewport, including portrait corners outside its crop.
      const backdrop=detached||release||on||off||open;
      const iw=backdrop.naturalWidth,ih=backdrop.naturalHeight,pad=Math.max(w,h);
      const columns=[[0,1,-pad,pad+1],[0,iw,0,w],[iw-1,1,w-1,pad+1]];
      const rows=[[0,1,-pad,pad+1],[0,ih,0,h],[ih-1,1,h-1,pad+1]];
      for(let j=0;j<3;j++)for(let i=0;i<3;i++){
        if(i===1&&j===1)continue;
        const [sx,sw,dx,dw]=columns[i],[sy,sh,dy,dh]=rows[j];
        context.drawImage(backdrop,sx,sy,sw,sh,dx,dy,dw,dh);
      }
    }
    function plate(im,opacity){
      if(im&&opacity>0){context.globalAlpha=opacity;context.drawImage(im,0,0,w,h);}
    }
    if(toSurface<1){
      plate(open,1);plate(off,app);plate(on,light);plate(detail,ramp(progress,.385,.47)*light);
      plate(release,ramp(progress,.47,.614));
      plate(detached,ramp(progress,release ? .610 : .47,.705));
    }
    context.restore();
    if(surface&&toSurface){
      context.save();context.globalCompositeOperation="destination-out";context.globalAlpha=toSurface;
      context.fillRect(0,0,w,h);context.restore();
      context.save();if(travel<1)register(final);
      context.globalAlpha=toSurface;
      context.drawImage(surface,targetX-targetW/2,targetY-targetW*864/2112,targetW,targetW*864/1056);
      context.restore();context.globalAlpha=1;
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
    const names=["uModel","uView","uOrigin","uFocus","uHalf","uOffset","uScale","uPerspective","uColor","uLamp","uEye","uPlate","uSocket","uType","uLit","uFade","uOpen","uDetail","uStudio","uPixels","uMount","uCadScale","uFacePixel","uRing"];
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
    const boxParts=Object.entries(deviceBox()).map(([name,data])=>{mesh(name,data);return name;});
    Object.assign(colors,{plasterEdge:[.40,.34,.28],boxRim:[.65,.63,.59],boxSides:[.42,.43,.43],
      boxBack:[.43,.425,.41],boxEars:[.60,.595,.57],boxBore:[.25,.24,.22],
      boxStamp:[.45,.445,.425],boxStampDark:[.245,.25,.245]});
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
      const mount=at(mix(.66,.644,narrow),mix(.35,.314,narrow),0,aspect);
      const lampPos=layout.screen(...layout.lamp);
      const lamp=at(lampPos[0],lampPos[1],.72,aspect);
      const phone=at(mix(.502,.32,narrow),mix(.567,.612,narrow),2.45,aspect);
      const sizePhone=mix(1.24,.92,narrow);
      const sizeCAD=mix(.00565,.0048,narrow);
      const approach=ramp(t,.47,.69), lift=ramp(t,.535,.705), leave=ramp(t,.81,.95);
      const depart=ramp(t,.47,.663);
      const plate=add(mount,[0,0,184*sizeCAD*lift]);
      const retreat=leave*1.12, socket=add(mount,[0,0,20.005*sizeCAD-retreat]);
      const basisNow=basis(-28*approach-15*leave,9+4*leave,-2*approach-13*leave);
      const [right,up,look]=basisNow;
      const cadCenter=add(scale(closing[0],10.05063),scale(closing[1],.32020));
      const dest=add(plate,scale(cadCenter,sizeCAD));
      const displayCenter=add(mount,[0,0,92*sizeCAD*lift]);
      const focus=lerp(scale(displayCenter,approach),dest,leave);
      const slice=91.36181*sizeCAD*height/endWidth;
      const holdHalf=sizeCAD*Math.max(127,103/aspect);
      const halfH=Math.exp(mix(mix(Math.log(half),Math.log(holdHalf),approach),Math.log(slice),leave));
      const offset=[mix(mix(.23,0,narrow)*approach,ox,leave),mix(-.045*approach,oy,leave)];
      const perspective=(1-.66*approach)*(1-leave);
      const phoneBasis=basis(mix(-25,-44,depart),mix(3,8,depart),mix(-5,-27,depart));
      const currentPhone=add(phone,[-depart*(4.25+1.5*aspect),-.85*depart,.65*depart]);
      const roomAlpha=1-ramp(t,.815,.94);
      const phoneAlpha=1-ramp(t,.56,.65);
      const viewMatrix=[right[0],up[0],look[0],right[1],up[1],look[1],right[2],up[2],look[2]];
      scalar("uOpen",appReveal());scalar("uDetail",ramp(t,.385,.48));scalar("uLit",lit());
      scalar("uMount",1-lift);scalar("uCadScale",sizeCAD);
      scalar("uFacePixel",2*halfH/(canvas.height*sizeCAD));
      scalar("uStudio",ramp(t,.82,.96));scalar("uPerspective",perspective);
      mat("uView",viewMatrix);vec2("uPixels",[canvas.width,canvas.height]);
      vec2("uHalf",[halfH*aspect,halfH]);vec2("uOffset",offset);
      vec("uFocus",focus);vec("uEye",add(focus,scale(look,9)));vec("uPlate",plate);vec("uSocket",socket);vec("uLamp",lamp);
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
      // Project the same artwork coordinates used for the iPhone screen texture.
      const screenPoint=(u,v)=>project(place(currentPhone,phoneBasis,
        [(u-.5)*(PW-.056),(.5-v)*(PH-.056),.0525],sizePhone));
      updatePhoneCue(screenPoint(.5,640.5/1218),screenPoint(228/562,502/1218));
      if(roomAlpha>.001){
        scalar("uFade",roomAlpha);
        drawMesh("interior",[0,0,-retreat],0,"face");
        for(const name of boxParts)drawMesh(name,socket,8,name,sizeCAD);
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
      markSwitch(...project(add(plate, [0, 0, 24 * sizeCAD])));
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
