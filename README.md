# Vim Rtags

Vim bindings for rtags.

https://github.com/Andersbakken/rtags

# Requirements

# Installation
## Vundle
Add the following line to ```.vimrc```

    Plugin 'lyuts/vim-rtags'

then while in vim run:

    :source %
    :PluginInstall

## NeoBundle
Add the following line to ```.vimrc```

    NeoBundle 'lyuts/vim-rtags'

then while in vim run:

    :source %
    :NeoBundleInstall

## Pathogen
    $ cd ~/.vim/bundle
    $ git clone https://github.com/lyuts/vim-rtags

# Configuration
This plugin interacts with RTags by invoking ```rc``` commands and interpreting
their results.  You can override the path to ```rc``` binary by setting
```g:rtagsRcCmd``` variable.  By default, it is set to ```rc```, expecting it to be
found in the $PATH.

Out of box this plugin provides mappings. In order to use custom mappings the
default mappings can be disabled:

    let g:rtagsUseDefaultMappings = 0

By default, search results are showed in a location list. Location lists
are local to the current window. To use the vim QuickFix window, which is
shared between all windows, set:

    let g:rtagsUseLocationList = 0

To implement 'return to previous location after jump' feature, internal stack is used.
It is possible to set its maximum size (number of entries), default is 100:

    let g:rtagsJumpStackMaxSize = 100

# Usage

## Mappings
| Mapping          | rc flag                          | Description                                |
|------------------|----------------------------------|--------------------------------------------|
| &lt;Leader&gt;ri | -U                               | Symbol info                                |
| &lt;Leader&gt;rj | -f                               | Follow location                            |
| &lt;Leader&gt;rJ | -f --declaration-only            | Follow declaration location                |
| &lt;Leader&gt;rS | -f                               | Follow location (open in horizontal split) |
| &lt;Leader&gt;rV | -f                               | Follow location (open in vertical split)   |
| &lt;Leader&gt;rT | -f                               | Follow location open in a new tab          |
| &lt;Leader&gt;rp | -U --symbol-info-include-parents | Jump to parent                             |
| &lt;Leader&gt;rc | --class-hierarchy                | Find subclasses                            |
| &lt;Leader&gt;rC | --class-hierarchy                | Find superclasses                          |
| &lt;Leader&gt;rf | -e -r                            | Find references                            |
| &lt;Leader&gt;rn | -ae -R                           | Find references by name                    |
| &lt;Leader&gt;rs | -a -F                            | Find symbols by name                       |
| &lt;Leader&gt;rr | -V                               | Reindex current file                       |
| &lt;Leader&gt;rl | -w                               | List all available projects                |
| &lt;Leader&gt;rw | -e -r --rename                   | Rename symbol under cursor                 |
| &lt;Leader&gt;rv | -k -r                            | Find virtuals                              |
| &lt;Leader&gt;rb | N/A                              | Jump to previous location                  |

## Unite sources

This plugin defines three Unite sources:
* `rtags/references` - list references (i.e., &lt;Leader&gt;rf).
* `rtags/symbol` - find symbol (i.e., &lt;Leader&gt;rs). Use `rtags/symbol:i`
  for case insensitive search.
* `rtags/project` - list/switch projects.

## Code completion
Code completion functionality uses ```completefunc``` (i.e. CTRL-X CTRL-U). If ```completefunc```
is set, vim-rtags will not override it with ```RtagsCompleteFunc```. This functionality is still
unstable, but if you want to try it you will have to set ```completefunc``` by

    set completefunc=RtagsCompleteFunc

Also ```RtagsCompleteFunc``` can be used as omnifunc. For example, you can use
such approach with [neocomplete](https://github.com/Shougo/neocomplete.vim)(for more details read it's docs):

```
function! SetupNeocompleteForCppWithRtags()
    " Enable heavy omni completion.
    setlocal omnifunc=RtagsCompleteFunc

    if !exists('g:neocomplete#sources#omni#input_patterns')
        let g:neocomplete#sources#omni#input_patterns = {}
    endif
    let l:cpp_patterns='[^.[:digit:] *\t]\%(\.\|->\)\|\h\w*::'
    let g:neocomplete#sources#omni#input_patterns.cpp = l:cpp_patterns 
    set completeopt+=longest,menuone
endfunction

autocmd FileType cpp,c call SetupNeocompleteForCppWithRtags()

```
Such config provides automatic calls, of omnicompletion on c and cpp entity accessors.

### Current limitations
* There is no support for overridden functions and methods
* Thre is no support for function argument completion

# Notes
1. This plugin is wip.

# Development
Unit tests for some plugin functions can be found in ```tests``` directory.
To run tests, execute:

    $ vim tests/test_rtags.vim +UnitTest
