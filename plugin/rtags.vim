
if !has("python")
    echohl ErrorMsg | echomsg "[vim-rtags] Python support is disabled!" | echohl None
endif

let g:rcCmd = "rc"
let g:excludeSysHeaders = 0

if !has("g:rtagsUseDefaultMappings")
    let g:rtagsUseDefaultMappings = 1
endif

if g:rtagsUseDefaultMappings == 1
    noremap <Leader>ri :call rtags#SymbolInfo()<CR>
    noremap <Leader>rj :call rtags#JumpTo()<CR>
    noremap <Leader>rf :call rtags#FindRefs()<CR>
    noremap <Leader>rn :call rtags#FindRefsByName(input("Pattern? ")<CR>
    noremap <Leader>rs :call rtags#FindSymbols(input("Pattern? "))<CR>
    noremap 6 :call rtags#CompleteAtCursor()<CR>
endif

" LineCol2Offset {{{
" return Byte offset in the file for the current cursor position
function! LineCol2Offset()
    return line2byte('.') + col('.') - 1
endfunction
" }}}

" Offset2LineCol: {{{
" param filepath - fullpath to a file
" param offset - byte offset in the file
" returns [ line #, column # ]
function! Offset2LineCol(filepath, offset)
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

"
" Executes rc with given arguments and returns rc output
"
" param[in] args - dictionary of arguments
"
" return output split by newline
function! rtags#ExecuteRC(args)
    let cmd = rtags#getRcCmd()
    for [key, value] in items(a:args)
        let cmd .= " -".key

        if len(value) > 1
            let cmd .= " ".value
        endif
    endfor
    
    let output = split(system(cmd), '\n\+')

    return output
endfunction

function! rtags#CreateProject()

endfunction

"
" param[in] results - List of found locations by rc
" return locations - List of locations dict's recognizable by setloclist
"
function! rtags#ParseResults(results)
    let locations = []
    let nr = 1
    for record in a:results
        let [location; rest] = split(record, '\s\+')
        let [file, lnum, col; blank] = split(location, ':')

        let entry = {}
"        let entry.bufn = 0
        let entry.filename = substitute(file, getcwd().'/', '', 'g')
        let entry.lnum = lnum
"        let entry.pattern = ''
        let entry.col = col
        let entry.vcol = 0
"        let entry.nr = nr
        let entry.text = join(rest, ' ')
        let entry.type = 'ref'

        call add(locations, entry)

        let nr = nr + 1
    endfor
    return locations
endfunction

"
" param[in] results - List of locations, one per line
"
" Format of each line: <path>,<line>\s<text>
function! rtags#DisplayResults(results)
    let locations = rtags#ParseResults(a:results)
    call setloclist(winnr(), locations)
    lopen
endfunction

function! rtags#getRcCmd()
    if g:excludeSysHeaders == 1
		return g:rcCmd." -H "
    endif
	return g:rcCmd
endfunction

function! rtags#SymbolInfo()
    let args = {}
    let [lnum, col] = getpos('.')[1:2]
    let args.U = printf("%s:%s:%s", expand("%"), lnum, col)
    let output = rtags#ExecuteRC(args)
    for line in output
        echo line
    endfor
endfunction

function! rtags#JumpTo()
    let args = {}
    let [lnum, col] = getpos('.')[1:2]
    let args.f = printf("%s:%s:%s", expand("%"), lnum, col)
    let results = rtags#ExecuteRC(args)
    
    if len(results) > 1
        call rtags#DisplayResults(results)
    elseif len(results) == 1
        let [location; symbol_detail] = split(results[0], '\s\+')
        let [jump_file, lnum, col; rest] = split(location, ':')

        if jump_file != expand("%:p")
            exe "e ".jump_file
        endif
        call cursor(lnum, col)
        normal zz
    endif
endfunction

function! rtags#FindRefs()
    let args = {}
    let args.e = ''

    let [lnum, col] = getpos('.')[1:2]
    let args.r = printf("%s:%s:%s", expand("%"), lnum, col)

    let result = rtags#ExecuteRC(args)
    call rtags#DisplayResults(result)
endfunction

function! rtags#FindRefsByName(name)
    let result = rtags#ExecuteRC({ 'e' : '', 'R' : a:name })
    call rtags#DisplayResults(result)
endfunction

" Find all those references which has the name which is equal to the word
" under the cursor
function! rtags#FindRefsOfWordUnderCursor()
	let wordUnderCursor = expand("<cword>")
	call rtags#FindRefsByName(wordUnderCursor)
endfunction

""" rc -HF <pattern>
function! rtags#FindSymbols(pattern)
    let result = rtags#ExecuteRC({ 'F' : a:pattern })
    call rtags#DisplayResults(result)
endfunction

function! rtags#ProjectList()
    for line in  rtags#ExecuteRC({'w' : ''})
        echo line
    endfor
endfunction

function! rtags#ProjectOpen(pattern)
    call rtags#ExecuteRC({ 'w' : a:pattern })
endfunction

function! rtags#ProjectClose(pattern)
    call rtags#ExecuteRC({ 'u' : a:pattern })
endfunction

function! rtags#FindSymbolsOfWordUnderCursor()
	let wordUnderCursor = expand("<cword>")
	call rtags#FindSymbols(wordUnderCursor)
endfunction

function! rtags#CompleteAtCursor()
    let flags = "--synchronous-completions -l"
    let file = expand("%:p")
    let pos = getpos('.')
    let line = pos[1]
    let col = pos[2]
    
	let rcRealCmd = rtags#getRcCmd()
    let cmd = printf("%s %s %s:%s:%s", rcRealCmd, flags, file, line, col)
    let result = split(system(cmd), '\n\+')
    return result
"    for r in result
"        echo r
"    endfor
"    call rtags#DisplayResults(result)
endfunction

function! RtagsCompleteFunc(findstart, base)
    echomsg "RtagsCompleteFunc: ".a:base
    if a:findstart
        " todo: find word start
        exec "normal \<Esc>" 
        let cword = expand("<cword>")
        exec "startinsert!"
        echomsg cword
        return strridx(getline(line('.')), cword)
    else
        
        let completeopts = rtags#CompleteAtCursor()
        let a = []
            for line in completeopts
                let option = split(line)
                if a:base != "" && stridx(option[0], a:base) != 0
                    continue
                endif
                let match = {}
                let match.word = option[0]
                let match.kind = option[len(option) - 1]
                if match.kind == "CXXMethod"
                    let match.word = match.word.'('
                endif
                let match.menu = join(option[1:len(option) - 1], ' ')
                call add(a, match)
            endfor
        return a
    endif
endfunction


set completefunc=RtagsCompleteFunc

" Helpers to access script locals for unit testing {{{
function! s:get_SID()
    return matchstr(expand('<sfile>'), '<SNR>\d\+_')
endfunction
let s:SID = s:get_SID()
delfunction s:get_SID

function! rtags#__context__()
    return { 'sid': s:SID, 'scope': s: }
endfunction
"}}}
