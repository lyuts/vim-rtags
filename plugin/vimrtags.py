import vim
import json
import subprocess
import io
import os
import sys
import tempfile
import re
import logging
from time import time


logfile = '%s/vim-rtags-python.log' % tempfile.gettempdir()
loglevel = logging.DEBUG
logger = logging.getLogger(__name__)


def configure_logger():
    handler = logging.FileHandler(logfile)
    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.setLevel(loglevel)

configure_logger()


def get_identifier_beginning():
    line = vim.eval('s:line')
    column = int(vim.eval('s:start'))

    logger.debug(line)
    logger.debug(column)

    while column >= 0 and (line[column].isalnum() or line[column] == '_'):
        column -= 1

    return column + 1

def run_rc_command(arguments, content = None):
    rc_cmd = os.path.expanduser(vim.eval('g:rtagsRcCmd'))
    cmdline = rc_cmd + " " + arguments

    encoding = 'utf-8'
    out = None
    err = None
    logger.debug("RTags command: %s" % cmdline.split())
    if sys.version_info.major == 3 and sys.version_info.minor >= 5:
        r = subprocess.run(
            cmdline.split(),
            input = content and content.encode("utf-8"),
            stdout = subprocess.PIPE,
            stderr = subprocess.PIPE
        )
        out, err = r.stdout, r.stderr
        if not out is None:
            out = out.decode(encoding)
        if not err is None:
            err = err.decode(encoding)

    elif sys.version_info.major == 3 and sys.version_info.minor < 5:
        r = subprocess.Popen(
            cmdline.split(),
            bufsize=0,
            stdout=subprocess.PIPE,
            stdin=subprocess.PIPE,
            stderr=subprocess.STDOUT
        )
        out, err = r.communicate(input=content.encode(encoding))
        if not out is None:
            out = out.decode(encoding)
        if not err is None:
            err = err.decode(encoding)
    else:
        r = subprocess.Popen(
            cmdline.split(),
            stdout=subprocess.PIPE,
            stdin=subprocess.PIPE,
            stderr=subprocess.STDOUT
        )
        out, err = r.communicate(input=content)

    if r.returncode != 0:
        logger.debug(err)
        return None
    elif "is not indexed" in out:
        logger.debug(out)
        return None

    return out


def get_rtags_variable(name):
    return vim.eval('g:rtags' + name)

def parse_completion_result(data):
    result = json.loads(data)
    logger.debug(result)
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

      match = {'menu': " ".join([c['parent'], c['signature']]), 'word': c['completion'], 'kind': kind}
      completions.append(match)

    return completions

def send_completion_request():
    filename = vim.eval('s:file')
    line = int(vim.eval('s:line'))
    column = int(vim.eval('s:col'))
    prefix = vim.eval('s:prefix')

    for buffer in vim.buffers:
        logger.debug(buffer.name)
        if buffer.name == filename:
            lines = [x for x in buffer]
            content = '\n'.join(lines[:line - 1] + [lines[line - 1] + prefix] + lines[line:])

            cmd = ('--synchronous-completions -l %s:%d:%d --unsaved-file=%s:%d --json'
                % (filename, line, column, filename, len(content)))
            if len(prefix) > 0:
                cmd += ' --code-complete-prefix %s' % prefix

            content = run_rc_command(cmd, content)
            logger.debug("Got completion: %s" % content)
            if content == None:
                return None

            return parse_completion_result(content)

    assert False


class Buffer(object):
    _cache = {}
    _cache_last_cleaned = time()
    _CACHE_CLEAN_PERIOD = 30
    _DIAGNOSTICS_CHECK_PERIOD = 5
    _DIAGNOSTICS_LIST_TITLE = "RTags diagnostics"
    _DIAGNOSTICS_ALL_LIST_TITLE = "RTags diagnostics for all files"
    _FIXITS_LIST_TITLE = "RTags fixits applied"

    @staticmethod
    def current():
        return Buffer.get(vim.current.buffer.number)

    @staticmethod
    def find(name):
        """ Find a Buffer by vim buffer (file)name.
        """
        for buffer in vim.buffers:
            if buffer.name == name:
                return Buffer.get(buffer.number)
        else:
            return None

    @staticmethod
    def get(id_):
        """ Get a Buffer wrapping a vim buffer, by id_.

            Create the Buffer if necessary.
        """
        # Get from cache or create if it's not there.
        buff = Buffer._cache.get(id_)
        if buff is not None:
            return buff

        # Periodically clean closed buffers
        if time() - Buffer._cache_last_cleaned > Buffer._CACHE_CLEAN_PERIOD:
            logger.debug("Cleaning invalid buffers")
            for id_ in Buffer._cache.keys():
                if not Buffer._cache[id_]._vimbuffer.valid:
                    logger.debug("Cleaning invalid buffer %s" % id_)
                    del Buffer._cache[id_]
            Buffer._cache_last_cleaned = time()

        buff = Buffer(vim.buffers[id_])
        Buffer._cache[id_] = buff
        return buff

    @staticmethod
    def show_all_diagnostics():
        """ Get all diagnostics for all files and show in quickfix list.
        """
        # Get the diagnostics from rtags.
        content = run_rc_command('--diagnose-all  --synchronous-diagnostics --json')
        if content is None:
            return error('Failed to get diagnostics')
        data = json.loads(content)

        # Construct Diagnostic objects from rtags errors.
        diagnostics = []
        for filename, errors in data['checkStyle'].items():
            diagnostics += Diagnostic.from_rtags_errors(filename, errors)

        if not diagnostics:
            return message("No errors to show")

        # Convert list of Diagnostic objects to quickfix-compatible dict.
        height, lines = Diagnostic.to_qlist_errors(diagnostics)

        # Show diagnostics in location list or quickfix list, depending on user preference.
        if int(get_rtags_variable('UseLocationList')) == 1:
            vim.eval(
                'setloclist(%d, [], " ", {"items": %s, "title": "%s"})'
                % (vim.current.window.number, lines, Buffer._DIAGNOSTICS_ALL_LIST_TITLE)
            )
            vim.command('lopen %d' % height)
        else:
            vim.eval(
                'setqflist([], " ", {"items": %s, "title": "%s"})'
                % (lines, Buffer._DIAGNOSTICS_ALL_LIST_TITLE)
            )
            vim.command('copen %d' % height)

    def __init__(self, buffer):
        self._vimbuffer = buffer
        self._signs = []
        self._diagnostics = {}
        self._last_diagnostics_time = 0
        self._line_num_last = -1
        self._is_line_diagnostic_shown = False
        self._is_dirty = False

        self._project = Project.get(self._vimbuffer.name)

    def on_write(self):
        self._is_dirty = False

    def on_edit(self):
        """ Mark buffer dirty, potentially flagging a reindex using unsaved content.
        """
        if self._project is None:
            return
        self._is_dirty = True

    def on_idle(self):
        """ Reindex or update diagnostics for this buffer.
        """
        if self._project is None:
            return

        if self._is_dirty:
            # `TextChange` autocmd also triggers just by switching buffers, so we have to be sure.
            is_really_dirty = vim.eval('getbufvar(%d, "&mod")' % self._vimbuffer.number)
        else:
            is_really_dirty = False

        if is_really_dirty:
            # Reindex dirty buffer - no point refreshing diagnostics at this point.
            logger.debug("Buffer %s needs dirty reindex" % self._vimbuffer.number)
            self._rtags_dirty_reindex()
            # No point getting diagnostics any time soon.
            self._last_diagnostics_time = time()

        elif self._last_diagnostics_time < self._project.last_updated_time():
            # Update diagnostics signs/list.
            logger.debug(
                "Project updated, checking for updated diagnostics for %s" % self._vimbuffer.name
            )
            self._update_diagnostics()

    def on_cursor_moved(self):
        """ Print diagnostic info for current line
        """
        if self._project is None:
            return
        line_num = vim.current.window.cursor[0]
        if line_num != self._line_num_last:
            self._line_num_last = line_num
            diagnostic = self._diagnostics.get(line_num)
            if diagnostic is not None:
                print(diagnostic.text)
                self._is_line_diagnostic_shown = True
            elif self._is_line_diagnostic_shown:
                # If there is no diagnostic for this line, clear the message.
                print("")
                # Make sure we only clear the message when we've recently shown one, so we don't
                # splat other plugins messages.
                self._is_line_diagnostic_shown = False

    def show_diagnostics_list(self):
        """ Show diagnostics for this buffer in location/quickfix list.

            Diagnostics are updated before being displayed, just in case.
        """
        if self._project is None:
            return invalid_buffer_message(self._vimbuffer.name)

        self._update_diagnostics(open_loclist=True)
        if not self._diagnostics:
            return message("No errors to display")

    def apply_fixits(self):
        """ Fetch fixits from rtags, apply them, and show changed lines in quickfix/location list.
        """
        if self._project is None:
            return invalid_buffer_message(self._vimbuffer.name)
        # Not safe to apply fixits if file is not indexed, make extra sure it is.
        if (
            self._rtags_is_reindexing() or (
                int(vim.eval("g:rtagsAutoDiagnostics")) and
                self._last_diagnostics_time < self._project.last_updated_time()
            )
        ):
            return message(
                "File is currently reindexing, so fixits are unsafe, please try again shortly"
            )

        # Get the fixits from rtags.
        content = run_rc_command('--fixits %s' % self._vimbuffer.name)
        if content is None:
            return error("Failed to fetch fixits")
        content = content.strip()
        if not content:
            return message("No fixits to apply to this file")

        logger.debug("Fixits found:\n%s" % content)
        fixits = content.split('\n')
        lines = []

        # Loop over fixits applying each in turn and record what was done for qlist/loclist.
        for i, fixit in enumerate(fixits):
            # Regex parse the fixits.
            fixit = re.match("^(\d+):(\d+) (\d+) (.+)$", fixit)
            if fixit is None:
                continue
            line_num = int(fixit.group(1))
            line_idx = line_num - 1
            char_num = int(fixit.group(2))
            char_idx = char_num - 1
            length = int(fixit.group(3))
            text = fixit.group(4)

            # Edit the buffer to apply the fixit.
            self._vimbuffer[line_idx] = (
                self._vimbuffer[line_idx][:char_idx] + text +
                self._vimbuffer[line_idx][char_idx + length:]
            )
            # Construct quickfix list compatible dict.
            lines.append({
                'lnum': line_num, 'col': char_num, 'text': text, 'filename': self._vimbuffer.name
            })

        # Calculate height of quickfix list.
        max_height = int(get_rtags_variable('MaxSearchResultWindowHeight'))
        height = min(max_height, len(lines))
        lines = json.dumps(lines)

        # Render lines fixed to location list and open it.
        vim.eval(
            'setloclist(%d, [], " ", {"items": %s, "title": "%s"})'
            % (vim.current.window.number, lines, Buffer._FIXITS_LIST_TITLE)
        )
        vim.command('lopen %d' % height)

        message("Fixits applied")

    def _place_signs(self):
        """ Add gutter indicator signs next to lines that have diagnostics.
        """
        self._reset_signs()
        used_ids = Sign.used_ids(self._vimbuffer.number)
        for diagnostic in self._diagnostics.values():
            self._place_sign(diagnostic.line_num, diagnostic.type, used_ids)

    def _rtags_dirty_reindex(self):
        """ Reindex unsaved buffer contents in rtags.
        """
        content = "\n".join([x for x in self._vimbuffer])
        result = run_rc_command(
            '--json --reindex {0} --unsaved-file={0}:{1}'.format(
                self._vimbuffer.name, len(content)
            ), content
        )
        self._is_dirty = False
        logger.debug("Rtags responded to reindex request: %s" % result)

    def _rtags_is_reindexing(self):
        """ Check if rtags has this buffer queued for reindexing.
        """
        # Unfortunately, --check-reindex doesn't work if --unsaved-file used with --reindex.
        content = run_rc_command('--status jobs')
        if content is None:
            return error("Failed to check if %s needs reindex" % self._vimbuffer.name)
        return self._vimbuffer.name in content

    def _update_diagnostics(self, open_loclist=False):
        """ Fetch new diagnostics from rtags and update gutter signs and location list.
        """
        # Reset current diagnostics.
        self._diagnostics = {}
        # Reset diagnostic timer, so we don't query too often.
        self._last_diagnostics_time = time()

        # Get the diagnostics from rtags.
        content = run_rc_command(
            '--diagnose %s --synchronous-diagnostics --json' % self._vimbuffer.name
        )
        if content is None:
            return error('Failed to get diagnostics for "%s"' % self._vimbuffer.name)
        logger.debug("Diagnostics for %s from rtags: %s" % (self._vimbuffer.name, content))
        data = json.loads(content)
        errors = data['checkStyle'][self._vimbuffer.name]

        # Construct Diagnostic objects from rtags response, and cache keyed by line number.
        for diagnostic in Diagnostic.from_rtags_errors(self._vimbuffer.name, errors):
            self._diagnostics[diagnostic.line_num] = diagnostic

        # Update location list with new diagnostics, if ours is currently at the top of the stack.
        self._update_loclist(open_loclist)
        # Place gutter signs next to lines with diagnostics to show.
        self._place_signs()
        # Flag that we've changed cursor line to trick into rerendering diagnostic message.
        self._line_num_last = -1
        self.on_cursor_moved()

    def _update_loclist(self, force):
        """ Update the location list for the current buffer with updated diagnostics.

            Unfortunately, there doesn't seem to be a simple way to know if the location list for
            the current window is actually visible, so just always update it if it's at the top of
            the stack.

            If `force` is given then always update, and show, the location list.
        """
        # Only bother updating if the active window is showing this buffer.
        if self._vimbuffer.number != vim.current.window.buffer.number:
            return
        # Get title of this buffer's location list, if available.
        loclist_info = vim.eval(
            'getloclist(%s, {"title": 0})' % vim.current.window.number
        )
        loclist_title = loclist_info.get('title')
        # If the title matches our location list, then we want to update, otherwise either create
        # or quit.
        is_rtags_loclist_open = loclist_title == Buffer._DIAGNOSTICS_LIST_TITLE
        if not force and not is_rtags_loclist_open:
            logger.debug("Location list not open (title=%s) so not updating it" % loclist_title)
            return

        logger.debug("Updating location list with %s diagnostics" % len(self._diagnostics))

        # Get our diagnostics as quicklist/loclist formatted dict.
        height, lines = Diagnostic.to_qlist_errors(self._diagnostics.values())
        # If our loclist is open, we want to replace the contents, otherwise create a new loclist.
        if is_rtags_loclist_open:
            action = "r"
        else:
            action = " "

        # Create/replace the loclist with our diagnostics.
        vim.eval(
            'setloclist(%d, [], "%s", {"items": %s, "title": "%s"})'
            % (vim.current.window.number, action, lines, Buffer._DIAGNOSTICS_LIST_TITLE)
        )

        # If we want to open the loclist and we have something to show, then open it.
        if force:
            if height > 0:
                vim.command('lopen %d' % height)
            else:
                message("No errors to show")

    def _place_sign(self, line_num, name, used_ids):
        """ Create, place and remember a diagnostic gutter sign.
        """
        # Get last sign ID that we used in this buffer.
        id_ = self._signs and self._signs[-1].id or Sign.START_ID
        # We need a new ID.
        id_ += 1
        # Other plugins could have added signs, so make sure we don't splat them.
        while id_ in used_ids:
            id_ += 1
        logger.debug(
            'Appending sign %s on line %s with id %s in buffer %s (%s)' % (
                name, line_num, id_, self._vimbuffer.number, self._vimbuffer.name
            )
        )
        # Construct a Sign, which will also render it in the buffer, and cache it.
        self._signs.append(Sign(id_, line_num, name, self._vimbuffer.number))

    def _reset_signs(self):
        """ Remove all diagnostic signs from buffer gutter and reset our cache of them.
        """
        for sign in self._signs:
            sign.unplace()
        self._signs = []


class Project(object):
    """ Wrapper for an rtags "project".

        Used to track last modification time of rtags index database.
    """

    _rtags_data_dir = None
    _cache = {}

    @staticmethod
    def get(filepath):
        # A blank filename (e.g. loclist) has no project.
        if not filepath:
            return None
        # Get rtags project that given file belongs to, if any.
        project_root = run_rc_command('--project %s' % filepath)
        # If rc command line failed, then assume nothing to do.
        if project_root is None:
            return None
        # If no rtags project, then nothing to do.
        if project_root.startswith("No matches"):
            logger.debug("No rtags project found for %s" % filepath)
            return None

        # Lazily find the location of the rtags database. We check the modification date of the DB
        # to decide if/when we need to update our cache.
        if Project._rtags_data_dir is None:
            info = run_rc_command('--status info')
            logger.debug("RTags info:\n%s" % info)
            match = re.search("^dataDir: (.*)$", info, re.MULTILINE)
            Project._rtags_data_dir = match.group(1)
            logger.info("RTags data directory set to %s" % Project._rtags_data_dir)

        project_root = project_root.strip()
        # Get the project for the given file from the cache, if available.
        project = Project._cache.get(project_root)
        if project is not None:
            return project

        # Create a new Project and cache it.
        logger.info("Found RTags project %s for %s" % (project_root, filepath))
        project = Project(project_root)
        Project._cache[project_root] = project
        return project

    def __init__(self, project_root):
        self._project_root = project_root
        # Calculate the path of project database in the RTags data directory.
        self._db_path = os.path.join(
            Project._rtags_data_dir, project_root.replace("/", "_"), "project"
        )
        logger.debug("Project %s db path set to %s" % (self._project_root, self._db_path))

    def last_updated_time(self):
        """ Unix timestamp when the rtags database was last updated.
        """
        return os.path.getmtime(self._db_path)


class Diagnostic(object):

    @staticmethod
    def from_rtags_errors(filename, errors):
        diagnostics = []
        for e in errors:
            if e['type'] == 'skipped':
                continue
            # strip error prefix
            s = ' Issue: '
            index = e['message'].find(s)
            if index != -1:
                e['message'] = e['message'][index + len(s):]
                diagnostics.append(
                    Diagnostic(filename, e['line'], e['column'], e['type'], e['message'])
                )
        return diagnostics

    @staticmethod
    def to_qlist_errors(diagnostics):
        num_diagnostics = len(diagnostics)
        lines = [d._to_qlist_dict() for d in diagnostics]
        lines = sorted(lines, key=lambda d: (d['type'], d['filename'], d['lnum']))
        lines = json.dumps(lines)

        max_height = int(get_rtags_variable('MaxSearchResultWindowHeight'))
        height = min(max_height, num_diagnostics)

        return height, lines

    def __init__(self, filename, line_num, char_num, type_, text):
        self.filename = filename
        self.line_num = line_num
        self.char_num = char_num
        self.type = type_
        self.text = text

    def _to_qlist_dict(self):
        error_type = self.type[0].upper()
        return {
            'lnum': self.line_num, 'col': self.char_num, 'text': self.text,
            'filename': self.filename, 'type': error_type
        }


class Sign(object):
    START_ID = 2000
    _is_signs_defined = False

    @staticmethod
    def _define_signs():
        """ Define highlight group and gutter signs for diagnostics.

            Must do this lazily because other plugins can go and change SignColumn highlight
            group on initialisation (e.g. gitgutter).
        """
        logger.debug("Defining gutter diagnostic signs")
        def get_bgcolour(group):
            logger.debug("Scanning highlight group %s for background colour" % group)
            output = get_command_output("highlight %s" % group)
            logger.debug("Highlight group output:\n%s" % output)
            match = re.search(r"links to (\S+)", output)
            if match is None:
                ctermbg_match = re.search(r"ctermbg=(\S+)", output)
                guibg_match = re.search(r"guibg=(\S+)", output)
                return (
                    ctermbg_match and ctermbg_match.group(1),
                    guibg_match and guibg_match.group(1)
                )
            return get_bgcolour(match.group(1))

        ctermbg, guibg = get_bgcolour("SignColumn")
        bg = ""
        if guibg is not None:
            bg += " guibg=%s" % guibg
        if ctermbg is not None:
            bg += " ctermbg=%s" % ctermbg

        logger.debug("Background colours are %s, %s" % (ctermbg, guibg))
        vim.command(
            "highlight rtags_fixit guifg=#ff00ff ctermfg=5 %s" % bg
        )
        vim.command(
            "highlight rtags_warning guifg=#fff000 ctermfg=11 %s" % bg
        )
        vim.command(
            "highlight rtags_error guifg=#ff0000 ctermfg=1 %s" % bg
        )

        vim.command("sign define rtags_fixit text=Fx texthl=rtags_fixit")
        vim.command("sign define rtags_warning text=W texthl=rtags_warning")
        vim.command("sign define rtags_error text=E texthl=rtags_error")
        Sign._is_signs_defined = True

    @staticmethod
    def used_ids(buffer_num):
        signs_txt = get_command_output("sign place buffer=%s" % buffer_num)
        sign_ids = set()
        for sign_match in re.finditer("id=(\d+)", signs_txt):
            sign_ids.add(int(sign_match.group(1)))
        return sign_ids

    def __init__(self, id, line_num, name, buffer_num):
        self.id = id
        self._vimbuffer_num = buffer_num
        if not Sign._is_signs_defined:
            Sign._define_signs()
        vim.command(
            'sign place %d line=%s name=rtags_%s buffer=%s' % (
                self.id, line_num, name, self._vimbuffer_num
            )
        )

    def unplace(self):
        vim.command('sign unplace %s buffer=%s' % (self.id, self._vimbuffer_num))


def get_command_output(cmd_txt):
    return vim.eval('rtags#getCommandOutput("%s")' % cmd_txt)


def invalid_buffer_message(filename):
    print(
        "No RTags project for file: %s" % filename
        if filename else "Please select a file buffer and try again"
    )


def error(msg):
    message("""%s: see log file at" "%s" for more information""" % (msg, logfile))


def message(msg):
    vim.command("""echom '%s'""" % msg)

