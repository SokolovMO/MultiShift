import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from PIL import Image
from docx import Document
import fitz

ROOT=Path('~/Documents/MultiShift/macos-ui-audit')
WORKER='<TMP>/multi-ui-reviewed-shift/MultiShift.app/Contents/Resources/MultiShiftEngine/MultiShiftEngine'
fixtures=ROOT/'runtime/packaged-engine'; fixtures.mkdir(parents=True,exist_ok=True)
Image.new('RGBA',(96,72),(130,130,130,255)).save(fixtures/'input.png')
doc=fitz.open();page=doc.new_page();page.insert_text((72,72),'native audit fixture');page.insert_image(fitz.Rect(72,100,264,244),filename=str(fixtures/'input.png'));doc.save(fixtures/'input.pdf');doc.close()
doc=Document();doc.add_paragraph('native audit fixture');doc.save(fixtures/'input.docx')
(fixtures/'input.txt').write_text('native audit fixture\n')
items=[]
for target in ['PNG','JPG','WEBP','HEIC','TIFF','AVIF','BMP','PDF','ICO','GIF']:
 items.append(('image-'+target,'convert:'+target,['input.png'],{}))
for source,targets in [('pdf',['JPG','PNG','DOCX','TXT']),('docx',['PDF','TXT']),('txt',['PDF','DOCX'])]:
 for target in targets:items.append((source+'-'+target,'convert:'+target,['input.'+source],{}))
tools=[('Crop',{'x':3,'y':4,'width':20,'height':12}),('Add BG',{'colors':['#eeeeee','#aaaaaa'],'padding':.1}),('Annotate',{'items':[{'kind':'rect','box':[3,4,24,18],'color':'#222222','width':3}]}),('Redact',{'rects':[[3,4,24,18]],'mode':'pixelate'}),('Edit',{'brightness':1.1,'grayscale':True,'rotate':90}),('Metadata',{'mode':'strip'}),('Compress',{'quality':70,'max_side':32,'target':'webp'}),('Resize',{'mode':'exact','width':32,'height':24,'keep_proportions':True})]
for name,params in tools:items.append(('image-tool-'+name.replace(' ','-'),'tool:'+name,['input.png'],params))
for name,params in [('Compress',{}),('Split',{}),('Rotate',{'angle':90}),('Merge',{}),('Protect',{'password':'fixture-only'}),('Extract',{}),('Metadata',{'mode':'strip'})]:
 items.append(('pdf-tool-'+name,'tool:'+name,['input.pdf']*(2 if name=='Merge' else 1),params))
results=[]
for label,action,names,params in items:
 folder=fixtures/label;folder.mkdir(exist_ok=True);sources=[]
 for index,name in enumerate(names):
  dest=folder/(str(index)+'-'+name);shutil.copy2(fixtures/name,dest);sources.append(dest)
 before=[hashlib.sha256(p.read_bytes()).hexdigest() for p in sources]
 request={'request_id':label,'action':action,'files':[str(p) for p in sources],'parameters':params,'settings':{'output':'next'}}
 process=subprocess.run([WORKER],input=json.dumps(request),capture_output=True,text=True,timeout=40)
 try:response=json.loads(process.stdout)
 except Exception:response={'ok':False,'error':'invalid JSON response'}
 outputs=[Path(p) for p in response.get('outputs',[])]
 passed=process.returncode==0 and response.get('ok') is True and bool(outputs) and all(p.is_file() and p.stat().st_size>0 for p in outputs)
 originals=before==[hashlib.sha256(p.read_bytes()).hexdigest() for p in sources]
 results.append({'case':label,'action':action,'passed':bool(passed and originals),'originalsUnchanged':originals,'outputs':len(outputs),'exit':process.returncode,'failures':response.get('failures',[]),'error':response.get('error')})
 print(label,'PASS' if passed and originals else 'FAIL',flush=True)
(ROOT/'runtime/packaged-engine-results.json').write_text(json.dumps({'evidence':'actual frozen worker from delivered preview; real fixture files; UI apply/save excluded','cases':results},indent=2)+'\n')
print('TOTAL',sum(x['passed'] for x in results),'/',len(results))
