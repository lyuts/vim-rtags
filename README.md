# Vim Rtags

Vim bindings for rtags.

https://github.com/Andersbakken/rtags

# Requirements
1. Vim built with ```+python```.

# Installation

# Configuration
This plugin interacts with RTags by invoking ```rc``` commands and interpreting
their results.  You can override the path to ```rc``` binary by setting
```g:rcCmd``` variable.  By default, it is set to ```rc```, expecting it to be
found in the $PATH.

Out of box this plugin provides mappings. In order to use custom mappings the
default mappings can be disabled:

    let g:rtagsUseDefaultMappings = 0

# Usage

# Notes
1. This plugin is wip.
1. Code completion with rtags is not done yet.

# Development
Unit tests for some plugin functions can be found in ```tests``` directory.
To run tests, execute:

    $ vim tests/test_rtags.vim +UnitTest
