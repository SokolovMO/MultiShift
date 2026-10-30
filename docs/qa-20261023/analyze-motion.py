"""Measure sidebar's real divider in an unretouched 2x window recording."""
import json, subprocess, sys
import numpy as np
p=sys.argv[1]
raw=subprocess.check_output(['ffmpeg','-v','error','-i',p,'-vf','crop=330:64:90:840,format=gray','-f','rawvideo','-'])
a=np.frombuffer(raw,dtype=np.uint8).reshape(-1,64,330).mean(axis=1)
# The divider runs through the otherwise empty lower portion of the window.
x=(a[:,12:318].argmax(axis=1) if len(sys.argv)>2 and sys.argv[2]=="dark" else a[:,12:318].argmin(axis=1))+102
j=np.abs(np.diff(x)); changing=np.count_nonzero(j)
report={'frames':len(x),'divider_min_px':int(x.min()),'divider_max_px':int(x.max()),'intermediate_positions':int(len(set(x[(x>115)&(x<396)]))),'max_frame_step_px':int(j.max()),'changing_frames':int(changing)}
print(json.dumps(report,indent=2))
assert len(x)>60 and report['intermediate_positions']>=6, 'no continuous transition captured'
assert x.min()>=105 and x.max()<=405, 'divider escaped stable bounds'
