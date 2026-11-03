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
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = 'https://zliyxnvqnxmzgwltssjk.supabase.co'
FUNCTION = 'gospel-audio-import-20261024'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def jobs(root, catalog_path='evan-bsb/current.json'):
    catalog_file = root/'catalog.json'
    catalog = json.loads(catalog_file.read_text())
    assert catalog['schemaVersion'] == 1 and catalog['voiceID'] == 'evan-bsb-v1' and catalog['translation'] == 'BSB'
    scope = json.loads((root/'publication-scope.json').read_text())
    expected = {(item['book'], number) for item in scope['books'] for number in item['chapters']}
    actual = [(entry['book'], entry['chapter']) for entry in catalog['chapters']]
    assert expected and len(actual) == len(expected) and set(actual) == expected, 'Publish exactly the completed requested scope'
    assert catalog_path in ('evan-bsb/current.json', 'evan-bsb/current-v2.json', 'evan-bsb/current-v3.json')
    if catalog_path == 'evan-bsb/current.json':
        assert len(actual) <= 89, 'Older app builds reject larger catalogs; publish current-v2.json instead'
    if catalog_path != 'evan-bsb/current-v3.json':
        assert catalog_file.stat().st_size <= 2_000_000, 'Installed app builds cap older catalogs at 2 MB; publish current-v3.json instead'
    result=[]
    for entry in catalog['chapters']:
        folder = root/'chapters'/f'{entry["book"].lower().replace(" ", "-")}-{entry["chapter"]:02d}'
        receipt = json.loads((folder/'recording.json').read_text())
        assert receipt['catalog_entry'] == entry
        file = Path(receipt['local_audio'])
        assert file.stat().st_size == entry['byteCount'] and digest(file.read_bytes()) == entry['audioSHA256']
        result.append(dict(file=str(file), path=entry['audioPath'], bytes=entry['byteCount'], sha256=entry['audioSHA256'], mime='audio/mp4'))
    result.append(dict(file=str(catalog_file),path=catalog_path,bytes=catalog_file.stat().st_size,
        sha256=digest(catalog_file.read_bytes()),mime='application/json'))
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('root', type=Path)
    p.add_argument('action', choices=['prepare','upload'])
    p.add_argument('--catalog-path', choices=['evan-bsb/current.json', 'evan-bsb/current-v2.json', 'evan-bsb/current-v3.json'], default='evan-bsb/current.json')
    args = p.parse_args()
    root = args.root.resolve()/'gospels-v1'
    files = jobs(root, args.catalog_path)
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
        # Writes are idempotent: the server accepts only the allowlisted hash
        # and upserts those same bytes at the same path on a retry.
        for attempt in range(4):
            try:
                with urlopen(request,timeout=180) as response:
                    return json.load(response)
            except HTTPError as error:
                if error.code not in (429, 500, 502, 503, 504) or attempt == 3:
                    raise
                error.close()
            except (URLError, OSError):
                if attempt == 3:
                    raise
            print(f'Retrying identical upload after a temporary connection failure ({attempt+1}/3)',flush=True)
            time.sleep(2**attempt)
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
