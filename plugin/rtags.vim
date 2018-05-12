if has('nvim') || (has('job') && has('channel'))
    let s:rtagsAsync = 1
    let s:job_cid = 0
    let s:jobs = {}
    let s:result_stdout = {}
    let s:result_handlers = {}
else
    let s:rtagsAsync = 0
endif

if has('python')
    let g:rtagsPy = 'python'
elseif has('python3')
    let g:rtagsPy = 'python3'
else
    echohl ErrorMsg | echomsg "[vim-rtags] Vim is missing python support" | echohl None
    finish
end



if !exists("g:rtagsRcCmd")
    let g:rtagsRcCmd = "rc"
endif

if !exists("g:rtagsRdmCmd")
    let g:rtagsRdmCmd = "rdm"
endif

if !exists("g:rtagsLog")
    let g:rtagsLog = tempname()
endif

if !exists("g:rtagsRdmLog")
    let g:rtagsRdmLog = tempname()
endif

if !exists("g:rtagsAutoLaunchRdm")
    let g:rtagsAutoLaunchRdm = 0
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

if !exists("g:rtagsAutoDiagnostics")
    let g:rtagsAutoDiagnostics = 1
endif

if !exists("g:rtagsDiagnosticsPollingInterval")
    let g:rtagsDiagnosticsPollingInterval = 3000
endif

if !exists("g:rtagsCppOmnifunc")
    let g:rtagsCppOmnifunc = 1
endif


let g:SAME_WINDOW = 'same_window'
let g:H_SPLIT = 'hsplit'
let g:V_SPLIT = 'vsplit'
let g:NEW_TAB = 'tab'

let s:LOC_OPEN_OPTS = {
            \ g:SAME_WINDOW : '',
            \ g:H_SPLIT : ' ',
            \ g:V_SPLIT : 'vert',
            \ g:NEW_TAB : 'tab'
            \ }

if g:rtagsUseDefaultMappings == 1
    noremap <Leader>ri :call rtags#SymbolInfo()<CR>
    noremap <Leader>rj :call rtags#JumpTo(g:SAME_WINDOW)<CR>
    noremap <Leader>rJ :call rtags#JumpTo(g:SAME_WINDOW, { '--declaration-only' : '' })<CR>
    noremap <Leader>rS :call rtags#JumpTo(g:H_SPLIT)<CR>
    noremap <Leader>rV :call rtags#JumpTo(g:V_SPLIT)<CR>
    noremap <Leader>rT :call rtags#JumpTo(g:NEW_TAB)<CR>
    noremap <Leader>rp :call rtags#JumpToParent()<CR>
    noremap <Leader>rf :call rtags#FindRefs()<CR>
    noremap <Leader>rF :call rtags#FindRefsCallTree()<CR>
    noremap <Leader>rn :call rtags#FindRefsByName(input("Pattern? ", "", "customlist,rtags#CompleteSymbols"))<CR>
    noremap <Leader>rs :call rtags#FindSymbols(input("Pattern? ", "", "customlist,rtags#CompleteSymbols"))<CR>
    noremap <Leader>rr :call rtags#ReindexFile()<CR>
    noremap <Leader>rl :call rtags#ProjectList()<CR>
    noremap <Leader>rw :call rtags#RenameSymbolUnderCursor()<CR>
    noremap <Leader>rv :call rtags#FindVirtuals()<CR>
    noremap <Leader>rb :call rtags#JumpBack()<CR>
    noremap <Leader>rC :call rtags#FindSuperClasses()<CR>
    noremap <Leader>rc :call rtags#FindSubClasses()<CR>
    noremap <Leader>rd :call rtags#Diagnostics()<CR>
    noremap <Leader>rD :call rtags#DiagnosticsAll()<CR>
    noremap <Leader>rx :call rtags#ApplyFixit()<CR>
endif

let s:script_folder_path = escape( expand( '<sfile>:p:h' ), '\' )

function! rtags#InitPython()
    let s:pyInitScript = "
\ import vim;
\ script_folder = vim.eval('s:script_folder_path');
\ sys.path.insert(0, script_folder);
\ import vimrtags"

    exe g:rtagsPy." ".s:pyInitScript
endfunction

"""
" Logging routine
"""
function! rtags#Log(message)
    call writefile([strftime("%Y-%m-%d %H:%M:%S", localtime()) . " | vim | " . string(a:message)], g:rtagsLog, "a")
endfunction

"
" Executes rc with given arguments and returns rc output
"
" param[in] args - dictionary of arguments
"-
" return output split by newline
function! rtags#ExecuteRC(args)
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
    for [key, value] in items(a:args)
        let cmd .= " ".key
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

function! rtags#ExtractClassHierarchyLine(line)
    return substitute(a:line, '\v.*\s+(\S+:[0-9]+:[0-9]+:\s)', '\1', '')
endfunction

"
" Converts a class hierarchy of 'rc --class-hierarchy' like:
"
" Superclasses:
"   class Foo src/Foo.h:56:7: class Foo : public Bar {
"     class Bar	src/Bar.h:46:7:	class Bar : public Bas {
"       class Bas src/Bas.h:47:7: class Bas {
" Subclasses:
"   class Foo src/Foo.h:56:7: class Foo : public Bar {
"     class Foo2 src/Foo2.h:56:7: class Foo2 : public Foo {
"     class Foo3 src/Foo3.h:56:7: class Foo3 : public Foo {
"
" into the super classes:
"
" src/Foo.h:56:7: class Foo : public Bar {
" src/Bar.h:46:7: class Bar : public Bas {
" src/Bas.h:47:7: class Bas {
"
function! rtags#ExtractSuperClasses(results)
    let extracted = []
    for line in a:results
        if line == "Superclasses:"
            continue
        endif

        if line == "Subclasses:"
            break
        endif

        let extLine = rtags#ExtractClassHierarchyLine(line)
        call add(extracted, extLine)
    endfor
    return extracted
endfunction

"
" Converts a class hierarchy of 'rc --class-hierarchy' like:
"
" Superclasses:
"   class Foo src/Foo.h:56:7: class Foo : public Bar {
"     class Bar	src/Bar.h:46:7:	class Bar : public Bas {
"       class Bas src/Bas.h:47:7: class Bas {
" Subclasses:
"   class Foo src/Foo.h:56:7: class Foo : public Bar {
"     class Foo2 src/Foo2.h:56:7: class Foo2 : public Foo {
"     class Foo3 src/Foo3.h:56:7: class Foo3 : public Foo {
"
" into the sub classes:
"
" src/Foo.h:56:7: class Foo : public Bar {
" src/Foo2.h:56:7: class Foo2 : public Foo {
" src/Foo3.h:56:7: class Foo3 : public Foo {
"
function! rtags#ExtractSubClasses(results)
    let extracted = []
    let atSubClasses = 0
    for line in a:results
        if atSubClasses == 0
            if line == "Subclasses:"
                let atSubClasses = 1
            endif

            continue
        endif

        let extLine = rtags#ExtractClassHierarchyLine(line)
        call add(extracted, extLine)
    endfor
    return extracted
endfunction

"
" param[in] locations - List of locations, one per line
"
function! rtags#DisplayLocations(locations)
    let num_of_locations = len(a:locations)
    if g:rtagsUseLocationList == 1
        call setloclist(winnr(), a:locations)
        if num_of_locations > 0
            exe 'lopen '.min([g:rtagsMaxSearchResultWindowHeight, num_of_locations]) | set nowrap
        endif
    else
        call setqflist(a:locations)
        if num_of_locations > 0
            exe 'copen '.min([g:rtagsMaxSearchResultWindowHeight, num_of_locations]) | set nowrap
        endif
    endif
endfunction

"
" param[in] results - List of locations, one per line
"
" Format of each line: <path>,<line>\s<text>
function! rtags#DisplayResults(results)
    let locations = rtags#ParseResults(a:results)
    call rtags#DisplayLocations(locations)
endfunction

"
" Creates a tree viewer for references to a symbol
"
" param[in] results - List of locations, one per line
"
" Format of each line: <path>,<line>\s<text>\sfunction: <caller path>
function! rtags#ViewReferences(results)
    let cmd = g:rtagsMaxSearchResultWindowHeight . "new References"
    silent execute cmd
    setlocal noswapfile
    setlocal buftype=nowrite
    setlocal bufhidden=delete
    setlocal nowrap
    setlocal tw=0

    iabc <buffer>

    setlocal modifiable
    silent normal ggdG
    setlocal nomodifiable
    let b:rtagsLocations=[]
    call rtags#AddReferences(a:results, -1)
    setlocal modifiable
    silent normal ggdd
    setlocal nomodifiable

    let cpo_save = &cpo
    set cpo&vim
    nnoremap <buffer> <cr> :call <SID>OpenReference()<cr>
    nnoremap <buffer> o    :call <SID>ExpandReferences()<cr>
    let &cpo = cpo_save
endfunction

"
" Expands the callers of the reference on the current line.
"
function! s:ExpandReferences() " <<<
    let ln = line(".")

    " Detect expandable region
    if !empty(b:rtagsLocations[ln - 1].source)
        let location = b:rtagsLocations[ln - 1].source
        let rnum = b:rtagsLocations[ln - 1].rnum
        let b:rtagsLocations[ln - 1].source = ''
        let args = {
                \ '--containing-function-location' : '',
                \ '-r' : location }
        call rtags#ExecuteThen(args, [[function('rtags#AddReferences'), rnum]])
    endif
endfunction " >>>

"
" Opens the reference for viewing in the window below.
"
function! s:OpenReference() " <<<
    let ln = line(".")

    " Detect openable region
    if ln - 1 < len(b:rtagsLocations)
        let jump_file = b:rtagsLocations[ln - 1].filename
        let lnum = b:rtagsLocations[ln - 1].lnum
        let col = b:rtagsLocations[ln - 1].col
        wincmd j
        " Add location to the jumplist
        normal m'
        if rtags#jumpToLocation(jump_file, lnum, col)
            normal zz
        endif
    endif
endfunction " >>>

"
" Adds the list of references below the targeted item in the reference
" viewer window.
"
" param[in] results - List of locations, one per line
" param[in] rnum - The record number the references are calling or -1
"
" Format of each line: <path>,<line>\s<text>\sfunction: <caller path>
function! rtags#AddReferences(results, rnum)
    let ln = line(".")
    let depth = 0
    let nr = len(b:rtagsLocations)
    let i = -1
    " If a reference number is provided, find this entry in the list and insert
    " after it.
    if a:rnum >= 0
        let i = 0
        while i < nr && b:rtagsLocations[i].rnum != a:rnum
            let i += 1
        endwhile
        if i == nr
            " We didn't find the source record, something went wrong
            echo "Error finding insertion point."
            return
        endif
        let depth = b:rtagsLocations[i].depth + 1
        exec (":" . (i + 1))
    endif
    let prefix = repeat(" ", depth * 2)
    let new_entries = []
    setlocal modifiable
    for record in a:results
        let [line; sourcefunc] = split(record, '\s\+function: ')
        let [location; rest] = split(line, '\s\+')
        let [file, lnum, col] = rtags#parseSourceLocation(location)
        let entry = {}
        let entry.filename = substitute(file, getcwd().'/', '', 'g')
        let entry.filepath = file
        let entry.lnum = lnum
        let entry.col = col
        let entry.vcol = 0
        let entry.text = join(rest, ' ')
        let entry.type = 'ref'
        let entry.depth = depth
        let entry.source = matchstr(sourcefunc, '[^\s]\+')
        let entry.rnum = nr
        silent execute "normal! A\<cr>\<esc>i".prefix . substitute(entry.filename, '.*/', '', 'g').':'.entry.lnum.' '.entry.text."\<esc>"
        call add(new_entries, entry)
        let nr = nr + 1
    endfor
    call extend(b:rtagsLocations, new_entries, i + 1)
    setlocal nomodifiable
    exec (":" . ln)
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
    return printf("%s:%s:%s", expand("%:p"), lnum, col)
endfunction

function! rtags#SymbolInfoHandler(output)
    echo join(a:output, "\n")
endfunction

function! rtags#SymbolInfo()
    call rtags#ExecuteThen({ '-U' : rtags#getCurrentLocation() }, [function('rtags#SymbolInfoHandler')])
endfunction

function! rtags#cloneCurrentBuffer(type)
    if a:type == g:SAME_WINDOW
        return
    endif

    let [lnum, col] = getpos('.')[1:2]
    exec s:LOC_OPEN_OPTS[a:type]." new ".expand("%")
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

function! rtags#JumpToHandler(results, args)
    let results = a:results
    let open_opt = a:args['open_opt']
    if len(results) >= 0 && open_opt != g:SAME_WINDOW
        call rtags#cloneCurrentBuffer(open_opt)
    endif
    call rtags#Log("JumpTo results with ".json_encode(a:args).": ".json_encode(results))
    if len(results) > 1
        call rtags#DisplayResults(results)
    elseif len(results) == 1
        if results[0] == "Not indexed"
            echom "Failed to jump - file is not indexed"
            return
        endif
        let [location; symbol_detail] = split(results[0], '\s\+')
        let [jump_file, lnum, col; rest] = split(location, ':')

        " Add location to the jumplist
        normal! m'
        if rtags#jumpToLocation(jump_file, lnum, col)
            normal! zz
        endif
    else
        echom "Failed to jump - cannot follow symbol"
    endif

endfunction

"
" JumpTo(open_type, ...)
"     open_type - Vim command used for opening desired location.
"     Allowed values:
"       * g:SAME_WINDOW
"       * g:H_SPLIT
"       * g:V_SPLIT
"       * g:NEW_TAB
"
"     a:1 - dictionary of additional arguments for 'rc'
"
function! rtags#JumpTo(open_opt, ...)
    let args = {}
    if a:0 > 0
        let args = a:1
    endif

    call extend(args, { '-f' : rtags#getCurrentLocation() })
    let results = rtags#ExecuteThen(args, [[function('rtags#JumpToHandler'), { 'open_opt' : a:open_opt }]])

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

function! rtags#JumpToParentHandler(results)
    let results = a:results
    for line in results
        let matched = matchend(line, "^Parent: ")
        if matched == -1
            continue
        endif
        let [jump_file, lnum, col] = rtags#parseSourceLocation(line[matched:-1])
        if !empty(jump_file)
            if a:0 > 0
                call rtags#cloneCurrentBuffer(a:1)
            endif

            " Add location to the jumplist
            normal! m'
            if rtags#jumpToLocation(jump_file, lnum, col)
                normal! zz
            endif
            return
        endif
    endfor
endfunction

function! rtags#JumpToParent(...)
    let args = {
                \ '-U' : rtags#getCurrentLocation(),
                \ '--symbol-info-include-parents' : '' }

    call rtags#ExecuteThen(args, [function('rtags#JumpToParentHandler')])
endfunction

function! s:GetCharacterUnderCursor()
    return matchstr(getline('.'), '\%' . col('.') . 'c.')
endfunction

function! rtags#RenameSymbolUnderCursorHandler(output)
    let locations = rtags#ParseResults(a:output)
    if len(locations) > 0
        let newName = input("Enter new name: ")
        let yesToAll = 0
        if !empty(newName)
            for loc in reverse(locations)
                if !rtags#jumpToLocationInternal(loc.filepath, loc.lnum, loc.col)
                    return
                endif
                normal! zv
                normal! zz
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
                        normal! l
                    endif
                    exec "normal! ciw".newName."\<Esc>"
                    write!
                elseif choice == 4
                    return
                endif
            endfor
        endif
    endif
endfunction

function! rtags#RenameSymbolUnderCursor()
    let args = {
                \ '-e' : '',
                \ '-r' : rtags#getCurrentLocation(),
                \ '--rename' : '' }

    call rtags#ExecuteThen(args, [function('rtags#RenameSymbolUnderCursorHandler')])
endfunction

function! rtags#TempFile(job_cid)
    return '/tmp/neovim_async_rtags.tmp.' . getpid() . '.' . a:job_cid
endfunction

function! rtags#ExecuteRCAsync(args, handlers)
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
    for [key, value] in items(a:args)
        let cmd .= " ".key
        if len(value) > 1
            let cmd .= " ".value
        endif
    endfor

    let s:callbacks = {
                \ 'on_exit' : function('rtags#HandleResults')
                \ }

    let s:job_cid = s:job_cid + 1
    " should have out+err redirection portable for various shells.
    if has('nvim')
        let cmd = cmd . ' >' . rtags#TempFile(s:job_cid) . ' 2>&1'
        let job = jobstart(cmd, s:callbacks)
        let s:jobs[job] = s:job_cid
        let s:result_handlers[job] = a:handlers
    elseif has('job') && has('channel')
        let l:opts = {}
        let l:opts.mode = 'nl'
        let l:opts.out_cb = {ch, data -> rtags#HandleResults(ch_info(ch).id, data, 'vim_stdout')}
        let l:opts.exit_cb = {ch, data -> rtags#HandleResults(ch_info(ch).id, data,'vim_exit')}
        let l:opts.stoponexit = 'kill'
        let job = job_start(cmd, l:opts)
        let channel = ch_info(job_getchannel(job)).id
        let s:result_stdout[channel] = []
        let s:jobs[channel] = s:job_cid
        let s:result_handlers[channel] = a:handlers
    endif

endfunction

function! rtags#HandleResults(job_id, data, event)


    if a:event == 'vim_stdout'
        call add(s:result_stdout[a:job_id], a:data)
    elseif a:event == 'vim_exit'

        let job_cid = remove(s:jobs, a:job_id)
        let handlers = remove(s:result_handlers, a:job_id)
        let output = remove(s:result_stdout, a:job_id)

        call rtags#ExecuteHandlers(output, handlers)
    else
        let job_cid = remove(s:jobs, a:job_id)
        let temp_file = rtags#TempFile(job_cid)
        let output = readfile(temp_file)
        let handlers = remove(s:result_handlers, a:job_id)
        call rtags#ExecuteHandlers(output, handlers)
        execute 'silent !rm -f ' . temp_file
    endif

endfunction

function! rtags#ExecuteHandlers(output, handlers)
    let result = a:output
    for Handler in a:handlers
        if type(Handler) == 3
            let HandlerFunc = Handler[0]
            let args = Handler[1]
            call HandlerFunc(result, args)
        else
            try
                let result = Handler(result)
            catch /E706/
                " If we're not returning the right type we're probably done
                return
            endtry
        endif
    endfor
endfunction

function! rtags#ExecuteThen(args, handlers)
    if s:rtagsAsync == 1
        call rtags#ExecuteRCAsync(a:args, a:handlers)
    else
        let result = rtags#ExecuteRC(a:args)
        call rtags#ExecuteHandlers(result, a:handlers)
    endif
endfunction

function! rtags#FindRefs()
    let args = {
                \ '-e' : '',
                \ '-r' : rtags#getCurrentLocation() }

    call rtags#ExecuteThen(args, [function('rtags#DisplayResults')])
endfunction

function! rtags#FindRefsCallTree()
    let args = {
                \ '--containing-function-location' : '',
                \ '-r' : rtags#getCurrentLocation() }

    call rtags#ExecuteThen(args, [function('rtags#ViewReferences')])
endfunction

function! rtags#FindSuperClasses()
    call rtags#ExecuteThen({ '--class-hierarchy' : rtags#getCurrentLocation() },
                \ [function('rtags#ExtractSuperClasses'), function('rtags#DisplayResults')])
endfunction

function! rtags#FindSubClasses()
    let result = rtags#ExecuteThen({ '--class-hierarchy' : rtags#getCurrentLocation() }, [
                \ function('rtags#ExtractSubClasses'),
                \ function('rtags#DisplayResults')])
endfunction

function! rtags#FindVirtuals()
    let args = {
                \ '-k' : '',
                \ '-r' : rtags#getCurrentLocation() }

    call rtags#ExecuteThen(args, [function('rtags#DisplayResults')])
endfunction

function! rtags#FindRefsByName(name)
    let args = {
                \ '-a' : '',
                \ '-e' : '',
                \ '-R' : a:name }

    call rtags#ExecuteThen(args, [function('rtags#DisplayResults')])
endfunction

" case insensitive FindRefsByName
function! rtags#IFindRefsByName(name)
    let args = {
                \ '-a' : '',
                \ '-e' : '',
                \ '-R' : a:name,
                \ '-I' : '' }

    call rtags#ExecuteThen(args, [function('rtags#DisplayResults')])
endfunction

" Find all those references which has the name which is equal to the word
" under the cursor
function! rtags#FindRefsOfWordUnderCursor()
    let wordUnderCursor = expand("<cword>")
    call rtags#FindRefsByName(wordUnderCursor)
endfunction

""" rc -HF <pattern>
function! rtags#FindSymbols(pattern)
    let args = {
                \ '-a' : '',
                \ '-F' : a:pattern }

    call rtags#ExecuteThen(args, [function('rtags#DisplayResults')])
endfunction

" Method for tab-completion for vim's commands
function! rtags#CompleteSymbols(arg, line, pos)
    if len(a:arg) < g:rtagsMinCharsForCommandCompletion
        return []
    endif
    call rtags#ExecuteThen({ '-S' : a:arg }, [function('filter')])
endfunction

" case insensitive FindSymbol
function! rtags#IFindSymbols(pattern)
    let args = {
                \ '-a' : '',
                \ '-I' : '',
                \ '-F' : a:pattern }

    call rtags#ExecuteThen(args, [function('rtags#DisplayResults')])
endfunction

function! rtags#ProjectListHandler(output)
    let projects = a:output
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

function! rtags#ProjectList()
    call rtags#ExecuteThen({ '-w' : '' }, [function('rtags#ProjectListHandler')])
endfunction

function! rtags#ProjectOpen(pattern)
    call rtags#ExecuteThen({ '-w' : a:pattern }, [])
endfunction

function! rtags#LoadCompilationDb(pattern)
    call rtags#ExecuteThen({ '-J' : a:pattern }, [])
endfunction

function! rtags#ProjectClose(pattern)
    call rtags#ExecuteThen({ '-u' : a:pattern }, [])
endfunction

function! rtags#PreprocessFileHandler(result)
    vnew
    call append(0, a:result)
endfunction

function! rtags#PreprocessFile()
    call rtags#ExecuteThen({ '-E' : expand("%:p") }, [function('rtags#PreprocessFileHandler')])
endfunction

function! rtags#ReindexFile()
    call rtags#ExecuteThen({ '-V' : expand("%:p") }, [])
endfunction

function! rtags#FindSymbolsOfWordUnderCursor()
    let wordUnderCursor = expand("<cword>")
    call rtags#FindSymbols(wordUnderCursor)
endfunction

function! rtags#Diagnostics()
    return s:Pyeval("vimrtags.Buffer.current().show_diagnostics_list()")
endfunction

function! rtags#DiagnosticsAll()
    return s:Pyeval("vimrtags.Buffer.show_all_diagnostics()")
endfunction

function! rtags#ApplyFixit()
    return s:Pyeval("vimrtags.Buffer.current().apply_fixits()")
endfunction

function! rtags#NotifyEdit()
    return s:Pyeval("vimrtags.Buffer.current().on_edit()")
endfunction

function! rtags#NotifyWrite()
    return s:Pyeval("vimrtags.Buffer.current().on_write()")
endfunction

function! rtags#NotifyIdle()
    return s:Pyeval("vimrtags.Buffer.current().on_idle()")
endfunction

function! rtags#NotifyCursorMoved()
    return s:Pyeval("vimrtags.Buffer.current().on_cursor_moved()")
endfunction

function! rtags#Poll(timer)
    if &filetype == "cpp" || &filetype == "c"
        call s:Pyeval("vimrtags.Buffer.current().on_poll()")
    endif
    call timer_start(g:rtagsDiagnosticsPollingInterval, "rtags#Poll")
endfunction

" Generic function to get output of a command.
" Used in python for things that can't be read directly via vim.eval(...)
function! rtags#getCommandOutput(cmd_txt) abort
  redir => output
    silent execute a:cmd_txt
  redir END
  return output
endfunction

function! s:Pyeval( eval_string )
  if g:rtagsPy == 'python3'
      return py3eval( a:eval_string )
  else
      return pyeval( a:eval_string )
  endif
endfunction

function! s:RcExecuteJobCompletion()
    call rtags#SetJobStateFinish()
    if ! empty(b:rtags_state['stdout']) && mode() == 'i'
        call feedkeys("\<C-x>\<C-o>", "t")
    else
        call RtagsCompleteFunc(0, RtagsCompleteFunc(1, 0))
    endif
endfunction

"{{{ RcExecuteJobHandler
"Handles stdout/stderr/exit events, and stores the stdout/stderr received from the shells.
function! RcExecuteJobHandler(job_id, data, event)
    if a:event == 'exit'
        call s:RcExecuteJobCompletion()
    else
        call rtags#AddJobStandard(a:event, a:data)
    endif
endf

function! rtags#SetJobStateFinish()
    let b:rtags_state['state'] = 'finish'
endfunction

function! rtags#AddJobStandard(eventType, data)
    call add(b:rtags_state[a:eventType], a:data)
endfunction

function! rtags#SetJobStateReady()
    let b:rtags_state['state'] = 'ready'
endfunction

function! rtags#IsJobStateReady()
    if b:rtags_state['state'] == 'ready'
        return 1
    endif
    return 0
endfunction

function! rtags#IsJobStateBusy()
    if b:rtags_state['state'] == 'busy'
        return 1
    endif
    return 0
endfunction

function! rtags#IsJobStateFinish()
    if b:rtags_state['state'] == 'finish'
        return 1
    endif
    return 0
endfunction


function! rtags#SetStartJobState()
    let b:rtags_state['state'] = 'busy'
    let b:rtags_state['stdout'] = []
    let b:rtags_state['stderr'] = []
endfunction

function! rtags#GetJobStdOutput()
    return b:rtags_state['stdout']
endfunction

function! rtags#ExistsAndCreateRtagsState()
    if !exists('b:rtags_state')
        let b:rtags_state = { 'state': 'ready', 'stdout': [], 'stderr': [] }
    endif
endfunction

"{{{ s:RcExecute
" Execute clang binary to generate completions and diagnostics.
" Global variable:
" Buffer vars:
"     b:rtags_state => {
"       'state' :  // updated to 'ready' in sync mode
"       'stdout':  // updated in sync mode
"       'stderr':  // updated in sync mode
"     }
"
"     b:clang_execute_job_id  // used to stop previous job
"
" @root Clang root, project directory
" @line Line to complete
" @col Column to complete
" @return [completion, diagnostics]
function! s:RcJobExecute(offset, line, col)

    let file = expand("%:p")
    let l:cmd = printf("rc --absolute-path --synchronous-completions -l %s:%s:%s --unsaved-file=%s:%s", file, a:line, a:col, file, a:offset)

    if exists('b:rc_execute_job_id') && job_status(b:rc_execute_job_id) == 'run'
      try
        call job_stop(b:rc_execute_job_id, 'term')
        unlet b:rc_execute_job_id
      catch
        " Ignore
      endtry
    endif

    call rtags#SetStartJobState()

    let l:argv = l:cmd
    let l:opts = {}
    let l:opts.mode = 'nl'
    let l:opts.in_io = 'buffer'
    let l:opts.in_buf = bufnr('%')
    let l:opts.out_cb = {ch, data -> RcExecuteJobHandler(ch, data,  'stdout')}
    let l:opts.err_cb = {ch, data -> RcExecuteJobHandler(ch, data,  'stderr')}
    let l:opts.exit_cb = {ch, data -> RcExecuteJobHandler(ch, data, 'exit')}
    let l:opts.stoponexit = 'kill'

    let l:jobid = job_start(l:argv, l:opts)
    let b:rc_execute_job_id = l:jobid

    if job_status(l:jobid) != 'run'
        unlet b:rc_execute_job_id
    endif

endf

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
    if s:rtagsAsync == 1 && !has('nvim')
        return s:RtagsCompleteFunc(a:findstart, a:base, 1)
    else
        return s:RtagsCompleteFunc(a:findstart, a:base, 0)
    endif
endfunction

function! s:RtagsCompleteFunc(findstart, base, async)
    call rtags#Log("RtagsCompleteFunc: [".a:findstart."], [".a:base."]")

    if a:findstart
        let s:line = getline('.')
        let s:start = col('.') - 2
        return s:Pyeval("vimrtags.get_identifier_beginning()")
    else
        let pos = getpos('.')
        let s:file = expand("%:p")
        let s:line = str2nr(pos[1])
        let s:col = str2nr(pos[2]) + len(a:base)
        let s:prefix = a:base
        return s:Pyeval("vimrtags.send_completion_request()")
    endif
endfunction

" Prefer omnifunc, if enabled.
if g:rtagsCppOmnifunc == 1
    autocmd Filetype cpp,c setlocal omnifunc=RtagsCompleteFunc
" Override completefunc if it's available to be used.
elseif &completefunc == ""
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

" Reset all Python caches - maybe useful if the RTags project has been messed with
" after the vim session has started.
command! RtagsResetCaches call s:Pyeval('vimrtags.reset_caches()')

if g:rtagsAutoLaunchRdm
    call system(g:rtagsRcCmd." -w")
    if v:shell_error != 0
        call system(g:rtagsRdmCmd." --daemon  --log-timestamp --log-flush --log-file ".rtagsRdmLog)
    end
end


call rtags#InitPython()


if g:rtagsAutoDiagnostics == 1
    augroup rtags_auto_diagnostics
        autocmd!
        autocmd BufWritePost *.cpp,*.c,*.hpp,*.h call rtags#NotifyWrite()
        autocmd TextChanged,TextChangedI *.cpp,*.c,*.hpp,*.h call rtags#NotifyEdit()
        autocmd CursorHold,CursorHoldI,BufEnter *.cpp,*.c,*.hpp,*.h call rtags#NotifyIdle()
        autocmd CursorMoved,CursorMovedI *.cpp,*.c,*.hpp,*.h call rtags#NotifyCursorMoved()
    augroup END

    if g:rtagsDiagnosticsPollingInterval > 0
        call rtags#Log("Starting async update checking")
        call rtags#Poll(0)
    endif
endif

