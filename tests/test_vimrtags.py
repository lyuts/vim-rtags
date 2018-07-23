import json
import logging
import sys
try:
    from unittest import TestCase
    from unittest.mock import Mock, MagicMock, patch, call
except ImportError:
    from unittest2 import TestCase
    from mock import Mock, MagicMock, patch, call

#from nose.tools import set_trace

# Create a mocked vim in the environment.
vim = MagicMock()
sys.modules["vim"] = vim
with patch.object(logging, "FileHandler"):
    from plugin import vimrtags

vim.reset_mock()


class VimRtagsTest(TestCase):
    def setUp(self):
        vim.reset_mock()


@patch("plugin.vimrtags.logging", autospec=True)
@patch("plugin.vimrtags.logger", autospec=True)
class Test_configure_logger(VimRtagsTest):

    def test_logs_to_user_defined_file(self, logger, logging):
        vimrtags.configure_logger()

        vim.eval.assert_called_once_with('g:rtagsLog')
        logging.FileHandler.assert_called_once_with(vim.eval.return_value)
        logger.addHandler.assert_called_once_with(logging.FileHandler.return_value)


class Test_parse_completion_result(VimRtagsTest):

    def test(self):
        completions = []
        for kind in (
            'FunctionDecl', 'FunctionTemplate', 'CXXMethod', 'CXXConstructor', 'VarDecl',
            'macro definition', 'EnumDecl', 'TypedefDecl', 'StructDecl', 'EnumConstantDecl',
            'ClassDecl', 'FieldDecl', 'Unknown'
        ):
            completions += self._completion(kind)

        completions = {'completions': completions}

        parsed = vimrtags.parse_completion_result(json.dumps(completions))

        self.assertListEqual(
            parsed, [
                self._with_parent_sig('f'), self._simple('f'), self._simple('f'),
                self._with_parent_sig('f'), self._simple('f'), self._simple('f'),
                self._with_parent_sig('m'), self._simple('m'), self._simple('m'),
                self._with_parent_sig('m'), self._simple('m'), self._simple('m'),
                self._with_parent_sig('v'), self._simple('v'), self._simple('v'),
                self._with_sig('d'), self._simple('d'), self._simple('d'),
                self._with_parent('e'), self._simple('e'), self._simple('e'),
                self._with_parent('t'), self._simple('t'), self._simple('t'),
                self._with_parent('t'), self._simple('t'), self._simple('t'),
                self._with_parent('t'), self._simple('t'), self._simple('t'),
                self._with_parent('t'), self._simple('t'), self._simple('t'),
                self._with_parent('t'), self._simple('t'), self._simple('t'),
                self._with_comment(''), self._simple(''), self._simple('')
            ]
        )

    def _completion(self, kind):
        return [{
            'kind': kind,
            'completion': 'mock completion',
            'parent': 'mock parent',
            'signature': 'mock signature',
            'brief_comment': 'mock comment',
        }, {
            'kind': kind,
            'completion': 'mock completion',
            'parent': 'mock completion',
            'signature': 'mock completion',
            'brief_comment': 'mock completion',
        }, {
            'kind': kind,
            'completion': 'mock completion',
            'parent': '',
            'signature': '',
            'brief_comment': '',
        }]

    def _with_parent_sig(self, kind):
        return {
            'menu': "mock parent -- mock signature -- mock comment",
            'word': "mock completion", 'kind': kind
        }

    def _with_sig(self, kind):
        return {
            'menu': "mock signature -- mock comment", 'word': "mock completion",
            'kind': kind
        }

    def _with_parent(self, kind):
        return {
            'menu': "mock parent -- mock comment", 'word': "mock completion",
            'kind': kind
        }

    def _with_comment(self, kind):
        return {
            'menu': "mock comment", 'word': "mock completion", 'kind': kind
        }

    def _simple(self, kind):
        return {
            'menu': "", 'word': "mock completion", 'kind': kind
        }


@patch("plugin.vimrtags.Buffer", autospec=True)
@patch("plugin.vimrtags.Project", autospec=True)
@patch("plugin.vimrtags.Sign", autospec=True)
@patch("plugin.vimrtags.message", autospec=True)
class Test_reset_caches(VimRtagsTest):
    def test(self, message, Sign, Project, Buffer):
        vimrtags.reset_caches()

        Buffer.reset.assert_called_once_with()
        Project.reset.assert_called_once_with()
        Sign.reset.assert_called_once_with()
        self.assertTrue(message.called)


class Test_Buffer_find(VimRtagsTest):
    def setUp(self):
        super(Test_Buffer_find, self).setUp()
        first = Mock()
        second = Mock(number=9)
        third = Mock()
        first.name = "first buf"
        second.name = "second buf"
        third.name = "third buf"
        vim.buffers = [first, second, third]

    def test_not_found(self):
        buffer = vimrtags.Buffer.find("wont find")
        self.assertIsNone(buffer)

    @patch("plugin.vimrtags.Buffer.get")
    def test_found(self, get):
        buffer = vimrtags.Buffer.find("second buf")
        get.assert_called_once_with(9)
        self.assertIs(buffer, get.return_value)


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.Buffer._cache", {})
class Test_Buffer_get(VimRtagsTest):
    def test_found(self):
        cached_buffer = Mock()
        vimrtags.Buffer._cache = {3: cached_buffer}
        buffer = vimrtags.Buffer.get(3)
        self.assertIs(buffer, cached_buffer)

    @patch("plugin.vimrtags.Project", MagicMock())
    @patch("plugin.vimrtags.Buffer._clean_cache_periodically")
    def test_not_found(self, _clean_cache_periodically):
        vimbuffer = Mock()
        vim.buffers.append(vimbuffer)
        other_buffer = Mock()
        vimrtags.Buffer._cache = {4: other_buffer}

        buffer = vimrtags.Buffer.get(3)
        buffer_again = vimrtags.Buffer.get(3)

        _clean_cache_periodically.assert_called_once_with()
        self.assertIsInstance(buffer, vimrtags.Buffer)
        self.assertIs(buffer._vimbuffer, vimbuffer)
        self.assertDictEqual(vimrtags.Buffer._cache, {3: buffer, 4: other_buffer})
        self.assertIs(buffer, buffer_again)


@patch("plugin.vimrtags.Buffer._cache", None)
@patch("plugin.vimrtags.Buffer._clean_cache")
class Test_Buffer_reset(VimRtagsTest):
    def test(self, _clean_cache):
        buffer1 = Mock(spec=vimrtags.Buffer)
        buffer2 = Mock(spec=vimrtags.Buffer)
        vimrtags.Buffer._cache = {2: buffer1, 7: buffer2}
        calls = MagicMock()
        calls.attach_mock(_clean_cache, "clean")
        calls.attach_mock(buffer1._reset_signs, "reset1")
        calls.attach_mock(buffer2._reset_signs, "reset2")

        vimrtags.Buffer.reset()

        self.assertListEqual(
            calls.method_calls, [
                call.clean(), call.reset1(), call.reset2()
            ]
        )
        self.assertDictEqual(vimrtags.Buffer._cache, {})


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.time", autospec=True)
@patch("plugin.vimrtags.Buffer._cache", None)
@patch("plugin.vimrtags.Buffer._cache_last_cleaned", 6)
@patch("plugin.vimrtags.Buffer._CACHE_CLEAN_PERIOD", 4)
class Test_Buffer__clean_cache_periodically(VimRtagsTest):
    def prepare(self):
        self.buffer = Mock(_vimbuffer=Mock(valid=False))
        vimrtags.Buffer._cache = {3: self.buffer}

    def test_throttled(self, time):
        self.prepare()
        time.return_value = 10
        vimrtags.Buffer._clean_cache_periodically()
        self.assertIs(vimrtags.Buffer._cache[3], self.buffer)

    def test_removes(self, time):
        self.prepare()
        time.return_value = 11
        vimrtags.Buffer._clean_cache_periodically()
        self.assertDictEqual(vimrtags.Buffer._cache, {})


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.Buffer._cache", None)
class Test_Buffer__clean_cache(VimRtagsTest):
    def test(self):
        valid_buffer = Mock(_vimbuffer=Mock(valid=True))
        invalid_buffer = Mock(_vimbuffer=Mock(valid=False))
        vimrtags.Buffer._cache = {3: valid_buffer, 5: invalid_buffer}

        vimrtags.Buffer._clean_cache()

        self.assertDictEqual(vimrtags.Buffer._cache, {3: valid_buffer})


@patch("plugin.vimrtags.run_rc_command", autospec=True)
class Test_Buffer_show_all_diagnostics(VimRtagsTest):

    @patch("plugin.vimrtags.error", autospec=True)
    def test_rc_fails(self, error, run_rc_command):
        run_rc_command.return_value = None
        vimrtags.Buffer.show_all_diagnostics()
        self.assertTrue(error.called)
        self.assertFalse(vim.command.called)

    @patch("plugin.vimrtags.message", autospec=True)
    def test_no_diagnostics(self, message, run_rc_command):
        run_rc_command.return_value = '{"checkStyle": {}}'
        vimrtags.Buffer.show_all_diagnostics()
        self.assertTrue(message.called)
        self.assertFalse(vim.command.called)

    def prepare(self, get_rtags_variable, Diagnostic, run_rc_command):
        run_rc_command.return_value = (
            '{"checkStyle": {"file 1": ["error 1", "error 2"], "file 2": ["error 3"]}}'
        )
        Diagnostic.from_rtags_errors.side_effect = [["diag 1", "diag 2"], ["diag 3"]]
        Diagnostic.to_qlist_errors.return_value = (123, "lines")
        vim.current.window.number = 7

    @patch("plugin.vimrtags.Buffer._DIAGNOSTICS_ALL_LIST_TITLE", "list title")
    @patch("plugin.vimrtags.Diagnostic", autospec=True)
    @patch("plugin.vimrtags.get_rtags_variable", autospec=True)
    def test_use_loclist(self, get_rtags_variable, Diagnostic, run_rc_command):
        self.prepare(get_rtags_variable, Diagnostic, run_rc_command)

        get_rtags_variable.return_value = 1
        vimrtags.Buffer.show_all_diagnostics()

        self.assert_diagnostics_constructed(Diagnostic)
        vim.eval.assert_called_once_with(
            'setloclist(7, [], " ", {"items": lines, "title": "list title"})'
        )
        vim.command.assert_called_once_with("lopen 123")

    @patch("plugin.vimrtags.Buffer._DIAGNOSTICS_ALL_LIST_TITLE", "list title")
    @patch("plugin.vimrtags.Diagnostic", autospec=True)
    @patch("plugin.vimrtags.get_rtags_variable", autospec=True)
    def test_use_qlist(self, get_rtags_variable, Diagnostic, run_rc_command):
        self.prepare(get_rtags_variable, Diagnostic, run_rc_command)

        get_rtags_variable.return_value = 0
        vimrtags.Buffer.show_all_diagnostics()

        self.assert_diagnostics_constructed(Diagnostic)
        vim.eval.assert_called_once_with(
            'setqflist([], " ", {"items": lines, "title": "list title"})'
        )
        vim.command.assert_called_once_with("copen 123")

    def assert_diagnostics_constructed(self, Diagnostic):
        self.assertListEqual(
            Diagnostic.from_rtags_errors.call_args_list, [
                call("file 1", ["error 1", "error 2"]),
                call("file 2", ["error 3"])
            ]
        )
        Diagnostic.to_qlist_errors.assert_called_once_with(["diag 1", "diag 2", "diag 3"])


@patch("plugin.vimrtags.Project", autospec=True)
class Test_Buffer_init(VimRtagsTest):
    def test(self, Project):
        vimbuffer = Mock()
        vimbuffer.name = "mock buffer"

        buffer = vimrtags.Buffer(vimbuffer)

        self.assertIs(buffer._vimbuffer, vimbuffer)
        Project.get.assert_called_once_with("mock buffer")
        self.assertIs(buffer._project, Project.get.return_value)


class MockVimBuffer(list):
    def __init__(self):
        super(MockVimBuffer, self).__init__()
        self.name = "mock buffer"
        self.number = 7


class BufferInstanceTest(VimRtagsTest):
    def setUp(self):
        super(BufferInstanceTest, self).setUp()
        self.project = Mock(spec=vimrtags.Project)
        self.vimbuffer = MockVimBuffer()

        with patch("plugin.vimrtags.Project.get", Mock(return_value=self.project)):
            self.buffer = vimrtags.Buffer(self.vimbuffer)


class Test_Buffer_on_write(BufferInstanceTest):
    def test(self):
        self.buffer._is_dirty = True

        self.buffer.on_write()

        self.assertFalse(self.buffer._is_dirty)


class Test_Buffer_on_edit(BufferInstanceTest):
    def test_no_project(self):
        self.buffer._project = None

        self.buffer.on_edit()

        self.assertFalse(self.buffer._is_dirty)

    def test_has_project(self):
        self.buffer.on_edit()

        self.assertTrue(self.buffer._is_dirty)


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.Buffer._is_really_dirty", autospec=True)
@patch("plugin.vimrtags.Buffer._rtags_dirty_reindex", autospec=True)
@patch("plugin.vimrtags.Buffer._update_diagnostics", autospec=True)
class Test_Buffer_on_idle(BufferInstanceTest):
    def test_no_project(self, _update_diagnostics, _rtags_dirty_reindex, _is_really_dirty):
        self.buffer._project = None

        self.buffer.on_idle()

        self.assertFalse(_is_really_dirty.called)
        self.assertFalse(_update_diagnostics.called)
        self.assertFalse(_rtags_dirty_reindex.called)

    def test_nothing_to_do(self, _update_diagnostics, _rtags_dirty_reindex, _is_really_dirty):
        _is_really_dirty.return_value = False
        self.buffer._last_diagnostics_time = 1
        self.project.last_updated_time.return_value = 1

        self.buffer.on_idle()

        self.assertFalse(_update_diagnostics.called)
        self.assertFalse(_rtags_dirty_reindex.called)

    @patch("plugin.vimrtags.time", autospec=True)
    def test_reindex(self, time, _update_diagnostics, _rtags_dirty_reindex, _is_really_dirty):
        _is_really_dirty.return_value = True

        self.buffer.on_idle()

        self.assertIs(self.buffer._last_diagnostics_time, time.return_value)
        _rtags_dirty_reindex.assert_called_once_with(self.buffer)
        self.assertFalse(_update_diagnostics.called)

    def test_update_diagnostics(self, _update_diagnostics, _rtags_dirty_reindex, _is_really_dirty):
        _is_really_dirty.return_value = False
        self.buffer._last_diagnostics_time = 1
        self.project.last_updated_time.return_value = 2

        self.buffer.on_idle()

        self.assertFalse(_rtags_dirty_reindex.called)
        _update_diagnostics.assert_called_once_with(self.buffer)


@patch("plugin.vimrtags.Buffer._is_really_dirty", autospec=True)
@patch("plugin.vimrtags.Buffer._update_diagnostics", autospec=True)
class Test_Buffer_on_poll(BufferInstanceTest):
    def test_no_project(self, _update_diagnostics, _is_really_dirty):
        self.buffer._project = None

        self.buffer.on_poll()

        self.assertFalse(_is_really_dirty.called)
        self.assertFalse(_update_diagnostics.called)

    def test_is_dirty(self, _update_diagnostics, _is_really_dirty):
        _is_really_dirty.return_value = True
        self.buffer._last_diagnostics_time = 1
        self.project.last_updated_time.return_value = 2

        self.buffer.on_poll()

        self.assertFalse(_update_diagnostics.called)

    def test_too_soon(self, _update_diagnostics, _is_really_dirty):
        _is_really_dirty.return_value = False
        self.buffer._last_diagnostics_time = 2
        self.project.last_updated_time.return_value = 2

        self.buffer.on_poll()

        self.assertFalse(_update_diagnostics.called)

    @patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
    def test_update(self, _update_diagnostics, _is_really_dirty):
        _is_really_dirty.return_value = False
        self.buffer._last_diagnostics_time = 1
        self.project.last_updated_time.return_value = 2

        self.buffer.on_poll()

        _update_diagnostics.assert_called_once_with(self.buffer)


@patch("plugin.vimrtags.print", autospec=True)
class Test_Buffer_on_cursor_moved(BufferInstanceTest):
    def test_no_project(self, print_):
        self.buffer._project = None

        self.buffer.on_cursor_moved()

        self.assertFalse(print_.called)

    def test_line_num_not_changed(self, print_):
        self.buffer._line_num_last = 2
        vim.current.window.cursor = (2, 123)

        self.buffer.on_cursor_moved()

        self.assertFalse(print_.called)

    def test_no_diagnostic_now_or_before(self, print_):
        self.buffer._line_num_last = 1
        vim.current.window.cursor = (2, 123)
        self.buffer._diagnostics = {3: Mock(text="mock diagnostic")}

        self.buffer.on_cursor_moved()

        self.assertFalse(print_.called)

    def test_has_diagnostic(self, print_):
        self.buffer._line_num_last = 1
        vim.current.window.cursor = (3, 123)
        self.buffer._diagnostics = {3: Mock(text="mock diagnostic")}

        self.buffer.on_cursor_moved()

        print_.assert_called_once_with("mock diagnostic")
        self.assertTrue(self.buffer._is_line_diagnostic_shown)

    def test_no_diagnostic_now_but_had_one_before(self, print_):
        self.buffer._line_num_last = 1
        vim.current.window.cursor = (2, 123)
        self.buffer._diagnostics = {3: Mock(text="mock diagnostic")}
        self.buffer._is_line_diagnostic_shown = True

        self.buffer.on_cursor_moved()

        print_.assert_called_once_with("")
        self.assertFalse(self.buffer._is_line_diagnostic_shown)


@patch("plugin.vimrtags.Buffer._update_diagnostics", autospec=True)
class Test_Buffer_show_diagnostics_list(BufferInstanceTest):

    @patch("plugin.vimrtags.invalid_buffer_message", autospec=True)
    def test_no_project(self, invalid_buffer_message, _update_diagnostics):
        self.buffer._project = None

        self.buffer.show_diagnostics_list()

        self.assertFalse(_update_diagnostics.called)
        invalid_buffer_message.assert_called_once_with("mock buffer")

    @patch("plugin.vimrtags.message", autospec=True)
    def test_has_diagnostics(self, message, _update_diagnostics):

        def set_diagnostics(*args, **kwargs):
            self.buffer._diagnostics = "something"

        _update_diagnostics.side_effect = set_diagnostics

        self.buffer.show_diagnostics_list()

        _update_diagnostics.assert_called_once_with(self.buffer, open_loclist=True)
        self.assertFalse(message.called)

    @patch("plugin.vimrtags.message", autospec=True)
    def test_no_diagnostics(self, message, _update_diagnostics):

        def set_diagnostics(*args, **kwargs):
            self.buffer._diagnostics = None

        _update_diagnostics.side_effect = set_diagnostics

        self.buffer.show_diagnostics_list()

        _update_diagnostics.assert_called_once_with(self.buffer, open_loclist=True)
        self.assertTrue(message.called)


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.get_rtags_variable", autospec=True)
@patch("plugin.vimrtags.run_rc_command", autospec=True)
@patch("plugin.vimrtags.Buffer._rtags_is_reindexing", autospec=True)
class Test_Buffer_apply_fixits(BufferInstanceTest):

    def prepare(self, _rtags_is_reindexing, get_rtags_variable):
        _rtags_is_reindexing.return_value = False
        get_rtags_variable.side_effect = ["1", "20"]
        self.buffer._last_diagnostics_time = 1
        self.buffer._project.last_updated_time.return_value = 1

    @patch("plugin.vimrtags.invalid_buffer_message", autospec=True)
    def test_no_project(
        self, invalid_buffer_message, _rtags_is_reindexing, run_rc_command, get_rtags_variable
    ):
        self.prepare(_rtags_is_reindexing, get_rtags_variable)
        self.buffer._project = None

        self.buffer.apply_fixits()

        invalid_buffer_message.assert_called_once_with("mock buffer")
        self.assertFalse(_rtags_is_reindexing.called)
        self.assertFalse(run_rc_command.called)
        self.assertFalse(vim.eval.called)
        self.assertFalse(vim.command.called)

    @patch("plugin.vimrtags.message", autospec=True)
    def test_is_reindexing(
        self, message, _rtags_is_reindexing, run_rc_command, get_rtags_variable
    ):
        self.prepare(_rtags_is_reindexing, get_rtags_variable)
        _rtags_is_reindexing.return_value = True

        self.buffer.apply_fixits()

        self.assertTrue(message.called)
        self.assertFalse(run_rc_command.called)
        self.assertFalse(vim.command.called)

    @patch("plugin.vimrtags.message", autospec=True)
    def test_has_changes_to_project(
        self, message, _rtags_is_reindexing, run_rc_command, get_rtags_variable
    ):
        self.prepare(_rtags_is_reindexing, get_rtags_variable)
        self.buffer._project.last_updated_time.return_value = 2

        self.buffer.apply_fixits()

        self.assertTrue(message.called)
        self.assertFalse(run_rc_command.called)
        self.assertFalse(vim.command.called)

    @patch("plugin.vimrtags.error", autospec=True)
    def test_rc_fails(
        self, error, _rtags_is_reindexing, run_rc_command, get_rtags_variable
    ):
        self.prepare(_rtags_is_reindexing, get_rtags_variable)
        run_rc_command.return_value = None

        self.buffer.apply_fixits()

        run_rc_command.assert_called_once_with(['--fixits', 'mock buffer'])
        self.assertTrue(error.called)
        self.assertFalse(vim.command.called)

    @patch("plugin.vimrtags.message", autospec=True)
    def test_no_fixits_found(
        self, message, _rtags_is_reindexing, run_rc_command, get_rtags_variable
    ):
        self.prepare(_rtags_is_reindexing, get_rtags_variable)
        run_rc_command.return_value = "   "
        vim.current.window.number = 5

        self.buffer.apply_fixits()

        run_rc_command.assert_called_once_with(['--fixits', 'mock buffer'])
        self.assertTrue(message.called)
        self.assertFalse(vim.command.called)

    def prepare_buffer(self, run_rc_command, dumps):
        fixit_txt = """
some junk
1:2 3 first
10:11 12 second
"""
        run_rc_command.return_value = fixit_txt
        vim.current.window.number = 5
        dumps.return_value = "some json"
        self.vimbuffer += [
             "some mock text to be fixed",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "some other mock text to be fixed",
             "not modified",
             "not modified"
        ]

    def assert_buffer_and_loclist(self, dumps, message):
        self.assertListEqual(
            self.vimbuffer, [
             "sfirst mock text to be fixed",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "not modified",
             "some othersecondo be fixed",
             "not modified",
             "not modified"
        ])

        dumps.assert_called_once_with([
            {'lnum': 1, 'col': 2, 'text': "first", 'filename': "mock buffer"},
            {'lnum': 10, 'col': 11, 'text': "second", 'filename': "mock buffer"}
        ])
        vim.eval.assert_called_once_with(
            'setloclist(5, [], " ", {"items": some json, "title": "list title"})'
        )
        self.assertTrue(message.called)

    @patch("plugin.vimrtags.Buffer._FIXITS_LIST_TITLE", "list title")
    @patch("plugin.vimrtags.message", autospec=True)
    @patch("plugin.vimrtags.json.dumps", autospec=True)
    def test_fixits_found_fits_in_max_height(
        self, dumps, message, _rtags_is_reindexing, run_rc_command, get_rtags_variable
    ):
        self.prepare(_rtags_is_reindexing, get_rtags_variable)
        self.prepare_buffer(run_rc_command, dumps)

        self.buffer.apply_fixits()

        self.assert_buffer_and_loclist(dumps, message)
        vim.command.assert_called_once_with('lopen 2')

    @patch("plugin.vimrtags.Buffer._FIXITS_LIST_TITLE", "list title")
    @patch("plugin.vimrtags.message", autospec=True)
    @patch("plugin.vimrtags.json.dumps", autospec=True)
    def test_fixits_found_doesnt_fit_in_max_height(
        self, dumps, message, _rtags_is_reindexing, run_rc_command, get_rtags_variable
    ):
        self.prepare(_rtags_is_reindexing, get_rtags_variable)
        self.prepare_buffer(run_rc_command, dumps)
        get_rtags_variable.side_effect = ["1", "1"]

        self.buffer.apply_fixits()

        self.assert_buffer_and_loclist(dumps, message)
        vim.command.assert_called_once_with('lopen 1')

    @patch("plugin.vimrtags.Buffer._FIXITS_LIST_TITLE", "list title")
    @patch("plugin.vimrtags.message", autospec=True)
    @patch("plugin.vimrtags.json.dumps", autospec=True)
    def test_fixits_found_when_auto_diagnostics_disabled(
        self, dumps, message, _rtags_is_reindexing, run_rc_command, get_rtags_variable
    ):
        self.prepare(_rtags_is_reindexing, get_rtags_variable)
        self.prepare_buffer(run_rc_command, dumps)
        get_rtags_variable.side_effect = ["0", "20"]
        self.buffer._project.last_updated_time.return_value = 2

        self.buffer.apply_fixits()

        self.assert_buffer_and_loclist(dumps, message)
        vim.command.assert_called_once_with('lopen 2')


class Test_Buffer__is_really_dirty(BufferInstanceTest):
    def test_not_dirty(self):
        self.buffer._is_dirty = False

        is_dirty = self.buffer._is_really_dirty()

        self.assertFalse(is_dirty)
        self.assertFalse(vim.eval.called)

    def test_is_dirty_but_not_really(self):
        self.buffer._is_dirty = True
        vim.eval.return_value = "0"

        is_dirty = self.buffer._is_really_dirty()

        vim.eval.assert_called_once_with('getbufvar(7, "&mod")')
        self.assertFalse(is_dirty)

    def test_is_dirty_really(self):
        self.buffer._is_dirty = True
        vim.eval.return_value = "1"

        is_dirty = self.buffer._is_really_dirty()

        vim.eval.assert_called_once_with('getbufvar(7, "&mod")')
        self.assertTrue(is_dirty)


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.run_rc_command", autospec=True)
class Test_Buffer__rtags_dirty_reindex(BufferInstanceTest):
    def test(self, run_rc_command):
        self.vimbuffer += ["ab", "cd"]
        self.buffer._is_dirty = True

        self.buffer._rtags_dirty_reindex()

        run_rc_command.assert_called_once_with([
            '--json', '--reindex', "mock buffer", '--unsaved-file', 'mock buffer:5'
        ], "ab\ncd")
        self.assertFalse(self.buffer._is_dirty)


@patch("plugin.vimrtags.run_rc_command", autospec=True)
class Test_Buffer__rtags_is_reindexing(BufferInstanceTest):

    @patch("plugin.vimrtags.error", autospec=True)
    def test_rc_fails(self, error, run_rc_command):
        run_rc_command.return_value = None

        is_reindexing = self.buffer._rtags_is_reindexing()

        self.assertTrue(error.called)
        self.assertIs(is_reindexing, error.return_value)

    def test_not_reindexing(self, run_rc_command):
        run_rc_command.return_value = "something"

        is_reindexing = self.buffer._rtags_is_reindexing()

        self.assertFalse(is_reindexing)

    def test_is_reindexing(self, run_rc_command):
        run_rc_command.return_value = "something mock buffer something"

        is_reindexing = self.buffer._rtags_is_reindexing()

        self.assertTrue(is_reindexing)


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.time", autospec=True)
@patch("plugin.vimrtags.run_rc_command", autospec=True)
@patch("plugin.vimrtags.Diagnostic", autospec=True)
@patch("plugin.vimrtags.Buffer._update_loclist", autospec=True)
@patch("plugin.vimrtags.Buffer._place_signs", autospec=True)
@patch("plugin.vimrtags.Buffer.on_cursor_moved", autospec=True)
class Test_Buffer__update_diagnostics(BufferInstanceTest):

    @patch("plugin.vimrtags.error", autospec=True)
    def test_rc_failed(
        self, error, on_cursor_moved, _place_signs, _update_loclist, Diagnostic, run_rc_command,
        time
    ):
        run_rc_command.return_value = None

        self.buffer._update_diagnostics()

        self.assertTrue(error.called)
        self.assertFalse(_update_loclist.called)
        self.assertFalse(_place_signs.called)

    def test_success(
        self, on_cursor_moved, _place_signs, _update_loclist, Diagnostic, run_rc_command, time
    ):
        # setup

        self.buffer._diagnostics = "replace me"
        self.buffer._line_num_last = "replace me"
        open_loclist = Mock()

        run_rc_command.return_value = '{"checkStyle": {"mock buffer": ["diag 1", "diag 2"]}}'

        diag1 = Mock(line_num=3)
        diag2 = Mock(line_num=12)
        Diagnostic.from_rtags_errors.return_value = [diag1, diag2]

        on_cursor_moved.side_effect = (
            lambda *a, **k: self.assertEqual(self.buffer._line_num_last, -1)
        )

        # action

        self.buffer._update_diagnostics(open_loclist=open_loclist)

        # confirm

        run_rc_command.assert_called_once_with([
            '--diagnose', "mock buffer", '--synchronous-diagnostics', '--json'
        ])
        Diagnostic.from_rtags_errors.assert_called_once_with("mock buffer", ["diag 1", "diag 2"])

        self.assertDictEqual(self.buffer._diagnostics, {3: diag1, 12: diag2})

        _update_loclist.assert_called_once_with(self.buffer, open_loclist)
        _place_signs.assert_called_once_with(self.buffer)
        on_cursor_moved.assert_called_once_with(self.buffer)


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.Buffer._DIAGNOSTICS_LIST_TITLE", "list title")
@patch("plugin.vimrtags.Diagnostic", autospec=True)
class Test_Buffer__update_loclist(BufferInstanceTest):
    def prepare(self, Diagnostic):
        vim.current.window.number = 6
        vim.current.window.buffer.number = 7
        vim.eval.return_value = {'title': "list title"}
        Diagnostic.to_qlist_errors.return_value = (3, "some json")

    def test_not_current_window(self, Diagnostic):
        self.prepare(Diagnostic)
        vim.current.window.buffer.number = 123

        self.buffer._update_loclist(False)

        self.assertFalse(Diagnostic.to_qlist_errors.called)
        self.assertFalse(vim.eval.called)
        self.assertFalse(vim.command.called)

    def test_not_force_not_already_open(self, Diagnostic):
        self.prepare(Diagnostic)
        vim.eval.return_value = {'title': "some other loclist"}

        self.buffer._update_loclist(False)

        vim.eval.assert_called_once_with('getloclist(6, {"title": 0})')
        self.assertFalse(Diagnostic.to_qlist_errors.called)
        self.assertFalse(vim.command.called)

    def test_not_force_and_already_open(self, Diagnostic):
        self.prepare(Diagnostic)

        self.buffer._update_loclist(False)

        self.assertListEqual(
            vim.method_calls, [
                call.eval('getloclist(6, {"title": 0})'),
                call.eval('setloclist(6, [], "r", {"items": some json, "title": "list title"})')
            ]
        )

    def test_force_and_already_open_no_results(self, Diagnostic):
        self.prepare(Diagnostic)
        Diagnostic.to_qlist_errors.return_value = (0, "some json")

        self.buffer._update_loclist(True)

        self.assertListEqual(
            vim.method_calls, [
                call.eval('getloclist(6, {"title": 0})'),
                call.eval('setloclist(6, [], "r", {"items": some json, "title": "list title"})')
            ]
        )

    def test_force_and_already_open_has_results(self, Diagnostic):
        self.prepare(Diagnostic)

        self.buffer._update_loclist(True)

        self.assertListEqual(
            vim.method_calls, [
                call.eval('getloclist(6, {"title": 0})'),
                call.eval('setloclist(6, [], "r", {"items": some json, "title": "list title"})'),
                call.command('lopen 3')
            ]
        )

    def test_force_not_already_open_has_results(self, Diagnostic):
        self.prepare(Diagnostic)
        vim.eval.return_value = {'title': "some other loclist"}

        self.buffer._update_loclist(True)

        self.assertListEqual(
            vim.method_calls, [
                call.eval('getloclist(6, {"title": 0})'),
                call.eval('setloclist(6, [], " ", {"items": some json, "title": "list title"})'),
                call.command('lopen 3')
            ]
        )


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.Sign", autospec=True)
@patch("plugin.vimrtags.Buffer._reset_signs")
@patch("plugin.vimrtags.Buffer._place_sign")
class Test_Buffer__place_signs(BufferInstanceTest):

    def test(self, _place_sign, _reset_signs, Sign):
        self.buffer._diagnostics = MagicMock(values=Mock(return_value=[
            Mock(spec=vimrtags.Diagnostic, line_num=4, type="a"),
            Mock(spec=vimrtags.Diagnostic, line_num=65, type="b")
        ]))
        calls = MagicMock()
        calls.attach_mock(_reset_signs, "reset")
        calls.attach_mock(_place_sign, "place")

        self.buffer._place_signs()

        Sign.used_ids.assert_called_once_with(7)
        self.assertListEqual(
            calls.method_calls, [
                call.reset(),
                call.place(4, "a", Sign.used_ids.return_value),
                call.place(65, "b", Sign.used_ids.return_value)
            ]
        )


@patch("plugin.vimrtags.Sign", autospec=True)
class Test_Buffer__place_sign(BufferInstanceTest):
    def test(self, Sign):
        Sign.START_ID = 100
        Sign.side_effect = lambda id_, *a: Mock(id=id_)
        used_ids = set([50, 102])

        self.buffer._place_sign(123, "name 1", used_ids)
        self.buffer._place_sign(456, "name 2", used_ids)
        self.buffer._place_sign(789, "name 3", used_ids)

        self.assertListEqual(
            Sign.call_args_list, [
                call(101, 123, "name 1", 7),
                call(103, 456, "name 2", 7),
                call(104, 789, "name 3", 7)
            ]
        )
        self.assertEqual(len(self.buffer._signs), 3)
        self.assertEqual(self.buffer._signs[0].id, 101)
        self.assertEqual(self.buffer._signs[1].id, 103)
        self.assertEqual(self.buffer._signs[2].id, 104)


class Test_Buffer__reset_signs(BufferInstanceTest):
    def test(self):
        sign1 = Mock(spec=vimrtags.Sign)
        sign2 = Mock(spec=vimrtags.Sign)
        self.buffer._signs = [sign1, sign2]

        self.buffer._reset_signs()

        sign1.unplace.assert_called_once_with()
        sign2.unplace.assert_called_once_with()
        self.assertListEqual(self.buffer._signs, [])


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.run_rc_command", autospec=True)
class Test_Project_get(VimRtagsTest):

    def test_no_filename(self, run_rc_command):
        project = vimrtags.Project.get("")

        self.assertFalse(run_rc_command.called)
        self.assertIsNone(project)

    def test_rc_fails(self, run_rc_command):
        run_rc_command.return_value = None

        project = vimrtags.Project.get("/path/to/file.ext")

        run_rc_command.assert_called_once_with(['--project', "/path/to/file.ext"])
        self.assertIsNone(project)

    def test_no_project_root(self, run_rc_command):
        run_rc_command.return_value = "No matches found"

        project = vimrtags.Project.get("/path/to/file.ext")

        run_rc_command.assert_called_once_with(['--project', "/path/to/file.ext"])
        self.assertIsNone(project)

    @patch("plugin.vimrtags.Project._cache", None)
    @patch("plugin.vimrtags.Project._rtags_data_dir", "/data/dir")
    def test_known_data_dir_known_project(self, run_rc_command):
        run_rc_command.return_value = "  /project/root "
        cached_project = Mock()
        vimrtags.Project._cache = {"/other/project": Mock(), "/project/root": cached_project}

        project = vimrtags.Project.get("/path/to/file.ext")

        run_rc_command.assert_called_once_with(['--project', "/path/to/file.ext"])
        self.assertIs(project, cached_project)

    @patch("plugin.vimrtags.Project._cache", None)
    @patch("plugin.vimrtags.Project._rtags_data_dir", None)
    def test_unknown_data_dir_known_project(self, run_rc_command):
        run_rc_command.side_effect = [
            "  /project/root ",
            """
some junk
dataDir: /rtags/data
other junk
"""
        ]
        cached_project = Mock()
        vimrtags.Project._cache = {"/other/project": Mock(), "/project/root": cached_project}

        project = vimrtags.Project.get("/path/to/file.ext")

        self.assertListEqual(
            run_rc_command.call_args_list, [
                call(['--project', "/path/to/file.ext"]),
                call(['--status', 'info'])
            ]
        )
        self.assertIs(project, cached_project)
        self.assertEqual(vimrtags.Project._rtags_data_dir, "/rtags/data")

    @patch("plugin.vimrtags.Project._cache", None)
    @patch("plugin.vimrtags.Project._rtags_data_dir", "/data/dir")
    def test_known_data_dir_unknown_project(self, run_rc_command):
        run_rc_command.return_value = "  /project/root "
        other_project = Mock()
        vimrtags.Project._cache = {"/other/project": other_project}

        project = vimrtags.Project.get("/path/to/file.ext")

        run_rc_command.assert_called_once_with(['--project', "/path/to/file.ext"])
        self.assertIsInstance(project, vimrtags.Project)
        self.assertEqual(project._project_root, "/project/root")
        self.assertDictEqual(
            vimrtags.Project._cache, {
                "/other/project": other_project, "/project/root": project
            }
        )


@patch("plugin.vimrtags.Project._rtags_data_dir", "/data/dir")
@patch("plugin.vimrtags.Project._cache", {"some": "stuff"})
class Test_Project_reset(VimRtagsTest):
    def test(self):
        vimrtags.Project.reset()

        self.assertIsNone(vimrtags.Project._rtags_data_dir)
        self.assertDictEqual(vimrtags.Project._cache, {})


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.Project._rtags_data_dir", "/data/dir")
class Test_Project_init(VimRtagsTest):
    def test(self):
        project = vimrtags.Project("/project/root/")

        self.assertEqual(project._project_root, "/project/root/")
        self.assertEqual(project._db_path, "/data/dir/_project_root_")


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.Project._rtags_data_dir", "/data/dir")
@patch("plugin.vimrtags.os.path.getmtime", autospec=True)
@patch("plugin.vimrtags.os.listdir", autospec=True)
class Test_Project_last_updated_time(VimRtagsTest):
    def test_ok(self, listdir, getmtime):
        # setup
        listdir.return_value = ["file1", "file2", "file3"]
        getmtime.side_effect = [1, 3, 2]
        project = vimrtags.Project("/file/path/")

        # action
        mtime = project.last_updated_time()

        # confirm
        listdir.assert_called_once_with("/data/dir/_file_path_")
        self.assertListEqual(
            getmtime.call_args_list, [
                call("/data/dir/_file_path_/file1"), call("/data/dir/_file_path_/file2"),
                call("/data/dir/_file_path_/file3")
            ]
        )
        self.assertEqual(mtime, 3)

    @patch("plugin.vimrtags.reset_caches", autospec=True)
    def test_ioerror(self, reset_caches, listdir, getmtime):
        listdir.side_effect = IOError("Boom")
        project = vimrtags.Project("/file/path/")

        mtime = project.last_updated_time()

        reset_caches.assert_called_once_with()
        self.assertEqual(mtime, 0)


class Test_Diagnostic_from_rtags_errors(VimRtagsTest):
    def test(self):
        errors = [
            {'type': "type 1", 'line': 123, 'column': 345, 'message': "a Issue: message 1"},
            {'type': "skipped"},
            {'type': "type 2", 'line': 567, 'column': 789, 'message': "a Issue: message 2"}
        ]

        diagnostics = vimrtags.Diagnostic.from_rtags_errors("/some/file.ext", errors)

        self.assertEqual(len(diagnostics), 2)
        self.assertEqual(diagnostics[0]._filename, "/some/file.ext")
        self.assertEqual(diagnostics[0].line_num, 123)
        self.assertEqual(diagnostics[0]._char_num, 345)
        self.assertEqual(diagnostics[0].type, "type 1")
        self.assertEqual(diagnostics[0].text, "message 1")
        self.assertEqual(diagnostics[1]._filename, "/some/file.ext")
        self.assertEqual(diagnostics[1].line_num, 567)
        self.assertEqual(diagnostics[1]._char_num, 789)
        self.assertEqual(diagnostics[1].type, "type 2")
        self.assertEqual(diagnostics[1].text, "message 2")


@patch("plugin.vimrtags.get_rtags_variable", autospec=True)
@patch("plugin.vimrtags.Diagnostic._to_qlist_dict", autospec=True)
class Test_Diagnostic_to_qlist_errors(VimRtagsTest):
    def prepare(self, _to_qlist_dict):
        self.diagnostics = [
            vimrtags.Diagnostic("file2", 3, 1, "W", "message"),
            vimrtags.Diagnostic("file2", 4, 2, "E", "message"),
            vimrtags.Diagnostic("file2", 4, 3, "W", "message"),
            vimrtags.Diagnostic("file1", 4, 4, "W", "message")
        ]
        # Unused char_num property used to record original ordering.
        _to_qlist_dict.side_effect = lambda d: {"order": d._char_num}

    def test_within_max_height(self, _to_qlist_dict, get_rtags_variable):
        self.prepare(_to_qlist_dict)
        get_rtags_variable.return_value = "10"

        height, qlist = vimrtags.Diagnostic.to_qlist_errors(self.diagnostics)

        self.assertEqual(height, 4)
        self.assert_diagnostics(qlist)

    def test_outside_max_height(self, _to_qlist_dict, get_rtags_variable):
        self.prepare(_to_qlist_dict)
        get_rtags_variable.return_value = "2"

        height, qlist = vimrtags.Diagnostic.to_qlist_errors(self.diagnostics)

        self.assertEqual(height, 2)
        self.assert_diagnostics(qlist)

    def assert_diagnostics(self, qlist):
        self.assertListEqual(
            json.loads(qlist), [
                {"order": 2, "nr": 1},
                {"order": 4, "nr": 2},
                {"order": 1, "nr": 3},
                {"order": 3, "nr": 4}
            ]
        )


class Test_Diagnostic__to_qlist_dict(VimRtagsTest):
    def test_warning(self):
        diagnostic = vimrtags.Diagnostic("file", 3, 4, "warning", "mock text")

        self.assertDictEqual(
            diagnostic._to_qlist_dict(), {
                'lnum': 3, 'col': 4, 'text': "mock text", 'filename': "file", 'type': "W"
            }
        )

    def test_error(self):
        diagnostic = vimrtags.Diagnostic("file", 3, 4, "error", "mock text")

        self.assertDictEqual(
            diagnostic._to_qlist_dict(), {
                'lnum': 3, 'col': 4, 'text': "mock text", 'filename': "file", 'type': "E"
            }
        )

    def test_fixit(self):
        diagnostic = vimrtags.Diagnostic("file", 3, 4, "fixit", "mock text")

        self.assertDictEqual(
            diagnostic._to_qlist_dict(), {
                'lnum': 3, 'col': 4, 'text': "mock text [FIXIT]", 'filename': "file", 'type': "E"
            }
        )


@patch("plugin.vimrtags.logger", Mock(spec=logging.Logger))
@patch("plugin.vimrtags.Sign._is_signs_defined", False)
@patch("plugin.vimrtags.get_command_output", autospec=True)
class Test_Sign__define_signs(VimRtagsTest):

    def test_no_bg_colours(self, get_command_output):
        get_command_output.return_value = (
            "MockGroup         xxx term=underline ctermfg=236 guifg=#3F3F3F"
        )

        vimrtags.Sign._define_signs()

        get_command_output.assert_called_once_with("highlight SignColumn")
        self.assertEqual(vimrtags.Sign._is_signs_defined, True)
        self.assert_signs("")

    def test_no_link(self, get_command_output):
        get_command_output.return_value = (
            "MockGroup         "
            "xxx term=underline ctermfg=236 ctermbg=233 guifg=#3F3F3F guibg=#121212"
        )

        vimrtags.Sign._define_signs()

        get_command_output.assert_called_once_with("highlight SignColumn")
        self.assertEqual(vimrtags.Sign._is_signs_defined, True)
        self.assert_signs(" guibg=#121212 ctermbg=233")

    def test_with_link(self, get_command_output):
        get_command_output.side_effect = [
            "MockGroup     xxx ctermfg=141 guifg=#BF81FA guibg=#1F1F1F"
            "                   links to MockLink",
            "MockLink         "
            "xxx term=underline ctermfg=236 ctermbg=233 guifg=#3F3F3F guibg=#121212"
        ]

        vimrtags.Sign._define_signs()

        self.assertListEqual(
            get_command_output.call_args_list, [
                call("highlight SignColumn"), call("highlight MockLink")
            ]
        )
        self.assertEqual(vimrtags.Sign._is_signs_defined, True)
        self.assert_signs(" guibg=#121212 ctermbg=233")

    def assert_signs(self, bg):
        vim.command.assert_has_calls([
            call("highlight rtags_fixit guifg=#ff00ff ctermfg=5 %s" % bg),
            call("highlight rtags_warning guifg=#fff000 ctermfg=11 %s" % bg),
            call("highlight rtags_error guifg=#ff0000 ctermfg=1 %s" % bg),
            call("sign define rtags_fixit text=Fx texthl=rtags_fixit"),
            call("sign define rtags_warning text=W texthl=rtags_warning"),
            call("sign define rtags_error text=E texthl=rtags_error")
        ])


@patch("plugin.vimrtags.Sign._is_signs_defined", True)
class Test_Sign_reset(VimRtagsTest):
    def test(self):
        vimrtags.Sign.reset()

        self.assertFalse(vimrtags.Sign._is_signs_defined)


@patch("plugin.vimrtags.get_command_output", autospec=True)
class Test_Sign_used_ids(VimRtagsTest):
    def test(self, get_command_output):
        get_command_output.return_value = ("""
--- Signs ---
Signs for path/to/file.ext:
    line=363  id=3000  name=MockSign
    line=439  id=3001  name=MockSign
    line=664  id=3005  name=MockSign
    line=665  id=3006  name=MockSign
""")

        used_ids = vimrtags.Sign.used_ids(4)

        self.assertSetEqual(used_ids, set([3000, 3001, 3005, 3006]))


@patch("plugin.vimrtags.Sign._is_signs_defined", None)
@patch("plugin.vimrtags.Sign._define_signs")
class Test_Sign_init(VimRtagsTest):
    def test_signs_already_defined(self, _define_signs):
        vimrtags.Sign._is_signs_defined = True

        sign = vimrtags.Sign(123, 234, "mock", 456)

        self.assertFalse(_define_signs.called)
        vim.command.assert_called_once_with('sign place 123 line=234 name=rtags_mock buffer=456')
        self.assertEqual(sign.id, 123)
        self.assertEqual(sign._vimbuffer_num, 456)

    def test_signs_not_defined(self, _define_signs):
        vimrtags.Sign._is_signs_defined = False

        sign = vimrtags.Sign(123, 234, "mock", 456)

        _define_signs.assert_called_once_with()
        vim.command.assert_called_once_with('sign place 123 line=234 name=rtags_mock buffer=456')
        self.assertEqual(sign.id, 123)
        self.assertEqual(sign._vimbuffer_num, 456)


@patch("plugin.vimrtags.Sign._is_signs_defined", True)
class Test_Sign_unplace(VimRtagsTest):
    def test(self):
        sign = vimrtags.Sign(123, 456, "mock", 567)
        vim.command.reset_mock()

        sign.unplace()

        vim.command.assert_called_once_with('sign unplace 123 buffer=567')


class Test_get_command_output(VimRtagsTest):
    def test(self):
        output = vimrtags.get_command_output("some command")

        vim.eval.assert_called_once_with('rtags#getCommandOutput("some command")')
        self.assertIs(output, vim.eval.return_value)
