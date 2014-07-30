let s:tc = unittest#testcase#new("rtagsUnitTests", rtags#__context__())

function! s:tc.test_parsingRcOutput()
    let line = "/path/to/file/Src.cpp:157:5:      init ();"
    let locations = rtags#ParseResults([line])
    call self.assert_equal(1, len(locations))

    let location = locations[0]
    call self.assert_equal("/path/to/file/Src.cpp", location.filename)
    call self.assert_equal(157, location.lnum)
    call self.assert_equal(5, location.col)
    call self.assert_equal(0, location.vcol)
"    call self.assert_equal(0, location.nr)
    call self.assert_equal('init ();', location.text)
    call self.assert_equal('ref', location.type)
endfunction

function! s:tc.test_parseSourceLocation()
    let line = "/path/to/file/Src.cpp:157:5:      init ();"
    let [file, lnum, col] = rtags#parseSourceLocation(line)
    call self.assert_equal("/path/to/file/Src.cpp", file)
    call self.assert_equal(157, lnum)
    call self.assert_equal(5, col)
endfunction

function! s:tc.test_parseSourceLocation_should_return_empty_file_when_input_does_not_have_source_location()
    let line = "bad input -- no source location"
    let [file, lnum, col] = rtags#parseSourceLocation(line)
    call self.assert_equal("", file)
endfunction

function! s:tc.test_parseSourceLocation_should_return_empty_file_when_there_is_no_leading_slash()
    let line = "path/to/file/Src.cpp:157:5:      init ();"
    let [file, lnum, col] = rtags#parseSourceLocation(line)
    call self.assert_equal("", file)
endfunction

