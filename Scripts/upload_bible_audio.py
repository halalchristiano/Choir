#!/usr/bin/env python3
"""Prepare a scoped temporary uploader, then publish verified audio and catalog.

Deploy the prepared function through the connected Supabase tool before upload.
The import token stays outside Git; the function contains only its SHA-256.
"""
import argparse
import hashlib
import json
import secrets
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = 'https://zliyxnvqnxmzgwltssjk.supabase.co'
FUNCTION = 'gospel-audio-import-20261024'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def jobs(root):
    catalog_path = root/'catalog.json'
    catalog = json.loads(catalog_path.read_text())
    assert catalog['schemaVersion'] == 1 and catalog['voiceID'] == 'evan-bsb-v1' and catalog['translation'] == 'BSB'
    scope = json.loads((root/'publication-scope.json').read_text())
    expected = {(item['book'], number) for item in scope['books'] for number in item['chapters']}
    actual = [(entry['book'], entry['chapter']) for entry in catalog['chapters']]
    assert expected and len(actual) == len(expected) and set(actual) == expected, 'Publish exactly the completed requested scope'
    result=[]
    for entry in catalog['chapters']:
        folder = root/'chapters'/f'{entry["book"].lower().replace(" ", "-")}-{entry["chapter"]:02d}'
        receipt = json.loads((folder/'recording.json').read_text())
        assert receipt['catalog_entry'] == entry
        file = Path(receipt['local_audio'])
        assert file.stat().st_size == entry['byteCount'] and digest(file.read_bytes()) == entry['audioSHA256']
        result.append(dict(file=str(file), path=entry['audioPath'], bytes=entry['byteCount'], sha256=entry['audioSHA256'], mime='audio/mp4'))
    result.append(dict(file=str(catalog_path),path='evan-bsb/current.json',bytes=catalog_path.stat().st_size,
        sha256=digest(catalog_path.read_bytes()),mime='application/json'))
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('root', type=Path)
    p.add_argument('action', choices=['prepare','upload'])
    args = p.parse_args()
    root = args.root.resolve()/'gospels-v1'
    files = jobs(root)
    token_file = root/'private-upload-token'
    if args.action == 'prepare':
        if not token_file.exists():
            token_file.write_text(secrets.token_hex(32))
            token_file.chmod(0o600)
        allowlist = {item['path']:{k:item[k] for k in ('bytes','sha256','mime')} for item in files}
        template = Path(__file__).with_name('bible_audio_upload_proxy.ts').read_text()
        template = template.replace('__ALLOWLIST__',json.dumps(allowlist,separators=(',',':')))
        template = template.replace('__EXPIRY__',str(int((time.time()+12*3600)*1000)))
        template = template.replace('__TOKEN_DIGEST__',digest(token_file.read_bytes()))
        (root/'temporary-upload-proxy.ts').write_text(template)
        (root/'upload-plan.json').write_text(json.dumps(files,indent=2)+'\n')
        print(f'Prepared {len(files)-1} exact chapter files and catalog for {FUNCTION}',flush=True)
        return
    assert json.loads((root/'upload-plan.json').read_text()) == files, 'Re-prepare and deploy updated allowlist first'
    def call(query, data=b''):
        request = Request(BASE+'/functions/v1/'+FUNCTION+'?'+urlencode(query),data=data,
            headers={'x-import-token':token_file.read_text(),'Content-Type':'application/octet-stream','Content-Length':str(len(data))},method='POST')
        with urlopen(request,timeout=180) as response:
            return json.load(response)
    print(call({'action':'init'}),flush=True)
    receipts=[]
    for item in files:
        url = BASE+'/storage/v1/object/public/bible-audio/'+item['path']
        status='uploaded'
        try:
            with urlopen(url+'?check='+str(time.time_ns()),timeout=120) as response:
                existing=response.read()
            if digest(existing)==item['sha256'] and len(existing)==item['bytes']:
                status='verified_existing'
        except HTTPError as error:
            if error.code not in (400,404):
                raise
        if status=='uploaded':
            result=call({'path':item['path']},Path(item['file']).read_bytes())
            assert result['sha256']==item['sha256'] and result['bytes']==item['bytes']
        with urlopen(url+'?check='+str(time.time_ns()),timeout=120) as response:
            stored=response.read()
        assert len(stored)==item['bytes'] and digest(stored)==item['sha256']
        if item['mime']=='audio/mp4':
            with urlopen(Request(url,headers={'Range':'bytes=0-1023'}),timeout=30) as response:
                assert response.status==206 and response.read()==stored[:1024]
        receipts.append(dict(path=item['path'],url=url,bytes=item['bytes'],sha256=item['sha256'],status=status,
            verified_at=time.time(),verification='full public object SHA-256; audio also checked with HTTP range'))
        (root/'upload-receipts.json').write_text(json.dumps(receipts,indent=2)+'\n')
        print(status,item['path'],flush=True)
    print(f'UPLOAD_COMPLETE {len(files)-1} chapters; catalog published last',flush=True)


if __name__ == '__main__':
    main()
