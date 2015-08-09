# Vim Rtags

Vim bindings for rtags.

https://github.com/Andersbakken/rtags

# Requirements
1. Vim built with ```+python```.

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
```g:rcCmd``` variable.  By default, it is set to ```rc```, expecting it to be
found in the $PATH.

Out of box this plugin provides mappings. In order to use custom mappings the
default mappings can be disabled:

    let g:rtagsUseDefaultMappings = 0

By default, search results are showed in a location list. Location lists
are local to the current window. To use the vim QuickFix window, which is
shared between all windows, set:

    let g:rtagsUseLocationList = 0

# Usage

## Mappings
| Mapping    | rc flag                          | Description                                |
|------------|----------------------------------|--------------------------------------------|
| <Leader>ri | -U                               | Symbol info                                |
| <Leader>rj | -f                               | Follow location                            |
| <Leader>rS | -f                               | Follow location (open in horizontal split) |
| <Leader>rV | -f                               | Follow location (open in vertical split)   |
| <Leader>rT | -f                               | Follow location open in a new tab          |
| <Leader>rp | -U --symbol-info-include-parents | Jump to parent                             |
| <Leader>rf | -e -r                            | Find references                            |
| <Leader>rn | -ae -R                           | Find references by name                    |
| <Leader>rs | -a -F                            | Find symbols by name                       |
| <Leader>rr | -V                               | Reindex current file                       |
| <Leader>rl | -w                               | List all available projects                |
| <Leader>rw | -e -r --rename                   | Rename symbol under cursor                 |

## Code completion
Code completion functionality uses ```completefunc``` (i.e. CTRL-X CTRL-U). If ```completefunc```
is set, vim-rtags will not override it with ```RtagsCompleteFunc```. This functionality is still
unstable, but if you want to try it you will have to set ```completefunc``` by

    set completefunc=RtagsCompleteFunc

# Notes
1. This plugin is wip.
1. Code completion with rtags is not done yet. Completion does not work when invoked right after '.' (dot), '::' (scope resolution operator), therefore requires typing at least one character before invocation.

# Development
Unit tests for some plugin functions can be found in ```tests``` directory.
To run tests, execute:

    $ vim tests/test_rtags.vim +UnitTest
