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
