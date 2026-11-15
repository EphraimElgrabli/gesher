#!/usr/bin/env python3
"""Opt-in native lifecycle check. Writes only unique QA containers and cleans exact IDs."""
import argparse
import json
import os
import subprocess
import tempfile
import uuid
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--run-live', action='store_true', required=True)
parser.add_argument('--bin-dir', type=Path, default=Path('.build/release'))
parser.add_argument('--calendar-source', help='Calendar account id (calendar-cli account list); otherwise require one unique local account')
parser.add_argument('--network', action='store_true', help='Also exercise Maps routes and Weather forecasts without changing data')
args = parser.parse_args()
if not args.run_live:
    parser.error('--run-live is required; this test creates temporary Apple app data')
root = args.bin_dir.resolve()
prefix = 'QA-gesher-' + str(uuid.uuid4())
# Backups of QA fixtures go to a temporary directory, not the user's backup folder.
os.environ['GESHER_BACKUP_DIR'] = tempfile.mkdtemp(prefix='QA-gesher-backups-')


def invoke(app, *command, stdin=None, absent=False):
    p = subprocess.run([str(root / f'{app}-cli'), *command], input=stdin,
                       capture_output=True, text=True, timeout=30)
    value = json.loads(p.stdout)
    if absent:
        assert p.returncode == 1 and value.get('error', {}).get('code') == 'not_found', value.get('error')
        return None
    if p.returncode or value.get('ok') is False or 'error' in value:
        raise RuntimeError(value.get('error'))
    # Converted apps (AgentOperation) print the result itself; legacy apps wrap it in {ok, data}.
    return value['data'] if 'ok' in value else value


def reminders():
    group_id = list_id = None
    try:
        group_id = invoke('reminders', 'list', 'create', prefix + ' group', '--kind', 'group')['id']
        result = invoke('reminders', 'list', 'create', prefix, '--group', group_id, '--emoji', '🍎', '--color', '#FF9500')
        list_id = result['id']
        assert result['emoji'] == '🍎' and result['color'].upper() in ('#FF9500', '#FF9500FF') and result['group']
        result = invoke('reminders', 'list', 'update', list_id, '--name', prefix + ' renamed', '--emoji', '🥕', '--ungroup')
        assert result['emoji'] == '🥕' and 'group' not in result
        invoke('reminders', 'section', 'create', '--list', list_id, prefix + ' vegetables', prefix + ' fruit')
        invoke('reminders', 'section', 'update', '--list', list_id, prefix + ' fruit', '--position', '1')
        created = invoke('reminders', 'task', 'create', '--json', json.dumps({'list': list_id, 'items': [
            {'title': prefix + ' task', 'section': prefix + ' vegetables', 'due': '2030-11-01',
             'url': 'https://example.com/gesher-qa', 'tags': ['qa'], 'priority': 'high'},
            {'title': prefix + ' subtask', 'parent': prefix + ' task', 'due': '2030-11-01 09:30', 'earlyAlert': '1h'},
            {'title': prefix + ' weekly', 'due': '2030-11-04 08:00', 'repeats': 'weekly on mon,thu'}]}))
        task, subtask, weekly = [entry['result'] for entry in created['results']]
        assert task['section'] == prefix + ' vegetables' and task['due'] == '2030-11-01' and task['allDay']
        assert subtask['parent'] == task['id'] and subtask['earlyAlert'] == '1h before'
        invoke('reminders', 'task', 'update', task['id'], '--flagged', '--add-tags', 'more', '--clear', 'section')
        done = invoke('reminders', 'task', 'complete', weekly['id'])['results'][0]['result']
        assert done['nextDue'].startswith('2030-11-07T08:00')
        found = invoke('reminders', 'tasks', '--list', list_id, '--view', 'flagged')['tasks']
        assert [t['id'] for t in found] == [task['id']] and 'section' not in found[0]
        invoke('reminders', 'task', 'delete', task['id'])
        remaining = invoke('reminders', 'tasks', '--list', list_id, '--include-completed')['tasks']
        assert not {task['id'], subtask['id']} & {t['id'] for t in remaining}, 'parent and subtask deleted'
    finally:
        for identifier in [list_id, group_id]:
            if identifier:
                invoke('reminders', 'list', 'delete', identifier)
                lists = invoke('reminders', 'lists')
                assert identifier not in [l['id'] for l in lists['lists']] + [g['id'] for g in lists.get('groups', [])]


def notes():
    parent = child = note = None
    try:
        parent = invoke('notes', 'folder', 'create', prefix)['results'][0]['result']['id']
        child = invoke('notes', 'folder', 'create', prefix + ' child', '--parent', parent)['results'][0]['result']['id']
        document = json.dumps({'paragraphs': [
            {'style': 'body', 'runs': [{'text': 'טקסט מודגש', 'bold': True}]},
            {'style': 'body', 'runs': [], 'table': [['כותרת', 'עמודה'], ['ערך', 'נתון']]}]}, ensure_ascii=False)
        note = invoke('notes', 'note', 'create', '--folder', child, '--title', prefix, '--document', document)['id']
        before = invoke('notes', 'note', 'get', note)
        invoke('notes', 'note', 'append', '--note', note, 'פסקה נוספת', '--if-revision', before['revision'])
        invoke('notes', 'checklist', 'add', '--note', note, 'חלב', '--top')
        invoke('notes', 'checklist', 'check', '--note', note, '1')
        long_title = (prefix + ' ' + ('כותרת ארוכה מאוד לבדיקת שמירה ' * 12)).strip()
        invoke('notes', 'note', 'update', note, '--title', long_title)
        after = invoke('notes', 'note', 'get', note)
        assert after['title'] == long_title
        assert after['markdown'].split('\n')[1] == '- [x] חלב' and after['markdown'].endswith('פסקה נוספת')
        assert '**טקסט מודגש**' in after['markdown'] and '| ערך | נתון |' in after['markdown']
        invoke('notes', 'note', 'delete', note)
        invoke('notes', 'note', 'delete', note, '--permanent')
        invoke('notes', 'note', 'get', note, absent=True)
        note = None
    finally:
        if note:
            invoke('notes', 'note', 'delete', note)
            invoke('notes', 'note', 'delete', note, '--permanent')
        for folder in (child, parent):
            if folder:
                invoke('notes', 'folder', 'delete', folder)
        if parent:
            assert not [f for f in invoke('notes', 'folder', 'list')['folders'] if f['name'].startswith(prefix)]


def calendar():
    accounts = invoke('calendar', 'account', 'list')['accounts']
    local = [account for account in accounts if account['kind'] == 'local' and account['enabled']]
    account_id = args.calendar_source
    if not account_id:
        if len(local) != 1:
            print('Calendar lifecycle skipped: supply --calendar-source; no unique local account.')
            return
        account_id = local[0]['id']
    calendar_id = event_id = None
    try:
        result = invoke('calendar', 'calendar', 'create', prefix, '--account', account_id, '--color', '#FF9500')
        calendar_id = result['id']
        assert result['color'].upper() == '#FF9500'
        event_id = invoke('calendar', 'event', 'create', prefix, '--calendar', calendar_id,
                          '--start', '2026-11-01T10:00:00Z', '--end', '2026-11-01T11:00:00Z',
                          '--location', 'QA Room')['event']['id']
        invoke('calendar', 'event', 'update', event_id, '--location', 'QA Room Two')
        assert invoke('calendar', 'event', 'get', event_id)['location'] == 'QA Room Two'
        invoke('calendar', 'event', 'update', event_id, '--location', '')
        assert invoke('calendar', 'event', 'get', event_id).get('location') is None
    finally:
        if event_id:
            invoke('calendar', 'event', 'delete', event_id)
            invoke('calendar', 'event', 'get', event_id, absent=True)
        if calendar_id:
            invoke('calendar', 'calendar', 'delete', calendar_id)
            calendars = invoke('calendar', 'calendar', 'list')['calendars']
            assert all(item['id'] != calendar_id for item in calendars)
    print('Calendar color and event lifecycle passed; fixtures cleaned.')


def weather_favorites():
    def saved():
        return invoke('weather', 'location', 'list')['locations']
    baseline = {item['id'] for item in saved()}
    favorite_id = None
    try:
        added = invoke('weather', 'location', 'add', '32.08,34.78', '--name', prefix, '--time-zone', 'Asia/Jerusalem')
        favorite_id = added['results'][0]['result']['id']
        fresh = saved()
        item = next(item for item in fresh if item['id'] == favorite_id)
        assert item['name'] == prefix and item['timeZone'] == 'Asia/Jerusalem'
        assert baseline.issubset({item['id'] for item in fresh})
    finally:
        if favorite_id:
            invoke('weather', 'location', 'remove', favorite_id)
            final_ids = {item['id'] for item in saved()}
            assert favorite_id not in final_ids and baseline.issubset(final_ids)
    print('Weather favorite add, fresh-process read and remove passed; original IDs preserved.')


def contacts():
    """QA contact + group only; existing contacts and groups must be unchanged afterwards."""
    def ids():
        return {c['id'] for c in invoke('contacts', 'list', '--limit', '1000')['contacts']}
    def group_ids():
        return {g['id'] for g in invoke('contacts', 'group', 'list')['groups']}
    baseline, baseline_groups = ids(), group_ids()
    contact_id = group_id = None
    try:
        created = invoke('contacts', 'create', '--first-name', prefix, '--phone', 'mobile: +972 50-000-0000',
                         '--email', 'work: qa@example.invalid', '--birthday=--05-17')
        contact_id = created['id']
        got = invoke('contacts', 'get', '050-0000000')['results'][0]['result']
        assert got['id'] == contact_id and got['birthday'] == '--05-17'
        updated = invoke('contacts', 'update', contact_id, '--add-phone', 'work: 04-000-0000',
                         '--remove-email', 'qa@example.invalid', '--job-title', 'QA')
        assert [p['value'] for p in updated['phones']] == ['+972 50-000-0000', '04-000-0000']
        assert 'emails' not in updated and updated['jobTitle'] == 'QA'
        group = invoke('contacts', 'group', 'create', prefix)['results'][0]['result']
        group_id = group['id']
        assert invoke('contacts', 'group', 'add', '--group', group_id, contact_id)['succeeded'] == 1
        assert invoke('contacts', 'list', group_id)['total'] == 1
        assert invoke('contacts', 'group', 'remove', '--group', group_id, contact_id)['succeeded'] == 1
        assert 'BEGIN:VCARD' in invoke('contacts', 'export', contact_id)['vcard']
    finally:
        if contact_id:
            invoke('contacts', 'delete', contact_id)
        if group_id:
            invoke('contacts', 'group', 'delete', group_id)
        assert ids() == baseline and group_ids() == baseline_groups
    print('Contacts create/get-by-phone/update/group membership/export/delete passed; owner data unchanged.')


def network():
    for mode in ['driving', 'walking', 'cycling', 'transit']:
        command = ['route', '--from', '32.08,34.78', '--to', '32.09,34.79', '--mode', mode, '--no-steps']
        p = subprocess.run([str(root / 'maps-cli'), *command], capture_output=True, text=True, timeout=45)
        response = json.loads(p.stdout)
        if 'error' not in response:
            assert response['from']['latitude'] == 32.08 and response['to']['longitude'] == 34.79
            print('Maps ' + mode + ' explicit endpoint route passed.')
        else:
            assert response['error']['code'] in ('route_unavailable', 'route_service_error'), response['error']
            print('Maps ' + mode + ': ' + response['error']['code'] + '; native route was not verified.')
    for operation in ['current', 'hourly', 'daily']:
        result = invoke('weather', operation, '32.08,34.78')
        assert result is not None
        print('Weather ' + operation + ' native response passed.')


if __name__ == '__main__':
    reminders()
    print('Reminders field, section and deletion readbacks passed; fixtures cleaned.')
    notes()
    print('Notes Hebrew table, formatting, append, title and deletion readbacks passed; fixtures cleaned.')

    calendar()
    weather_favorites()
    contacts()
    if args.network:
        network()
