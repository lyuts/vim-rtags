function! unite#rtags#get_filepath(result)
    return split(a:result, ':')[0]
endfunction

function! unite#rtags#get_fileline(result)
    return split(a:result, ':')[1]
endfunction

function! unite#rtags#get_filecol(result)
    return split(a:result, ':')[2]
endfunction

function! unite#rtags#get_word(result)
    let cwd = getcwd()
    let relpath = split(a:result, cwd.'/')[0]
    let relfix = ''

    while relpath ==# a:result
        " the current working directory isn't fully contained in the result's
        " path. E.g., result may contain /a/b/c/d and the current working
        " directory might be /a/b/c/e
        let cwd = join(split(cwd, '/')[:-2], '/')
        " since the join does not place a starting '/' we need to skip to the
        " second element
        let relpath = split(a:result, cwd.'/')[1]
        let relfix = relfix . '../'
    endwhile

    return relfix . relpath
endfunction
