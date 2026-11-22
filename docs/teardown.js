/* The transparent studio photographs are registered to the room by three CAD datums.
   Once free of the box, the photographed assembly fills the responsive model area. */
(() => {
  "use strict";
  const base = "assets/teardown/";
  const mix = (a,b,t) => a+(b-a)*t;
  const blend = (a,b,t) => a.map((v,i)=>mix(v,b[i],t));
  const ease = (p,a,b) => {
    const t = Math.max(0,Math.min(1,(p-a)/(b-a)));
    return t*t*(3-2*t);
  };

  function registration(from,to) {
    const [p,q,r]=from,[P,Q,R]=to;
    const x=q[0]-p[0], y=q[1]-p[1], u=r[0]-p[0], v=r[1]-p[1];
    const X=Q[0]-P[0], Y=Q[1]-P[1], U=R[0]-P[0], V=R[1]-P[1];
    const determinant=x*v-u*y;
    if(Math.abs(determinant)<.0001)return null;
    const a=(X*v-U*y)/determinant, b=(Y*v-V*y)/determinant;
    const c=(U*x-X*u)/determinant, d=(V*x-Y*u)/determinant;
    return [a,b,c,d,P[0]-a*p[0]-c*p[1],P[1]-b*p[0]-d*p[1]];
  }
  const project=(m,[x,y])=>[m[0]*x+m[2]*y+m[4],m[1]*x+m[3]*y+m[5]];

  window.NultraTeardown = function(stage,redraw) {
    const canvas=document.createElement("canvas");
    canvas.setAttribute("aria-hidden","true");
    canvas.hidden=true;
    canvas.className="teardown-photographs";
    stage.querySelector("#room-canvas").after(canvas);
    const context=canvas.getContext("2d");
    if(!context)return null;
    let meta=null, studioStart=null, explosion=null;
    let lastT=0, lastWanted=[], pendingMeta=false, metaRetry=0;
    const sheets=new Map(), pending=new Set(), retries=new Map();
    const reduced=window.matchMedia("(prefers-reduced-motion: reduce)");
    const conserve=()=>reduced.matches||navigator.connection?.saveData===true;
    const compact=()=>stage.clientWidth<=650;
    window.addEventListener("online",()=>{retries.clear();metaRetry=0;redraw();});
    function loadManifest(){
      if(meta||pendingMeta||Date.now()<metaRetry)return;
      pendingMeta=true;
      fetch(base+"poses.json").then(r=>{
        if(!r.ok)throw new Error("Teardown poses unavailable");
        return r.json();
      }).then(data=>{
        if(data.frames?.length>1&&data.width&&data.height){
          meta=data;
          const closest=t=>data.frames.reduce((a,b)=>Math.abs(a.t-t)<Math.abs(b.t-t)?a:b);
          studioStart=closest(.566);explosion=closest(.693);
        }
      }).catch(()=>{metaRetry=Date.now()+15000;}).finally(()=>{pendingMeta=false;redraw();});
    }
    function loadSheet(name){
      if(!name||sheets.has(name)||pending.has(name)||pending.size>=(conserve()?1:2)||Date.now()<(retries.get(name)||0))return;
      pending.add(name);
      const im=new Image();im.decoding="async";im.src=base+name;
      im.decode().then(()=>{
        sheets.set(name,im);retries.delete(name);
        while(sheets.size>(compact()?3:5)){
          const stale=[...sheets.keys()].find(key=>!lastWanted.includes(key));
          if(!stale)break;
          sheets.delete(stale);
        }
      }).catch(()=>{retries.set(name,Date.now()+10000);}).finally(()=>{pending.delete(name);redraw();});
    }
    function frame(t){
      if(!meta)loadManifest();
      if(!meta)return null;
      const frames=meta.frames, first=frames[0], last=frames[frames.length-1];
      if(t<first.t-.1||t>last.t+.025){
        // Keep only the adjacent boundary pose once the room or PCB owns the screen.
        const edge=t<first.t?first.sheet:last.sheet;
        for(const key of sheets.keys())if(key!==edge)sheets.delete(key);
        return null;
      }
      const next=frames.findIndex(f=>f.t>t+.000001);
      const index=next<0?frames.length-1:Math.max(0,next-1);
      let a=frames[index],b=frames[Math.min(index+1,frames.length-1)];
      const direction=t<lastT?-1:1;lastT=t;
      const ahead=conserve()?[]:[frames[index+direction*4]?.sheet];
      if(!conserve()&&!compact())ahead.push(frames[index+direction*8]?.sheet);
      lastWanted=[...new Set([a.sheet,b.sheet,...ahead].filter(Boolean))];
      lastWanted.forEach(loadSheet);
      if(t<first.t)return null;
      if(!sheets.has(a.sheet)){
        if(sheets.has(b.sheet))a=b;
        else return null; // A direct seek uses the matching geometric or poster pose during decode.
      }
      if(!sheets.has(b.sheet))b=a;
      const part=b.t>a.t?Math.max(0,Math.min(1,(t-a.t)/(b.t-a.t))):0;
      return {a,b,part,alpha:ease(t,first.t,first.t+.012)};
    }
    function paint(t,shot,mountPoints,modelRect) {
      if(!shot||!shot.alpha||!mountPoints){
        canvas.hidden=true;
        return null;
      }
      canvas.hidden=false;
      const rect=stage.getBoundingClientRect(), w=rect.width,h=rect.height;
      const dpr=Math.min(window.devicePixelRatio||1,1.5,1800/w);
      if(canvas.width!==Math.round(w*dpr)||canvas.height!==Math.round(h*dpr)){
        canvas.width=Math.round(w*dpr);canvas.height=Math.round(h*dpr);
      }
      context.setTransform(1,0,0,1,0,0);context.clearRect(0,0,canvas.width,canvas.height);
      const {width,height}=meta;
      const mobile=stage.clientWidth<=650;
      const maxW=w*(mobile?.88:.55), maxH=h*(mobile?.57:.78);
      function studioFit(pose){
        // Keep the camera calibrated to the assembled unit during extraction and
        // to the full explosion while the other parts move out of the PCB shot.
        const reference=pose.t<.566?studioStart:pose.t>.693?explosion:pose;
        const [left,top,right,bottom]=reference?.bounds||[0,0,1,1];
        const k=Math.min(maxW/((right-left)*width),maxH/((bottom-top)*height));
        return [k,0,0,k,w*(mobile?.5:.705)-(right+left)*width*k/2,
          h*(mobile?.64:.52)-(bottom+top)*height*k/2];
      }
      const uv=([x,y])=>[x*width,y*height];
      const viewport=([x,y])=>[x*w,y*h];
      // The final still and the moving board share the measured U1 and SWD locations.
      const bench=ease(t,.49,.569), finish=ease(t,.693,.751);
      function transform(pose){
        const studio=studioFit(pose);
        const mounted=registration([pose.mount,pose.top,pose.right].map(uv),mountPoints.map(viewport))||studio;
        let m=blend(mounted,studio,bench);
        if(finish&&pose.mcu&&pose.debug&&modelRect?.width){
          const a=uv(pose.mcu),b=uv(pose.debug);
          const final=([x,y])=>[modelRect.left-rect.left+modelRect.width*x,modelRect.top-rect.top+modelRect.height*y];
          const A=final([.50094,.30918]),B=final([.42355,.73798]);
          const dx=b[0]-a[0],dy=b[1]-a[1],dist=dx*dx+dy*dy;
          if(dist>1){
            const vx=B[0]-A[0],vy=B[1]-A[1],cos=(vx*dx+vy*dy)/dist,sin=(vy*dx-vx*dy)/dist;
            m=blend(m,[cos,sin,-sin,cos,A[0]-cos*a[0]+sin*a[1],A[1]-sin*a[0]-cos*a[1]],finish);
          }
        }
        return m;
      }
      const {a,b,part,alpha}=shot, A=transform(a),B=a===b?A:transform(b);
      function atlas(pose,m,opacity){
        if(!opacity)return;
        context.setTransform(...m.map(v=>v*dpr));
        context.globalAlpha=opacity*alpha;
        context.drawImage(sheets.get(pose.sheet),pose.tile%meta.columns*width,Math.floor(pose.tile/meta.columns)*height,
          width,height,0,0,width,height);
      }
      context.globalCompositeOperation="lighter";
      atlas(a,A,1-part);atlas(b,B,part);
      context.globalCompositeOperation="source-over";
      function anchor(p,q){
        return blend(project(A,uv(p)),project(B,uv(q||p)),part);
      }
      const field=ease(t,.26,.28)*(1-ease(t,.322,.345));
      if(field&&a.magnets&&b.magnets){
        context.setTransform(dpr,0,0,dpr,0,0);context.globalAlpha=field*alpha*.88;
        context.strokeStyle="#efc485";context.lineWidth=1.45;context.lineCap="round";context.setLineDash([2.3,5.4]);
        for(let i=0;i<a.magnets.length;i++){
          const l=a.magnets[i], r=b.magnets[i]||l;
          const P=anchor(l.from,r.from),Q=anchor(l.to,r.to);
          context.beginPath();context.moveTo(...P);context.lineTo(...Q);context.stroke();
        }
        context.setLineDash([]);
      }
      context.globalAlpha=1;
      if(!a.battery)return null;
      const [x,y]=anchor(a.battery,b.battery);return [x/w,y/h];
    }
    loadManifest();
    return {frame,paint};
  };
})();
