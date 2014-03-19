
if !has("python")
    echohl ErrorMsg | echomsg "[vim-rtags] Python support is disabled!" | echohl None
endif

let g:rcCmd = "rc"


noremap 1 :call rtags#SymbolInfo()<CR>
noremap 2 :call rtags#JumpTo()<CR>
noremap 3 :call rtags#FindRefs()<CR>
noremap 4 :call rtags#FindRefsByName(input("Pattern? ")<CR>
noremap 5 :call rtags#FindSymbols(input("Pattern? "), 0)<CR>

" LineCol2Offset {{{
" return Byte offset in the file for the current cursor position
function LineCol2Offset()
    return line2byte('.') + col('.') - 1
endfunction
" }}}

" Offset2LineCol: {{{
" param filepath - fullpath to a file
" param offset - byte offset in the file
" returns [ line #, column # ]
function Offset2LineCol(filepath, offset)
python << endscript
import vim
f = open(vim.eval("a:filepath"))

row = 1
offset = int(vim.eval("a:offset"))
for line in f:
    if offset <= len(line):
        col = offset
        break
    else:
        offset -= len(line)
        row += 1

f.close()
vim.command("return [%d, %s]" % (row, col))
endscript
endfunction
" }}}

function rtags#CreateProject()

endfunction

"
" param[in] results - List of locations, one per line
"
" Format of each line: <path>,<line>\s<text>
function rtags#DisplayResults(results)
    let locations = []
    let nr = 1
    for record in a:results
        let [location; rest] = split(record, '\s\+')
        let file = split(location, ',')[0]
        let offset = str2nr(split(location, ',')[1])

        let cursor_pos = Offset2LineCol(file, offset)

        let entry = {}
"        let entry.bufn = 0
        let entry.filename = substitute(file, getcwd().'/', '', 'g')
        let entry.lnum = cursor_pos[0]
"        let entry.pattern = ''
        let entry.col = cursor_pos[1]
        let entry.vcol = 0
"        let entry.nr = nr
        let entry.text = join(rest, ' ')
        let entry.type = 'ref'

        call add(locations, entry)

        let nr = nr + 1
    endfor

    call setloclist(winnr(), locations)
    lopen
endfunction

function rtags#SymbolInfo()
    let cmd = printf("%s -U %s,%s", g:rcCmd, expand("%"), LineCol2Offset())
    exe "!".cmd
endfunction

function rtags#JumpTo()
    let cmd = printf("%s -f %s,%s", g:rcCmd, expand("%"), LineCol2Offset())
    let [location; symbol_detail] = split(system(cmd), '\s\+')
    let jump_location = split(location, ',')
    let jump_file = jump_location[0]
    let jump_byte_offset = jump_location[1]

    if jump_file != expand("%:p")
        exe "e +".jump_byte_offset."go ".jump_file
    else
        exe jump_byte_offset."go"
    endif
endfunction

function rtags#FindRefs()
    let cmd = printf("%s -er %s,%s", g:rcCmd, expand("%"), LineCol2Offset())
    let result = split(system(cmd), '\n\+')
    call rtags#DisplayResults(result)
endfunction

function rtags#FindRefsByName(name)
    let cmd = printf("%s -eR %s", g:rcCmd, a:name)
    let result = split(system(cmd), '\n\+')
    call rtags#DisplayResults(result)
endfunction

""" rc -HF <pattern>
function rtags#FindSymbols(pattern, excludeSysHeaders)
    let flags = "F"
    if a:excludeSysHeaders == 1
        let flags = "H".flags
    endif

    let cmd = printf("%s -%s %s", g:rcCmd, flags, a:pattern)
    let result = split(system(cmd), '\n\+')
    call rtags#DisplayResults(result)
endfunction
