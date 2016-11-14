import vim
import json
import subprocess
import io

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
            # TODO: make it more elegant
            lines = [x for x in buffer]
            content = '\n'.join(lines[:line - 1] + [lines[line - 1] + prefix] + lines[line:])

            cmd = 'rc --synchronous-completions -l %s:%d:%d --unsaved-file=%s:%d --json' % (filename, line, column, filename, len(content))
            if len(prefix) > 0:
                cmd += ' --code-complete-prefix %s' % prefix
            r = subprocess.run(cmd,
                    input = content,
                    stdout = subprocess.PIPE,
                    stderr = subprocess.PIPE,
                    shell = True,
                    encoding = 'utf-8')
            logging.debug(r.returncode)
            logging.debug(r.stderr)

            if r.returncode != 0:
                return -1

            return parse_completion_result(r.stdout)

    assert False
