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

let s:classHierarchy = [
    \ "Superclasses:",
    \ "  class Foo src/Foo.h:56:7: class Foo : public Bar {",
    \ "    class Bar src/Bar.h:46:7: class Bar : public Bas {",
    \ "      class Bas src/Bas.h:47:7: class Bas {",
    \ "Subclasses:",
    \ "  class Foo src/Foo.h:56:7: class Foo : public Bar {",
    \ "    class Foo2 src/Foo2.h:56:7: class Foo2 : public Foo {",
    \ "      class Foo3 src/Foo3.h:56:7: class Foo3 : public Foo {" ]

function! s:tc.test_extractSuperClasses()
    let lines = rtags#ExtractSuperClasses(s:classHierarchy)
    call self.assert_equal(len(lines), 3)
    call self.assert_equal(lines[0], "src/Foo.h:56:7: class Foo : public Bar {")
    call self.assert_equal(lines[1], "src/Bar.h:46:7: class Bar : public Bas {")
    call self.assert_equal(lines[2], "src/Bas.h:47:7: class Bas {")
endfunction

function! s:tc.test_extractSubClasses()
    let lines = rtags#ExtractSubClasses(s:classHierarchy)
    call self.assert_equal(len(lines), 3)
    call self.assert_equal(lines[0], "src/Foo.h:56:7: class Foo : public Bar {")
    call self.assert_equal(lines[1], "src/Foo2.h:56:7: class Foo2 : public Foo {")
    call self.assert_equal(lines[2], "src/Foo3.h:56:7: class Foo3 : public Foo {")
endfunction

