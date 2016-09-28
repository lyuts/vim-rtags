function! unite#sources#rtags_references#define() "{{{
  return s:source_rtags_references
endfunction "}}}

" line source. "{{{
let s:source_rtags_references = {
      \ 'name' : 'rtags/references',
      \ 'syntax' : 'uniteSource__RtagsReferences',
      \ 'hooks' : {},
      \ 'default_kind' : 'jump_list',
      \ 'matchers' : 'matcher_regexp',
      \ 'sorters' : 'sorter_nothing',
      \ }

function! s:source_rtags_references.hooks.on_syntax(args, context)
    syntax match uniteSource__RtagsReferences_File /[^:]*: / contained
                \ containedin=uniteSource__RtagsReferences
                \ nextgroup=uniteSource__RtagsReferences_LineNR
    syntax match uniteSource__RtagsReferences_LineNR /\d\+:/ contained
                \ containedin=uniteSource__RtagsReferences
                \ nextgroup=uniteSource__RtagsReferences_Symbol
    execute 'syntax match uniteSource__RtagsReferences_Symbol /'
                \ . a:context.source__cword
                \ . '/ contained containedin=uniteSource__RtagsReferences'
    highlight default link uniteSource__RtagsReferences_File Comment
    highlight default link uniteSource__RtagsReferences_LineNr LineNR
    highlight default link uniteSource__RtagsReferences_Symbol Function
endfunction

function! s:source_rtags_references.gather_candidates(args, context)
    let a:context.source__cword = expand("<cword>")
    let args = {
        \ '-e' : '',
        \ '-r' : rtags#getCurrentLocation() }
    let result = rtags#ExecuteRC(args)
    return map(result, "{
                \ 'word': unite#rtags#get_word(v:val),
                \ 'action__path': unite#rtags#get_filepath(v:val),
                \ 'action__line': unite#rtags#get_fileline(v:val),
                \ 'action__col': unite#rtags#get_filecol(v:val),
                \ }")
endfunction
