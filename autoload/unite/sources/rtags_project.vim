function! unite#sources#rtags_project#define() "{{{
  return s:source_rtags_project
endfunction "}}}

" line source. "{{{
let s:source_rtags_project = {
      \ 'name' : 'rtags/project',
      \ 'syntax' : 'uniteSource__RtagsProject',
      \ 'hooks' : {},
      \ 'default_kind' : 'command',
      \ 'matchers' : 'matcher_regexp',
      \ 'sorters' : 'sorter_nothing',
      \ }
" }}}

function! s:source_rtags_project.gather_candidates(args, context)
    let args = {}
    let args.w = ''
    let result = rtags#ExecuteRC(args)
    return map(result, "{
                \ 'word': v:val,
                \ 'action__command': 'call unite#sources#rtags_project#SetProject(\"'.split(v:val, ' ')[0].'\")',
                \ 'action__histadd': 0,
                \ }")
endfunction

function! unite#sources#rtags_project#SetProject(name)
    let args = {}
    let args.w = a:name
    let result = rtags#ExecuteRC(args)
endfunction
