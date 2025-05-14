vim9script

#{{{ Global initialization
if exists('g:clang_loaded')
  finish
endif
g:clang_loaded = 0

if !exists('g:clang_auto')
  g:clang_auto = v:true
endif

if !exists('g:clang_compilation_database')
  g:clang_compilation_database = '.'
endif

if !exists('g:clang_c_options')
  g:clang_c_options = ''
endif

if !exists('g:clang_cpp_options')
  g:clang_cpp_options = ''
endif

if !exists('g:clang_completeopt')
  g:clang_completeopt = 'menuone,preview,noinsert,noselect'
endif

if !exists('g:clang_debug')
  g:clang_debug = 10
endif

if !exists('g:clang_diagsopt') || (!empty(g:clang_diagsopt) && g:clang_diagsopt !~# '^[a-z]\+\(:[0-9]\)\?$')
  g:clang_diagsopt = 'rightbelow:6'
endif

if !exists('g:clang_dotfile')
  g:clang_dotfile = '.clang'
endif

if !exists('g:clang_dotfile_overwrite')
  g:clang_dotfile_overwrite = '.clang.ow'
endif

if !exists('g:clang_exec')
  g:clang_exec = 'clang'
endif

if !exists('g:clang_gcc_exec')
  g:clang_gcc_exec = 'gcc'
endif

if !exists('g:clang_format_auto')
  g:clang_format_auto = 0
endif

if !exists('g:clang_format_exec')
  g:clang_format_exec = 'clang-format'
endif

if !exists('g:clang_format_style')
  g:clang_format_style = 'LLVM'
endif

if !exists('g:clang_enable_format_command')
  g:clang_enable_format_command = 1
endif

if !exists('g:clang_check_syntax_auto')
	g:clang_check_syntax_auto = 0
endif

if !exists('g:clang_include_sysheaders')
  g:clang_include_sysheaders = 1
endif

if !exists('g:clang_include_sysheaders_from_gcc')
  g:clang_include_sysheaders_from_gcc = 0
endif

if !exists('g:clang_load_if_clang_dotfile')
  g:clang_load_if_clang_dotfile = 0
endif

if !exists('g:clang_pwheight')
  g:clang_pwheight = 4
endif

if !exists('g:clang_sh_exec')
  # sh default is dash on Ubuntu, which is unsupported
  g:clang_sh_exec = 'bash'
endif
g:clang_sh_is_cmd = g:clang_sh_exec =~ 'cmd.exe'

if !exists('g:clang_statusline')
  g:clang_statusline = '%s\ \|\ %%l/\%%L\ \|\ %%p%%%%'
endif

if !exists('g:clang_stdafx_h')
  g:clang_stdafx_h = 'stdafx.h'
endif

if !exists('g:clang_use_path')
  g:clang_use_path = 1
endif

if !exists('g:clang_vim_exec')
  if has('mac')
    g:clang_vim_exec = 'mvim'
  elseif has('gui_running')
    g:clang_vim_exec = 'gvim'
  else
    g:clang_vim_exec = 'vim'
  endif
endif

# Init on c/c++ files
au FileType c,cpp,cc ClangCompleteInit(0)
#}}}

def IsValidFile(): bool
  var cur = expand("%")
  # don't load plugin when in fugitive buffer
  if cur =~ 'fugitive://'
    return 0
  endif
  # Please don't use filereadable to test, as the new created file is also
  # unreadable before writting to disk.
  return &filetype == "c" || &filetype == "cpp" || &filetype == "cc"
enddef

# Use `:messages` to see debug info or read the var `b:clang_pdebug_storage`
#
# Buffer var used to store messages
#   b:clang_pdebug_storage
#
# @head Prefix of debug info
# @info Can be a string list, string, or dict
# @lv   Debug level, write info only when lv < g:clang_debug, default is 1
func PDebug(head, info, ...)
  let l:lv = a:0 > 0 && a:1 > 1 ? a:1 : 1

  if !exists('b:clang_pdebug_storage')
    let b:clang_pdebug_storage = []
  endif

  if l:lv <= g:clang_debug
    let l:msg = printf("Clang: debug: %s >>> %s", string(a:head), string(a:info))
    echom l:msg
    call add(b:clang_pdebug_storage, l:msg)
  endif
endf

# Uses 'echoe' to preserve @err
# Call ':messages' to see error messages
# @head Prefix of error message
# @err Can be a string list, string, or dict
func PError(head, err)
  echoerror printf(#Clang: error: %s >>> %s", string(a:head), string(a:err))
endf

# Uses 'echom' to preserve @info.
# @head Prefix of log info
# @info Can be a string list, string, or dict
func PLog(head, info)
  echom printf(#Clang: log: %s >>> %s", string(a:head), string(a:info))
endf

# Store current global var into b:clang_bufvars_storage
# Set global options that different in different buffer
def BufVarSet()
  b:clang_bufvars_storage = {'completeopt':  &completeopt}
  if (&filetype == 'cpp' || &filetype == 'cc' || &filetype == 'c')
    && ! empty(g:clang_completeopt)
  endif
enddef

# Restore global vim options
def BufVarRestore()
  if exists('b:clang_bufvars_storage')
    execute 'set completeopt=' .. b:clang_bufvars_storage['completeopt']
  endif
enddef

def ShouldComplete(): bool
  if getline('.') =~# '#\s*\(include\|import\)' || getline('.')[col('.') - 2] == "'"
    return 0
  endif
  if col('.') == 1
    return 1
  endif
  for id in synstack(line('.'), col('.') - 1)
    if synIDattr(id, 'name') =~# 'Comment\|String\|Number\|Char\|Label\|Special'
      return 0
    endif
  endfor
  return v:true
enddef

def CompleteDot(): string
  if ShouldComplete()
    PDebug("s:CompleteDot", 'do')
    return ".\<C-x>\<C-o>"
  endif
  return '.'
enddef

def CompleteArrow(): string
  if ShouldComplete() && getline('.')[col('.') - 2] == '-'
    PDebug("s:CompleteArrow", "do")
    return ">\<C-x>\<C-o>"
  endif
  return '>'
enddef

def CompleteColon(): string
  if ShouldComplete() && getline('.')[col('.') - 2] == ':'
    PDebug("s:CompleteColon", "do")
    return ":\<C-x>\<C-o>"
  endif
  return ':'
enddef

#{{{ DiscoverIncludeDirs
# Discover clang default include directories.
# Output of `echo | clang -c -v -x c++ -`:
#   clang version ...
#   Target: ...
#   Thread model: ...
#    "/usr/bin/clang" -cc1 ....
#   clang -cc1 version ...
#   ignoring ..
#   #include "..."...
#   #include <...>...
#    /usr/include/..
#    /usr/include/
#    ....
#   End of search list.
#
# @clang Path of clang.
# @options Additional options passed to clang, e.g. -stdlib=libc++
# @return List of dirs: ['path1', 'path2', ...]
func DiscoverIncludeDirs(clang, options)
  var l:echo = g:clang_sh_is_cmd ? 'type NUL' : 'echo'
  var l:command = printf('%s | %s -fsyntax-only -v %s - 2>&1', l:echo, a:clang, a:options)
  call PDebug("s:DiscoverIncludeDirs::cmd", l:command, 2)
  var l:clang_output = split(system(l:command), #\n")
  call PDebug("s:DiscoverIncludeDirs::raw", l:clang_output, 3)

  var l:i = 0
  var l:hit = 0
  for l:line in l:clang_output
    if l:line =~# '^#include'
      var l:hit = 1
    elseif l:hit
      break
    endif
    var l:i += 1
  endfor

  var l:clang_output = l:clang_output[l:i : -1]
  var l:res = []
  for l:line in l:clang_output
    if l:line[0] == ' '
      # a dirty workaround for Mac OS X (see issue #5)
      var l:path=substitute(l:line[1:-1], ' (framework directory)$', '', 'g')
      call add(l:res, l:path)
    elseif l:line =~# '^End'
      break
    endif
  endfor
  call PDebug("s:DiscoverIncludeDirs::parsed", l:res, 2)
  return l:res
endf
#}}}

#{{{ DiscoverDefaultIncludeDirs
# Discover default include directories of clang and gcc (if existed).
# @options Additional options passed to clang and gcc, e.g. -stdlib=libc++
# @return List of dirs: ['path1', 'path2', ...]
def DiscoverDefaultIncludeDirs(options: string): any
  var res = []
  if g:clang_include_sysheaders_from_gcc
    res = DiscoverIncludeDirs(g:clang_gcc_exec, options)
  else
    res = DiscoverIncludeDirs(g:clang_exec, options)
  endif
  PDebug("s:DiscoverDefaultIncludeDirs", res, 2)
  return res
enddef
#}}}

# Split a window to show clang diagnostics. If there's no diagnostics, close
# the split window.
# Global variable:
#   g:clang_diagsopt
#   g:clang_statusline
# Tab variable
#   t:clang_diags_bufnr         <= diagnostics window bufnr
#   t:clang_diags_driver_bufnr  <= the driver buffer number, who opens this window
#   NOTE: Don't use winnr, winnr maybe changed.
# @src Relative path to current source file, to replace <stdin>
# @diags A list of lines from clang diagnostics, or a diagnostics file name.
# @return -1 or buffer number t:clang_diags_bufnr
func DiagnosticsWindowOpen(src, diags)
  if g:clang_diagsopt ==# ''
    return
  endif

  var l:diags = a:diags
  if type(l:diags) == type('')
    # diagnostics file name
    var l:diags = readfile(l:diags)
  elseif type(l:diags) != type([])
    call PError(#s:DiagnosticsWindowOpen", 'Invalid arg ' . string(l:diags))
    return -1
  endif

  var l:i = stridx(g:clang_diagsopt, ':')
  var l:mode      = g:clang_diagsopt[0 : l:i-1]
  var l:maxheight = g:clang_diagsopt[l:i+1 : -1]

  var l:cbuf = bufnr('%')
  # Here uses t:clang_diags_bufnr to keep only one window in a *tab*
  if !exists('t:clang_diags_bufnr') || !bufexists(t:clang_diags_bufnr)
    var t:clang_diags_bufnr = bufnr('ClangDiagnostics@' . l:cbuf, 1)
  endif

  var l:winnr = bufwinnr(t:clang_diags_bufnr)
  if l:winnr == -1
    if ! empty(l:diags)
      # split a new window, go into it automatically
      exe 'silent keepalt keepjumps keepmarks ' .l:mode. ' sbuffer ' . t:clang_diags_bufnr
      call PDebug("s:DiagnosticsWindowOpen::sbuffer", t:clang_diags_bufnr)
    else
      # empty result, return
      return -1
    endif
  elseif empty(l:diags)
    # just close window(but not preview window) and return
    call DiagnosticsWindowClose()
    return -1
  else
    # goto the exist window
    call PDebug("s:DiagnosticsWindowOpen::wincmd", l:winnr)
    exe l:winnr . 'wincmd w'
  endif

  # the last line will be showed in status line as file name
  var l:diags_statics = ''
  if empty(l:diags[-1]) || l:diags[-1] =~ '^[0-9]\+\serror\|warn\|note'
    var l:diags_statics = l:diags[-1]
    var l:diags = l:diags[0: -2]
  endif

  var l:height = min([len(l:diags), l:maxheight])
  exe 'silent resize '. l:height

  setl modifiable
  # clear buffer before write
  silent 1,$ delete _

  # add diagnostics
  for l:line in l:diags
    # 1. ^<stdin>:
    # 2. ^In file inlcuded from <stdin>:
    # So only to replace <stdin>: ?
    call append(line('$')-1, substitute(l:line, '<stdin>:', a:src . ':', ''))
  endfor
  # the last empty line
  $delete _

  # goto the 1st line
  silent 1

  setl buftype=nofile bufhidden=hide
  setl noswapfile nobuflisted nowrap nonumber nospell nomodifiable winfixheight winfixwidth
  setl cursorline
  setl colorcolumn=-1

  # Don't use indentLine in the diagnostics window
  # See https://github.com/Yggdroot/indentLine.git
  if exists('b:indentLine_enabled') && b:indentLine_enabled
    IndentLinesToggle
  endif

  syn match ClangSynDiagsError    display 'error:'
  syn match ClangSynDiagsWarning  display 'warning:'
  syn match ClangSynDiagsNote     display 'note:'
  syn match ClangSynDiagsPosition display '^\s*[~^ ]\+$'

  hi ClangSynDiagsError           guifg=Red     ctermfg=9
  hi ClangSynDiagsWarning         guifg=Magenta ctermfg=13
  hi ClangSynDiagsNote            guifg=Gray    ctermfg=8
  hi ClangSynDiagsPosition        guifg=Green   ctermfg=10

  # change file name to the last line of diags and goto line 1
  exe printf('setl statusline='.g:clang_statusline, escape(l:diags_statics, ' \'))

  # back to current window, aka the driver window
  var t:clang_diags_driver_bufnr = l:cbuf
  exe bufwinnr(l:cbuf) . 'wincmd w'
  return t:clang_diags_bufnr
endf
#}}}

# Close diagnostics window or quit the editor
# Tab variable
#   t:clang_diags_bufnr
def DiagnosticsWindowClose()
  # diag window buffer is not exist
  if ! exists('t:clang_diags_bufnr')
    return
  endif
  PDebug("s:DiagnosticsWindowClose", "try")

  var cbn = bufnr('%')
  var cwn = bufwinnr(cbn)
  var dwn = bufwinnr(t:clang_diags_bufnr)

  # the window does not exist
  if dwn == -1
    return
  endif

  execute dwn .. 'wincmd w'
  quit
  execute cwn .. 'wincmd w'

  PDebug("s:DiagnosticsWindowClose", dwn)
enddef
#}}}

def DiagnosticsPreviewWindowClose()
  PDebug("s:DiagnosticsPreviewWindowClose", "")
  pclose
  DiagnosticsWindowClose()
enddef

# Called when driver buffer is unavailable, close preivew and window when
# leave from the driver buffer
def DiagnosticsPreviewWindowCloseWhenLeave()
  if ! exists('t:clang_diags_driver_bufnr')
    return
  endif

  var cbuf = expand('<abuf>')
  if cbuf != t:clang_diags_driver_bufnr
    return
  endif
  DiagnosticsPreviewWindowClose()
enddef

# {{{ ParseCompletePoint
# <IDENT> indicates an identifier
# </> the completion point
# <.> including a `.` or `->` or `::`
# <s> zero or more spaces and tabs
# <*> is anything other then the new line `\n`
#
# 1  <*><IDENT><s></>         complete identfiers start with <IDENT> # 2  <*><.><s></>             complete all members
# 3  <*><.><s><IDENT><s></>   complete identifers start with <IDENT>
# @return [start, base] start is used by omni and base is used to filter
# completion result
def ParseCompletePoint(): list<any>
    var line = getline('.')
    var start = col('.') - 1 # start column

    #trim right spaces
    while start > 0 && line[start - 1] =~ '\s'
      start -= 1
    endwhile

    var col = start
    while col > 0 && line[col - 1] =~# '[_0-9a-zA-Z]'  # find valid ident
      col -= 1
    endwhile

    # end of base word to filter completions
    var base = ''
    if col < start
      # may exist <IDENT>
      if line[col] =~# '[_a-zA-Z]'
        #<ident> doesn't start with a number
        base = line[col : start - 1]
        # reset l:start in case 1
        start = col
      else
        PError("s:ParseCompletePoint", 'Can not complete after an invalid identifier <'
            \ .. line[col : start - 1] .. '>')
        return [-3, base]
      endif
    endif

    # trim right spaces
    while col > 0 && line[col - 1] =~ '\s'
      col -= 1
    endwhile

    var ismber = 0
    if (col >= 1 && line[col - 1] == '.')
        \ || (col >= 2 && line[col - 1] == '>' && line[col - 2] == '-')
        \ || (col >= 2 && line[col - 1] == ':' && line[col - 2] == ':' && &filetype != "c")
      start = col
      ismber = 1
    endif

    #Nothing to complete, pattern completion is not supported...
    if ! ismber && empty(base)
      return [-3, base]
    endif
    PDebug("s:ParseCompletePoint", printf("start: %s, base: %s", start, base))
    return [start, base]
enddef

def ParseCompletionResult(channel: channel, base: string): list<dict<string>>
  const has_preview = &completeopt =~# 'preview'
  var matches = {accessible: [], inaccessible: []}
  while ch_canread(channel)
    const line = ch_read(channel)
    var core: string
    var kind: string
    var proto: string
    var rettype: string
    var word: string
    const collon = stridx(line, ':', 13)
    if collon == -1
      word = line[12 : -1]
      proto = word
    else
      word = line[12 : collon - 2]
      proto = line[collon + 2 : -1]
    endif

    if word !~# '^' .. base || word =~ '(.*Hidden.*)$'
      continue
    endif

    const is_inaccessible = word =~# '(.*Inaccessible.*)$'
    const bucket = is_inaccessible ? 'inaccessible' : 'accessible'
    const is_empty = empty(matches[bucket])

    if proto =~ '\v^\[#void#\]\~.+\(\)$'
      kind = 'D'
    elseif proto =~ '\v^\[#.{-}#\].+\(.*\).*'
      kind = 'f'
    elseif proto =~ '\v^\[#.*#\].+'
      kind = 'v'
    elseif proto =~ '\v^.+\(.*\)$'
      kind = 'C'
    elseif proto =~ '\v.+'
      kind = 't'
    else
      kind = '?'
    endif

    if kind == 'f' || kind == 'v' || kind == 'D'
      # Get the type of return value in the first []
      var typeraw = matchlist(proto, '\v^\[#.{-}#\]')
      rettype = len(typeraw) > 0 ? typeraw[0][1 : -2] : ""
      core = rettype .. ' ' .. proto[strlen(rettype) + 2 :]
      core = substitute(core, '\[# \(.*\)#\]$', ' \1', '')
    else
      rettype = ""
      core = proto
    endif

    core = substitute(core, '\v\<#|#\>|#', '', 'g')
    rettype = substitute(rettype, '\v\<#|#\>|#', '', 'g')

    if is_empty || matches[bucket][-1].word !=# word
      add(matches[bucket], {'word': word, 'kind': kind, 'menu': rettype, 'info': core})
    elseif ! is_empty
      matches[bucket][-1].info = matches[bucket][-1].info .. "\n" .. core
    endif
  endwhile
  return matches.accessible + matches.inaccessible
enddef

# Initialization for every C/C++ source buffer:
#   1. find set root to file .clang
#   2. read config file .clang
#   3. append user options first
#   3.5 append clang default include directories to option
#   4. setup buffer maps to auto completion
#
#  Usable vars after return:
#     b:clang_options => parepared clang cmd options
#     b:clang_options_noPCH  => same as b:clang_options except no pch options
#     b:clang_root => project root to run clang
#
# @force Force init
def ClangCompleteInit(force: bool)
  if ! IsValidFile()
    return
  endif

  # find project file first
  var localdir = haslocaldir()
  var cwd = fnameescape(getcwd())
  var fwd = fnameescape(expand('%:p:h'))
  var dotclang = ''
  var dotclangow = ''
  if isdirectory(fwd)
    silent execute 'lcd ' .. fwd
    dotclang = fnamemodify(findfile(g:clang_dotfile, '.;'), ':p')
    dotclangow = fnamemodify(findfile(g:clang_dotfile_overwrite, '.;'), ':p')
    if localdir
      silent execute 'lcd ' .. cwd
    else
      silent execute 'cd ' .. cwd
    endif
  endif

  var has_dotclang = strlen(dotclang) + strlen(dotclangow)
  if ! has_dotclang && g:clang_load_if_clang_dotfile
    return
  endif

  setl omnifunc=ClangComplete

  if ! exists('b:clang_complete_inited')
    b:clang_complete_inited = 1
  elseif ! force
    return
  endif

  # PDebug("ClangCompleteInit", "start")

  # Firstly, add clang options for current buffer file
  b:clang_options = ''

  var is_ow = 0
  if filereadable(dotclangow)
    is_ow = 1
    dotclang = dotclangow
  endif

  # clang root(aka .clang located directory) for current buffer
  if filereadable(dotclang)
    b:clang_root = fnameescape(fnamemodify(dotclang, ':p:h'))
    var opts = readfile(dotclang)
    for opt in opts
      if opt =~ "^[ \t]*//"
        continue
      endif
      b:clang_options = b:clang_options .. ' ' .. opt
    endfor
  else
    # or means source file directory
    b:clang_root = fwd
  endif

  # Secondly, add options defined by user if is not ow
  if &filetype == 'c'
    b:clang_options = b:clang_options .. ' -x c '
    if ! is_ow
      b:clang_options = b:clang_options .. g:clang_c_options
    endif
  elseif &filetype == 'cpp' || &filetype == 'cc'
    b:clang_options = b:clang_options .. ' -x c++ '
    if ! is_ow
      b:clang_options = b:clang_options .. g:clang_cpp_options
    endif
  endif

  # add current dir to include path
  b:clang_options = b:clang_options .. ' -I ' .. shellescape(expand("%:p:h"))

  # add include directories if is enabled and not ow
  # var default_incs = DiscoverDefaultIncludeDirs(b:clang_options)
  var default_incs = []
  if g:clang_include_sysheaders && ! is_ow
    for dir in default_incs
      b:clang_options = b:clang_options .. ' -I ' .. shellescape(dir)
    endfor
  endif

  # parse include path from &path
  if g:clang_use_path
    var dirs = map(split(&path, '\\\@<![, ]'), 'substitute(v:val, ''\\\([, ]\)'', ''\1'', ''g'')')
    for dir in dirs
      if len(dir) == 0 || !isdirectory(dir)
        continue
      endif

      # Add only absolute paths
      if matchstr(dir, '\s*/') != ''
        b:clang_options = b:clang_options .. ' -I ' .. shellescape(dir)
      endif
    endfor
  endif

  # backup options without PCH support
  b:clang_options_noPCH = b:clang_options
  # try to find PCH files in clang_root and clang_root/include
  # Or add `-include-pch /path/to/x.h.pch` into the root file .clang manully
  if (&filetype == 'cpp' || &filetype == 'cc') && b:clang_options !~# '-include-pch'
    localdir = haslocaldir()
    cwd = fnameescape(getcwd())
    if isdirectory(b:clang_root)
      silent execute 'lcd ' .. b:clang_root
      var afx = findfile(g:clang_stdafx_h, '.;./include') .. '.pch'
      if filereadable(afx)
        b:clang_options = b:clang_options .. ' -include-pch ' .. shellescape(afx)
      endif
      if isdirectory(cwd)
        if localdir
          silent exe 'lcd ' .. cwd
        else
          silent exe 'cd ' .. cwd
        endif
      endif
    endif
  endif

  # Create GenPCH command
  com! -nargs=* ClangGenPCHFromFile call GenPCH(g:clang_exec, <f-args>)

  # Create close diag and preview window command
  com! ClangCloseWindow  DiagnosticsPreviewWindowClose()

  # Useful to re-initialize plugin if .clang is changed
  com! ClangCompleteInit ClangCompleteInit(1)

  if g:clang_enable_format_command
    # Useful to format source code
    com! ClangFormat ClangFormat()
  endif

  if g:clang_auto # Auto completion
    inoremap <expr> <buffer> . CompleteDot()
    inoremap <expr> <buffer> > CompleteArrow()
    if &filetype == 'cpp' || &filetype == 'cc'
      inoremap <expr> <buffer> : CompleteColon()
    endif
  endif

  au CompleteDonePre <buffer> CompleteDonePre()
  au CompleteDone <buffer> CompleteDone()
  # au BufWritePost <buffer> ClangSyntaxCheck

  # auto check syntax when write buffer
	# endif

  # auto format current file if is enabled
  # if g:clang_format_auto
  #   au BufWritePost <buffer> ClangFormat
  # endif

  execute 'set completeopt=' .. g:clang_completeopt
enddef
#}}}

def CompleteDonePre()
  const info = complete_info()
  #PDebug('CompleteDonePre', info)
enddef

def CompleteDone()
  PDebug('CompleteDone', v:completed_item)
  const kind = has_key(v:completed_item, 'kind') ? v:completed_item.kind : ''
  var should_close = v:false
  if kind == 'v'
    should_close = v:true
  elseif has_key(v:completed_item, 'info') && has_key(v:completed_item, 'word')
    if kind == 't'
      if v:completed_item.info =~ '<'
        feedkeys('<')
      else
        should_close = v:true
      endif
    elseif (kind == 'C' || kind == 'D' || kind == 'f')
      if v:completed_item.info =~ escape(v:completed_item.word, '~[]') .. '<'
        feedkeys('<')
      else
        feedkeys('(')
        if v:completed_item.info !~ '\n'
           && v:completed_item.info =~ escape(v:completed_item.word, '~[]') .. '()'
          feedkeys(')')
          should_close = v:true
        endif
      endif
    endif
  endif
  try
    wincmd P
    if should_close
      close
    else
      const height = min([line('$'), 10])
      execute 'resize ' .. height
      wincmd p
    endif
  catch /^Vim\%((\a\+)\)\=:E441:/
  endtry
enddef

def Error()
  const current_window = win_getid()
  const info = getbufinfo('clang-errors')[0]
  var window_clang_errors = bufwinid('clang-errors')
  if -1 == window_clang_errors
    execute('new clang-errors')
    window_clang_errors = bufwinid('clang-errors')
    win_execute(window_clang_errors, 'resize ' .. min([info.linecount, 10]))
  endif
  win_gotoid(current_window)
enddef

def Complete(col: number, base: string, channel: channel)
  const job = ch_getjob(channel)
  const info = job_info(job)
  if 0 != info.exitval
    const buffer_clang_errors = bufadd('clang-errors')
    if ! bufloaded(buffer_clang_errors)
      bufload(buffer_clang_errors)
      setbufvar(buffer_clang_errors, '&buflisted', 1)
      setbufvar(buffer_clang_errors, '&buftype', 'nofile')
    else
      setbufvar(buffer_clang_errors, '&modifiable', 1)
      deletebufline(buffer_clang_errors, 1, '$')
    endif
    while ch_status(channel, {part: 'err'}) == 'buffered'
      const line = ch_read(channel, {part: 'err'})
      appendbufline(buffer_clang_errors, '$', line)
    endwhile
    deletebufline(buffer_clang_errors, 1)
    setbufvar(buffer_clang_errors, '&modifiable', 0)
    Error()
  elseif 0 < col
    if bufexists('clang-errors')
      const buffer_clang_errors = bufname('clang-errors')
      setbufvar(buffer_clang_errors, '&modifiable', 1)
      deletebufline(buffer_clang_errors, 1, '$')
      setbufvar(buffer_clang_errors, '&modifiable', 0)
      var window_clang_errors = bufwinid('clang-errors')
      if -1 != window_clang_errors
        win_execute(window_clang_errors, 'close')
      endif
    endif
    const matches = ParseCompletionResult(channel, base)
    complete(col, matches)
  endif
enddef

def ClangExecute(root: string, clang_options: string, line: number, col: number, base: string): job
  var localdir = haslocaldir()
  var cwd = fnameescape(getcwd())
  silent execute 'lcd ' .. root
  var src = join(getline(1, '$'), "\n") .. "\n"
  # shorter version, without redirecting stdout and stderr
  const command = printf('%s -w -fsyntax-only -Xclang -code-completion-macros -Xclang -code-completion-at=-:%d:%d %s -',
                      \ g:clang_exec, line, col, clang_options)

  PDebug("s:ClangExecute::command", command, 2)

  const job = job_start(command, {
    \ close_cb: (channel: channel) => Complete(col, base, channel),
    \ err_msg: 0,
    \ in_buf: winbufnr(winnr()),
    \ in_io: 'buffer'})

  return job

  # PDebug("s:ClangExecute::stdout", output)
  # PDebug("s:ClangExecute::stderr", res[1], 2)
  # if localdir
  #   silent execute 'lcd ' .. cwd
  # else
  #   silent execute 'cd ' .. cwd
  # endif
  # b:clang_state['stdout'] = res[0]
  # b:clang_state['stderr'] = res[1]
enddef

#
# Only do syntax check without completion, will open diags window when have
# problem. Now this function will block...
func ClangSyntaxCheck(root, clang_options)
  var l:localdir = haslocaldir()
  var l:cwd = fnameescape(getcwd())
  silent exe 'lcd ' . a:root
  var l:src = join(getline(1, '$'), #\n")
  var l:command = printf('%s -fsyntax-only %s -', g:clang_exec, a:clang_options)
  call PDebug("ClangSyntaxCheck::command", l:command)
  var l:clang_output = system(l:command, l:src)
  call DiagnosticsWindowOpen(expand('%:p:.'), split(l:clang_output, '\n'))
  if l:localdir
    silent exe 'lcd ' . l:cwd
  else
    silent exe 'cd ' . l:cwd
  endif
endf
#
def ClangComplete(findstart: bool, base: string): any
  PDebug("ClangComplete", "start")

  if findstart
    PDebug("ClangComplete", "phase 1")
    const [start, bas] = ParseCompletePoint()
    if start < 0
      return start
    endif

    const line = line('.')
    const col = start + 1
    const getline = getline('.')[0 : col - 2]
    PDebug("ClangComplete", printf("line: %s, col: %s, getline: %s", line, col, getline))
    ClangExecute(b:clang_root, b:clang_options, line, col, bas)
    return start
  else
    PDebug("ClangComplete", "phase 2")
    return v:none
  endif
enddef

defcompile
