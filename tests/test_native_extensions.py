from pathlib import Path
import zipfile
import numpy as np
from PIL import Image
from dragshift.engine_cli import handle
from dragshift import media, convert


def test_target_compression_real_byte_limit_and_original(tmp_path):
    src = tmp_path / 'photo.png'
    Image.fromarray(np.random.default_rng(9).integers(0,256,(600,900,3),dtype=np.uint8)).save(src)
    original = src.read_bytes()
    result = handle({'action':'tool:Compress','files':[str(src)],'parameters':{'target_bytes':50000}})
    assert result['ok']
    assert Path(result['outputs'][0]).stat().st_size <= 50000
    assert src.read_bytes() == original
    assert result['metrics']['after_bytes'] <= 50000


def test_preview_uses_save_pipeline_for_warmth_sharpness(tmp_path, monkeypatch):
    monkeypatch.setenv('MULTISHIFT_CACHE_DIR', str(tmp_path/'cache'))
    src = tmp_path/'photo.png'
    Image.fromarray(np.random.default_rng(5).integers(0,256,(80,120,3),dtype=np.uint8)).save(src)
    p = {'warmth':0.6,'sharpness':1.8,'flip_h':True}
    preview = handle({'operation':'render','path':str(src),'action':'tool:Edit','parameters':p})
    save = handle({'action':'tool:Edit','files':[str(src)],'parameters':p})
    assert np.array_equal(np.asarray(Image.open(preview['preview']['path'])), np.asarray(Image.open(save['outputs'][0])))
    assert preview['metrics']['after_dimensions'] == [120,80]
    assert not list(tmp_path.glob('*Edited (1)*'))


def test_multiple_marks_freehand_steps_and_reverse_arrow(tmp_path):
    src = tmp_path/'image.png'; Image.new('RGB',(200,200),'white').save(src)
    items = [
        {'kind':'arrow','box':[170,160,20,20],'color':'#ff0000','width':5},
        {'kind':'pen','box':[10,100,100,150],'points':[[10,100],[50,130],[100,150]],'color':'#0000ff','width':4},
        {'kind':'highlight','box':[10,180,190,180],'points':[[10,180],[190,180]],'color':'#ffcc00','width':4},
        {'kind':'step','box':[100,60,110,70],'text':'1','color':'#000000','width':4}]
    result = handle({'action':'tool:Annotate','files':[str(src)],'parameters':{'items':items}})
    assert result['ok']
    out = Image.open(result['outputs'][0]).convert('RGB')
    assert out.getpixel((50,130))[2] > 200 and out.getpixel((50,130))[0] < 50
    assert out.getpixel((88,60)) == (0,0,0)
    assert out.getpixel((80,180))[2] < 255


def test_archive_folder_skips_links_keeps_contents_and_original(tmp_path):
    folder = tmp_path/'project';folder.mkdir(); (folder/'nested').mkdir()
    (folder/'nested'/'keep.txt').write_text('important')
    (folder/'link').symlink_to(tmp_path/'outside.txt');(tmp_path/'outside.txt').write_text('private')
    result = handle({'action':'convert:ZIP','files':[str(folder)]})
    assert result['ok']
    with zipfile.ZipFile(result['outputs'][0]) as archive:
        assert archive.read('project/nested/keep.txt') == b'important'
        assert not any('link' in n for n in archive.namelist())
    assert (folder/'nested'/'keep.txt').read_text() == 'important'


def test_capabilities_and_formatted_markdown(tmp_path):
    src = tmp_path/'notes.md';src.write_text('# Heading\n\n**Bold**\n\n- First\n- Second\n')
    result = handle({'operation':'capabilities','path':str(src)})
    assert 'PDF' in result['targets'] and 'MD' not in result['targets']
    out = handle({'action':'convert:PDF','files':[str(src)]})
    with convert.fitz.open(out['outputs'][0]) as pdf:
        assert pdf.metadata['title'] == 'Heading'
        assert 'Heading' in pdf[0].get_text() and '**' not in pdf[0].get_text()


def test_media_preview_and_native_protocol(tmp_path, monkeypatch):
    monkeypatch.setenv('MULTISHIFT_CACHE_DIR',str(tmp_path/'cache'))
    src = tmp_path/'tone.wav';src.write_bytes(media.silent_wav(1.0))
    result = handle({'operation':'media_render','path':str(src),'action':'tool:Edit','parameters':{'speed':2}})
    info = media.probe(result['media_preview'])
    assert result['ok'] and 0.35 < info.duration < 0.7
    saved = handle({'action':'tool:Edit','files':[str(src)],'parameters':{'speed':2}})
    assert saved['ok'] and Path(saved['outputs'][0]).exists()


def test_auto_enhance_combines_with_manual_grayscale(tmp_path):
    src = tmp_path/'image.png';Image.new('RGB',(80,60),(180,60,20)).save(src)
    result=handle({'action':'tool:Edit','files':[str(src)],'parameters':{'auto':True,'grayscale':True,'rotate':90}})
    image=Image.open(result['outputs'][0]).convert('RGB')
    assert image.size == (60,80)
    assert len(set(image.getpixel((10,10)))) == 1


def test_pdf_to_word_keeps_stdout_as_single_json(tmp_path):
    import subprocess, sys, json
    src=tmp_path/'sample.pdf'
    with convert.fitz.open() as pdf:
        page=pdf.new_page();page.insert_text((40,40),'Protocol check');pdf.save(src)
    result=subprocess.run([sys.executable, 'engine_main.py'],input=json.dumps({'request_id':'wire-test','action':'convert:DOCX','files':[str(src)]}),text=True,capture_output=True)
    response=json.loads(result.stdout)
    assert response['request_id']=='wire-test' and response['ok']
