
if !exists("g:rtagsRcCmd")
    let g:rtagsRcCmd = "rc"
endif

if !exists("g:rtagsJumpStackMaxSize")
    let g:rtagsJumpStackMaxSize = 100
endif

if !exists("g:rtagsExcludeSysHeaders")
    let g:rtagsExcludeSysHeaders = 0
endif

let g:rtagsJumpStack = []

if !exists("g:rtagsUseLocationList")
    let g:rtagsUseLocationList = 1
endif

if !exists("g:rtagsUseDefaultMappings")
    let g:rtagsUseDefaultMappings = 1
endif

if !exists("g:rtagsMinCharsForCommandCompletion")
    let g:rtagsMinCharsForCommandCompletion = 4
endif

if !exists("g:rtagsMaxSearchResultWindowHeight")
    let g:rtagsMaxSearchResultWindowHeight = 10
endif

if g:rtagsUseDefaultMappings == 1
    noremap <Leader>ri :call rtags#SymbolInfo()<CR>
    noremap <Leader>rj :call rtags#JumpTo()<CR>
    noremap <Leader>rS :call rtags#JumpTo(" ")<CR>
    noremap <Leader>rV :call rtags#JumpTo("vert")<CR>
    noremap <Leader>rT :call rtags#JumpTo("tab")<CR>
    noremap <Leader>rp :call rtags#JumpToParent()<CR>
    noremap <Leader>rf :call rtags#FindRefs()<CR>
    noremap <Leader>rn :call rtags#FindRefsByName(input("Pattern? ", "", "customlist,rtags#CompleteSymbols"))<CR>
    noremap <Leader>rs :call rtags#FindSymbols(input("Pattern? ", "", "customlist,rtags#CompleteSymbols"))<CR>
    noremap <Leader>rr :call rtags#ReindexFile()<CR>
    noremap <Leader>rl :call rtags#ProjectList()<CR>
    noremap <Leader>rw :call rtags#RenameSymbolUnderCursor()<CR>
    noremap <Leader>rv :call rtags#FindVirtuals()<CR>
    noremap <Leader>rb :call rtags#JumpBack()<CR>
endif

"""
" Logging routine
"""
function! rtags#Log(message)
    if exists("g:rtagsLog")
        call writefile([string(a:message)], g:rtagsLog, "a")
    endif
endfunction

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
    if exists('b:rtags_sent_content')
        let content = join(getline(1, line('$')), "\n")
        if b:rtags_sent_content != content
            let unsaved_content = content
        endif
    elseif &modified
        let unsaved_content = join(getline(1, line('$')), "\n")
    endif
    if exists('unsaved_content')
        let filename = expand("%")
        let output = system(printf("%s --unsaved-file=%s:%s -V %s", cmd, filename, strlen(unsaved_content), filename), unsaved_content)
        let b:rtags_sent_content = unsaved_content
    endif

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
    let num_of_locations = len(locations)
    if g:rtagsUseLocationList == 1
        call setloclist(winnr(), locations)
        if num_of_locations > 0
            exe 'lopen '.min([g:rtagsMaxSearchResultWindowHeight, num_of_locations]) | set nowrap
        endif
    else
        call setqflist(locations)
        if num_of_locations > 0
            exe 'copen '.min([g:rtagsMaxSearchResultWindowHeight, num_of_locations]) | set nowrap
        endif
    endif
endfunction

function! rtags#getRcCmd()
    let cmd = g:rtagsRcCmd
    let cmd .= " --absolute-path "
    if g:rtagsExcludeSysHeaders == 1
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
    call rtags#saveLocation()
    return rtags#jumpToLocationInternal(a:file, a:line, a:col)
endfunction

function! rtags#jumpToLocationInternal(file, line, col)
    try
        if a:file != expand("%:p")
            exe "e ".a:file
        endif
        call cursor(a:line, a:col)
        return 1
    catch /.*/
        echohl ErrorMsg
        echomsg v:exception
        echohl None
        return 0
    endtry
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
        if rtags#jumpToLocation(jump_file, lnum, col)
            normal zz
        endif
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

function! rtags#saveLocation()
  let [lnum, col] = getpos('.')[1:2]
  call rtags#pushToStack([expand("%"), lnum, col])
endfunction

function! rtags#pushToStack(location)
  let jumpListLen = len(g:rtagsJumpStack) 
  if jumpListLen > g:rtagsJumpStackMaxSize
    call remove(g:rtagsJumpStack, 0)
  endif
  call add(g:rtagsJumpStack, a:location)
endfunction

function! rtags#JumpBack()
  if len(g:rtagsJumpStack) > 0
    let [jump_file, lnum, col] = remove(g:rtagsJumpStack, -1)
    call rtags#jumpToLocationInternal(jump_file, lnum, col)
  else
    echo "rtags: jump stack is empty"
  endif
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
                if rtags#jumpToLocation(jump_file, lnum, col)
                    normal zz
                endif
                return
            endif
        endif
    endfor
endfunction

function! s:GetCharacterUnderCursor()
    return matchstr(getline('.'), '\%' . col('.') . 'c.')
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
                if !rtags#jumpToLocationInternal(loc.filepath, loc.lnum, loc.col)
                    return
                fi
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
                    " Special case for destructors
                    if s:GetCharacterUnderCursor() == '~'
                        normal l
                    endif
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
    let col = pos[2]

    if index(['.', '::', '->'], a:base) != -1
        let col += 1
    endif

    let rcRealCmd = rtags#getRcCmd()

    exec "normal \<Esc>"
    let stdin_lines = join(getline(1, "$"), "\n").a:base
    let offset = len(stdin_lines)

    exec "startinsert!"
"    echomsg getline(line)
"    sleep 1
"    echomsg "DURING INVOCATION POS: ".pos[2]
"    sleep 1
"    echomsg stdin_lines
"    sleep 1
    " sed command to remove CDATA prefix and closing xml tag from rtags output
    let sed_cmd = "sed -e 's/.*CDATA\\[//g' | sed -e 's/.*\\/completions.*//g'"
    let cmd = printf("%s %s %s:%s:%s --unsaved-file=%s:%s | %s", rcRealCmd, flags, file, line, col, file, offset, sed_cmd)
    call rtags#Log("Command line:".cmd)

    let result = split(system(cmd, stdin_lines), '\n\+')
"    echomsg "Got ".len(result)." completions"
"    sleep 1
    call rtags#Log("-----------")
    "call rtags#Log(result)
    call rtags#Log("-----------")
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
    call rtags#Log("RtagsCompleteFunc: [".a:findstart."], [".a:base."]")
    if a:findstart
        " got from RipRip/clang_complete
        let l:line = getline('.')
        let l:start = col('.') - 1
        let l:wsstart = l:start
        if l:line[l:wsstart - 1] =~ '\s'
            while l:wsstart > 0 && l:line[l:wsstart - 1] =~ '\s'
                let l:wsstart -= 1
            endwhile
        endif
        while l:start > 0 && l:line[l:start - 1] =~ '\i'
            let l:start -= 1
        endwhile
        let b:col = l:start + 1
        call rtags#Log("column:".b:col)
        call rtags#Log("start:".l:start)
        return l:start
    else
        let wordstart = getpos('.')[0]
        let completeopts = rtags#CompleteAtCursor(wordstart, a:base)
        "call rtags#Log(completeopts)
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
            "call rtags#Log(match)
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

