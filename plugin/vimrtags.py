import vim
import json
import subprocess
import io
import logging

def initialize():
    logfile = vim.eval('g:rtagsPythonLog')
    if logfile != None:
        logging.basicConfig(filename = logfile, level=logging.DEBUG)

def display_diagnostics_results():
    results = vim.eval('s:results')
    if len(results) == 0:
        return

    data = json.loads(results[0])

    filename, errors = list(data['checkStyle'].items())[0]
    quickfix_errors = []

    for i, e in enumerate(errors):
        if e['type'] == 'skipped':
            continue

        # strip error prefix
        s = ' Issue: '
        index = e['message'].find(s)
        if index != -1:
          e['message'] = e['message'][index + len(s):]
          error_type = 'E' if e['type'] == 'error' else 'W'
          quickfix_errors.append({'lnum': e['line'], 'col': e['column'],
              'nr': i, 'text': e['message'], 'filename': filename,
              'type': error_type})
          cmd = 'sign place %d line=%s name=%s file=%s' % (i + 1, e['line'], e['type'], filename)
          vim.command(cmd)

    vim.eval('rtags#DisplayLocations(%s)' % json.dumps(quickfix_errors))
