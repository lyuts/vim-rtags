function! unite#rtags#get_filepath(result)
    return split(a:result, ':')[0]
endfunction

function! unite#rtags#get_fileline(result)
    return split(a:result, ':')[1]
endfunction

function! unite#rtags#get_filecol(result)
    return split(a:result, ':')[2]
endfunction

function! unite#rtags#get_filetext(result)
    return substitute( split(a:result, ':')[3], '^\t', '', '')
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
        let parts = split(a:result, cwd.'/')

        if (len(parts) == 2)
            let relpath = parts[1]
            let relfix = relfix . '../'
        else
            " no common ancestry
            let relpath = a:result
            let relfix = ''
            break
        endif
    endwhile

    return relfix . relpath
endfunction
