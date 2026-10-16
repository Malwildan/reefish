import csv, json, hashlib, math, statistics, sys
from pathlib import Path
from collections import Counter

import numpy as np
from shapely.geometry import shape, box
from shapely.validation import explain_validity
from pyproj import Transformer, Geod

import argparse
parser=argparse.ArgumentParser(description='Audit enam unggahan awal dan klorofil-a dan siapkan aset Flutter turunan tanpa menimpa sumber.')
parser.add_argument('--input',type=Path,required=True,help='Folder berisi tujuh nama berkas sumber')
parser.add_argument('--output',type=Path,required=True,help='Folder baru/terpisah untuk hasil audit dan assets/geodata')
args=parser.parse_args()
input_dir=args.input.resolve()
root=args.output.resolve()
if root == input_dir or root in input_dir.parents or input_dir in root.parents:
    parser.error('Folder input dan output harus terpisah, bukan saling bersarang.')
root.mkdir(parents=True,exist_ok=True)
FILES = {name: str(input_dir/name) for name in ['coralreef(1).geojson', 'potensi_ikan.csv', 'suhu_laut.csv', 'kedalaman_laut.csv', 'kedalaman_laut (1).csv', 'mangrove_2023_jatim.geojson']}

AOI = box(112.25,-9.15,113.10,-8.35)
out = {'aoi_bbox':[112.25,-9.15,113.10,-8.35],'files':{}}
csvs = {}
for name, file in FILES.items():
 p=Path(file); raw=p.read_bytes()
 d={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(), 'utf8_bom':raw.startswith(b'\xef\xbb\xbf')}
 if name.endswith('.csv'):
  reader=csv.DictReader(raw.decode('utf-8-sig').splitlines()); rows=list(reader)
  d.update(columns=reader.fieldnames,rows=len(rows))
  d['empty_fields']={k:sum(r[k].strip()=='' for r in rows) for k in reader.fieldnames}
  vals={k:[float(r[k]) for r in rows] for k in reader.fieldnames}
  d['nonfinite_fields']={k:sum(not math.isfinite(v) for v in vs) for k,vs in vals.items()}
  d['range']={k:[min(vs),max(vs)] for k,vs in vals.items()}
  d['value_quantiles']={str(q):float(np.quantile(vals['value'],q)) for q in [0,.25,.5,.75,1]}
  d['value_unique']=len(set(vals['value']))
  d['value_top_counts']=Counter(vals['value']).most_common(10)
  d['negative_value_count']=sum(x<0 for x in vals['value'])
  d['zero_value_count']=sum(x==0 for x in vals['value'])
  d['grid_indices_noninteger']=sum(not float(r[k]).is_integer() for r in rows for k in ['grid_x','grid_y'])
  keys=[(int(r['grid_x']),int(r['grid_y'])) for r in rows]
  d['duplicate_grid_keys']=len(keys)-len(set(keys))
  coords=[(float(r['longitude']),float(r['latitude'])) for r in rows]
  d['duplicate_coordinates']=len(coords)-len(set(coords))
  d['outside_aoi_centers']=sum(not AOI.covers(shape({'type':'Point','coordinates':p})) for p in coords)
  d['first_rows']=rows[:3]
  csvs[name]={key:(*coord,float(row['value'])) for key,coord,row in zip(keys,coords,rows)}
 else:
  j=json.loads(raw); features=j['features']; geoms=[shape(f['geometry']) for f in features]
  d.update(type=j['type'],top_keys=list(j),crs=j.get('crs'),feature_count=len(features),geometry_types=dict(Counter(g.geom_type for g in geoms)))
  d['properties_types']={k:dict(Counter(type(f.get('properties',{}).get(k)).__name__ for f in features)) for k in set().union(*(f.get('properties',{}).keys() for f in features))}
  d['first_properties']=[f.get('properties') for f in features[:3]]
  d['property_value_counts']={k:dict(Counter(str(f.get('properties',{}).get(k)) for f in features)) for k in d['properties_types']}
  if name.startswith('coral'):
   d['bbox_by_value']={str(v):[min(g.bounds[0] for f,g in zip(features,geoms) if f['properties']['value']==v),min(g.bounds[1] for f,g in zip(features,geoms) if f['properties']['value']==v),max(g.bounds[2] for f,g in zip(features,geoms) if f['properties']['value']==v),max(g.bounds[3] for f,g in zip(features,geoms) if f['properties']['value']==v)] for v in [0,1]}
  d['invalid']=[{'feature_index':i,'reason':explain_validity(g)} for i,g in enumerate(geoms) if not g.is_valid]
  d['empty_geometries']=sum(g.is_empty for g in geoms)
  d['bbox']=[min(g.bounds[0] for g in geoms),min(g.bounds[1] for g in geoms),max(g.bounds[2] for g in geoms),max(g.bounds[3] for g in geoms)]
  d['features_intersecting_aoi']=sum(g.intersects(AOI) for g in geoms)
  d['features_fully_within_aoi']=sum(AOI.covers(g) for g in geoms)
  polys=[p for g in geoms for p in (list(g.geoms) if g.geom_type=='MultiPolygon' else [g])]
  d['polygon_parts']=len(polys); d['holes']=sum(len(p.interiors) for p in polys)
  rings=[r for p in polys for r in [p.exterior,*p.interiors]]
  d['vertices']=sum(len(r.coords) for r in rings)
  d['unclosed_rings']=sum(r.coords[0]!=r.coords[-1] for r in rings)
  d['coordinate_dimensions']=dict(Counter(len(c) for r in rings for c in r.coords))
 out['files'][name]=d

ref=csvs['potensi_ikan.csv']
out['csv_alignment']={n:{'same_keys':set(v)==set(ref),'same_order':list(v)==list(ref),'max_coordinate_delta_deg':max(max(abs(v[k][i]-ref[k][i]) for i in [0,1]) for k in set(v)&set(ref))} for n,v in csvs.items()}
t=Transformer.from_crs(4326,32749,always_xy=True)
projected={k:t.transform(v[0],v[1]) for k,v in ref.items()}
# Affine regression against provided grid indices; validate grid CRS/origin hypothesis.
keys=list(ref); A=np.array([[1,k[0],k[1]] for k in keys]); xy=np.array([projected[k] for k in keys])
coef=np.linalg.lstsq(A,xy,rcond=None)[0]; residual=xy-A@coef
out['grid_fit_utm49s']={'equation':'[E,N] = intercept + grid_x * coefficient_x + grid_y * coefficient_y','coefficients':coef.tolist(),'max_abs_residual_m':np.max(np.abs(residual),axis=0).tolist(),'rms_residual_m':np.sqrt(np.mean(residual**2,axis=0)).tolist()}
out['neighbor_spacing_utm49s']={}
for label,delta in [('x',(1,0)),('y',(0,1))]:
 ds=[math.dist(xy,projected[(k[0]+delta[0],k[1]+delta[1])]) for k,xy in projected.items() if (k[0]+delta[0],k[1]+delta[1]) in projected]
 out['neighbor_spacing_utm49s'][label]={'pairs':len(ds),'min':min(ds),'median':statistics.median(ds),'max':max(ds)}
out['projected_center_range']=[min(p[0] for p in projected.values()), min(p[1] for p in projected.values()),max(p[0] for p in projected.values()),max(p[1] for p in projected.values())]
out['grid_rect_count']=(max(k[0] for k in keys)-min(k[0] for k in keys)+1)*(max(k[1] for k in keys)-min(k[1] for k in keys)+1)
out['grid_missing_in_index_rectangle']=out['grid_rect_count']-len(keys)



import sys, json, csv, shutil
from pathlib import Path

from shapely import make_valid
from shapely.geometry import shape, mapping, box, MultiPolygon
from shapely.geometry.polygon import orient
from shapely.ops import transform
from pyproj import Transformer


assets=root/'assets/geodata'; assets.mkdir(parents=True,exist_ok=True)
report=out
sources={'coral':input_dir/'coralreef(1).geojson','mangrove':input_dir/'mangrove_2023_jatim.geojson'}
aoi=box(112.25,-9.15,113.10,-8.35)
def parts(g):
 if g.geom_type=='Polygon': return [g] if not g.is_empty and g.area>0 else []
 if hasattr(g,'geoms'): return [p for sub in g.geoms for p in parts(sub)]
 return []
prepared={}
for name,path in sources.items():
 j=json.loads(path.read_text(encoding='utf-8')); features=[]; changes=[]
 for i,f in enumerate(j['features']):
  g=shape(f['geometry']); valid=make_valid(g) if not g.is_valid else g
  clipped=valid.intersection(aoi); ps=[orient(p,sign=1) for p in parts(clipped)]
  if not ps: continue
  geom=ps[0] if len(ps)==1 else MultiPolygon(ps)
  assert geom.is_valid and aoi.covers(geom)
  props=dict(f.get('properties',{})); props['source_feature_index']=i
  features.append({'type':'Feature','id':f'{name}-{i}','properties':props,'geometry':mapping(geom)})
  if not g.is_valid or not aoi.covers(g): changes.append({'source_feature_index':i,'repaired':not g.is_valid,'clipped':not aoi.covers(g),'result_geometry_type':geom.geom_type})
 dst=assets/f'{name}.geojson'
 dst.write_text(json.dumps({'type':'FeatureCollection','features':features},separators=(',',':'),ensure_ascii=False),encoding='utf-8')
 prepared[name]={'features':len(features),'types':{},'changes':changes,'all_valid':True,'all_within_aoi':True}
 for f in features:
  typ=f['geometry']['type']; prepared[name]['types'][typ]=prepared[name]['types'].get(typ,0)+1

csvfiles={name:input_dir/name for name in ['potensi_ikan.csv','suhu_laut.csv','kedalaman_laut.csv']}
for name,path in csvfiles.items(): shutil.copyfile(path,assets/name)
fwd=Transformer.from_crs(4326,32749,always_xy=True)
inv=Transformer.from_crs(32749,4326,always_xy=True)
rows=list(csv.DictReader(csvfiles['potensi_ikan.csv'].open()))
cross=0; maxres=0; full=0; example=None
for r in rows:
 gx=int(r['grid_x']); gy=int(r['grid_y'])
 e=637250+500*gx; n=8987750+500*gy
 actual=fwd.transform(float(r['longitude']),float(r['latitude']))
 maxres=max(maxres,abs(actual[0]-e),abs(actual[1]-n))
 corners=[inv.transform(e+dx,n+dy) for dx,dy in [(-250,-250),(250,-250),(250,250),(-250,250)]]
 poly=shape({'type':'Polygon','coordinates':[[*corners,corners[0]]]})
 if not aoi.covers(poly): cross+=1
 else: full+=1
 if gx==149 and gy==1: example={'grid_x':gx,'grid_y':gy,'center_utm':[e,n],'corners_lon_lat':corners}
prepared['grid']={'origin_lower_left_utm':[637500,8988000],'step_m':500,'center_max_abs_residual_m':maxres,'full_cells_inside_aoi':full,'cells_needing_clip':cross,'example':example}
report['prepared_assets']=prepared
report['validation_scope']='Structural, numeric, topology and spatial checks only; scientific provenance and value units are not verified.'
(root/'validation_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print('Selesai. Audit: '+str(root/'validation_report.json'))

# Tambahan revisi 2: semua entri klorofil dipertahankan; tanpa asumsi waktu.
from prepare_chlorophyll import prepare as prepare_chlorophyll
chlorophyll_manifest = prepare_chlorophyll(input_dir/'klorofil_a.csv',
    input_dir/'potensi_ikan.csv', assets/'klorofil_a')
report['files']['klorofil_a.csv'] = {
    'bytes': chlorophyll_manifest['source_bytes'],
    'sha256': chlorophyll_manifest['source_sha256'],
    'rows': chlorophyll_manifest['rows'],
    'unique_grid_keys': chlorophyll_manifest['unique_grid_keys'],
    'block_count': chlorophyll_manifest['block_count']}
report['prepared_assets']['chlorophyll'] = chlorophyll_manifest
report['revision'] = 2
(root/'validation_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('Tambahan klorofil selesai: 24 entri per sel; tanpa agregasi/asumsi waktu.')
