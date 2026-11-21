"""Bake the interactive room from its shared furniture meshes, with Mitsuba 3.

Each atlas contains the wall, counter, cabinet fronts and the lamp with its
still life. Both lighting states share identical cameras. Run with Mitsuba
3.9.1, NumPy and Pillow.
"""
import argparse
import json
import math
from pathlib import Path
from tempfile import TemporaryDirectory

import mitsuba as mi
import numpy as np
from PIL import Image

ROOM = Path(__file__).resolve().parents[1] / 'docs' / 'assets' / 'room'
PITCH = math.radians(9)
# The architectural cameras sit just above each actual receiving surface.
# They see the complete shadow under the lamp, including the areas obscured
# in an ordinary hero photograph. Light paths still intersect every object.
ANGLE=math.radians(-11)
OBJECT_LOOK=np.array([math.sin(ANGLE)*math.cos(PITCH),math.sin(PITCH),math.cos(ANGLE)*math.cos(PITCH)])
OBJECT_UP=np.array([-math.sin(ANGLE)*math.sin(PITCH),math.cos(PITCH),-math.cos(ANGLE)*math.sin(PITCH)])
LAYOUTS=[
    ('wall',.5,[-2.15,1.,-.775],[0,0,1],[0,1,0],.115,6.8),
    ('stone',.1875,[-2.15,0,.17],[0,1,0],[0,0,-1],.006,6.8),
    ('front',.25,[-2.15,-.76,1.175],[0,0,1],[0,1,0],.18,6.8),
    ('objects',.5625,[.22,.86,0],OBJECT_LOOK,OBJECT_UP,15.,1.91),
]


def noise(rng, shape, cells):
    h,w = shape
    v = rng.integers(0,256,(max(2,cells[1]),max(2,cells[0])),dtype=np.uint8)
    return np.asarray(Image.fromarray(v).resize((w,h),Image.Resampling.BICUBIC),dtype=float)/255


def images(folder):
    rng = np.random.default_rng(4352)
    shape=(1024,1024)
    Y,X=np.mgrid[0:1:1024j,0:1:1024j]
    fine=rng.random(shape); coarse=noise(rng,shape,(5,5)); mid=noise(rng,shape,(31,29))
    speck=noise(rng,shape,(440,421)); plaster=.82+.15*coarse+.10*mid+.07*fine
    # Large wavering mineral bands and pores in the two cut stones.
    cloud=noise(rng,shape,(12,8)); stretch=noise(rng,shape,(9,173)); wave=Y*.79+X*.38
    warp=wave + .058*coarse+.027*cloud+.009*mid
    trav=(.84+.22*noise(rng,shape,(9,135))+.12*stretch+.07*fine
          -.14*(np.sin(warp*171+.65*mid)>.984)*(.35+.65*stretch))
    strata=.53*noise(rng,shape,(8,4))+.26*noise(rng,shape,(18,13))+.13*mid+.07*noise(rng,shape,(68,45))
    veins=np.exp(-np.abs(strata-.488)*103)*(.25+.68*cloud)
    capillary=np.exp(-np.abs(.57*cloud+.33*mid+.1*speck-.49)*150)*(.11+.26*veins)
    brown=(.51+.65*cloud+.22*strata+.15*mid+.055*fine)
    marble=brown[...,None]*[.261,.237,.209]+(veins+capillary)[...,None]*[.295,.279,.235]
    fiber=noise(rng,shape,(12,271)); ripple=noise(rng,shape,(7,69))
    growth=np.sin((Y+.056*coarse+.012*cloud)*144+1.85*ripple)
    wood=.75+.23*fiber+.14*ripple+.082*growth+.044*fine
    yarn=.90+.038*np.sin(Y*2*np.pi*246+.9*mid)+.035*np.sin(X*2*np.pi*323+mid)+.09*fine
    maps={'plaster':(plaster,[.288,.284,.258]),'limestone':(trav,[.625,.601,.547]),
          'walnut':(wood,[.352,.264,.189]),'oak':(wood,[.332,.257,.191]),
          'linen':(yarn,[.837,.817,.740]),'marble':(marble,None)}
    for name,(scalar,color) in maps.items():
        pixels=scalar if color is None else scalar[...,None]*color
        Image.fromarray(np.uint8(np.clip(pixels,0,1)*255)).save(folder/f'{name}.png')
    bump=.5+(.18*(fine-.5)+.16*(speck-.5)+.14*(mid-.5))
    Image.fromarray(np.uint8(np.clip(bump,0,1)*255)).save(folder/'relief.png')
    # The bulb sits inside the shade. Its linen is brightest around its middle,
    # with less transmission at the stitched top and bottom.
    output=(.36+.76*np.exp(-((Y-.51)/.37)**2))*(.95+.05*yarn)
    emission=np.float32(output[...,None]*[1.19,.775,.384])
    mi.Bitmap(emission).write(str(folder/'shade-glow.exr'))


def bitmap(path):
    return {'type':'bitmap','filename':str(path),'wrap_mode':'repeat','filter_type':'bilinear'}


def shaders(folder):
    mat={}
    for name,rough,bump in [('plaster',.84,.00062),('limestone',.42,.00033),('walnut',.43,.00025),
                            ('oak',.50,.00031),('marble',.23,.00017),('linen',.78,.00033)]:
        base={'type':'principled','base_color':bitmap(folder/f'{name}.png'),'roughness':rough}
        mat[name]={'type':'bumpmap','texture':bitmap(folder/'relief.png'),'scale':bump,'material':base}
    for name,color,rough,metal in (
        ('agedbrass',[.42,.31,.16],.27,.86),('lining',[.63,.54,.40],.63,0),
        ('diffuser',[.62,.55,.40],.62,.04),('selvedge',[.26,.23,.155],.76,0),
        ('ebony',[.021,.016,.012],.52,.04),('olive',[.058,.073,.054],.81,0),
        ('ochre',[.20,.132,.082],.83,0),('paper',[.51,.457,.34],.76,0),('ceramic',[.12,.096,.071],.19,.04)):
        mat[name]={'type':'principled','base_color':{'type':'rgb','value':color},'roughness':rough,'metallic':metal}
    return mat


def box(dims,material):
    vertices=[]; normals=[]; uvs=[]; indices=[]
    h=np.array(dims)*.5
    for axis in range(3):
        a,b=(axis+1)%3,(axis+2)%3
        for sign in (-1,1):
            start=len(vertices)
            for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]:
                p=np.zeros(3);p[axis]=sign*h[axis];p[a]=x*h[a];p[b]=y*h[b]
                N=np.zeros(3);N[axis]=sign; vertices.append(p);normals.append(N)
                if material=='plaster': uv=[p[0]/5.1,p[1]/4.5]
                elif material=='oak': uv=[p[1]/2.9,p[0]/1.9]
                elif axis==1: uv=[p[0]/3.7,p[2]/2.7]
                else: uv=[p[0]/3.7,p[1]/2.7]
                uvs.append(uv)
            tri=[0,1,2,0,2,3] if sign>0 else [0,2,1,0,3,2]
            indices.extend(start+i for i in tri)
    return vertices,normals,uvs,indices


def lathe(points):
    vertices=[];normals=[];uvs=[];indices=[]; count=128
    for j,(radius,y) in enumerate(points):
        first=points[max(0,j-1)];last=points[min(len(points)-1,j+1)]
        for i in range(count+1):
            a=i*2*math.pi/count;c=math.cos(a);s=math.sin(a)
            vertices.append([radius*c,y,radius*s])
            N=np.asarray([(last[1]-first[1])*c,first[0]-last[0],(last[1]-first[1])*s])
            normals.append(N/max(np.linalg.norm(N),.0001));uvs.append([i/count,y*.87])
            if i<count and j<len(points)-1:
                k=j*(count+1)+i;indices.extend([k,k+count+1,k+1,k+1,k+count+1,k+count+2])
    return vertices,normals,uvs,indices


def geometry(descriptor,entry,shaders,on,folder):
    name,material,position,*extras=entry
    scale=extras[0] if extras else 1; yaw=math.radians(extras[1]) if len(extras)>1 else 0.
    steps=extras[2] if len(extras)>2 else 1; spacing=extras[3] if len(extras)>3 else 0
    kind,data=descriptor[name]
    vert,norm,uv,indices=box(data,material) if kind=='box' else lathe(data)
    # Same local-to-world yaw as the browser.
    rotation=np.array([[math.cos(yaw),0,math.sin(yaw)],[0,1,0],[-math.sin(yaw),0,math.cos(yaw)]])
    props=mi.Properties();props['bsdf']=mi.load_dict(shaders[material])
    if on and material in ('linen','lining','diffuser','selvedge'):
        power={'linen':[1.24,.80,.37],'lining':[1.7,1.14,.55],'diffuser':[4.3,2.75,1.35],'selvedge':[.29,.18,.085]}[material]
        radiance=bitmap(folder/'shade-glow.exr') if material=='linen' else {'type':'rgb','value':power}
        props['emitter']=mi.load_dict({'type':'area','radiance':radiance})
    if material=='linen':
        uv=[(u,(vert[i][1]-1.105)/.604) for i,(u,_) in enumerate(uv)]
    for i in range(steps):
        m=mi.Mesh(name,len(vert),len(indices)//3,props,True,True)
        pos=np.array(position)+[i*spacing,0,0];parameters=mi.traverse(m)
        parameters['vertex_positions']=(np.asarray(vert)@rotation.T*scale+pos).astype(np.float32).ravel()
        parameters['faces']=np.asarray(indices,dtype=np.uint32)
        parameters['vertex_normals']=(np.asarray(norm)@rotation.T).astype(np.float32).ravel()
        parameters['vertex_texcoords']=np.asarray(uv,dtype=np.float32).ravel()
        parameters.update();yield m


def area(pos,toward,size,power):
    t=mi.ScalarTransform4f.look_at(origin=pos,target=toward,up=[0,1,0])
    return {'type':'rectangle','to_world':t@mi.ScalarTransform4f.scale([*size,1]),
            'emitter':{'type':'area','radiance':{'type':'rgb','value':power}}}


def scene(room,folder,light,layout,size):
    w,h=size;_,_,center,look,up,distance,half=layout;center=np.array(center);mats=shaders(folder)
    cam=mi.ScalarTransform4f.look_at(origin=(center+np.asarray(look)*distance).tolist(),target=center.tolist(),up=up)
    out={'type':'scene','integrator':{'type':'path','max_depth':5},'cam':{'type':'orthographic',
        'to_world':cam@mi.ScalarTransform4f.scale([half,half,1]),'near_clip':.0001,
        'sampler':{'type':'independent','sample_count':4},
        'film':{'type':'hdrfilm','width':w,'height':h,'pixel_format':'rgba','rfilter':{'type':'tent'}}}}
    for group in ['architecture','objects']:
        for j,entry in enumerate(room[group]):
            for i,m in enumerate(geometry(room['meshes'],entry,mats,light,folder)):
                out[f'{group}{j}_{i}']=m
    out['window']=area([10.5,18.4,18.9],[-.7,.35,-.75],[4.1,7.6],[7.40,8.12,8.9])
    out['strip']=area([-14.4,11.2,15.6],[0,.64,0],[1.36,4.8],[2.31,2.14,1.82])
    out['bounce']=area([-4.4,17.5,17.7],[0,0,0],[9.5,4.3],[.78,.81,.83])
    # A tall window and its mullion interrupt the afternoon sun. Both the
    # source and casement are behind the reference cameras.
    out['sun']=area([37.,32.,44.],[0,.40,0],[.72,.86],[2380.,2035.,1620.])
    tf=mi.ScalarTransform4f
    casement=tf.translate([16.7,14.65,20.])@tf.rotate([0,0,1],-26.)
    for i,(x,width) in enumerate([(-5.8,5.4),(1.65,.084),(6.55,2.36)]):
        out[f'casement{i}']={'type':'cube','to_world':casement@tf.translate([x,0,0])@tf.scale([width,12,.07]),
            'bsdf':{'type':'diffuse','reflectance':.018}}
    # Out-of-frame foliage beyond the window softens the edge of the sun patch.
    seed=np.random.default_rng(33)
    for i in range(72):
        y=seed.uniform(-2.5,3.6);x=.50*y+seed.normal(.23,.60)
        t=casement@tf.translate([x,y,-1.6+seed.uniform(-.10,.18)])@tf.rotate([0,0,1],seed.uniform(-60,48))
        out[f'leaf{i}']={'type':'disk','to_world':t@tf.scale([seed.uniform(.08,.16),seed.uniform(.17,.27),1]),
            'bsdf':{'type':'diffuse','reflectance':.033}}
    out['environment']={'type':'constant','radiance':{'type':'rgb','value':[.080,.090,.105]}}
    return mi.load_dict(out)


def photograph(sc,size,spp):
    w,h=size;total=None
    for first in range(0,spp,4):
        batch=min(4,spp-first)
        im=np.array(mi.render(sc,spp=batch,seed=9328+first),copy=True)
        total=im*batch if total is None else total+im*batch
    rgba=total/spp
    linear=np.ascontiguousarray(rgba[:,:,:3])
    if mi.variant()=='cuda_ad_rgb' and spp>=8:
        filtered=np.array(mi.OptixDenoiser([w,h])(mi.TensorXf(linear)),copy=True)
        linear=.97*filtered+.03*linear
    # Compress highlights before sRGB encoding.
    x=np.maximum(0.,linear*1.36)
    x=x*(1.+.08*x)/(1.+.49*x)
    out=np.where(x<.0031308,12.92*x,1.055*np.maximum(0.,x)**(1/2.4)-.055)
    return Image.fromarray(np.uint8(np.clip(out,0,1)*255+.5))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--width',type=int,default=1536)
    p.add_argument('--samples',type=int,default=112);p.add_argument('--texture-width',type=int,default=1280)
    p.add_argument('--dest',type=Path,default=ROOM)
    p.add_argument('--lights',nargs='+',choices=['on','off'],default=['off','on'])
    p.add_argument('--variant',default='cuda_ad_rgb');args=p.parse_args()
    mi.set_variant(args.variant);room=json.loads((ROOM/'furniture.json').read_text())
    args.dest.mkdir(parents=True,exist_ok=True)
    with TemporaryDirectory(prefix='nultra-room-materials-') as tmp:
        folder=Path(tmp);images(folder)
        for state in args.lights:
            on=state=='on';heights=[round(args.width*l[1]) for l in LAYOUTS]
            atlas=Image.new('RGB',(args.width,sum(heights))); offset=0
            for layout,h in zip(LAYOUTS,heights):
                size=(args.width,h)
                img=photograph(scene(room,folder,on,layout,size),size,args.samples)
                atlas.paste(img,(0,offset));offset+=h; print(state,layout[0],flush=True)
            if atlas.width>args.texture_width:
                atlas=atlas.resize((args.texture_width,round(args.texture_width*1.5)),Image.Resampling.LANCZOS)
            atlas.save(args.dest/f'lighting-{state}.webp',quality=88,method=5)


if __name__=='__main__':
    main()
