function! unite#sources#rtags_symbol#define() "{{{
  return s:source_rtags_symbol
endfunction "}}}

" line source. "{{{
let s:source_rtags_symbol = {
      \ 'name' : 'rtags/symbol',
      \ 'syntax' : 'uniteSource__RtagsSymbol',
      \ 'hooks' : {},
      \ 'default_kind' : 'jump_list',
      \ 'matchers' : 'matcher_regexp',
      \ 'sorters' : 'sorter_nothing',
      \ }
" }}}

function! s:source_rtags_symbol.hooks.on_syntax(args, context)
    if (a:context.source__case ==# 'i')
        syntax case ignore
    endif

    syntax match uniteSource__RtagsSymbol_File /[^:]*: / contained
                \ containedin=uniteSource__RtagsSymbol
                \ nextgroup=uniteSource__RtagsSymbol_LineNR
    syntax match uniteSource__RtagsSymbol_LineNR /\d\+:/ contained
                \ containedin=uniteSource__RtagsSymbol
                \ nextgroup=uniteSource__RtagsSymbol_Symbol
    execute 'syntax match uniteSource__RtagsSymbol_Symbol /'
                \ . a:context.source__input
                \ . '/ contained containedin=uniteSource__RtagsSymbol'
    highlight default link uniteSource__RtagsSymbol_File Comment
    highlight default link uniteSource__RtagsSymbol_LineNr LineNR
    highlight default link uniteSource__RtagsSymbol_Symbol Function
endfunction

function! s:source_rtags_symbol.hooks.on_init(args, context)
    let a:context.source__input = get(a:args, 1, '')
    if (a:context.source__input ==# '')
       let a:context.source__input = unite#util#input('Pattern: ')
    endif

    call unite#print_source_message('Pattern: '
                \ . a:context.source__input, s:source_rtags_symbol.name)

    let a:context.source__case = get(a:args, 0, '')
endfunction

function! s:source_rtags_symbol.gather_candidates(args, context)
    let args = { '-a' : '' }
    if (a:context.source__case ==# 'i')
        let args['-I'] = ''
    endif
    let args['-F'] = a:context.source__input
    let result = rtags#ExecuteRC(args)
    return map(result, "{
                \ 'word': unite#rtags#get_word(v:val),
                \ 'action__path': unite#rtags#get_filepath(v:val),
                \ 'action__line': unite#rtags#get_fileline(v:val),
                \ 'action__col': unite#rtags#get_filecol(v:val),
                \ 'action__text': unite#rtags#get_filetext(v:val)
                \ }")
endfunction
