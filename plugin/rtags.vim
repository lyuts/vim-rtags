
if !has("python")
    echohl ErrorMsg | echomsg "[vim-rtags] Python support is disabled!" | echohl None
endif

let g:rcCmd = "rc"
let g:excludeSysHeaders = 0

if !exists("g:rtagsUseLocationList")
    let g:rtagsUseLocationList = 1
endif

if !exists("g:rtagsUseDefaultMappings")
    let g:rtagsUseDefaultMappings = 1
endif

if !exists("g:rtagsMinCharsForCommandCompletion")
    let g:rtagsMinCharsForCommandCompletion = 4
endif

if g:rtagsUseDefaultMappings == 1
    noremap <Leader>ri :call rtags#SymbolInfo()<CR>
    noremap <Leader>rj :call rtags#JumpTo()<CR>
    noremap <Leader>rS :call rtags#JumpTo(" ")<CR>
    noremap <Leader>rV :call rtags#JumpTo("vert")<CR>
    noremap <Leader>rT :call rtags#JumpTo("tab")<CR>
    noremap <Leader>rp :call rtags#JumpToParent()<CR>
    noremap <Leader>rf :call rtags#FindRefs()<CR>
    noremap <Leader>rn :call rtags#FindRefsByName(input("Pattern? ", "", "customlist,rtags#CompleteSymbols")<CR>
    noremap <Leader>rs :call rtags#FindSymbols(input("Pattern? ", "", "customlist,rtags#CompleteSymbols"))<CR>
    noremap <Leader>rr :call rtags#ReindexFile()<CR>
    noremap <Leader>rl :call rtags#ProjectList()<CR>
    noremap <Leader>rw :call rtags#RenameSymbolUnderCursor()<CR>
    noremap <Leader>rv :call rtags#FindVirtuals()<CR>
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
" param[in] ...
"   param a:1 - list of long arguments (e.g. --cursorinfo-include-parents)
"-
" return output split by newline
function! rtags#ExecuteRC(args, ...)
    let cmd = rtags#getRcCmd()

    " Give rdm unsaved file content, so that you don't have to save files
    " before each rc invocation.
    let unsaved_content = join(getline(1, line('$')), "\n")
    let filename = expand("%")
    let output = system(printf("%s --unsaved-file=%s:%s -V %s", cmd, filename, strlen(unsaved_content), filename), unsaved_content)

    " prepare for the actual command invocation
    if a:0 > 0
        let longArgs = a:1
        for longArg in longArgs
            let cmd .= " --".longArg." "
        endfor
    endif
    for [key, value] in items(a:args)
        let cmd .= " -".key
        if len(value) > 1
            let cmd .= " ".value
        endif
    endfor

    let output = system(cmd)
    if v:shell_error && len(output) > 0
        let output = substitute(output, '\n', '', '')
        echohl ErrorMsg | echomsg "[vim-rtags] Error: " . output | echohl None
        return []
    endif
    if output =~ '^Not indexed'
        echohl ErrorMsg | echomsg "[vim-rtags] Current file is not indexed!" | echohl None
        return []
    endif
    return split(output, '\n\+')
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
        let [file, lnum, col] = rtags#parseSourceLocation(location)

        let entry = {}
"        let entry.bufn = 0
        let entry.filename = substitute(file, getcwd().'/', '', 'g')
        let entry.filepath = file
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
    if g:rtagsUseLocationList == 1
        call setloclist(winnr(), locations)
        if len(locations) > 0
            lopen
        endif
    else
        call setqflist(locations)
        if len(locations) > 0
            copen
        endif
    endif
endfunction

function! rtags#getRcCmd()
    let cmd = g:rcCmd
    let cmd .= " --absolute-path "
    if g:excludeSysHeaders == 1
        return cmd." -H "
    endif
    return cmd
endfunction

function! rtags#getCurrentLocation()
    let [lnum, col] = getpos('.')[1:2]
    return printf("%s:%s:%s", expand("%"), lnum, col)
endfunction

function! rtags#SymbolInfo()
    let args = {}
    let args.U = rtags#getCurrentLocation()
    let output = rtags#ExecuteRC(args)
    for line in output
        echo line
    endfor
endfunction

function! rtags#cloneCurrentBuffer(type)
    let [lnum, col] = getpos('.')[1:2]
    exec a:type." new ".expand("%")
    call cursor(lnum, col)
endfunction

function! rtags#jumpToLocation(file, line, col)
    if a:file != expand("%:p")
        exe "e ".a:file
    endif
    call cursor(a:line, a:col)
endfunction

function! rtags#JumpTo(...)
    let args = {}
    let args.f = rtags#getCurrentLocation()
    let results = rtags#ExecuteRC(args)

    if len(results) >= 0 && a:0 > 0
        call rtags#cloneCurrentBuffer(a:1)
    endif

    if len(results) > 1
        call rtags#DisplayResults(results)
    elseif len(results) == 1
        let [location; symbol_detail] = split(results[0], '\s\+')
        let [jump_file, lnum, col; rest] = split(location, ':')

        " Add location to the jumplist
        normal m'
        call rtags#jumpToLocation(jump_file, lnum, col)
        normal zz
    endif
endfunction

function! rtags#parseSourceLocation(string)
    let [location; symbol_detail] = split(a:string, '\s\+')
    let splittedLine = split(location, ':')
    if len(splittedLine) == 3
        let [jump_file, lnum, col; rest] = splittedLine
        " Must be a path, therefore leading / is compulsory
        if jump_file[0] == '/'
            return [jump_file, lnum, col]
        endif
    endif
    return ["","",""]
endfunction

function! rtags#JumpToParent(...)
    let args = {}
    let args.U = rtags#getCurrentLocation()
    let longArgs = ["symbol-info-include-parents"]
    let results = rtags#ExecuteRC(args, longArgs)

    let parentSeparator = "===================="
    let parentSeparatorPassed = 0
    for line in results
        if line == parentSeparator
            let parentSeparatorPassed = 1
        endif
        if parentSeparatorPassed == 1
            let [jump_file, lnum, col] = rtags#parseSourceLocation(line)
            if !empty(jump_file)
                if a:0 > 0
                    call rtags#cloneCurrentBuffer(a:1)
                endif

                " Add location to the jumplist
                normal m'
                call rtags#jumpToLocation(jump_file, lnum, col)
                normal zz
                return
            endif
        endif
    endfor
endfunction

function! rtags#RenameSymbolUnderCursor()
    let args = {}
    let args.e = ''
    let args.r = rtags#getCurrentLocation()
    let longArgs = ["rename"]
    let locations = rtags#ParseResults(rtags#ExecuteRC(args, longArgs))
    if len(locations) > 0
        let newName = input("Enter new name: ")
        let yesToAll = 0
        if !empty(newName)
            for loc in reverse(locations)
                call rtags#jumpToLocation(loc.filepath, loc.lnum, loc.col)
                normal zv
                normal zz
                redraw
                let choice = yesToAll
                if choice == 0
                    let location = loc.filepath.":".loc.lnum.":".loc.col
                    let choices = "&Yes\nYes to &All\n&No\n&Cancel"
                    let choice = confirm("Rename symbol at ".location, choices)
                endif
                if choice == 2
                    let choice = 1
                    let yesToAll = 1
                endif
                if choice == 1
                    exec "normal ciw".newName."\<Esc>"
                    write!
                elseif choice == 4
                    return
                endif
            endfor
        endif
    endif
endfunction

function! rtags#FindRefs()
    let args = {}
    let args.e = ''
    let args.r = rtags#getCurrentLocation()
    let result = rtags#ExecuteRC(args)
    call rtags#DisplayResults(result)
endfunction

function! rtags#FindVirtuals()
    let args = {}
    let args.k = ''
    let args.r = rtags#getCurrentLocation()
    let result = rtags#ExecuteRC(args)
    call rtags#DisplayResults(result)
endfunction

function! rtags#FindRefsByName(name)
    let result = rtags#ExecuteRC({ 'ae' : '', 'R' : a:name })
    call rtags#DisplayResults(result)
endfunction

" case insensitive FindRefsByName
function! rtags#IFindRefsByName(name)
    let result = rtags#ExecuteRC({ 'ae' : '', 'R' : a:name, 'I' : '' })
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
    let result = rtags#ExecuteRC({ 'aF' : a:pattern })
    call rtags#DisplayResults(result)
endfunction

" Method for tab-completion for vim's commands
function! rtags#CompleteSymbols(arg, line, pos)
    if len(a:arg) < g:rtagsMinCharsForCommandCompletion
        return []
    endif
    let result = rtags#ExecuteRC({ 'S' : a:arg })
    return filter(result, 'v:val !~ "("')
endfunction

" case insensitive FindSymbol
function! rtags#IFindSymbols(pattern)
    let result = rtags#ExecuteRC({ 'aIF' : a:pattern })
    call rtags#DisplayResults(result)
endfunction

function! rtags#ProjectList()
    let projects = rtags#ExecuteRC({'w' : ''})
    let i = 1
    for p in projects
        echo '['.i.'] '.p
        let i = i + 1
    endfor
    let choice = input('Choice: ')
    if choice > 0 && choice <= len(projects)
        call rtags#ProjectOpen(projects[choice-1])
    endif
endfunction

function! rtags#ProjectOpen(pattern)
    call rtags#ExecuteRC({ 'w' : a:pattern })
endfunction

function! rtags#LoadCompilationDb(pattern)
    call rtags#ExecuteRC({ 'J' : a:pattern })
endfunction

function! rtags#ProjectClose(pattern)
    call rtags#ExecuteRC({ 'u' : a:pattern })
endfunction

function! rtags#PreprocessFile()
    let result = rtags#ExecuteRC({ 'E' : expand("%:p") })
    vnew
    call append(0, result)
endfunction

function! rtags#ReindexFile()
    call rtags#ExecuteRC({ 'V' : expand("%:p") })
endfunction

function! rtags#FindSymbolsOfWordUnderCursor()
    let wordUnderCursor = expand("<cword>")
    call rtags#FindSymbols(wordUnderCursor)
endfunction

"
" This function assumes it is invoked from insert mode
"
function! rtags#CompleteAtCursor(wordStart, base)
    let flags = "--synchronous-completions -l"
    let file = expand("%:p")
    let pos = getpos('.')
    let line = pos[1]
    let col = a:wordStart

    if index(['.', '::', '->'], a:base) != -1
        let col += 1
    endif

    let rcRealCmd = rtags#getRcCmd()

    exec "normal \<Esc>"
    let stdin_lines = join(getline(1, line), "\n").a:base
    let offset = line2byte(line + 1)

    if offset == -1
        " in case completion is on the last row
        let offset = line2byte(line('$') + 1)
    endif

    exec "startinsert!"
"    echomsg getline(line)
"    sleep 1
"    echomsg "DURING INVOCATION POS: ".pos[2]
"    sleep 1
    echomsg stdin_lines
"    sleep 1
    " sed command to remove CDATA prefix and closing xml tag from rtags output
    let sed_cmd = "sed -e 's/.*CDATA\\[//g' | sed -e 's/.*\\/completions.*//g'"
    let cmd = printf("%s %s %s:%s:%s --unsaved-file=%s:%s | %s", rcRealCmd, flags, file, line, col, file, offset, sed_cmd)
    echomsg cmd
    sleep 1
    let result = split(system(cmd, stdin_lines), '\n\+')
    echomsg "Got ".len(result)." completions"
    sleep 1
    return result
"    for r in result
"        echo r
"    endfor
"    call rtags#DisplayResults(result)
endfunction

"""
" Temporarily the way this function works is:
"     - completeion invoked on
"         object.meth*
"       , where * is cursor position
"     - find the position of a dot/arrow
"     - invoke completion through rc
"     - filter out options that start with meth (in this case).
"     - show completion options
" 
"     Reason: rtags returns all options regardless of already type method name
"     portion
"""
function! RtagsCompleteFunc(findstart, base)
    echomsg "RtagsCompleteFunc: [".a:findstart."], [".a:base."]"
    sleep 1
    if a:findstart
        " todo: find word start
        exec "normal \<Esc>"
        let cword = expand("<cword>")
        exec "startinsert!"
"        echomsg "CWORD [".cword."]"
        let wordstart = strridx(getline('.'), cword)
"        if index([ '.', '->', '::' ], cword) != -1
"            let wordstart += 1
"        endif
"        echomsg wordstart
"        sleep 2

        return wordstart
    else
        let wordstart = getpos('.')[2]

        " this is the case when completion invoked right after the dot
"        if index([ '.', '->', '::' ], a:base) != -1
        if a:base == ""
            let wordstart += 1
        endif

"        let cdata_pivot = 'CDATA['
        let completeopts = rtags#CompleteAtCursor(wordstart, a:base)
        let a = []
            for line in completeopts
"                let cdata_pos = stridx(line, cdata_pivot)
"                if cdata_pos != -1
"                    let line = strpart(line, cdata_pos + strlen(cdata_pivot))
"                endif
"                echo line
"                sleep 1
                " remove lines with closing </completions> tag
"                if stridx(line, "completions>") != -1
"                    continue
"                endif

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

if &completefunc == ""
    set completefunc=RtagsCompleteFunc
endif

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

command! -nargs=1 -complete=customlist,rtags#CompleteSymbols RtagsFindSymbols call rtags#FindSymbols(<q-args>)
command! -nargs=1 -complete=customlist,rtags#CompleteSymbols RtagsFindRefsByName call rtags#FindRefsByName(<q-args>)

command! -nargs=1 -complete=customlist,rtags#CompleteSymbols RtagsIFindSymbols call rtags#IFindSymbols(<q-args>)
command! -nargs=1 -complete=customlist,rtags#CompleteSymbols RtagsIFindRefsByName call rtags#IFindRefsByName(<q-args>)

command! -nargs=1 -complete=dir RtagsLoadCompilationDb call rtags#LoadCompilationDb(<q-args>)

" The most commonly used find operation
command! -nargs=1 -complete=customlist,rtags#CompleteSymbols Rtag RtagsIFindSymbols <q-args>

