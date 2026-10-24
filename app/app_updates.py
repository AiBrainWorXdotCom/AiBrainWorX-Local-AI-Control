"""Explicit, read-only update checks against the public AiBrainWorX repository."""
import base64
import json
import re
import urllib.request

REPOSITORY='https://github.com/AiBrainWorXdotCom/AiBrainWorX-Local-AI-Control'
API='https://api.github.com/repos/AiBrainWorXdotCom/AiBrainWorX-Local-AI-Control'


def version_key(value):
    match=re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?',value.strip())
    if not match:
        raise ValueError('Unrecognized version format.')
    return (*map(int,match.group(1,2,3)),{'alpha':0,'beta':1,'rc':2,None:3}[match[4]],int(match[5] or 0))


def request_json(url):
    req=urllib.request.Request(url,headers={'Accept':'application/vnd.github+json','User-Agent':'AiBrainWorX-Update-Check'})
    with urllib.request.urlopen(req,timeout=8) as reply:
        raw=reply.read(512*1024+1)
        if len(raw)>512*1024:
            raise ValueError('Update metadata was too large.')
        return json.loads(raw)


def check(current, include_prereleases=True):
    try:
        releases=request_json(API+'/releases?per_page=20')
        candidates=[]
        for release in releases:
            if release.get('draft') or release.get('prerelease') and not include_prereleases:
                continue
            tag=release.get('tag_name','')
            try:
                key=version_key(tag)
            except ValueError:
                continue
            candidates.append((key,tag))
        if candidates:
            key,latest=max(candidates)
            channel='GitHub release'
            url=REPOSITORY+'/releases'
        else:
            if not include_prereleases:
                return dict(state='no-release',current=current,latest='',url=REPOSITORY+'/releases',detail='No versioned stable release is published. Enable alpha/beta checks to compare the main source package.')
            data=request_json(API+'/contents/VERSION?ref=main')
            latest=base64.b64decode(data['content']).decode('utf-8').strip()
            key=version_key(latest);channel='main source package';url=REPOSITORY
        own=version_key(current)
        state='available' if key>own else 'current' if key==own else 'ahead'
        return dict(state=state,current=current,latest=latest,channel=channel,url=url,
                    detail={'available':'An update is available. Review changes and download the source ZIP; your files have not been changed.',
                            'current':'This copy matches the published version.','ahead':'This development copy is newer than the published version.'}[state])
    except (OSError,ValueError,KeyError,TypeError):
        return dict(state='unavailable',current=current,latest='',url=REPOSITORY,detail='Could not verify updates. Check the connection or try again later; this does not confirm you are up to date.')
