import vim
import json
import subprocess
import io
import os

import logging
logging.basicConfig(filename='/tmp/vim-rtags-python.log',level=logging.DEBUG)

def get_identifier_beginning():
    line = vim.eval('s:line')
    column = int(vim.eval('s:start'))

    logging.debug(line)
    logging.debug(column)

    while column >= 0 and (line[column].isalnum() or line[column] == '_'):
        column -= 1

    return column + 1

def run_rc_command(arguments, content = None):
    rc_cmd = os.path.expanduser(vim.eval('g:rtagsRcCmd'))
    r = subprocess.run(rc_cmd + " " + arguments, input = content,
            stdout = subprocess.PIPE, stderr = subprocess.PIPE, shell = True,
            encoding = 'utf-8')

    if r.returncode != 0:
        logging.debug(r.stderr)
        return None

    return r.stdout

def get_rtags_variable(name):
    return vim.eval('g:rtags' + name)

def parse_completion_result(data):
    result = json.loads(data)
    logging.debug(result)
    completions = []

    for c in result['completions']:
      k = c['kind']
      kind = ''
      if k == 'FunctionDecl' or k == 'FunctionTemplate':
        kind = 'f'
      elif k == 'CXXMethod' or k == 'CXXConstructor':
        kind = 'm'
      elif k == 'VarDecl':
        kind = 'v'
      elif k == 'macro definition':
        kind = 'd'
      elif k == 'EnumDecl':
        kind = 'e'
      elif k == 'TypedefDecl' or k == 'StructDecl' or k == 'EnumConstantDecl':
        kind = 't'

      match = {'menu': c['completion'], 'word': c['completion'], 'kind': kind}
      completions.append(match)

    return completions

def send_completion_request():
    filename = vim.eval('s:file')
    line = int(vim.eval('s:line'))
    column = int(vim.eval('s:col'))
    prefix = vim.eval('s:prefix')

    for buffer in vim.buffers:
        logging.debug(buffer.name)
        if buffer.name == filename:
            lines = [x for x in buffer]
            content = '\n'.join(lines[:line - 1] + [lines[line - 1] + prefix] + lines[line:])

            cmd = ('--synchronous-completions -l %s:%d:%d --unsaved-file=%s:%d --json'
                % (filename, line, column, filename, len(content)))
            if len(prefix) > 0:
                cmd += ' --code-complete-prefix %s' % prefix

            content = run_rc_command(cmd, content)
            if content == None:
                return None

            return parse_completion_result(content)

    assert False

def display_locations(errors, buffer):
    if len(errors) == 0:
        return

    error_data = json.dumps(errors)
    max_height = int(get_rtags_variable('MaxSearchResultWindowHeight'))
    height = min(max_height, len(errors))

    if int(get_rtags_variable('UseLocationList')) == 1:
        vim.eval('setloclist(%d, %s)' % (buffer.number, error_data))
        vim.command('lopen %d' % height)
    else:
        vim.eval('setqflist(%s)' % error_data)
        vim.command('copen %d' % height)

def display_diagnostics_results(data, buffer):
    data = json.loads(data)
    logging.debug(data)

    check_style = data['checkStyle']
    vim.command('sign unplace *')

    # There are no errors
    if check_style == None:
        return

    filename, errors = list(check_style.items())[0]
    quickfix_errors = []

    vim.command('sign define fixit text=F texthl=FixIt')
    vim.command('sign define warning text=W texthl=Warning')
    vim.command('sign define error text=E texthl=Error')

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

    display_locations(quickfix_errors, buffer)

def get_diagnostics():
    filename = vim.eval('s:file')

    for buffer in vim.buffers:
        if buffer.name == filename:
            is_modified = bool(int((vim.eval('getbufvar(%d, "&mod")' % buffer.number))))
            cmd = '--diagnose %s --synchronous-diagnostics --json' % filename

            content = None
            if is_modified:
                content = '\n'.join([x for x in buffer])
                cmd += ' --unsaved-file=%s:%d' % (filename, len(content))

            content = run_rc_command(cmd, content)
            if content == None:
                return None

            display_diagnostics_results(content, buffer)
