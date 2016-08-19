" -*- mode: vim; tab-width: 4; indent-tabs-mode: nil; fill-column: 99 -*-
"
" emacsmodeline.vim
" Brief: Parse emacs mode line and setlocal in vim
" Version: 1.2
" Date: Jun 07, 2015
" Maintainer: Chris Pickel <sfiera@gmail.com>
"
" Installation: put this file under your ~/.vim/plugin/
"
" Usage:
"
" This script is used to parse emacs mode lines, for example:
" -*- tab-width: 4 -*-
"
" Which is the same meaning as:
" vim:tabstop=4:
"
" Revisions:
"
" 0.1, May 18, 2007:
"  * Initial version with tab-width support by Yuxuan 'fishy' Wang <fishywang@gmail.com>.
" 1.0, Dec 23, 2010:
"  * Support for mode, fill-column, buffer-read-only, and indent-tabs-mode.
"  * Maintainership taken up by Chris Pickel <sfiera@gmail.com>.
" 1.1, Feb 20, 2013
"  * Prevent an exploit.  Not seen in the wild, but likely to be used by vengeful emacs users.
" 1.2, Jun 07, 2015:
"  * More file support.  Let vim provide defaults.
" 1.x, xxx xx, xxxx:
"  * More rigidly adhere to emacs' own behaviour, as described at
"    https://www.gnu.org/software/emacs/manual/html_node/emacs/Specifying-File-Variables.html
"    ie: only support '-*-' in the first 2 lines, but also support
"    'Local Variables:' in the last 3000 chars, and set the latter after
"    the former.

" No attempt is made to support vim versions before 7.0.
if version < 700
    finish
endif

" Note: Entries to emacsModeDict must be lowercase. E. g. 'makefile' instead of 'Makefile'.
let s:emacsModeDictDefault = {
    \ 'c++':          'cpp',
    \ 'shell-script': 'sh',
    \ 'makefile':     'make',
    \ 'js':           'javascript',
    \ 'protobuf':     'proto',
\ }

if (!exists('g:emacsModeDict'))
    let g:emacsModeDict = {}
endif

" Add all default entries to the mode dict, keeping any user-defined entries
call extend(g:emacsModeDict, s:emacsModeDictDefault, "keep")

function! <SID>FindParameterValue(modeline, emacs_name, value)
    let pattern = '\c' . '\(^\|.*;\)\s*' . a:emacs_name . ':\s*\(' . a:value . '\)\s*\($\|;.*\)'
    if a:modeline =~ pattern
        return substitute(a:modeline, pattern, '\2', '')
    endif
    return ''
endfunc

function! <SID>SetVimModeOption(modeline)
    let value = <SID>FindParameterValue(a:modeline, 'mode', '[A-Za-z_+-]\+')
    if strlen(value)
        let value = tolower(value)
        if (has_key(g:emacsModeDict, value))
            let value = g:emacsModeDict[value]
        endif
        exec 'setlocal filetype=' . value
    endif
endfunc

function! <SID>SetVimNumberOption(modeline, emacs_name, vim_name)
    let value = <SID>FindParameterValue(a:modeline, a:emacs_name, '\d\+')
    if strlen(value)
        exec 'setlocal ' . a:vim_name . '=' . value
        return 1
    endif
    return 0
endfunc

function! <SID>SetVimStringOption(modeline, emacs_name, vim_name, validate_pattern)
    let value = <SID>FindParameterValue(a:modeline, a:emacs_name, a:validate_pattern)
    if strlen(value)
        exec 'setlocal ' . a:vim_name . '=' . value
        return 1
    endif
    return 0
endfunc

function! <SID>SetVimToggleOption(modeline, emacs_name, vim_name, nil_value)
    let value = <SID>FindParameterValue(a:modeline, a:emacs_name, '[^;[:space:]]\+')
    if strlen(value)
        if (value == 'nil') == a:nil_value
            exec 'setlocal ' . a:vim_name
        else
            exec 'setlocal no' . a:vim_name
        end
    endif
endfunc

function! <SID>ParseEmacsOption(modeline)

    call <SID>SetVimModeOption(a:modeline)

    call <SID>SetVimNumberOption(a:modeline, 'fill-column',        'textwidth')
    if <SID>SetVimNumberOption(a:modeline,   'tab-width',          'tabstop')
        " - When shiftwidth is zero, the 'tabstop' value is used.
        "   Use the shiftwidth() function to get the effective shiftwidth value.
        " - When 'sts' is negative, the value of 'shiftwidth' is used.
        setlocal shiftwidth=0
        setlocal softtabstop=-1
    endif
    call <SID>SetVimNumberOption(a:modeline, 'c-basic-offset',     'softtabstop')
    call <SID>SetVimNumberOption(a:modeline, 'c-basic-offset',     'shiftwidth')

    call <SID>SetVimToggleOption(a:modeline, 'buffer-read-only',   'readonly',     0)
    call <SID>SetVimToggleOption(a:modeline, 'indent-tabs-mode',   'expandtab',    1)
    call <SID>SetVimStringOption(a:modeline, 'coding',             'fileencoding', '[\w\-]\+')

    let value = substitute(a:modeline, '^ *\([^ ]*\) *$', '\L\1', '')
    if (has_key(g:emacsModeDict, value))
        exec 'setlocal filetype=' .  g:emacsModeDict[value]
    endif

    " Other emacs options seen in the wild include:
    "  * c-file-style: no vim equivalent (?).
    "  * compile-command: probably equivalent to &makeprg.  However, vim will refuse to
    "    set it from a modeline, as a security risk, and we follow that decision here.
    "  * mmm-classes: appears to be for other languages inline in HTML, e.g. PHP.
    "  * package: equal to mode, in the one place I've seen it.
    "  * syntax: equal to mode, in the one place I've seen it.
endfunc

function! ParseEmacsModeLine()
    " Prepare to scan the first 2 lines.
    let lines = range(1, 2)

    let pattern = '.*-\*-\(.*\)-\*-.*'
    for n in lines
        let line = getline(n)
        if line =~ pattern
            let modeline = substitute(line, pattern, '\1', '')
            call <SID>ParseEmacsOption(modeline)
        endif
    endfor

    " Prepare to scan the last 3000 characters' worth of lines.
    let lastline = line("$")
    let bname = bufname("")
    let fsize = getfsize(bname)
    if fsize > 3000
        let firstline = byte2line(fsize-3000)
    else
        let firstline = 1
    endif

    " Find the last line in the file that has 'Local Variables:' in it,
    " to try and be reasonably sure we aren't hitting another use of
    " that string. Use the comments around that string to filter out
    " all but the option name and value, as emacs purportedly does.
    let lines = range(lastline, firstline, -1)
    let pattern = '^\(.*\)[ \t]*Local [vV]ariables:[ \t]*\(.*\)$'
    for n in lines
        let line = getline(n)
        if line =~ 'End:'
            let lastline = n - 1
        elseif line =~ pattern
            let firstline = n + 1
            let cstart = substitute(line, pattern, '\1', '')
            let cend = substitute(line, pattern, '\2', '')
            break
        endif
    endfor

    " Now actually parse the lines we've found.
    let lines = range(firstline, lastline)
    for n in lines
        let modeline = getline(n)
        let modeline = substitute(modeline, '^'.cstart, '', '')
        let modeline = substitute(modeline, cend.'$', '', '')
        call <SID>ParseEmacsOption(modeline)
    endfor
endfunc

autocmd BufReadPost * :call ParseEmacsModeLine()
